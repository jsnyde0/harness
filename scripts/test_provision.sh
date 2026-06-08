#!/usr/bin/env bash
# test_provision.sh — verify the provisioning phase of install.sh
#
# Three test legs:
#   (a) from-absent: PATH-masked bd+cm absent, throwaway target → both deps fetched,
#       checksum-verified, installed; W3 wiring completes (known symlink asserted)
#   (b) re-run: provisioning is a no-op (no re-fetch — log shows "already installed")
#   (c) corrupt-checksum: aborts non-zero, does NOT install
#
# Never touches real $HOME — all installs go into a mktemp throwaway target.
# Network required for leg (a); skips with loud message if unreachable.

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS_COUNT=0
FAIL_COUNT=0

log() { printf '[test_provision] %s\n' "$*"; }
pass() { log "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { log "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# Network check — skip if unreachable
# ---------------------------------------------------------------------------
check_network() {
  if ! curl -fsSL --max-time 5 https://github.com >/dev/null 2>&1; then
    echo ""
    echo "============================================================"
    echo "  NETWORK UNREACHABLE — test_provision.sh skipping leg (a)"
    echo "  (curl to github.com failed; would give false-green results)"
    echo "  Re-run when network is available."
    echo "============================================================"
    echo ""
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Detect current OS/arch string used in manifest
# ---------------------------------------------------------------------------
detect_arch() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  if [ "$os" = "Darwin" ]; then
    if [ "$arch" = "arm64" ]; then
      echo "darwin-arm64"
    else
      echo "darwin-amd64"
    fi
  elif [ "$os" = "Linux" ]; then
    if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
      echo "linux-arm64"
    else
      echo "linux-amd64"
    fi
  else
    echo "unknown"
  fi
}

# ---------------------------------------------------------------------------
# Build a PATH that masks the real bd and cm binaries.
# Strategy: create a temp "shadow" dir whose only purpose is to block bd/cm.
# We create empty non-executable files named bd and cm in that dir and prepend
# it to PATH. Since they're not executable, command -v still won't find them
# as valid commands. Instead, we create tiny "fail-loudly" stubs that exit 127.
#
# We keep the original PATH intact (so uv, curl, python3, etc. still work),
# only prepending a shadow dir that overrides bd/cm with absent stubs.
# ---------------------------------------------------------------------------
make_masked_path() {
  local shadow_dir
  shadow_dir="$(mktemp -d)"
  # Create stub scripts that loudly refuse to run (simulate absence)
  # We don't create bd/cm here — they simply don't exist in the shadow dir.
  # Since shadow_dir is first in PATH and has no bd/cm, they won't be found
  # there. But they WILL still be found further down PATH.
  # Better approach: create stubs that exit 127 to block the real binaries.
  printf '#!/usr/bin/env bash\necho "bd: command not found (masked by test)" >&2\nexit 127\n' > "$shadow_dir/bd"
  printf '#!/usr/bin/env bash\necho "cm: command not found (masked by test)" >&2\nexit 127\n' > "$shadow_dir/cm"
  chmod +x "$shadow_dir/bd" "$shadow_dir/cm"
  echo "$shadow_dir:$PATH"
}

# Cleanup shadow dirs created by make_masked_path
cleanup_masked_path() {
  local masked_path="$1"
  local shadow_dir
  shadow_dir="${masked_path%%:*}"
  if [ -d "$shadow_dir" ] && echo "$shadow_dir" | grep -q "^/var/folders\|^/tmp"; then
    rm -rf "$shadow_dir"
  fi
}

# ---------------------------------------------------------------------------
# LEG (a): from-absent test
# ---------------------------------------------------------------------------
run_leg_a() {
  log "=== LEG (a): from-absent (PATH-masked, throwaway target) ==="

  if ! check_network; then
    log "SKIP leg (a): network unavailable"
    return 0
  fi

  local target
  target="$(mktemp -d)"
  log "Target dir: $target"

  local masked_path
  masked_path="$(make_masked_path)"

  # Verify PATH-masking actually works — bd/cm stubs must exit 127 (not work normally)
  local bd_exit=0
  PATH="$masked_path" bd version >/dev/null 2>&1 || bd_exit=$?
  if [ "$bd_exit" -ne 127 ]; then
    fail "leg (a): PATH masking failed — bd did not exit 127 in masked PATH (exit: $bd_exit)"
    cleanup_masked_path "$masked_path"
    rm -rf "$target"
    return 1
  fi
  local cm_exit=0
  PATH="$masked_path" cm --version >/dev/null 2>&1 || cm_exit=$?
  if [ "$cm_exit" -ne 127 ]; then
    fail "leg (a): PATH masking failed — cm did not exit 127 in masked PATH (exit: $cm_exit)"
    cleanup_masked_path "$masked_path"
    rm -rf "$target"
    return 1
  fi
  log "PATH masking verified: bd and cm stubs exit 127 in masked PATH"

  # Run install.sh (full install: provision + wire) with throwaway target and masked PATH
  local install_log
  install_log="$(mktemp)"
  log "Running install.sh (first run — full install: provision + wire)..."
  if ! PATH="$masked_path" DOTPI_TEST_TARGET="$target" bash "$HARNESS_ROOT/install.sh" >"$install_log" 2>&1; then
    log "install.sh output:"
    cat "$install_log"
    fail "leg (a): install.sh exited non-zero"
    rm -rf "$target"
    rm -f "$install_log"
    return 1
  fi

  log "install.sh output:"
  cat "$install_log"

  # Assert: bd installed in target bin dir
  local bin_dir="$target/.local/bin"
  if [ ! -f "$bin_dir/bd" ]; then
    fail "leg (a): bd not installed at $bin_dir/bd"
    rm -rf "$target"
    rm -f "$install_log"
    return 1
  fi
  pass "leg (a): bd installed at $bin_dir/bd"

  # Assert: cm installed in target bin dir
  if [ ! -f "$bin_dir/cm" ]; then
    fail "leg (a): cm not installed at $bin_dir/cm"
    rm -rf "$target"
    rm -f "$install_log"
    return 1
  fi
  pass "leg (a): cm installed at $bin_dir/cm"

  # Assert: provisioning log mentions checksum verification
  if ! grep -q "checksum" "$install_log" 2>/dev/null; then
    # fallback: check for sha256
    if ! grep -qi "sha256\|checksum\|verify" "$install_log" 2>/dev/null; then
      fail "leg (a): install log does not mention checksum/sha256 verification"
      rm -rf "$target"
      rm -f "$install_log"
      return 1
    fi
  fi
  pass "leg (a): install log mentions checksum/sha256 verification"

  # Assert: bd verify runs successfully (version check)
  if ! PATH="$bin_dir:$masked_path" bd version >/dev/null 2>&1; then
    fail "leg (a): bd verify (bd version) failed after install"
    rm -rf "$target"
    rm -f "$install_log"
    return 1
  fi
  pass "leg (a): bd verify passes (bd version)"

  # Assert: cm verify runs successfully (cm --version)
  if ! PATH="$bin_dir:$masked_path" cm --version >/dev/null 2>&1; then
    fail "leg (a): cm verify (cm --version) failed after install"
    rm -rf "$target"
    rm -f "$install_log"
    return 1
  fi
  pass "leg (a): cm verify passes (cm --version)"

  # Assert: W3 wiring completed — check for known symlink
  # The wiring creates ~/.pi/agent/AGENTS.md symlink
  local expected_symlink="$target/.pi/agent/AGENTS.md"
  if [ ! -L "$expected_symlink" ]; then
    fail "leg (a): W3 wiring symlink not found at $expected_symlink (wiring did not complete)"
    rm -rf "$target"
    rm -f "$install_log"
    return 1
  fi
  pass "leg (a): W3 wiring completed (symlink at $expected_symlink)"

  # Store target for leg (b)
  LEG_A_TARGET="$target"
  LEG_A_MASKED_PATH="$masked_path"
  LEG_A_LOG="$install_log"
  LEG_A_SHADOW_DIR="${masked_path%%:*}"

  return 0
}

# ---------------------------------------------------------------------------
# LEG (b): re-run is a no-op (idempotency)
# ---------------------------------------------------------------------------
run_leg_b() {
  log "=== LEG (b): re-run → provisioning no-op ==="

  if [ -z "${LEG_A_TARGET:-}" ]; then
    log "SKIP leg (b): leg (a) did not complete (no target)"
    return 0
  fi

  local target="$LEG_A_TARGET"
  local masked_path="$LEG_A_MASKED_PATH"

  # Record modification time of the binaries before re-run
  local bd_mtime_before cm_mtime_before
  bd_mtime_before="$(stat -f '%m' "$target/.local/bin/bd" 2>/dev/null || stat -c '%Y' "$target/.local/bin/bd" 2>/dev/null)"
  cm_mtime_before="$(stat -f '%m' "$target/.local/bin/cm" 2>/dev/null || stat -c '%Y' "$target/.local/bin/cm" 2>/dev/null)"

  # Small sleep to ensure mtime would differ if re-written
  sleep 2

  local rerun_log
  rerun_log="$(mktemp)"
  log "Running install.sh (re-run — full install)..."
  if ! PATH="$masked_path" DOTPI_TEST_TARGET="$target" bash "$HARNESS_ROOT/install.sh" >"$rerun_log" 2>&1; then
    log "install.sh (re-run) output:"
    cat "$rerun_log"
    fail "leg (b): install.sh re-run exited non-zero"
    rm -f "$rerun_log"
    return 1
  fi

  log "install.sh (re-run) output:"
  cat "$rerun_log"

  # Assert: provisioning log mentions "already installed" or "skip"
  if ! grep -qi "already\|skip" "$rerun_log" 2>/dev/null; then
    fail "leg (b): re-run log does not mention 'already installed' or 'skip' — not idempotent?"
    rm -f "$rerun_log"
    return 1
  fi
  pass "leg (b): re-run log mentions already-installed/skip"

  # Assert: binaries were NOT re-written (mtime unchanged)
  local bd_mtime_after cm_mtime_after
  bd_mtime_after="$(stat -f '%m' "$target/.local/bin/bd" 2>/dev/null || stat -c '%Y' "$target/.local/bin/bd" 2>/dev/null)"
  cm_mtime_after="$(stat -f '%m' "$target/.local/bin/cm" 2>/dev/null || stat -c '%Y' "$target/.local/bin/cm" 2>/dev/null)"

  if [ "$bd_mtime_before" != "$bd_mtime_after" ]; then
    fail "leg (b): bd binary was re-written on re-run (mtime changed: $bd_mtime_before -> $bd_mtime_after)"
    rm -f "$rerun_log"
    return 1
  fi
  pass "leg (b): bd binary NOT re-written on re-run (mtime unchanged)"

  if [ "$cm_mtime_before" != "$cm_mtime_after" ]; then
    fail "leg (b): cm binary was re-written on re-run (mtime changed: $cm_mtime_before -> $cm_mtime_after)"
    rm -f "$rerun_log"
    return 1
  fi
  pass "leg (b): cm binary NOT re-written on re-run (mtime unchanged)"

  rm -f "$rerun_log"
  return 0
}

# ---------------------------------------------------------------------------
# LEG (c): corrupt checksum → non-zero abort, no install
# ---------------------------------------------------------------------------
run_leg_c() {
  log "=== LEG (c): corrupt-checksum → abort, no install ==="

  if ! check_network; then
    log "SKIP leg (c): network unavailable"
    return 0
  fi

  local target
  target="$(mktemp -d)"
  log "Target dir: $target"

  local masked_path
  masked_path="$(make_masked_path)"

  # Create a corrupted deps.toml — flip the last hex digit of EVERY sha256 entry.
  # This ensures the entry matching the current arch is also corrupted.
  local corrupted_toml
  corrupted_toml="$(mktemp -t deps_corrupted).toml"
  # Read real manifest and mangle ALL sha256 values
  python3 - "$HARNESS_ROOT/manifest/deps.toml" "$corrupted_toml" <<'PYEOF'
import sys, re

src = open(sys.argv[1], 'r').read()
dst = sys.argv[2]

# Replace ALL sha256 values: flip the last hex digit
def corrupt_sha(m):
    prefix = m.group(1)  # sha256  = "
    hex63 = m.group(2)   # first 63 hex chars
    last = m.group(3)    # last hex char
    # Flip: if it's not '0', make it '0'; if it is '0', make it '1'
    new_last = '0' if last != '0' else '1'
    return prefix + hex63 + new_last + '"'

corrupted = re.sub(
    r'(sha256\s*=\s*")([0-9a-f]{63})([0-9a-f])"',
    corrupt_sha,
    src,
    flags=re.MULTILINE
)

if corrupted == src:
    print("ERROR: could not corrupt any sha256 in manifest", file=sys.stderr)
    sys.exit(1)

open(dst, 'w').write(corrupted)
print(f"Corrupted manifest written to {dst}")
PYEOF

  log "Corrupted deps.toml created at $corrupted_toml"

  # Run install.sh with corrupted manifest — must fail non-zero
  local corrupt_log
  corrupt_log="$(mktemp)"
  log "Running install.sh with corrupted checksum (provision-only is sufficient for this leg)..."
  local exit_code=0
  PATH="$masked_path" DOTPI_TEST_TARGET="$target" DOTPI_DEPS_MANIFEST="$corrupted_toml" \
    bash "$HARNESS_ROOT/install.sh" provision >"$corrupt_log" 2>&1 || exit_code=$?

  log "install.sh (corrupt) output:"
  cat "$corrupt_log"

  if [ "$exit_code" -eq 0 ]; then
    fail "leg (c): install.sh did NOT abort on corrupted checksum (exit code 0)"
    rm -rf "$target"
    rm -f "$corrupted_toml" "$corrupt_log"
    return 1
  fi
  pass "leg (c): install.sh aborted non-zero (exit code $exit_code) on corrupted checksum"

  # Assert: clear error message about checksum mismatch
  if ! grep -qi "checksum\|sha256\|mismatch\|corrupt\|fail" "$corrupt_log" 2>/dev/null; then
    fail "leg (c): abort log does not mention checksum/sha256 mismatch — message not clear enough"
    rm -rf "$target"
    rm -f "$corrupted_toml" "$corrupt_log"
    return 1
  fi
  pass "leg (c): abort log contains clear checksum-failure message"

  # Assert: bd was NOT installed
  if [ -f "$target/.local/bin/bd" ]; then
    fail "leg (c): bd WAS installed despite checksum mismatch — verify-before-install not enforced"
    rm -rf "$target"
    rm -f "$corrupted_toml" "$corrupt_log"
    return 1
  fi
  pass "leg (c): bd was NOT installed (checksum abort fired before install)"

  # Assert: cm was NOT installed (regardless of manifest ordering)
  if [ -f "$target/.local/bin/cm" ]; then
    fail "leg (c): cm WAS installed despite checksum mismatch — verify-before-install not enforced"
    rm -rf "$target"
    rm -f "$corrupted_toml" "$corrupt_log"
    return 1
  fi
  pass "leg (c): cm was NOT installed (checksum abort fired before install)"

  rm -rf "$target"
  rm -f "$corrupted_toml" "$corrupt_log"
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

LEG_A_TARGET=""
LEG_A_MASKED_PATH=""
LEG_A_LOG=""
LEG_A_SHADOW_DIR=""

run_leg_a
run_leg_b
run_leg_c

# Cleanup leg (a) target and shadow dir
if [ -n "${LEG_A_TARGET:-}" ] && [ -d "$LEG_A_TARGET" ]; then
  rm -rf "$LEG_A_TARGET"
fi
if [ -n "${LEG_A_LOG:-}" ] && [ -f "$LEG_A_LOG" ]; then
  rm -f "$LEG_A_LOG"
fi
if [ -n "${LEG_A_SHADOW_DIR:-}" ] && [ -d "$LEG_A_SHADOW_DIR" ]; then
  rm -rf "$LEG_A_SHADOW_DIR"
fi

echo ""
echo "============================================================"
echo "  test_provision.sh results: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT"
echo "============================================================"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
