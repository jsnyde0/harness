#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# CLI dispatch skeleton
# ---------------------------------------------------------------------------
# Default (no args): full install = provision + wire (backward-compatible).
# Subcommands:
#   provision     — run only the provisioning phase (download + install deps)
#   install       — alias for default (provision + wire)
# Future subcommands (stubs for child .3): doctor, --help
# ---------------------------------------------------------------------------
SUBCOMMAND="${1:-install}"

# Target home directory. Override via DOTPI_TEST_TARGET for throwaway-target testing.
# Default: real $HOME.
TARGET_HOME="${DOTPI_TEST_TARGET:-$HOME}"

PI_AGENT="$TARGET_HOME/.pi/agent"
CLAUDE_AGENTS="$TARGET_HOME/.claude/agents"
CODEX_AGENTS="$TARGET_HOME/.codex/agents"
CODEX_CONFIG_TOML="$TARGET_HOME/.codex/config.toml"
CODEX_SKILLS_ROOT="$TARGET_HOME/.agents/skills"

mkdir -p "$PI_AGENT"
mkdir -p "$CLAUDE_AGENTS"
mkdir -p "$CODEX_AGENTS"
mkdir -p "$(dirname "$CODEX_CONFIG_TOML")"
mkdir -p "$(dirname "$CODEX_SKILLS_ROOT")"

backup_existing() {
  local path="$1"

  if [ -L "$path" ]; then
    # Resolve where the existing symlink points
    local existing_raw
    existing_raw=$(readlink "$path")
    local existing_resolved
    existing_resolved=$(cd "$(dirname "$path")" && realpath "$existing_raw" 2>/dev/null || echo "")
    # If the symlink already points into this dotpi source tree, remove it (clean re-install is fine).
    # If it points somewhere else (another agent, another repo), back it up — never silently destroy it.
    if [[ "$existing_resolved" == "$ROOT/"* ]] || [ "$existing_resolved" = "$ROOT" ]; then
      rm -f "$path"
    else
      local backup="$path.backup.$(date +%Y%m%d%H%M%S)"
      mv -f "$path" "$backup"
      echo "Backed up existing symlink $path -> $backup (pointed to: $existing_raw)"
    fi
  elif [ -e "$path" ]; then
    local backup="$path.backup.$(date +%Y%m%d%H%M%S)"
    mv -f "$path" "$backup"
    echo "Backed up $path -> $backup"
  fi
}

# Create a RELATIVE symlink from $link pointing at $target.
# Computes the relative path from link's parent dir to target.
link_relative() {
  local target="$1"   # absolute path to the real file/dir
  local link="$2"     # absolute path where the symlink will live

  # python3 is available on macOS; use it to compute relpath portably
  local rel
  rel=$(python3 -c "import os.path; print(os.path.relpath('$target', '$(dirname "$link")'))")

  backup_existing "$link"
  ln -s "$rel" "$link"
  echo "Linked $link -> $rel"
}

link_dir() {
  local name="$1"
  local target="$ROOT/agent/$name"
  local link="$PI_AGENT/$name"

  mkdir -p "$target"
  link_relative "$target" "$link"
}

link_file() {
  local name="$1"
  local target="$ROOT/agent/$name"
  local link="$PI_AGENT/$name"

  if [ ! -f "$target" ]; then
    echo "Missing $target" >&2
    exit 1
  fi

  link_relative "$target" "$link"
}

# ---------------------------------------------------------------------------
# Provisioning phase — runs BEFORE wiring phases
# ---------------------------------------------------------------------------
# Reads manifest/deps.toml and installs external deps (beads, CASSMS) into
# $TARGET_HOME/.local/bin. Idempotent: already-correct deps are skipped.
# SHA256 verified BEFORE install; aborts on mismatch (non-zero exit).
# Core config: no per-tool config write needed — binaries on PATH is sufficient.
# beads and cm read their own per-workspace config at runtime.
# ---------------------------------------------------------------------------

run_provision() {
  bash "$ROOT/scripts/provision-deps.sh"
}

case "$SUBCOMMAND" in
  provision)
    run_provision
    exit 0
    ;;
  install|"")
    run_provision
    ;;
  *)
    echo "install.sh: unknown subcommand '$SUBCOMMAND'" >&2
    echo "Usage: install.sh [provision|install]" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# W3 symlink / wiring phases (unchanged — provisioning runs before these)
# ---------------------------------------------------------------------------

