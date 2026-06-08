#!/usr/bin/env bash
# doctor.sh — read-only health check for the harness
#
# Reports per-dep health (beads + CASSMS present AND matching the manifest version pin)
# and per-harness health (CC/pi/Codex wiring symlinks resolve into the harness tree;
# a named reference role round-trips structurally through the loader/compile).
#
# Reference role for structural round-trip: implementer
# (implementer.md is a stable, general-purpose role with standard frontmatter)
#
# One line per item: [ok] <description>  OR  [FAIL] <description>
# Summary tail with counts; exits non-zero if any item failed.
#
# READ-ONLY: this script must NOT create, modify, or delete anything.
#
# Environment:
#   TARGET_HOME           — harness installation root (default: $HOME)
#   HARNESS_ROOT          — path to the harness source tree (set by caller)
#   DOTPI_DEPS_MANIFEST   — path to deps.toml (default: <harness-root>/manifest/deps.toml)

set -euo pipefail

# HARNESS_ROOT and TARGET_HOME are set by the caller (install.sh)
HARNESS_ROOT="${HARNESS_ROOT:?HARNESS_ROOT must be set by caller}"
TARGET_HOME="${TARGET_HOME:-$HOME}"

MANIFEST="${DOTPI_DEPS_MANIFEST:-$HARNESS_ROOT/manifest/deps.toml}"

BIN_DIR="$TARGET_HOME/.local/bin"
PI_AGENT="$TARGET_HOME/.pi/agent"
CLAUDE_AGENTS="$TARGET_HOME/.claude/agents"
CLAUDE_SKILLS="$TARGET_HOME/.claude/skills"
CLAUDE_HOOKS="$TARGET_HOME/.claude/hooks"
CLAUDE_DECISIONS="$TARGET_HOME/.claude/docs/decisions"
CODEX_AGENTS="$TARGET_HOME/.codex/agents"
CODEX_CONFIG_TOML="$TARGET_HOME/.codex/config.toml"

# Reference role for structural round-trip check
REFERENCE_ROLE="implementer"

# ---------------------------------------------------------------------------
# Tracking
# ---------------------------------------------------------------------------
OK_COUNT=0
FAIL_COUNT=0

ok_item() {
  printf '[ok]   %s\n' "$*"
  OK_COUNT=$((OK_COUNT + 1))
}

fail_item() {
  printf '[FAIL] %s\n' "$*"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ---------------------------------------------------------------------------
# Arch detection (mirrors provision-deps.sh)
# ---------------------------------------------------------------------------
detect_arch() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  if [ "$os" = "Darwin" ]; then
    if [ "$arch" = "arm64" ]; then echo "darwin-arm64"
    else echo "darwin-amd64"
    fi
  elif [ "$os" = "Linux" ]; then
    if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then echo "linux-arm64"
    else echo "linux-amd64"
    fi
  else
    echo "unknown-$(uname -m)"
  fi
}

# ---------------------------------------------------------------------------
# Parse manifest deps for the current arch → emit NAME|BIN|VERSION|VERIFY lines
# (mirrors provision-deps.sh parse_deps, read-only subset)
# ---------------------------------------------------------------------------
parse_deps_for_doctor() {
  local arch="$1"
  uv run python3 - "$MANIFEST" "$arch" <<'PYEOF'
import sys
import tomllib

manifest_path = sys.argv[1]
target_arch = sys.argv[2]

with open(manifest_path, 'rb') as f:
    data = tomllib.load(f)

deps = data.get('dep', [])
seen_names = set()

for dep in deps:
    dep_arch = dep.get('arch', '')
    dep_name = dep.get('name', '')
    # Also match linux-amd64 against linux-x64 (CASSMS naming)
    arch_match = (dep_arch == target_arch)
    if not arch_match:
        norm_dep = dep_arch.replace('-x64', '-amd64')
        norm_target = target_arch.replace('-x64', '-amd64')
        arch_match = (norm_dep == norm_target)
    if not arch_match:
        continue
    if dep_name in seen_names:
        continue
    seen_names.add(dep_name)
    bin_name = dep.get('bin', dep_name)
    version = dep.get('version', '')
    verify = dep.get('verify', '')
    parts = [dep_name, bin_name, version, verify]
    print('|'.join(p.replace('|', '_') for p in parts))
PYEOF
}

# ---------------------------------------------------------------------------
# Per-dep health checks
# ---------------------------------------------------------------------------
check_deps() {
  local arch
  arch="$(detect_arch)"

  local deps_data
  deps_data="$(parse_deps_for_doctor "$arch")"

  if [ -z "$deps_data" ]; then
    fail_item "deps: no deps found for arch '$arch' in manifest (cannot check)"
    return
  fi

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    IFS='|' read -r dep_name bin_name pinned_version verify_cmd <<< "$line"

    local bin_path="$BIN_DIR/$bin_name"

    # Check 1: binary present in target bin dir
    if [ ! -f "$bin_path" ]; then
      fail_item "dep/$dep_name: binary '$bin_name' not found at $bin_path"
      continue
    fi

    # Check 2: version matches pin (word-boundary match — same as provision already_installed)
    local actual_version_output=""
    if ! actual_version_output="$(PATH="$BIN_DIR:$PATH" $verify_cmd 2>/dev/null)"; then
      fail_item "dep/$dep_name: '$verify_cmd' failed (binary present but not executable or erroring)"
      continue
    fi

    if echo "$actual_version_output" | grep -qFw "$pinned_version"; then
      ok_item "dep/$dep_name: $bin_name present @ $pinned_version"
    else
      local actual_ver_short
      actual_ver_short="$(echo "$actual_version_output" | head -1 | tr -d '\n')"
      fail_item "dep/$dep_name: version mismatch — pin=$pinned_version, got: $actual_ver_short"
    fi
  done <<< "$deps_data"
}

