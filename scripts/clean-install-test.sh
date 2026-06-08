#!/usr/bin/env bash
# clean-install-test.sh — integration proof for W4 Distribution epic
#
# Proves: on a machine with NONE of beads/CASSMS preinstalled, run install.sh
# (provision + wire) → doctor all-green → reference role round-trips structurally
# → idempotent re-run (provisioning is a no-op).
#
# Reference role: implementer
# Round-trip assertions (all three must hold):
#   1. CC symlink:   $CLAUDE_AGENTS/implementer.md  is a symlink resolving into harness
#   2. Codex TOML:  $CODEX_AGENTS/implementer.toml  exists and contains the string "implementer"
#   3. pi roles:    $PI_AGENT/roles symlink resolves into harness AND
#                   agent/roles/implementer.md exists in the harness tree
#
# Usage:
#   bash scripts/clean-install-test.sh
#
# Environment:
#   DOTPI_TEST_TARGET   — override target home (default: mktemp -d, cleaned at exit)
#   DOTPI_DEPS_MANIFEST — override manifest path (default: harness manifest/deps.toml)
#   HARNESS_ROOT        — path to harness source tree (default: parent of this script)
#
# Runs on: linux-amd64 (CI) and macOS (local dev, cm arch-gap warning expected on arm64)
# Prerequisites (must be in PATH before running):
#   uv, python3, git, curl, tar, sha256sum (or shasum on macOS)
#
# On macOS local runs: cm provisioning may emit an arch-gap WARNING for darwin-arm64
# if only linux-x64 binaries are in the manifest — this is expected and documented.
# The CI runner (ubuntu-latest, linux-amd64) is the authoritative clean-machine signal.

set -euo pipefail

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

PASS_COUNT=0
FAIL_COUNT=0

