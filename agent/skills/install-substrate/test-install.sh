#!/usr/bin/env bash
# Test harness for install-substrate:
# - Creates a throwaway target directory
# - Runs install.sh against it
# - Verifies all symlinks resolve to dotpi source
# - Verifies role files are byte-identical to source (symlink, not copy)
# - Verifies no host dotfiles were mutated
# RED: before install.sh is updated, this FAILS on missing roles and relative links

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTPI_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Create throwaway target inside $HOME so relative symlinks resolve correctly.
# (On macOS, /tmp -> /private/tmp which doesn't share the path tree with $HOME,
# so relative symlinks from /tmp to ~/... would dangle. Using $HOME/tmp/ keeps
# all paths under the same root, matching real install behavior.)
mkdir -p "$HOME/tmp"
TARGET_DIR=$(mktemp -d "$HOME/tmp/install-target-XXXX")
PI_AGENT="$TARGET_DIR/.pi/agent"
CLAUDE_DIR="$TARGET_DIR/.claude"
mkdir -p "$PI_AGENT"
mkdir -p "$CLAUDE_DIR/agents"

echo "=== Install test target: $TARGET_DIR ==="
echo "=== dotpi root: $DOTPI_ROOT ==="

PASS=0
FAIL=0

check() {
  local label="$1"
  local result="$2"
  if [ "$result" = "ok" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label ($result)"
    FAIL=$((FAIL + 1))
  fi
}

# Run install against throwaway target
echo ""
echo "--- Running install.sh against throwaway target ---"
DOTPI_TEST_TARGET="$TARGET_DIR" bash "$DOTPI_ROOT/install.sh"
echo ""

echo "--- Verifying symlinks ---"

# 1. extensions symlink exists and is relative
EXT_LINK="$PI_AGENT/extensions"
if [ -L "$EXT_LINK" ]; then
  raw=$(readlink "$EXT_LINK")
  if [[ "$raw" != /* ]]; then
    check "extensions link is relative" "ok"
  else
    check "extensions link is relative" "absolute: $raw"
  fi
  # resolves to correct target
  resolved=$(cd "$(dirname "$EXT_LINK")" && cd "$raw" && pwd)
  if [ "$resolved" = "$DOTPI_ROOT/agent/extensions" ]; then
    check "extensions resolves to dotpi source" "ok"
  else
    check "extensions resolves to dotpi source" "got: $resolved"
  fi
else
  check "extensions symlink exists" "missing"
fi

# 2. skills symlink exists and is relative
SKL_LINK="$PI_AGENT/skills"
if [ -L "$SKL_LINK" ]; then
  raw=$(readlink "$SKL_LINK")
  if [[ "$raw" != /* ]]; then
    check "skills link is relative" "ok"
  else
    check "skills link is relative" "absolute: $raw"
  fi
  resolved=$(cd "$(dirname "$SKL_LINK")" && cd "$raw" && pwd)
  if [ "$resolved" = "$DOTPI_ROOT/agent/skills" ]; then
    check "skills resolves to dotpi source" "ok"
  else
    check "skills resolves to dotpi source" "got: $resolved"
  fi
else
  check "skills symlink exists" "missing"
fi

# 3. prompts symlink
PRO_LINK="$PI_AGENT/prompts"
if [ -L "$PRO_LINK" ]; then
  check "prompts symlink exists" "ok"
else
  check "prompts symlink exists" "missing"
fi

# 4. roles dir symlink in ~/.pi/agent/roles
ROLES_LINK="$PI_AGENT/roles"
if [ -L "$ROLES_LINK" ]; then
  raw=$(readlink "$ROLES_LINK")
  if [[ "$raw" != /* ]]; then
    check "roles link is relative" "ok"
  else
    check "roles link is relative" "absolute: $raw"
  fi
  resolved=$(cd "$(dirname "$ROLES_LINK")" && cd "$raw" && pwd)
  if [ "$resolved" = "$DOTPI_ROOT/agent/roles" ]; then
    check "roles resolves to dotpi source" "ok"
  else
    check "roles resolves to dotpi source" "got: $resolved"
  fi
else
  check "roles symlink in .pi/agent" "missing"
fi

# 5. Each role file linked individually into the methodology home's agents/
echo ""
echo "--- Verifying per-role links in .claude/agents ---"
for role_src in "$DOTPI_ROOT/agent/roles/"*.md; do
  role_name=$(basename "$role_src")
  role_link="$CLAUDE_DIR/agents/$role_name"
  if [ -L "$role_link" ]; then
    # verify relative
    raw=$(readlink "$role_link")
    if [[ "$raw" != /* ]]; then
      check "role $role_name link is relative" "ok"
    else
      check "role $role_name link is relative" "absolute: $raw"
    fi
    # verify byte-identical (symlink, not a copy)
    resolved=$(cd "$(dirname "$role_link")" && realpath "$raw" 2>/dev/null || cd "$(dirname "$role_link")" && cd "$(dirname "$raw")" && echo "$(pwd)/$(basename "$raw")")
    if diff "$role_src" "$role_link" > /dev/null 2>&1; then
      check "role $role_name byte-identical to source" "ok"
    else
      check "role $role_name byte-identical to source" "diff found"
    fi
    # verify both model: and pi-model: fields present
    if grep -q "^model:" "$role_link"; then
      check "role $role_name has model: field" "ok"
    else
      check "role $role_name has model: field" "missing"
    fi
    if grep -q "^pi-model:" "$role_link"; then
      check "role $role_name has pi-model: field" "ok"
    else
      check "role $role_name has pi-model: field" "missing"
    fi
  else
    check "role $role_name linked to .claude/agents" "missing"
  fi
done

# 6. AGENTS.md file link — relative AND resolves to dotpi source
AGENTS_LINK="$PI_AGENT/AGENTS.md"
if [ -L "$AGENTS_LINK" ]; then
  raw=$(readlink "$AGENTS_LINK")
  if [[ "$raw" != /* ]]; then
    check "AGENTS.md link is relative" "ok"
  else
    check "AGENTS.md link is relative" "absolute: $raw"
  fi
  # F5: verify resolution
  resolved=$(cd "$(dirname "$AGENTS_LINK")" && realpath "$raw" 2>/dev/null || echo "")
  if [ "$resolved" = "$DOTPI_ROOT/agent/AGENTS.md" ]; then
    check "AGENTS.md resolves to dotpi source" "ok"
  else
    check "AGENTS.md resolves to dotpi source" "got: $resolved"
  fi
else
  check "AGENTS.md symlink exists" "missing"
fi

# 6b. keybindings.json link — relative AND resolves to dotpi source (F5)
KB_LINK="$PI_AGENT/keybindings.json"
if [ -L "$KB_LINK" ]; then
  raw=$(readlink "$KB_LINK")
  if [[ "$raw" != /* ]]; then
    check "keybindings.json link is relative" "ok"
  else
    check "keybindings.json link is relative" "absolute: $raw"
  fi
  # F5: verify resolution
  resolved=$(cd "$(dirname "$KB_LINK")" && realpath "$raw" 2>/dev/null || echo "")
  if [ "$resolved" = "$DOTPI_ROOT/agent/keybindings.json" ]; then
    check "keybindings.json resolves to dotpi source" "ok"
  else
    check "keybindings.json resolves to dotpi source" "got: $resolved"
  fi
else
  check "keybindings.json symlink exists" "missing"
fi

# 7. No host dotfiles mutated — check ~/.pi and the methodology home weren't touched
echo ""
echo "--- Verifying host dotfiles not mutated ---"
# The actual ~/.pi/agent should still have its original symlinks
# (We check that nothing in the real home dirs was changed by install test)
if [ -L "${HOME}/.pi/agent/skills" ]; then
  orig_target=$(readlink "${HOME}/.pi/agent/skills")
  if [[ "$orig_target" == *"$TARGET_DIR"* ]]; then
    check "host ~/.pi/agent/skills not mutated by test" "mutated!"
  else
    check "host ~/.pi/agent/skills not mutated by test" "ok"
  fi
else
  check "host ~/.pi/agent/skills not mutated by test" "ok (doesn't exist)"
fi

# 8. SKILL.md content assertions (F4 — harness invalidation predicate)
echo ""
echo "--- Verifying SKILL.md discipline content ---"
SKILL_MD="$DOTPI_ROOT/agent/skills/install-substrate/SKILL.md"
if grep -q "Host vs. container" "$SKILL_MD" || grep -q "Host vs container" "$SKILL_MD" || grep -q "Host vs. cage" "$SKILL_MD" || grep -q "Host vs cage" "$SKILL_MD"; then
  check "SKILL.md contains host-vs-container distinction" "ok"
else
  check "SKILL.md contains host-vs-container distinction" "missing"
fi
if grep -q "relies.on" "$SKILL_MD" || grep -q "relies on" "$SKILL_MD"; then
  check "SKILL.md contains sandbox relies-on language" "ok"
else
  check "SKILL.md contains sandbox relies-on language" "missing"
fi
if grep -q "containerized-agent" "$SKILL_MD" || grep -q "sandbox" "$SKILL_MD"; then
  check "SKILL.md references container sandbox" "ok"
else
  check "SKILL.md references container sandbox" "missing"
fi
if grep -q '\$SKILL' "$SKILL_MD"; then
  check "SKILL.md contains \$SKILL convention" "ok"
else
  check "SKILL.md contains \$SKILL convention" "missing"
fi

# 9. Backup-not-destroy test (F6): a symlink pointing ELSEWHERE must be backed up, not silently deleted
echo ""
echo "--- Verifying backup-not-destroy safety for foreign symlinks ---"
# Pick the first role name we know exists
FIRST_ROLE_SRC=$(ls "$DOTPI_ROOT/agent/roles/"*.md 2>/dev/null | head -1)
if [ -z "$FIRST_ROLE_SRC" ]; then
  check "F6 test: at least one role .md exists" "no roles found"
else
  FIRST_ROLE_NAME=$(basename "$FIRST_ROLE_SRC")
  # macOS mktemp does not support non-X suffixes; use a plain template then rename
  FOREIGN_TARGET_BASE=$(mktemp "$HOME/tmp/foreign-agent-XXXX")
  FOREIGN_TARGET="${FOREIGN_TARGET_BASE}.md"
  mv "$FOREIGN_TARGET_BASE" "$FOREIGN_TARGET"
  echo "# foreign agent" > "$FOREIGN_TARGET"
  AGENT_LINK="$CLAUDE_DIR/agents/$FIRST_ROLE_NAME"

  # Pre-plant a symlink pointing to a DIFFERENT file (simulates a real CC agent symlink)
  ln -sf "$FOREIGN_TARGET" "$AGENT_LINK"

  # Re-run install — backup_existing should back it up, not destroy it
  DOTPI_TEST_TARGET="$TARGET_DIR" bash "$DOTPI_ROOT/install.sh" > /dev/null 2>&1

  # The foreign target file must still exist (not deleted)
  if [ -f "$FOREIGN_TARGET" ]; then
    check "F6: foreign symlink target not destroyed" "ok"
  else
    check "F6: foreign symlink target not destroyed" "target was deleted"
  fi

  # A .backup.<ts> file must exist next to the original link path
  BACKUP_COUNT=$(ls "$CLAUDE_DIR/agents/${FIRST_ROLE_NAME}.backup."* 2>/dev/null | wc -l | tr -d ' ')
  if [ "$BACKUP_COUNT" -gt 0 ]; then
    check "F6: foreign symlink was backed up (not silently destroyed)" "ok"
  else
    check "F6: foreign symlink was backed up (not silently destroyed)" "no backup found"
  fi

  # A NEW symlink pointing to dotpi must exist (install completed)
  if [ -L "$AGENT_LINK" ]; then
    new_target=$(readlink "$AGENT_LINK")
    # Should now point into dotpi, not the foreign target
    resolved_new=$(cd "$(dirname "$AGENT_LINK")" && realpath "$new_target" 2>/dev/null || echo "")
    if [ "$resolved_new" = "$FIRST_ROLE_SRC" ]; then
      check "F6: new symlink points to dotpi source after backup" "ok"
    else
      check "F6: new symlink points to dotpi source after backup" "got: $resolved_new"
    fi
  else
    check "F6: new symlink created after backup" "no symlink"
  fi

  rm -f "$FOREIGN_TARGET"
fi

CODEX_DIR="$TARGET_DIR/.codex"
CODEX_AGENTS="$CODEX_DIR/agents"
CODEX_CONFIG_TOML="$CODEX_DIR/config.toml"
CODEX_SKILLS_ROOT="$TARGET_DIR/.agents/skills"

# 10. Codex role TOML generation (a): generated TOML parses and carries required fields
echo ""
echo "--- Verifying Codex role TOML generation ---"
for role_src in "$DOTPI_ROOT/agent/roles/"*.md; do
  role_name=$(basename "$role_src" .md)
  toml_file="$CODEX_AGENTS/$role_name.toml"
  if [ -f "$toml_file" ]; then
    check "Codex TOML generated for $role_name" "ok"
    # (a) Parse validation via tomllib (stdlib 3.11+, NOT grep).
    # Uses `uv run python3` to ensure Python 3.11+ is available (repo mandates uv).
    parse_result=$(uv run python3 -c "
import tomllib, sys
with open('$toml_file', 'rb') as f:
    d = tomllib.load(f)
missing = []
for field in ('name', 'description', 'developer_instructions', 'model', 'model_provider'):
    if not d.get(field):
        missing.append(field)
if missing:
    print('MISSING: ' + ', '.join(missing))
    sys.exit(1)
print('OK')
" 2>&1)
    if [ "$parse_result" = "OK" ]; then
      check "Codex TOML $role_name: tomllib parse + required fields present" "ok"
    else
      check "Codex TOML $role_name: tomllib parse + required fields present" "$parse_result"
    fi
  else
    check "Codex TOML generated for $role_name" "missing: $toml_file"
    check "Codex TOML $role_name: tomllib parse + required fields present" "no file to parse"
  fi
done

# (b) Codex hooks merged into config.toml with [[hooks.PreToolUse]] array-of-tables schema
echo ""
echo "--- Verifying Codex hooks merged into config.toml ---"
if [ -f "$CODEX_CONFIG_TOML" ]; then
  check "Codex config.toml emitted" "ok"
  # Uses `uv run python3` because bare python3 on this system is 3.9 which lacks
  # tomllib (stdlib only in 3.11+). uv provides a 3.11+ interpreter — load-bearing
  # property (real tomllib parse, not grep) is preserved.
  hooks_parse=$(uv run python3 -c "
import tomllib, sys
with open('$CODEX_CONFIG_TOML', 'rb') as f:
    d = tomllib.load(f)
hooks = d.get('hooks', {})
if not hooks:
    print('NO_HOOKS_TABLE')
    sys.exit(1)
# Expect hooks.PreToolUse as an array-of-tables (list of dicts with optional matcher key)
pre_tool_use = hooks.get('PreToolUse', [])
if not pre_tool_use:
    print('NO_PRETOOLUSE_ENTRIES')
    sys.exit(1)
# Verify each entry is a dict with a 'hooks' key (list of handler dicts with 'type' and 'command')
found_handler = False
for group in pre_tool_use:
    if not isinstance(group, dict):
        print('INVALID_GROUP_TYPE')
        sys.exit(1)
    for handler in group.get('hooks', []):
        if isinstance(handler, dict) and handler.get('type') == 'command' and 'command' in handler:
            found_handler = True
if not found_handler:
    print('NO_COMMAND_HANDLERS')
    sys.exit(1)
print('OK - hooks.PreToolUse groups:', len(pre_tool_use))
" 2>&1)
  if echo "$hooks_parse" | grep -q "^OK"; then
    check "Codex config.toml: [[hooks.PreToolUse]] array-of-tables with command handlers" "ok"
  else
    check "Codex config.toml: [[hooks.PreToolUse]] array-of-tables with command handlers" "$hooks_parse"
  fi
  # Also verify the old hooks.toml is NOT created (wrong file)
  if [ -f "$CODEX_DIR/hooks.toml" ]; then
    check "Codex hooks.toml NOT created (wrong file — must not exist)" "hooks.toml exists (FAIL)"
  else
    check "Codex hooks.toml NOT created (wrong file — must not exist)" "ok"
  fi
else
  check "Codex config.toml emitted" "missing: $CODEX_CONFIG_TOML"
  check "Codex config.toml: [[hooks.PreToolUse]] array-of-tables with command handlers" "no file"
  check "Codex hooks.toml NOT created (wrong file — must not exist)" "cannot check (config.toml missing)"
fi

# (c) Skills SKILL.md folders resolve under Codex discovery root
echo ""
echo "--- Verifying Codex skills root ---"
if [ -d "$CODEX_SKILLS_ROOT" ] || [ -L "$CODEX_SKILLS_ROOT" ]; then
  check "Codex skills root exists" "ok"
  # Verify at least one SKILL.md is reachable under the skills root.
  # -L: follow symlinks (the root is a symlink so -L is required to traverse it)
  skill_count=$(find -L "$CODEX_SKILLS_ROOT" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$skill_count" -gt 0 ]; then
    check "Codex skills root: SKILL.md files resolve ($skill_count found)" "ok"
  else
    check "Codex skills root: SKILL.md files resolve" "none found under $CODEX_SKILLS_ROOT"
  fi
else
  check "Codex skills root exists" "missing: $CODEX_SKILLS_ROOT"
  check "Codex skills root: SKILL.md files resolve" "no root"
fi

# (d) git diff of the four runner files is EMPTY
echo ""
echo "--- Verifying runner files untouched (D2 invariant) ---"
RUNNER_FILES=(
  "agent/extensions/subagent/role-loader.mjs"
  "agent/extensions/subagent/index.ts"
  "agent/extensions/hooks/core.mjs"
  "agent/extensions/hooks/index.ts"
)
all_runner_clean=true
for rf in "${RUNNER_FILES[@]}"; do
  diff_out=$(git -C "$DOTPI_ROOT" diff HEAD -- "$rf" 2>/dev/null)
  staged_diff=$(git -C "$DOTPI_ROOT" diff --cached -- "$rf" 2>/dev/null)
  if [ -z "$diff_out" ] && [ -z "$staged_diff" ]; then
    check "Runner file untouched: $rf" "ok"
  else
    check "Runner file untouched: $rf" "has diff (D2 violation)"
    all_runner_clean=false
  fi
done

# (e) SKILL.md no longer contains stale pure-symlink / no-per-harness-transform claims
echo ""
echo "--- Verifying SKILL.md stale claims removed (assertion e) ---"
SKILL_MD="$DOTPI_ROOT/agent/skills/install-substrate/SKILL.md"
if grep -q "no keyword-keyed mapping table and no per-harness transform" "$SKILL_MD"; then
  check "SKILL.md stale pure-symlink / no-per-harness-transform claim removed" "STILL PRESENT (must be removed)"
else
  check "SKILL.md stale pure-symlink / no-per-harness-transform claim removed" "ok"
fi

# (f) SKILL.md DOES contain the ask-fails-open Codex divergence note.
# Proximity check: look for "fail-open" or "fail open" within 2 lines of "ask"
# so the two concepts must co-occur in the same divergence-note context.
if grep -A2 "ask" "$SKILL_MD" | grep -q "fail.open\|fail open"; then
  check "SKILL.md contains ask-fails-open Codex divergence note" "ok"
else
  check "SKILL.md contains ask-fails-open Codex divergence note" "missing"
fi

# 11. Idempotency test: running install.sh N times must yield exactly ONE
#     [hooks] table and ONE [hooks.state] entry per hook, and the result must be valid TOML.
#     Uses a THROWAWAY CODEX_HOME that is NOT the main TARGET_DIR (isolated from other tests).
echo ""
echo "--- Verifying Codex hooks emission IDEMPOTENCY ---"

IDEM_HOME=$(mktemp -d "$HOME/tmp/idem-target-XXXX")
IDEM_CODEX="$IDEM_HOME/.codex"
mkdir -p "$IDEM_CODEX"

# Run install.sh 3 times into the throwaway home
for i in 1 2 3; do
  DOTPI_TEST_TARGET="$IDEM_HOME" bash "$DOTPI_ROOT/install.sh" > /dev/null 2>&1
done

IDEM_CONFIG="$IDEM_CODEX/config.toml"

if [ -f "$IDEM_CONFIG" ]; then
  # Snapshot counts after 3 runs (pass config path as arg, always exits 0)
  RUN3_LINE=$(uv run python3 - "$IDEM_CONFIG" 2>&1 << 'PYEOF' || echo "PARSE_ERROR"
import tomllib, sys
with open(sys.argv[1], 'rb') as f:
    try:
        d = tomllib.load(f)
    except Exception as e:
        print(f'INVALID_TOML:{e}')
        sys.exit(0)
hooks = d.get('hooks', {})
state = hooks.get('state', {})
pre = hooks.get('PreToolUse', [])
print(f'pre={len(pre)},state={len(state)}')
PYEOF
)

  # Run a 4th time
  DOTPI_TEST_TARGET="$IDEM_HOME" bash "$DOTPI_ROOT/install.sh" > /dev/null 2>&1

  # Snapshot counts after 4 runs
  RUN4_LINE=$(uv run python3 - "$IDEM_CONFIG" 2>&1 << 'PYEOF' || echo "PARSE_ERROR"
import tomllib, sys
with open(sys.argv[1], 'rb') as f:
    try:
        d = tomllib.load(f)
    except Exception as e:
        print(f'INVALID_TOML:{e}')
        sys.exit(0)
hooks = d.get('hooks', {})
state = hooks.get('state', {})
pre = hooks.get('PreToolUse', [])
print(f'pre={len(pre)},state={len(state)}')
PYEOF
)

  if echo "$RUN3_LINE" | grep -q "^INVALID_TOML"; then
    check "Idempotency (after 3 runs): config.toml is valid TOML" "FAIL: $RUN3_LINE"
    check "Idempotency (run3->run4 stable): no accumulation of hook entries" "skipped (run3 invalid)"
  elif echo "$RUN4_LINE" | grep -q "^INVALID_TOML"; then
    check "Idempotency (after 3 runs): config.toml is valid TOML" "ok"
    check "Idempotency (run3->run4 stable): no accumulation of hook entries" "FAIL after run4: $RUN4_LINE"
  elif [ "$RUN3_LINE" = "$RUN4_LINE" ] && echo "$RUN3_LINE" | grep -qE "^pre=[1-9]"; then
    check "Idempotency (after 3 runs): config.toml is valid TOML" "ok"
    check "Idempotency (run3->run4 stable): no accumulation of hook entries [$RUN3_LINE]" "ok"
  elif [ "$RUN3_LINE" != "$RUN4_LINE" ]; then
    check "Idempotency (after 3 runs): config.toml is valid TOML" "ok"
    check "Idempotency (run3->run4 stable): no accumulation of hook entries" "FAIL: run3=$RUN3_LINE run4=$RUN4_LINE"
  else
    check "Idempotency (after 3 runs): config.toml is valid TOML" "unexpected: $RUN3_LINE"
    check "Idempotency (run3->run4 stable): no accumulation of hook entries" "unexpected state"
  fi
else
  check "Idempotency: config.toml generated after 3 runs" "missing: $IDEM_CONFIG"
  check "Idempotency (run3->run4 stable): no accumulation of hook entries" "no file"
fi

echo "Idempotency target dir: $IDEM_HOME (not cleaned up for inspection)"

# 12. Methodology phase assertions: each skill/hook/decision link exists, is relative,
#     resolves to harness/methodology/ (or harness/agent/skills/browser-automation), byte-identical.
echo ""
echo "--- Verifying methodology phase: skills ---"
CLAUDE_SKILLS_DIR="$TARGET_DIR/.claude/skills"
CLAUDE_HOOKS_DIR="$TARGET_DIR/.claude/hooks"
CLAUDE_DECISIONS_DIR="$TARGET_DIR/.claude/docs/decisions"
CLAUDE_AGENTS_MD="$TARGET_DIR/.claude/AGENTS.md"

for skill_src in "$DOTPI_ROOT/methodology/skills/"*/; do
  skill_name=$(basename "$skill_src")
  skill_link="$CLAUDE_SKILLS_DIR/$skill_name"
  if [ -L "$skill_link" ]; then
    raw=$(readlink "$skill_link")
    if [[ "$raw" != /* ]]; then
      check "methodology skill $skill_name link is relative" "ok"
    else
      check "methodology skill $skill_name link is relative" "absolute: $raw"
    fi
    resolved=$(cd "$(dirname "$skill_link")" && realpath "$raw" 2>/dev/null || echo "")
    expected="$DOTPI_ROOT/methodology/skills/$skill_name"
    if [ "$resolved" = "$expected" ]; then
      check "methodology skill $skill_name resolves to harness source" "ok"
    else
      check "methodology skill $skill_name resolves to harness source" "got: $resolved"
    fi
  else
    check "methodology skill $skill_name link exists" "missing: $skill_link"
  fi
done

# browser-automation cross-bin link: must point to agent/skills/browser-automation
echo ""
echo "--- Verifying browser-automation cross-bin link ---"
BA_LINK="$CLAUDE_SKILLS_DIR/browser-automation"
if [ -L "$BA_LINK" ]; then
  raw=$(readlink "$BA_LINK")
  if [[ "$raw" != /* ]]; then
    check "browser-automation link is relative" "ok"
  else
    check "browser-automation link is relative" "absolute: $raw"
  fi
  resolved=$(cd "$(dirname "$BA_LINK")" && realpath "$raw" 2>/dev/null || echo "")
  expected="$DOTPI_ROOT/agent/skills/browser-automation"
  if [ "$resolved" = "$expected" ]; then
    check "browser-automation resolves to agent/skills (cross-bin link)" "ok"
  else
    check "browser-automation resolves to agent/skills (cross-bin link)" "got: $resolved"
  fi
else
  check "browser-automation link exists" "missing: $BA_LINK"
fi

echo ""
echo "--- Verifying methodology phase: hooks ---"
for hook_src in "$DOTPI_ROOT/methodology/hooks/"*; do
  hook_name=$(basename "$hook_src")
  hook_link="$CLAUDE_HOOKS_DIR/$hook_name"
  if [ -L "$hook_link" ]; then
    raw=$(readlink "$hook_link")
    if [[ "$raw" != /* ]]; then
      check "methodology hook $hook_name link is relative" "ok"
    else
      check "methodology hook $hook_name link is relative" "absolute: $raw"
    fi
    resolved=$(cd "$(dirname "$hook_link")" && realpath "$raw" 2>/dev/null || echo "")
    expected="$DOTPI_ROOT/methodology/hooks/$hook_name"
    if [ "$resolved" = "$expected" ]; then
      check "methodology hook $hook_name resolves to harness source" "ok"
    else
      check "methodology hook $hook_name resolves to harness source" "got: $resolved"
    fi
    if diff "$hook_src" "$hook_link" > /dev/null 2>&1; then
      check "methodology hook $hook_name byte-identical to source" "ok"
    else
      check "methodology hook $hook_name byte-identical to source" "diff found"
    fi
  else
    check "methodology hook $hook_name link exists" "missing: $hook_link"
  fi
done

echo ""
echo "--- Verifying methodology phase: decisions ---"
for decision_src in "$DOTPI_ROOT/docs/decisions/"*; do
  decision_name=$(basename "$decision_src")
  decision_link="$CLAUDE_DECISIONS_DIR/$decision_name"
  if [ -L "$decision_link" ]; then
    raw=$(readlink "$decision_link")
    if [[ "$raw" != /* ]]; then
      check "decision $decision_name link is relative" "ok"
    else
      check "decision $decision_name link is relative" "absolute: $raw"
    fi
    resolved=$(cd "$(dirname "$decision_link")" && realpath "$raw" 2>/dev/null || echo "")
    expected="$DOTPI_ROOT/docs/decisions/$decision_name"
    if [ "$resolved" = "$expected" ]; then
      check "decision $decision_name resolves to harness source" "ok"
    else
      check "decision $decision_name resolves to harness source" "got: $resolved"
    fi
  else
    check "decision $decision_name link exists" "missing: $decision_link"
  fi
done

echo ""
echo "--- Verifying methodology AGENTS.md link ---"
if [ -L "$CLAUDE_AGENTS_MD" ]; then
  raw=$(readlink "$CLAUDE_AGENTS_MD")
  if [[ "$raw" != /* ]]; then
    check "methodology AGENTS.md link is relative" "ok"
  else
    check "methodology AGENTS.md link is relative" "absolute: $raw"
  fi
  resolved=$(cd "$(dirname "$CLAUDE_AGENTS_MD")" && realpath "$raw" 2>/dev/null || echo "")
  if [ "$resolved" = "$DOTPI_ROOT/methodology/AGENTS.md" ]; then
    check "methodology AGENTS.md resolves to harness source" "ok"
  else
    check "methodology AGENTS.md resolves to harness source" "got: $resolved"
  fi
  if diff "$DOTPI_ROOT/methodology/AGENTS.md" "$CLAUDE_AGENTS_MD" > /dev/null 2>&1; then
    check "methodology AGENTS.md byte-identical to source" "ok"
  else
    check "methodology AGENTS.md byte-identical to source" "diff found"
  fi
else
  check "methodology AGENTS.md link exists" "missing: $CLAUDE_AGENTS_MD"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
echo "Target dir: $TARGET_DIR (not cleaned up for inspection)"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "ALL PASS"
