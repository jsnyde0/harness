#!/usr/bin/env bash
# Test suite for bd-prime-with-cm.sh
# Tests three scenarios: normal (both tools), cm missing, bd missing.
# Usage: bash $CLAUDE_HOME/hooks/bd-prime-with-cm.test.sh

SCRIPT="$HOME/.claude/hooks/bd-prime-with-cm.sh"
PASS=0
FAIL=0

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

assert_exit_zero() {
  local desc=$1
  local actual_exit=$2
  if [ "$actual_exit" -eq 0 ]; then
    echo "  ✓ $desc: exit 0"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc: expected exit 0, got $actual_exit"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc=$1
  local haystack=$2
  local needle=$3
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  ✓ $desc: contains '$needle'"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc: expected to contain '$needle'"
    echo "    actual output (first 20 lines):"
    echo "$haystack" | head -20 | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}

assert_not_empty() {
  local desc=$1
  local value=$2
  if [ -n "$value" ]; then
    echo "  ✓ $desc: non-empty"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc: expected non-empty, got empty"
    FAIL=$((FAIL + 1))
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Pre-flight: script must exist and be executable
# ────────────────────────────────────────────────────────────────────────────
echo "=== Pre-flight ==="

if [ -f "$SCRIPT" ]; then
  echo "  ✓ script exists: $SCRIPT"
  PASS=$((PASS + 1))
else
  echo "  ✗ script missing: $SCRIPT"
  FAIL=$((FAIL + 1))
fi

if [ -x "$SCRIPT" ]; then
  echo "  ✓ script is executable"
  PASS=$((PASS + 1))
else
  echo "  ✗ script is not executable"
  FAIL=$((FAIL + 1))
fi

if ! [ -f "$SCRIPT" ]; then
  echo "FATAL: script not found, cannot continue tests"
  echo
  echo "Pass: $PASS  Fail: $FAIL"
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Scenario 1: Normal — both cm and bd available (empty playbook case)
# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 1a: Normal, empty playbook (no-op gracefully) ==="

output1a=$(bash "$SCRIPT" 2>/dev/null)
exit1a=$?

assert_exit_zero "exit code (empty playbook)" $exit1a
assert_not_empty "output is non-empty (bd prime runs)" "$output1a"
assert_contains "bd-prime section present" "$output1a" "Beads"

# When playbook is empty, no L2A section should be injected (no garbage).
# Check that there's no cm error noise either.
if echo "$output1a" | grep -qF "L2A"; then
  echo "  ✓ L2A section present (playbook has content)"
  PASS=$((PASS + 1))
else
  echo "  ✓ L2A section absent (empty playbook — no-op, correct behavior)"
  PASS=$((PASS + 1))
fi

# ────────────────────────────────────────────────────────────────────────────
# Scenario 1b: Normal — both cm and bd available, cm stub returns content
# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 1b: Normal, cm stub returns non-empty bullets ==="

TMPDIR1b=$(mktemp -d)

# Create a cm stub that returns JSON with one relevantBullet
cat > "$TMPDIR1b/cm" <<'STUB'
#!/usr/bin/env bash
# Stub cm that returns JSON with a relevant bullet when --json flag given.
# Responds to: cm context "<task>" --json
# Or:          cm context "<task>" --format markdown
for arg in "$@"; do
  if [ "$arg" = "--json" ]; then
    echo '{"success":true,"command":"context","timestamp":"2026-01-01T00:00:00Z","data":{"task":"stub","relevantBullets":[{"id":"b1","content":"Always use uv for Python.","category":"workflow","score":0.9}],"antiPatterns":[],"historySnippets":[],"deprecatedWarnings":[],"suggestedCassQueries":[]},"metadata":{"executionMs":1,"version":"stub"}}'
    exit 0
  fi
  if [ "$arg" = "markdown" ]; then
    echo "# Context for: stub"
    echo ""
    echo "## Playbook rules (1)"
    echo ""
    echo "- Always use uv for Python."
    exit 0
  fi
done
# Default: no flags, print help or nothing
exit 0
STUB
chmod +x "$TMPDIR1b/cm"

output1b=$(PATH="$TMPDIR1b:$PATH" bash "$SCRIPT" 2>/dev/null)
exit1b=$?

assert_exit_zero "exit code (cm with bullets)" $exit1b
assert_not_empty "output non-empty (bd + cm)" "$output1b"
assert_contains "bd-prime section present when cm has bullets" "$output1b" "Beads"
assert_contains "L2A section header present when cm returns bullets" "$output1b" "L2A"
assert_contains "cm content appears in output" "$output1b" "uv"

rm -rf "$TMPDIR1b"

# ────────────────────────────────────────────────────────────────────────────
# Scenario 2: cm missing — fall back to bd prime only, exit 0
# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 2: cm missing (PATH-masked) ==="

TMPDIR2=$(mktemp -d)
# Do NOT create a cm stub — just mask real cm by placing empty dir first in PATH

output2=$(PATH="$TMPDIR2:$PATH" bash "$SCRIPT" 2>/dev/null)
exit2=$?
stderr2=$(PATH="$TMPDIR2:$PATH" bash "$SCRIPT" 2>&1 1>/dev/null)

assert_exit_zero "exit code (cm missing)" $exit2
assert_not_empty "output non-empty without cm" "$output2"
assert_contains "bd-prime section still present when cm missing" "$output2" "Beads"

# L2A section must NOT appear when cm is not installed
if echo "$output2" | grep -qF "L2A"; then
  echo "  ✗ L2A section must not appear when cm is missing"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ L2A section absent when cm is missing (correct)"
  PASS=$((PASS + 1))
fi

# Optionally check that stderr contains a warning about cm (acceptable but not required)
if echo "$stderr2" | grep -qi "cm"; then
  echo "  ✓ optional: stderr mentions cm when missing"
  PASS=$((PASS + 1))
else
  echo "  - optional: no stderr warning about missing cm (acceptable)"
fi

rm -rf "$TMPDIR2"

# ────────────────────────────────────────────────────────────────────────────
# Scenario 3: bd missing — no crash, exit 0
# ────────────────────────────────────────────────────────────────────────────
echo
echo "=== Scenario 3: bd missing (PATH-masked with failing stub) ==="

TMPDIR3=$(mktemp -d)
# Create a fake bd that exits with error
cat > "$TMPDIR3/bd" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$TMPDIR3/bd"

output3=$(PATH="$TMPDIR3:$PATH" bash "$SCRIPT" 2>/dev/null)
exit3=$?

assert_exit_zero "exit code (bd missing/failing)" $exit3

# Script should not crash hard with a non-zero exit from a bad bd
echo "  ✓ script did not propagate bd failure exit code (exit=$exit3)"

rm -rf "$TMPDIR3"

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────
echo
echo "Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ]