# Existing behaviors (preserved)
link_file AGENTS.md
link_file keybindings.json
link_dir extensions
link_dir prompts
link_dir skills

# NEW: symlink agent/roles/ into ~/.pi/agent/roles/
link_dir roles

# NEW: symlink each agent/roles/*.md individually into $CLAUDE_AGENTS/<name>.md
# (Cannot dir-link the agents/ dir whole — it holds other Claude Code agents)
# nullglob guard: if no .md files exist the glob expands literally; skip in that case.
shopt -s nullglob
for role_src in "$ROOT/agent/roles/"*.md; do
  role_name="$(basename "$role_src")"
  role_link="$CLAUDE_AGENTS/$role_name"
  link_relative "$role_src" "$role_link"
done
shopt -u nullglob

# --- Codex wiring (compile-generation, D6) ---
# All Codex wiring lives here (install layer) — NEVER in the shared runner files.
# D2 invariant: agent/extensions/subagent/{role-loader.mjs,index.ts} and
# agent/extensions/hooks/{core.mjs,index.ts} MUST NOT gain Codex branches.

# 1. Generate Codex role TOML files (D6 compile-generation)
#    Each shared markdown brief → a TOML role file under $CODEX_AGENTS/
#    Fields: name, description, developer_instructions (body), model + model_provider
#    (split from codex-model: slug, e.g. openai/gpt-5.5 → model=gpt-5.5, model_provider=openai)
shopt -s nullglob
for role_src in "$ROOT/agent/roles/"*.md; do
  role_name="$(basename "$role_src" .md)"
  toml_out="$CODEX_AGENTS/$role_name.toml"

  # Extract frontmatter fields using python3 (available on macOS, no deps needed)
  python3 - "$role_src" "$toml_out" <<'PYEOF'
import sys, re

src_path = sys.argv[1]
out_path = sys.argv[2]

