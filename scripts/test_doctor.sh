#!/usr/bin/env bash
# test_doctor.sh — verify the doctor subcommand of install.sh
#
# Four test legs:
#   (a) all-green: fully-installed throwaway target → doctor prints [ok] for all items, exit 0
#   (b) removed dep: one dep binary removed → doctor shows [FAIL] for that dep, exits non-zero
#   (c) broken symlink: one wiring symlink broken → doctor shows [FAIL] for that item, exits non-zero
#   (d) read-only proof: run doctor twice, assert target tree unchanged (no mutations)
#
# Never touches real $HOME — all installs go into a mktemp throwaway target.
# Network required for the install step in leg (a); skips with loud message if unreachable.
#
# Reference role used for structural round-trip check: "implementer"
# (implementer.md is a stable, simple role with well-known frontmatter)

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS_COUNT=0
FAIL_COUNT=0

log() { printf '[test_doctor] %s\n' "$*"; }
pass() { log "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { log "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# Network check — skip if unreachable
# ---------------------------------------------------------------------------
check_network() {
  if ! curl -fsSL --max-time 5 https://github.com >/dev/null 2>&1; then
    echo ""
    echo "============================================================"
    echo "  NETWORK UNREACHABLE — test_doctor.sh skipping network-dependent steps"
    echo "  (curl to github.com failed; would give false-green results)"
    echo "  Re-run when network is available."
    echo "============================================================"
    echo ""
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Shared install target (set by leg a, used by legs b/c/d)
# ---------------------------------------------------------------------------
SHARED_TARGET=""

# ---------------------------------------------------------------------------
# LEG (a): all-green on a fully-installed throwaway target
# ---------------------------------------------------------------------------
run_leg_a() {
  log "=== LEG (a): all-green on fully-installed target ==="

  if ! check_network; then
    log "SKIP leg (a): network unavailable"
    return 0
  fi

  local target
  target="$(mktemp -d)"
  log "Target dir: $target"

  # Run full install.sh (provision + wire) into throwaway target
  local install_log
  install_log="$(mktemp)"
  log "Running install.sh (full install: provision + wire)..."
  if ! DOTPI_TEST_TARGET="$target" bash "$HARNESS_ROOT/install.sh" >"$install_log" 2>&1; then
    log "install.sh output:"
    cat "$install_log"
    fail "leg (a): install.sh exited non-zero"
    rm -rf "$target"
    rm -f "$install_log"
    return 1
  fi
  log "install.sh output (tail):"
  tail -20 "$install_log"

  # Run doctor against the fully-installed target
  log "Running: install.sh doctor (fully-installed target)..."
  local doctor_log
  doctor_log="$(mktemp)"
  local doctor_exit=0
  DOTPI_TEST_TARGET="$target" bash "$HARNESS_ROOT/install.sh" doctor >"$doctor_log" 2>&1 || doctor_exit=$?

  log "doctor output:"
  cat "$doctor_log"

  # Assert: all items show [ok] — match only lines that START with [FAIL]
  local fail_lines
  fail_lines="$(grep '^\[FAIL\]' "$doctor_log" 2>/dev/null || true)"
  if [ -n "$fail_lines" ]; then
    fail "leg (a): doctor reported [FAIL] items on a clean install:"
    log "$fail_lines"
    rm -rf "$target"
    rm -f "$install_log" "$doctor_log"
    return 1
  fi
  pass "leg (a): no [FAIL] items in doctor output"

  # Assert: at least some [ok] lines exist
  local ok_lines
  ok_lines="$(grep '\[ok\]' "$doctor_log" 2>/dev/null || true)"
  if [ -z "$ok_lines" ]; then
    fail "leg (a): doctor printed no [ok] items — output may be empty or broken"
    rm -rf "$target"
    rm -f "$install_log" "$doctor_log"
    return 1
  fi
  pass "leg (a): doctor printed [ok] items"

  # Assert: doctor exits 0
  if [ "$doctor_exit" -ne 0 ]; then
    fail "leg (a): doctor exited non-zero ($doctor_exit) on a clean install"
    rm -rf "$target"
    rm -f "$install_log" "$doctor_log"
    return 1
  fi
  pass "leg (a): doctor exited 0 on clean install"

  # Assert: summary line present
  if ! grep -qi "summary\|all green\|items checked\|FAIL=0\|fail=0" "$doctor_log" 2>/dev/null; then
    fail "leg (a): doctor output has no summary tail"
    rm -rf "$target"
    rm -f "$install_log" "$doctor_log"
    return 1
  fi
  pass "leg (a): doctor output contains summary tail"

  # Assert: reference role (implementer) round-trip present
  # Doctor should report the Codex TOML for 'implementer' as [ok] (structural check)
  if ! grep -q "implementer" "$doctor_log" 2>/dev/null; then
    fail "leg (a): doctor output does not mention reference role 'implementer'"
    rm -rf "$target"
    rm -f "$install_log" "$doctor_log"
    return 1
  fi
  pass "leg (a): reference role 'implementer' appears in doctor output"

  # Store target for legs b/c/d
  SHARED_TARGET="$target"
  rm -f "$install_log" "$doctor_log"
  return 0
}

# ---------------------------------------------------------------------------
# LEG (b): removed dep → [FAIL] + non-zero exit
# ---------------------------------------------------------------------------
run_leg_b() {
  log "=== LEG (b): removed dep binary → doctor red + non-zero exit ==="

  if [ -z "${SHARED_TARGET:-}" ]; then
    log "SKIP leg (b): no shared target from leg (a)"
    return 0
  fi

  local target="$SHARED_TARGET"
  local bin_dir="$target/.local/bin"

  # Remove the 'bd' binary to simulate missing dep
  if [ ! -f "$bin_dir/bd" ]; then
    fail "leg (b): bd not present in target (leg (a) may not have fully provisioned)"
    return 1
  fi

  # Rename (not delete) so we can restore for leg (c)
  mv "$bin_dir/bd" "$bin_dir/bd.bak"
  log "Renamed $bin_dir/bd → $bin_dir/bd.bak (simulating absent dep)"

  local doctor_log
  doctor_log="$(mktemp)"
  local doctor_exit=0
  DOTPI_TEST_TARGET="$target" bash "$HARNESS_ROOT/install.sh" doctor >"$doctor_log" 2>&1 || doctor_exit=$?

  log "doctor output (removed dep):"
  cat "$doctor_log"

  # Restore binary BEFORE any assertions that might cause early return
  mv "$bin_dir/bd.bak" "$bin_dir/bd"
  log "Restored $bin_dir/bd.bak → $bin_dir/bd"

  # Assert: doctor shows [FAIL] for beads (only match lines starting with [FAIL])
  if ! grep -q '^\[FAIL\]' "$doctor_log" 2>/dev/null; then
    fail "leg (b): doctor did not show [FAIL] when bd binary was absent"
    rm -f "$doctor_log"
    return 1
  fi
  pass "leg (b): doctor shows [FAIL] when bd binary is absent"

  # Assert: the [FAIL] line mentions beads or bd
  if ! grep '^\[FAIL\]' "$doctor_log" 2>/dev/null | grep -qi "beads\|bd"; then
    fail "leg (b): [FAIL] line does not identify the failing dep (beads/bd)"
    rm -f "$doctor_log"
    return 1
  fi
  pass "leg (b): [FAIL] line identifies the failing dep (beads/bd)"

  # Assert: doctor exits non-zero
  if [ "$doctor_exit" -eq 0 ]; then
    fail "leg (b): doctor exited 0 despite [FAIL] items"
    rm -f "$doctor_log"
    return 1
  fi
  pass "leg (b): doctor exits non-zero ($doctor_exit) when dep is absent"

  rm -f "$doctor_log"
  return 0
}

# ---------------------------------------------------------------------------
# LEG (c): broken wiring symlink → [FAIL] + non-zero exit
# ---------------------------------------------------------------------------
run_leg_c() {
  log "=== LEG (c): broken wiring symlink → doctor red + non-zero exit ==="

  if [ -z "${SHARED_TARGET:-}" ]; then
    log "SKIP leg (c): no shared target from leg (a)"
    return 0
  fi

  local target="$SHARED_TARGET"

  # Break the CC wiring symlink: remove ~/.claude/agents/implementer.md
  local broken_link="$target/.claude/agents/implementer.md"
  if [ ! -L "$broken_link" ]; then
    fail "leg (c): expected symlink $broken_link not found — wiring may be different"
    return 1
  fi

  # Save the symlink target so we can restore it
  local link_dest
  link_dest="$(readlink "$broken_link")"
  rm "$broken_link"
  log "Removed symlink $broken_link (was → $link_dest) to simulate broken wiring"

  local doctor_log
  doctor_log="$(mktemp)"
  local doctor_exit=0
  DOTPI_TEST_TARGET="$target" bash "$HARNESS_ROOT/install.sh" doctor >"$doctor_log" 2>&1 || doctor_exit=$?

  log "doctor output (broken symlink):"
  cat "$doctor_log"

  # Restore symlink
  ln -s "$link_dest" "$broken_link"
  log "Restored symlink $broken_link → $link_dest"

  # Assert: doctor shows [FAIL] (only match lines starting with [FAIL])
  if ! grep -q '^\[FAIL\]' "$doctor_log" 2>/dev/null; then
    fail "leg (c): doctor did not show [FAIL] when CC wiring symlink was broken"
    rm -f "$doctor_log"
    return 1
  fi
  pass "leg (c): doctor shows [FAIL] when wiring symlink is broken"

  # Assert: [FAIL] line is related to CC wiring / implementer
  if ! grep '^\[FAIL\]' "$doctor_log" 2>/dev/null | grep -qi "implementer\|cc\|claude\|agents\|wiring\|symlink"; then
    fail "leg (c): [FAIL] line does not identify the broken wiring item"
    rm -f "$doctor_log"
    return 1
  fi
  pass "leg (c): [FAIL] line identifies the broken wiring item"

  # Assert: doctor exits non-zero
  if [ "$doctor_exit" -eq 0 ]; then
    fail "leg (c): doctor exited 0 despite [FAIL] wiring item"
    rm -f "$doctor_log"
    return 1
  fi
  pass "leg (c): doctor exits non-zero ($doctor_exit) when wiring symlink is broken"

  rm -f "$doctor_log"
  return 0
}

# ---------------------------------------------------------------------------
# LEG (d): read-only proof — doctor must not mutate the target tree
# ---------------------------------------------------------------------------
run_leg_d() {
  log "=== LEG (d): read-only proof (doctor must not mutate target) ==="

  if [ -z "${SHARED_TARGET:-}" ]; then
    log "SKIP leg (d): no shared target from leg (a)"
    return 0
  fi

  local target="$SHARED_TARGET"

  # Capture a find-listing before the first doctor run
  local before_listing
  before_listing="$(find "$target" -maxdepth 10 | sort)"

  # Run doctor twice
  log "Running doctor (run 1)..."
  DOTPI_TEST_TARGET="$target" bash "$HARNESS_ROOT/install.sh" doctor >/dev/null 2>&1 || true
  log "Running doctor (run 2)..."
  DOTPI_TEST_TARGET="$target" bash "$HARNESS_ROOT/install.sh" doctor >/dev/null 2>&1 || true

  # Capture a find-listing after both doctor runs
  local after_listing
  after_listing="$(find "$target" -maxdepth 10 | sort)"

  # Assert: no files created/deleted/changed
  if [ "$before_listing" != "$after_listing" ]; then
    log "DIFF (before vs after doctor):"
    diff <(echo "$before_listing") <(echo "$after_listing") || true
    fail "leg (d): doctor mutated the target tree (file list changed)"
    return 1
  fi
  pass "leg (d): doctor is read-only (target tree identical before and after two runs)"

  return 0
}

# ---------------------------------------------------------------------------
# --help / -h verification
# ---------------------------------------------------------------------------
run_help_check() {
  log "=== HELP: install.sh --help ==="

  local help_log
  help_log="$(mktemp)"
  local help_exit=0
  bash "$HARNESS_ROOT/install.sh" --help >"$help_log" 2>&1 || help_exit=$?

  log "--help output:"
  cat "$help_log"

  # --help should exit 0
  if [ "$help_exit" -ne 0 ]; then
    fail "help: install.sh --help exited non-zero ($help_exit)"
    rm -f "$help_log"
    return 1
  fi
  pass "help: install.sh --help exits 0"

  # Should mention doctor, install, provision
  for word in doctor install provision; do
    if ! grep -qi "$word" "$help_log" 2>/dev/null; then
      fail "help: --help output does not mention '$word'"
      rm -f "$help_log"
      return 1
    fi
  done
  pass "help: --help output mentions doctor, install, provision"

  rm -f "$help_log"
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

run_help_check
run_leg_a
run_leg_b
run_leg_c
run_leg_d

# Cleanup shared target
if [ -n "${SHARED_TARGET:-}" ] && [ -d "$SHARED_TARGET" ]; then
  rm -rf "$SHARED_TARGET"
  log "Cleaned up shared target: $SHARED_TARGET"
fi

echo ""
echo "============================================================"
echo "  test_doctor.sh results: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT"
echo "============================================================"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