log()  { printf '[clean-install] %s\n' "$*"; }
pass() { log "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { log "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# Throwaway target — guaranteed not to touch real $HOME
# ---------------------------------------------------------------------------
# If DOTPI_TEST_TARGET is pre-set, use it; otherwise create one and clean up
# at exit. Either way, we never write to the real $HOME.
_CREATED_TARGET=0
if [ -z "${DOTPI_TEST_TARGET:-}" ]; then
  DOTPI_TEST_TARGET="$(mktemp -d)"
  _CREATED_TARGET=1
  log "Created throwaway target: $DOTPI_TEST_TARGET"
else
  log "Using pre-set DOTPI_TEST_TARGET: $DOTPI_TEST_TARGET"
fi

TARGET="$DOTPI_TEST_TARGET"

cleanup() {
  if [ "$_CREATED_TARGET" -eq 1 ] && [ -d "$TARGET" ]; then
    rm -rf "$TARGET"
    log "Cleaned up throwaway target: $TARGET"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Network check — required for provisioning; fail fast if unreachable
# ---------------------------------------------------------------------------
check_network() {
  if ! curl -fsSL --max-time 5 https://github.com >/dev/null 2>&1; then
    echo ""
    echo "============================================================"
    echo "  NETWORK UNREACHABLE — clean-install-test.sh requires network"
    echo "  (curl to github.com failed; provisioning binaries cannot be fetched)"
    echo "  Re-run when network is available."
    echo "============================================================"
    echo ""
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# PATH-masking: shadow bd and cm so provisioning must install fresh copies
# ---------------------------------------------------------------------------
make_masked_path() {
  local shadow_dir
  shadow_dir="$(mktemp -d)"
  # Stub scripts that loudly exit 127 — simulates clean-machine absence of bd/cm
  printf '#!/usr/bin/env bash\necho "bd: command not found (masked by test)" >&2\nexit 127\n' > "$shadow_dir/bd"
  printf '#!/usr/bin/env bash\necho "cm: command not found (masked by test)" >&2\nexit 127\n' > "$shadow_dir/cm"
  chmod +x "$shadow_dir/bd" "$shadow_dir/cm"
  SHADOW_DIR="$shadow_dir"
  echo "$shadow_dir:$PATH"
}

SHADOW_DIR=""

# Verify PATH masking is effective before we start
verify_masking() {
  local masked_path="$1"
  local bd_exit=0
  PATH="$masked_path" bd version >/dev/null 2>&1 || bd_exit=$?
  if [ "$bd_exit" -ne 127 ]; then
    log "WARNING: PATH masking for bd did not produce exit 127 (got: $bd_exit) — test may not simulate clean-machine accurately"
  else
    log "PATH masking verified: bd stub exits 127"
  fi
  local cm_exit=0
  PATH="$masked_path" cm --version >/dev/null 2>&1 || cm_exit=$?
  if [ "$cm_exit" -ne 127 ]; then
    log "WARNING: PATH masking for cm did not produce exit 127 (got: $cm_exit) — test may not simulate clean-machine accurately"
  else
    log "PATH masking verified: cm stub exits 127"
  fi
}

# ---------------------------------------------------------------------------
# STEP 0: check network
# ---------------------------------------------------------------------------
log "=== STEP 0: network check ==="
check_network
log "Network reachable."

# ---------------------------------------------------------------------------
# STEP 1: mask bd/cm from PATH (simulate clean machine)
# ---------------------------------------------------------------------------
log "=== STEP 1: mask bd and cm from PATH ==="
MASKED_PATH="$(make_masked_path)"
verify_masking "$MASKED_PATH"

# ---------------------------------------------------------------------------
# STEP 2: run install.sh (provision + W3 wiring) — first run
# ---------------------------------------------------------------------------
log "=== STEP 2: first install (provision + wire) ==="
log "Target: $TARGET"

INSTALL_LOG="$(mktemp)"

log "Running: DOTPI_TEST_TARGET=$TARGET bash $HARNESS_ROOT/install.sh"
install_exit=0
PATH="$MASKED_PATH" DOTPI_TEST_TARGET="$TARGET" bash "$HARNESS_ROOT/install.sh" >"$INSTALL_LOG" 2>&1 || install_exit=$?

log "install.sh output:"
cat "$INSTALL_LOG"

if [ "$install_exit" -ne 0 ]; then
  fail "STEP 2: install.sh exited non-zero ($install_exit)"
  rm -f "$INSTALL_LOG"
  exit 1
fi
pass "STEP 2: install.sh exited 0"

# Assert: both deps installed into target bin dir
BIN_DIR="$TARGET/.local/bin"

if [ ! -f "$BIN_DIR/bd" ]; then
  fail "STEP 2: beads (bd) not installed at $BIN_DIR/bd — provisioning did not run or failed"
  rm -f "$INSTALL_LOG"
  exit 1
fi
pass "STEP 2: beads (bd) installed at $BIN_DIR/bd"

if [ ! -f "$BIN_DIR/cm" ]; then
  # cm may legitimately be absent on linux-arm64 (arch-gap warning), but on linux-amd64 it must be present.
  local_arch="$(uname -m)"
  if [ "$local_arch" = "aarch64" ] || [ "$local_arch" = "arm64" ]; then
    log "NOTE: cm not installed on arm64 — expected (arch-gap WARNING from provision, not a failure)"
  else
    fail "STEP 2: CASSMS (cm) not installed at $BIN_DIR/cm — provisioning did not run or failed"
    rm -f "$INSTALL_LOG"
    exit 1
  fi
else
  pass "STEP 2: CASSMS (cm) installed at $BIN_DIR/cm"
fi

# Assert: checksum verification ran (install log must mention it)
if ! grep -qi "checksum\|sha256\|verify" "$INSTALL_LOG" 2>/dev/null; then
  fail "STEP 2: install log does not mention checksum/sha256 verification — checksumming may have been skipped"
  rm -f "$INSTALL_LOG"
  exit 1
fi
pass "STEP 2: install log confirms checksum/sha256 verification ran"

# Assert: W3 wiring completed — pi/AGENTS.md symlink is the canonical wiring marker
EXPECTED_SYMLINK="$TARGET/.pi/agent/AGENTS.md"
if [ ! -L "$EXPECTED_SYMLINK" ]; then
  fail "STEP 2: W3 wiring symlink not found at $EXPECTED_SYMLINK — wiring did not complete"
  rm -f "$INSTALL_LOG"
  exit 1
fi
pass "STEP 2: W3 wiring completed (pi/agent/AGENTS.md symlink present)"

rm -f "$INSTALL_LOG"

# ---------------------------------------------------------------------------
# STEP 3: run install.sh doctor — expect all-green + exit 0
# ---------------------------------------------------------------------------
log "=== STEP 3: doctor (expect all-green + exit 0) ==="

DOCTOR_LOG="$(mktemp)"
doctor_exit=0
PATH="$MASKED_PATH" DOTPI_TEST_TARGET="$TARGET" bash "$HARNESS_ROOT/install.sh" doctor >"$DOCTOR_LOG" 2>&1 || doctor_exit=$?

log "doctor output:"
cat "$DOCTOR_LOG"

# Assert: no [FAIL] lines
fail_lines="$(grep '^\[FAIL\]' "$DOCTOR_LOG" 2>/dev/null || true)"
if [ -n "$fail_lines" ]; then
  fail "STEP 3: doctor reported [FAIL] items on a clean install:"
  log "$fail_lines"
  rm -f "$DOCTOR_LOG"
  exit 1
fi
pass "STEP 3: no [FAIL] items in doctor output"

# Assert: at least some [ok] lines
ok_lines="$(grep '\[ok\]' "$DOCTOR_LOG" 2>/dev/null || true)"
if [ -z "$ok_lines" ]; then
  fail "STEP 3: doctor printed no [ok] items — output may be empty or broken"
  rm -f "$DOCTOR_LOG"
  exit 1
fi
pass "STEP 3: doctor printed [ok] items"

# Assert: doctor exits 0
if [ "$doctor_exit" -ne 0 ]; then
  fail "STEP 3: doctor exited non-zero ($doctor_exit) on a clean install"
  rm -f "$DOCTOR_LOG"
  exit 1
fi
pass "STEP 3: doctor exited 0 (all-green)"

# Assert: summary says "all green"
if ! grep -qi "all green" "$DOCTOR_LOG" 2>/dev/null; then
  fail "STEP 3: doctor summary does not say 'all green'"
  rm -f "$DOCTOR_LOG"
  exit 1
fi
pass "STEP 3: doctor summary confirms 'all green'"

rm -f "$DOCTOR_LOG"

# ---------------------------------------------------------------------------
# STEP 4: named reference role round-trip — implementer
#
# Reference role: implementer
# Three assertions (all must hold):
#   (4a) CC symlink:  $CLAUDE_AGENTS/implementer.md   → symlink resolving into harness
#   (4b) Codex TOML: $CODEX_AGENTS/implementer.toml  → exists and contains "implementer"
#   (4c) pi roles:   $PI_AGENT/roles symlink resolves into harness
#                    AND $HARNESS_ROOT/agent/roles/implementer.md exists
# ---------------------------------------------------------------------------
log "=== STEP 4: reference role 'implementer' structural round-trip ==="

REFERENCE_ROLE="implementer"
CLAUDE_AGENTS="$TARGET/.claude/agents"
CODEX_AGENTS="$TARGET/.codex/agents"
PI_AGENT="$TARGET/.pi/agent"

# (4a) CC symlink
REF_CC_LINK="$CLAUDE_AGENTS/$REFERENCE_ROLE.md"
if [ ! -L "$REF_CC_LINK" ]; then
  fail "STEP 4a: CC symlink missing at $REF_CC_LINK"
  exit 1
fi
# Resolve the symlink and verify it points into the harness tree
ref_cc_raw="$(readlink "$REF_CC_LINK" 2>/dev/null || true)"
ref_cc_resolved="$(python3 -c "
import os.path
joined = os.path.join('$(dirname "$REF_CC_LINK")', '$ref_cc_raw')
print(os.path.normpath(joined))
" 2>/dev/null || true)"
harness_norm="$(python3 -c "import os.path; print(os.path.normpath('$HARNESS_ROOT'))" 2>/dev/null || true)"

if [[ "$ref_cc_resolved" == "$harness_norm/"* ]] || [ "$ref_cc_resolved" = "$harness_norm" ]; then
  pass "STEP 4a: CC symlink $REF_CC_LINK resolves into harness tree ($ref_cc_resolved)"
else
  fail "STEP 4a: CC symlink resolves outside harness tree ($REF_CC_LINK → $ref_cc_resolved, harness: $harness_norm)"
  exit 1
fi

# (4b) Codex TOML
REF_TOML="$CODEX_AGENTS/$REFERENCE_ROLE.toml"
if [ ! -f "$REF_TOML" ]; then
  fail "STEP 4b: Codex TOML missing at $REF_TOML"
  exit 1
fi
if [ ! -s "$REF_TOML" ]; then
  fail "STEP 4b: Codex TOML is empty at $REF_TOML"
  exit 1
fi
if ! grep -q "\"$REFERENCE_ROLE\"" "$REF_TOML" 2>/dev/null; then
  fail "STEP 4b: Codex TOML at $REF_TOML does not contain role name '\"$REFERENCE_ROLE\"'"
  exit 1
fi
pass "STEP 4b: Codex TOML $REF_TOML exists, is non-empty, and contains role name"

# (4c) pi roles
REF_PI_ROLES_LINK="$PI_AGENT/roles"
if [ ! -L "$REF_PI_ROLES_LINK" ]; then
  fail "STEP 4c: pi/roles symlink missing at $REF_PI_ROLES_LINK"
  exit 1
fi
ref_pi_roles_raw="$(readlink "$REF_PI_ROLES_LINK" 2>/dev/null || true)"
ref_pi_roles_resolved="$(python3 -c "
import os.path
joined = os.path.join('$(dirname "$REF_PI_ROLES_LINK")', '$ref_pi_roles_raw')
print(os.path.normpath(joined))
" 2>/dev/null || true)"

if [[ "$ref_pi_roles_resolved" == "$harness_norm/"* ]] || [ "$ref_pi_roles_resolved" = "$harness_norm" ]; then
  if [ -f "$HARNESS_ROOT/agent/roles/$REFERENCE_ROLE.md" ]; then
    pass "STEP 4c: pi/roles symlink resolves into harness and $REFERENCE_ROLE.md exists in harness"
  else
    fail "STEP 4c: pi/roles symlink OK but $REFERENCE_ROLE.md not found in $HARNESS_ROOT/agent/roles/"
    exit 1
  fi
else
  fail "STEP 4c: pi/roles symlink resolves outside harness ($REF_PI_ROLES_LINK → $ref_pi_roles_resolved)"
  exit 1
fi

log "Reference role 'implementer' round-trip: all three assertions passed."

# ---------------------------------------------------------------------------
# STEP 5: idempotent re-run — provisioning must be a no-op
# ---------------------------------------------------------------------------
log "=== STEP 5: idempotent re-run (provisioning no-op) ==="

# Record binary modification times before re-run
bd_mtime_before="$(stat -c '%Y' "$BIN_DIR/bd" 2>/dev/null || stat -f '%m' "$BIN_DIR/bd" 2>/dev/null || echo "0")"
if [ -f "$BIN_DIR/cm" ]; then
  cm_mtime_before="$(stat -c '%Y' "$BIN_DIR/cm" 2>/dev/null || stat -f '%m' "$BIN_DIR/cm" 2>/dev/null || echo "0")"
else
  cm_mtime_before=""
fi

# Sleep briefly to ensure mtime would differ if files were re-written
sleep 2

RERUN_LOG="$(mktemp)"
log "Running: DOTPI_TEST_TARGET=$TARGET bash $HARNESS_ROOT/install.sh (re-run)"
rerun_exit=0
PATH="$MASKED_PATH" DOTPI_TEST_TARGET="$TARGET" bash "$HARNESS_ROOT/install.sh" >"$RERUN_LOG" 2>&1 || rerun_exit=$?

log "install.sh (re-run) output:"
cat "$RERUN_LOG"

if [ "$rerun_exit" -ne 0 ]; then
  fail "STEP 5: re-run of install.sh exited non-zero ($rerun_exit)"
  rm -f "$RERUN_LOG"
  exit 1
fi
pass "STEP 5: re-run of install.sh exited 0"

# Assert: provisioning log says "already installed" / "skip" — not re-fetching
if ! grep -qi "already\|skip" "$RERUN_LOG" 2>/dev/null; then
  fail "STEP 5: re-run log does not mention 'already installed' or 'skip' — provisioning may have re-fetched"
  rm -f "$RERUN_LOG"
  exit 1
fi
pass "STEP 5: re-run log confirms 'already installed'/'skip' (no re-fetch)"

# Assert: binaries were NOT re-written (mtime unchanged proves no re-download)
bd_mtime_after="$(stat -c '%Y' "$BIN_DIR/bd" 2>/dev/null || stat -f '%m' "$BIN_DIR/bd" 2>/dev/null || echo "0")"
if [ "$bd_mtime_before" != "$bd_mtime_after" ]; then
  fail "STEP 5: bd binary mtime changed on re-run ($bd_mtime_before → $bd_mtime_after) — not idempotent"
  rm -f "$RERUN_LOG"
  exit 1
fi
pass "STEP 5: bd binary NOT re-written on re-run (mtime unchanged)"

if [ -n "$cm_mtime_before" ] && [ -f "$BIN_DIR/cm" ]; then
  cm_mtime_after="$(stat -c '%Y' "$BIN_DIR/cm" 2>/dev/null || stat -f '%m' "$BIN_DIR/cm" 2>/dev/null || echo "0")"
  if [ "$cm_mtime_before" != "$cm_mtime_after" ]; then
    fail "STEP 5: cm binary mtime changed on re-run ($cm_mtime_before → $cm_mtime_after) — not idempotent"
    rm -f "$RERUN_LOG"
    exit 1
  fi
  pass "STEP 5: cm binary NOT re-written on re-run (mtime unchanged)"
fi

rm -f "$RERUN_LOG"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  clean-install-test.sh results: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT"
echo "============================================================"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

# Cleanup shadow dir
if [ -n "${SHADOW_DIR:-}" ] && [ -d "$SHADOW_DIR" ]; then
  rm -rf "$SHADOW_DIR"
fi

exit 0