# ---------------------------------------------------------------------------
# Resolve a symlink's target path without following filesystem symlinks
# (os.path.normpath handles ../.. traversal; avoids macOS /private prefix issues
# that os.path.realpath introduces for paths under /var/folders).
# Arguments: $1 = base dir (parent of the symlink), $2 = raw symlink target
# Outputs: the normalised absolute path (stdout)
# ---------------------------------------------------------------------------
python_normpath() {
  local base="$1"
  local rel="$2"
  python3 -c "
import os.path
joined = os.path.join('$base', '$rel')
print(os.path.normpath(joined))
" 2>/dev/null
}

# Normalise an absolute path using normpath (no symlink following, consistent prefixes)
normalise_path() {
  python3 -c "import os.path; print(os.path.normpath('$1'))" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Check that a symlink exists and resolves into the harness tree
# ---------------------------------------------------------------------------
check_symlink_into_harness() {
  local label="$1"   # human-readable name for the item
  local link="$2"    # absolute path to the symlink

  if [ ! -L "$link" ]; then
    fail_item "$label: symlink missing at $link"
    return
  fi

  local raw_target
  raw_target="$(readlink "$link" 2>/dev/null || true)"
  if [ -z "$raw_target" ]; then
    fail_item "$label: cannot readlink at $link"
    return
  fi

  # Resolve: join the symlink's parent dir with the raw (possibly relative) target.
  # Use normpath (not realpath) to avoid macOS /private prefix issues.
  local link_dir resolved
  link_dir="$(dirname "$link")"
  resolved="$(python_normpath "$link_dir" "$raw_target")"
  if [ -z "$resolved" ]; then
    fail_item "$label: symlink at $link is dangling (cannot resolve)"
    return
  fi

  # Normalise HARNESS_ROOT to handle /private prefix on macOS
  local harness_norm
  harness_norm="$(normalise_path "$HARNESS_ROOT")"

  # Must resolve INTO the harness tree (normalised comparison)
  if [[ "$resolved" == "$harness_norm/"* ]] || [ "$resolved" = "$harness_norm" ]; then
    ok_item "$label: symlink resolves into harness tree ($link → $resolved)"
  else
    fail_item "$label: symlink resolves outside harness tree ($link → $resolved)"
  fi
}

# ---------------------------------------------------------------------------
# Per-harness health checks
# ---------------------------------------------------------------------------
check_harness() {
  # ── pi wiring ────────────────────────────────────────────────────────────
  check_symlink_into_harness "pi/AGENTS.md"       "$PI_AGENT/AGENTS.md"
  check_symlink_into_harness "pi/keybindings"     "$PI_AGENT/keybindings.json"
  check_symlink_into_harness "pi/extensions"      "$PI_AGENT/extensions"
  check_symlink_into_harness "pi/prompts"         "$PI_AGENT/prompts"
  check_symlink_into_harness "pi/skills"          "$PI_AGENT/skills"
  check_symlink_into_harness "pi/roles"           "$PI_AGENT/roles"

  # ── CC wiring ────────────────────────────────────────────────────────────
  # Each role .md should be symlinked individually into $CLAUDE_AGENTS/
  shopt -s nullglob
  for role_src in "$HARNESS_ROOT/agent/roles/"*.md; do
    local role_name
    role_name="$(basename "$role_src")"
    check_symlink_into_harness "cc/agents/$role_name" "$CLAUDE_AGENTS/$role_name"
  done
  shopt -u nullglob

  # Methodology assets
  check_symlink_into_harness "cc/AGENTS.md"       "$TARGET_HOME/.claude/AGENTS.md"
  # Skills: check at least the browser-automation cross-bin link
  check_symlink_into_harness "cc/skills/browser-automation" "$CLAUDE_SKILLS/browser-automation"

  # ── Codex wiring ─────────────────────────────────────────────────────────
  # Codex role TOML files are compiled (not symlinked) — assert each exists and is non-empty.
  shopt -s nullglob
  for role_src in "$HARNESS_ROOT/agent/roles/"*.md; do
    local role_name
    role_name="$(basename "$role_src" .md)"
    local toml_path="$CODEX_AGENTS/$role_name.toml"
    if [ -f "$toml_path" ] && [ -s "$toml_path" ]; then
      ok_item "codex/agents/$role_name.toml: compiled TOML present"
    else
      fail_item "codex/agents/$role_name.toml: compiled TOML missing or empty at $toml_path"
    fi
  done
  shopt -u nullglob

  # Codex config.toml managed hooks block
  if [ -f "$CODEX_CONFIG_TOML" ]; then
    if grep -q '>>> dotpi managed hooks >>>' "$CODEX_CONFIG_TOML" 2>/dev/null; then
      ok_item "codex/config.toml: managed hooks block present"
    else
      fail_item "codex/config.toml: managed hooks block missing (install may not have run hooks wiring)"
    fi
  else
    fail_item "codex/config.toml: file missing at $CODEX_CONFIG_TOML"
  fi

  # ── Reference role structural round-trip: implementer ────────────────────
  # Structural round-trip for 'implementer':
  #   1. CC symlink: $CLAUDE_AGENTS/implementer.md → resolves into harness
  #   2. Codex TOML: $CODEX_AGENTS/implementer.toml exists and contains 'implementer'
  #   3. pi symlink: $PI_AGENT/roles/implementer.md resolves (via the roles dir symlink)
  local ref_cc_link="$CLAUDE_AGENTS/$REFERENCE_ROLE.md"
  local ref_codex_toml="$CODEX_AGENTS/$REFERENCE_ROLE.toml"

  # CC round-trip (covered by the cc/agents/$REFERENCE_ROLE.md check above, but also assert explicitly)
  if [ -L "$ref_cc_link" ]; then
    local ref_cc_raw ref_cc_resolved harness_norm_rt
    ref_cc_raw="$(readlink "$ref_cc_link" 2>/dev/null || true)"
    ref_cc_resolved="$(python_normpath "$(dirname "$ref_cc_link")" "$ref_cc_raw")"
    harness_norm_rt="$(normalise_path "$HARNESS_ROOT")"
    if [[ "$ref_cc_resolved" == "$harness_norm_rt/"* ]]; then
      ok_item "round-trip/$REFERENCE_ROLE: CC symlink resolves into harness ($ref_cc_link)"
    else
      fail_item "round-trip/$REFERENCE_ROLE: CC symlink resolves outside harness ($ref_cc_link → $ref_cc_resolved)"
    fi
  else
    fail_item "round-trip/$REFERENCE_ROLE: CC symlink missing at $ref_cc_link"
  fi

  # Codex TOML round-trip: file exists AND contains the role name
  if [ -f "$ref_codex_toml" ] && [ -s "$ref_codex_toml" ]; then
    if grep -q "\"$REFERENCE_ROLE\"" "$ref_codex_toml" 2>/dev/null; then
      ok_item "round-trip/$REFERENCE_ROLE: Codex TOML present and contains role name"
    else
      fail_item "round-trip/$REFERENCE_ROLE: Codex TOML present but does not contain role name '$REFERENCE_ROLE'"
    fi
  else
    fail_item "round-trip/$REFERENCE_ROLE: Codex TOML missing or empty at $ref_codex_toml"
  fi

  # pi round-trip: the roles dir symlink resolves into the harness tree
  # and the reference role file exists there.
  # Use logical path resolution (normpath) rather than OS stat — the relative
  # symlink may go too many levels deep for OS resolution in throwaway test targets.
  local ref_pi_roles_link="$PI_AGENT/roles"
  if [ -L "$ref_pi_roles_link" ]; then
    local ref_pi_roles_raw ref_pi_roles_resolved harness_norm_pi
    ref_pi_roles_raw="$(readlink "$ref_pi_roles_link" 2>/dev/null || true)"
    ref_pi_roles_resolved="$(python_normpath "$(dirname "$ref_pi_roles_link")" "$ref_pi_roles_raw")"
    harness_norm_pi="$(normalise_path "$HARNESS_ROOT")"
    # The roles dir should point into the harness tree
    if [[ "$ref_pi_roles_resolved" == "$harness_norm_pi/"* ]] || [ "$ref_pi_roles_resolved" = "$harness_norm_pi" ]; then
      # Also verify the reference role .md exists in the harness roles dir
      local harness_roles_dir="$HARNESS_ROOT/agent/roles"
      if [ -f "$harness_roles_dir/$REFERENCE_ROLE.md" ]; then
        ok_item "round-trip/$REFERENCE_ROLE: pi/roles symlink resolves into harness and role file exists"
      else
        fail_item "round-trip/$REFERENCE_ROLE: pi/roles symlink OK but $REFERENCE_ROLE.md not found in harness roles dir"
      fi
    else
      fail_item "round-trip/$REFERENCE_ROLE: pi/roles symlink resolves outside harness ($ref_pi_roles_link → $ref_pi_roles_resolved)"
    fi
  else
    fail_item "round-trip/$REFERENCE_ROLE: pi/roles symlink missing at $ref_pi_roles_link"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "harness doctor — checking health..."
echo ""

check_deps
check_harness

echo ""
echo "------------------------------------------------------------"
echo "  Summary: [ok]=$OK_COUNT  [FAIL]=$FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "  RESULT: RED — $FAIL_COUNT item(s) need attention"
else
  echo "  RESULT: all green"
fi
echo "------------------------------------------------------------"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