with open(src_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Split frontmatter (YAML between --- delimiters) from body
fm_match = re.match(r'^---\n(.*?)\n---\n(.*)', content, re.DOTALL)
if not fm_match:
    print(f"WARNING: no frontmatter in {src_path}, skipping", file=sys.stderr)
    sys.exit(0)

fm_text = fm_match.group(1)
body = fm_match.group(2).strip()

def get_field(fm, key):
    """Extract a frontmatter field, handling both simple scalars and YAML block scalars (> and |)."""
    # Match the key line: either 'key: value' or 'key: >' / 'key: |' (block scalar)
    m = re.search(r'^' + re.escape(key) + r':\s*(.*)', fm, re.MULTILINE)
    if not m:
        return None
    rest = m.group(1).strip()
    if rest in ('>', '|'):
        # Block scalar: collect all continuation lines (more-indented than the key)
        # Lines start after the key line; gather until dedent or EOF
        block_style = rest
        key_line_end = m.end()
        remaining = fm[key_line_end:]
        continuation_lines = []
        for line in remaining.splitlines():
            # A continuation line must be indented (start with whitespace)
            if line == '' or line[0] == ' ' or line[0] == '\t':
                continuation_lines.append(line.strip())
            else:
                # Dedented — end of block scalar
                break
        # Filter empty lines and join
        non_empty = [l for l in continuation_lines if l]
        if block_style == '>':
            # Folded: join with spaces
            return ' '.join(non_empty)
        else:
            # Literal: join with newlines
            return '\n'.join(non_empty)
    elif rest:
        # Simple scalar: value is on the same line
        return rest
    return None

name = get_field(fm_text, 'name') or role_name
raw_description = get_field(fm_text, 'description') or ''
codex_model_slug = get_field(fm_text, 'codex-model') or ''

description = raw_description.strip()

# Split codex-model slug: provider/model-id → model_provider + model
if '/' in codex_model_slug:
    provider_part, model_part = codex_model_slug.split('/', 1)
else:
    provider_part = 'openai'
    model_part = codex_model_slug

def toml_escape(s):
    """Escape a string for TOML basic string (double-quoted)."""
    return s.replace('\\', '\\\\').replace('"', '\\"')

# Write TOML role file
with open(out_path, 'w', encoding='utf-8') as f:
    f.write(f'name = "{toml_escape(name)}"\n')
    f.write(f'description = "{toml_escape(description)}"\n')
    f.write(f'model = "{toml_escape(model_part)}"\n')
    f.write(f'model_provider = "{toml_escape(provider_part)}"\n')
    f.write(f'developer_instructions = """\n{body}\n"""\n')
PYEOF

  echo "Generated Codex TOML: $toml_out"
done
shopt -u nullglob

# 2. MERGE [hooks] table into user-level ~/.codex/config.toml from hooks-manifest.json.
#    Schema: [[hooks.PreToolUse]] (matcher) + nested [[hooks.PreToolUse.hooks]] (type/command).
#    Event table name is PascalCase (serde rename). One [[hooks.PreToolUse.hooks]] per command.
#    DO NOT clobber existing config.toml — merge by stripping old [hooks] section and appending.
#    Codex supported decisions: deny+reason, allow+updatedInput, exit-2+stderr (stdout JSON).
#    Codex hook wire shape: stdout JSON {hookSpecificOutput: {permissionDecision, permissionDecisionReason}}.
#    ADAPTER: dcg (outputFormat:"json") outputs {decision:"deny", reason:"..."} — NOT the Codex wire shape.
#    A generated adapter script translates dcg output to Codex wire shape.
#    The cc-hook scripts already speak the Codex wire format natively — no adapter needed for them.
#    DIVERGENCE NOTE: Codex PreToolUse supports only "deny"; "ask" is unsupported → fail-open.
#    An ask-emitting hook is silently ignored by Codex and the tool PROCEEDS (fail-open).
#    Pure deny-or-pass hooks (e.g. block-compound-commands.sh) are unaffected.

CODEX_DIR="$(dirname "$CODEX_CONFIG_TOML")"
DCG_ADAPTER_SCRIPT="$CODEX_DIR/dcg-codex-hook.sh"

# 2a. Generate the dcg → Codex wire adapter script (Python, avoids bash quoting issues).
#     dcg outputs {decision:"deny", reason:"..."} (outputFormat:"json").
#     Codex expects stdout JSON: {hookSpecificOutput:{hookEventName:"PreToolUse",
#                                                    permissionDecision:"deny",
#                                                    permissionDecisionReason:"..."}}
#     This adapter reads tool_input from stdin (Codex hook protocol), extracts the
#     command, runs dcg, and translates the result to the Codex wire shape.
python3 - "$DCG_ADAPTER_SCRIPT" << 'PYEOF'
import sys

out_path = sys.argv[1]
script_content = '''\
#!/usr/bin/env python3
# dotpi — dcg -> Codex wire adapter
# Codex sends {tool_input:{command:"..."}} on stdin as JSON.
# dcg outputs {decision:"deny"|"allow", reason:"..."}.
# This adapter bridges the two: runs dcg, emits Codex hookSpecificOutput JSON.
import json
import subprocess
import sys

def main():
    try:
        raw = sys.stdin.read()
        data = json.loads(raw)
    except Exception:
        sys.exit(0)

    command = data.get("tool_input", {}).get("command", "")
    if not command:
        sys.exit(0)

    try:
        result = subprocess.run(
            ["dcg", "test", "--format", "json", command],
            capture_output=True,
            text=True,
        )
        dcg_out = json.loads(result.stdout)
    except Exception:
        sys.exit(0)

    decision = dcg_out.get("decision", "allow")
    if decision == "deny":
        reason = dcg_out.get("reason", "blocked by dcg")
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }))

if __name__ == "__main__":
    main()
'''

with open(out_path, 'w', encoding='utf-8') as f:
    f.write(script_content)

import os
os.chmod(out_path, 0o755)
print(f"Generated dcg adapter: {out_path}")
PYEOF

# 2b. Merge [hooks] table and [hooks.state] trust seeds into config.toml.
#    Trust seeds are required because codex exec's --dangerously-bypass-hook-trust flag
#    only sets bypass_hook_trust in the exec-level bootstrap config, not in per-thread
#    configs. Per-thread configs always have bypass_hook_trust=false, so User-layer hooks
#    are treated as Untrusted and silently skipped unless trusted_hash is pre-seeded.
#    Pre-seeding trusted_hash=<sha256 of normalised hook identity> grants Trusted status
#    so hooks fire without relying on the bypass flag propagating.
HOOKS_MANIFEST="$ROOT/agent/hooks-manifest.json"
python3 - "$HOOKS_MANIFEST" "$CODEX_CONFIG_TOML" "$DCG_ADAPTER_SCRIPT" <<'PYEOF'
import sys, json, re, os, hashlib

manifest_path = sys.argv[1]
config_path = sys.argv[2]
dcg_adapter_path = sys.argv[3]

with open(manifest_path, 'r', encoding='utf-8') as f:
    manifest = json.load(f)

def toml_str(s):
    """Escape a string for TOML basic string (double-quoted)."""
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def expand_home(script):
    """Expand portable prefixes to shell-expandable forms for TOML.

    $CLAUDE_HOME/<rest> → $HOME/.claude/<rest>
      $CLAUDE_HOME is unset in every shell; emitting $HOME/.claude/ resolves
      correctly at Codex runtime without requiring an env var to be set.

    ~/<rest> → $HOME/<rest>
      Standard tilde expansion via $HOME so TOML values are portable.
    """
    if script.startswith('$CLAUDE_HOME/'):
        return '$HOME/.claude/' + script[len('$CLAUDE_HOME/'):]
    if script.startswith('~/'):
        return '$HOME' + script[1:]
    return script

def canonical_json(value):
    """Sort object keys recursively for canonical JSON."""
    if isinstance(value, dict):
        return {k: canonical_json(value[k]) for k in sorted(value.keys())}
    elif isinstance(value, list):
        return [canonical_json(item) for item in value]
    return value

def compute_hook_hash(command, matcher=None, timeout_sec=600):
    """
    Compute version_for_toml hash for a command hook (mirrors Codex Rust impl).
    Hash = sha256(canonical_json(NormalizedHookIdentity as TOML->JSON)).
    NormalizedHookIdentity { event_name, [matcher], hooks: [{type,command,timeout,async}] }
    None/Option fields are omitted (TOML has no null).
    command_windows=None and status_message=None are skipped.
    """
    hook_entry = {
        "type": "command",
        "command": command,
        "timeout": timeout_sec,
        "async": False,
    }
    identity = {"event_name": "pre_tool_use", "hooks": [hook_entry]}
    if matcher is not None:
        identity["matcher"] = matcher
    canonical = canonical_json(identity)
    serialized = json.dumps(canonical, separators=(',', ':')).encode('utf-8')
    return "sha256:" + hashlib.sha256(serialized).hexdigest()

def hook_state_key(config_realpath, event_label, group_idx, handler_idx):
    return f"{config_realpath}:{event_label}:{group_idx}:{handler_idx}"

from collections import OrderedDict

# Codex subset: only PreToolUse-class events are supported by Codex.
# Lifecycle events (SessionStart, SessionEnd, PreCompact, Stop, PermissionRequest)
# have no Codex analog and MUST NOT be projected to config.toml.
# (ADR-002 D2: per-harness projection is an event-axis SUBSET.)
CODEX_SUPPORTED_EVENTS = {'PreToolUse'}

# {ccEvent: {matcher: [command_str]}}
event_groups = OrderedDict()

for entry in manifest.get('hooks', []):
    cc_event = entry.get('ccEvent', 'PreToolUse')

    # Skip lifecycle events — not supported by Codex (subset projection).
    if cc_event not in CODEX_SUPPORTED_EVENTS:
        continue

    # Skip entries with no script (CC-only lifecycle entries).
    script = entry.get('script', '')
    if not script:
        continue

    matcher = entry.get('matcher', '')
    script_args = entry.get('scriptArgs', [])
    output_format = entry.get('outputFormat', '')

    script = expand_home(script)

    if output_format == 'json':
        # dcg protocol: route through the generated adapter script.
        # The adapter reads tool_input from stdin and emits Codex wire shape.
        command = dcg_adapter_path
    else:
        # cc-hook or exit-code: script already outputs Codex wire shape (or exits non-zero)
        parts = [script] + [f'"{a}"' if ' ' in a else a for a in script_args]
        command = ' '.join(parts)

    if cc_event not in event_groups:
        event_groups[cc_event] = OrderedDict()
    if matcher not in event_groups[cc_event]:
        event_groups[cc_event][matcher] = []
    event_groups[cc_event][matcher].append(command)

# Managed-block markers: the ENTIRE dotpi hooks region (including [hooks.*] and
# [hooks.state.*] sub-tables) is wrapped in BEGIN/END markers on every emit.
# Strip uses a simple string search for these markers — immune to sub-table lookahead bugs.
MANAGED_BEGIN = '# >>> dotpi managed hooks >>>'
MANAGED_END = '# <<< dotpi managed hooks <<<'

# Read existing config.toml (if it exists) and strip old managed hooks region.
if os.path.exists(config_path):
    with open(config_path, 'r', encoding='utf-8') as f:
        existing = f.read()
    # Strip the entire managed block (new-style: marker-delimited).
    while MANAGED_BEGIN in existing and MANAGED_END in existing:
        begin_idx = existing.index(MANAGED_BEGIN)
        end_idx = existing.index(MANAGED_END, begin_idx) + len(MANAGED_END)
        existing = existing[:begin_idx] + existing[end_idx:]
    # Strip any pre-marker legacy hooks content (old-style: emitted by .8 without markers).
    # This handles TWO legacy patterns:
    #   1. Orphaned [hooks.state.*] entries that accumulated before the [hooks] table
    #      (the .8 bug: strip stopped at first sub-table, leaving orphaned state entries).
    #   2. The [hooks] table + [[hooks.PreToolUse]] + trailing [hooks.state.*] entries.
    # Strategy: scan line-by-line. A line "belongs" to the dotpi hooks block if it starts
    # with [hooks (any sub-table), [[hooks, or is a dotpi comment/blank between such lines.
    # We collect contiguous runs of hooks-related lines and remove them all.
    lines = existing.splitlines()
    cleaned_lines = []
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        # Detect start of a hooks block: [hooks], [[hooks.*]], [hooks.*], or dotpi comments
        is_hooks_line = (
            stripped == '[hooks]'
            or stripped.startswith('[[hooks.')
            or stripped.startswith('[hooks.')
            or stripped.startswith('# dotpi hooks')
            or stripped.startswith('# dotpi hook trust seeds')
        )
        if is_hooks_line:
            # Skip this line and all subsequent lines that are part of this hooks block.
            # A hooks block ends when we hit a non-empty, non-comment line that is NOT
            # a [hooks*] header, NOT a key=value pair after a hooks header, and is a
            # new top-level TOML table (starts with '[' but not '[hooks').
            # We consume: headers, key=value lines, blank lines, comments.
            # We stop at: a [non-hooks] table header.
            j = i
            while j < len(lines):
                s = lines[j].strip()
                if s and s.startswith('[') and not s.startswith('[hooks') and not s.startswith('[[hooks'):
                    break  # next section — stop consuming
                j += 1
            i = j  # skip the hooks block entirely
        else:
            cleaned_lines.append(lines[i])
            i += 1
    existing = '\n'.join(cleaned_lines).rstrip()
else:
    existing = ''

# Build the [hooks] section in Codex array-of-tables TOML format.
# Schema per codex-rs/config/src/hook_config.rs HookEventsToml + MatcherGroup + HookHandlerConfig:
#   [hooks]
#   [[hooks.PreToolUse]]        ← MatcherGroup
#   matcher = "Bash"            ← optional regex
#   [[hooks.PreToolUse.hooks]]  ← HookHandlerConfig {type = "command", command = "..."}
#   type = "command"
#   command = "..."
hook_lines = [
    '',
    MANAGED_BEGIN,
    '# dotpi hooks — generated from agent/hooks-manifest.json by install.sh',
    '# Codex wire shape: stdout JSON {hookSpecificOutput:{permissionDecision,permissionDecisionReason}}.',
    '# DIVERGENCE: PreToolUse supports only "deny"; "ask" is unsupported → fail-open.',
    '[hooks]',
    '',
]

# Collect trust state entries while building TOML.
# key_source = realpath of config.toml (as Codex's discover_handlers sets key_source).
config_realpath = os.path.realpath(config_path)
trust_state_entries = []  # list of (key, hash_val)

for event, matchers in event_groups.items():
    # Codex discovery uses snake_case event label for state keys.
    event_label = re.sub(r'(?<=[a-z])(?=[A-Z])', '_', event).lower()  # PreToolUse -> pre_tool_use
    group_idx = 0
    for matcher, commands in matchers.items():
        hook_lines.append(f'[[hooks.{event}]]')
        if matcher:
            hook_lines.append(f'matcher = {toml_str(matcher)}')
        hook_lines.append('')
        handler_idx = 0
        for command in commands:
            hook_lines.append(f'[[hooks.{event}.hooks]]')
            hook_lines.append('type = "command"')
            hook_lines.append(f'command = {toml_str(command)}')
            hook_lines.append('')
            # Compute trust hash: matcher_pattern_for_event returns matcher for PreToolUse.
            matcher_for_hash = matcher if matcher else None
            h = compute_hook_hash(command, matcher=matcher_for_hash)
            key = hook_state_key(config_realpath, event_label, group_idx, handler_idx)
            trust_state_entries.append((key, h))
            handler_idx += 1
        group_idx += 1

# Build [hooks.state] trust seed section.
# trusted_hash pre-seeds Trusted status so hooks fire without bypass_hook_trust=true.
state_lines = [
    '',
    '# dotpi hook trust seeds — pre-seeded so hooks fire without interactive approval.',
    '# Codex trust: trusted_hash matches current_hash → HookTrustStatus::Trusted.',
    '# Recomputed on every install.sh run; stale entries (different command) are inert.',
]
for key, hash_val in trust_state_entries:
    state_lines.append(f'[hooks.state.{toml_str(key)}]')
    state_lines.append(f'trusted_hash = {toml_str(hash_val)}')
    state_lines.append('enabled = true')
    state_lines.append('')
state_lines.append(MANAGED_END)
state_lines.append('')

new_content = existing + '\n' + '\n'.join(hook_lines) + '\n'.join(state_lines)

with open(config_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"Merged [hooks] table and trust seeds into Codex config: {config_path}")
PYEOF

echo "Merged Codex hooks into: $CODEX_CONFIG_TOML"

# 2c. Remove stale ~/.codex/hooks.toml — old-wiring artifact from a prior schema.
#     Codex 0.137.0 never reads hooks.toml; it reads hooks only from config.toml or hooks.json.
#     Leaving it in place is misleading; remove silently.
rm -f "$CODEX_DIR/hooks.toml"

# 3. Skills → direct share: symlink agent/skills/ into Codex skills discovery root
#    Skills are native SKILL.md (same shape as CC) — direct symlink, no transformation needed.
#    Discovery root: $CODEX_SKILLS_ROOT (~/.agents/skills)
link_relative "$ROOT/agent/skills" "$CODEX_SKILLS_ROOT"

# ─── Methodology phase ────────────────────────────────────────────────────────
# Install methodology assets into the target's $CLAUDE_SKILLS, $CLAUDE_HOOKS,
# $CLAUDE_DECISIONS, and $CLAUDE_HOME/AGENTS.md. These are CC-home-only assets (not pi/Codex).
# Per-item links only — skills/ may hold foreign skills; never whole-dir link.

CLAUDE_SKILLS="$TARGET_HOME/.claude/skills"
CLAUDE_HOOKS="$TARGET_HOME/.claude/hooks"
CLAUDE_DECISIONS="$TARGET_HOME/.claude/docs/decisions"

mkdir -p "$CLAUDE_SKILLS"
mkdir -p "$CLAUDE_HOOKS"
mkdir -p "$CLAUDE_DECISIONS"

# Per-skill symlinks: one link per skill dir in methodology/skills/
shopt -s nullglob
for skill_src in "$ROOT/methodology/skills/"*/; do
  skill_name="$(basename "$skill_src")"
  skill_link="$CLAUDE_SKILLS/$skill_name"
  link_relative "$skill_src" "$skill_link"
done
shopt -u nullglob

# browser-automation re-point: single canonical copy lives in agent/skills/;
# methodology .claude/skills/ carries a cross-bin link so CC home has it too.
# (ADR-002 D2: the cross-bin link lives in the install layer, not the runner files.)
link_relative "$ROOT/agent/skills/browser-automation" "$CLAUDE_SKILLS/browser-automation"

# Per-file symlinks: one link per file in methodology/hooks/
shopt -s nullglob
for hook_src in "$ROOT/methodology/hooks/"*; do
  hook_name="$(basename "$hook_src")"
  hook_link="$CLAUDE_HOOKS/$hook_name"
  link_relative "$hook_src" "$hook_link"
done
shopt -u nullglob

# Per-file symlinks: one link per file in docs/decisions/
shopt -s nullglob
for decision_src in "$ROOT/docs/decisions/"*; do
  decision_name="$(basename "$decision_src")"
  decision_link="$CLAUDE_DECISIONS/$decision_name"
  link_relative "$decision_src" "$decision_link"
done
shopt -u nullglob

# methodology/AGENTS.md → $TARGET_HOME/.claude/AGENTS.md
link_relative "$ROOT/methodology/AGENTS.md" "$TARGET_HOME/.claude/AGENTS.md"

echo "harness installed. In pi, run /reload if already open."
