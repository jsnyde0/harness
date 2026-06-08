#!/usr/bin/env bash
# Regression test for bd-close-verdict-check.sh.
# Creates ephemeral probe beads, exercises each scenario, asserts the hook output,
# then deletes the probes. Run from any CWD inside a beads workspace.
#
# Usage: bash $CLAUDE_HOME/hooks/bd-close-verdict-check.test.sh

set -u
HOOK="$HOME/.claude/hooks/bd-close-verdict-check.sh"
PASS=0
FAIL=0
PROBES=()

cleanup() {
  if [ ${#PROBES[@]} -gt 0 ]; then
    bd delete "${PROBES[@]}" --force >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

assert_warns() {
  local desc=$1 cmd=$2 needle=$3
  local out
  out=$(echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | "$HOOK" 2>&1)
  if echo "$out" | grep -qF "$needle"; then
    echo "  ✓ $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ $desc"
    echo "    expected to contain: $needle"
    echo "    actual: $out"
    FAIL=$((FAIL+1))
  fi
}

assert_silent() {
  local desc=$1 cmd=$2
  local out
  out=$(echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | "$HOOK" 2>&1)
  if [ -z "$out" ]; then
    echo "  ✓ $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ $desc"
    echo "    expected silent; actual: $out"
    FAIL=$((FAIL+1))
  fi
}

# Probe 1: bead with non-empty acceptance, no verdict.
ID1=$(bd create --type=task --title="y0c-test: no-verdict probe" --acceptance="probe" --description="test" 2>&1 | grep -oE 'claude-[A-Za-z0-9.]+' | head -1)
PROBES+=("$ID1")
echo "[no-verdict] $ID1"
assert_warns "no verdict warns" "bd close $ID1" "no verdict"
assert_warns "bd done alias warns" "bd done $ID1" "no verdict"

# Probe 2: bead with fresh PASS by a different actor → silent.
ID2=$(bd create --type=task --title="y0c-test: pass probe" --acceptance="probe" --description="test" 2>&1 | grep -oE 'claude-[A-Za-z0-9.]+' | head -1)
PROBES+=("$ID2")
echo "[fresh-pass] $ID2"
echo "{\"kind\":\"verdict\",\"issue_id\":\"$ID2\",\"extra\":{\"verdict\":\"pass\"}}" | BEADS_ACTOR=reviewer:fresh-subagent bd audit record --stdin >/dev/null
assert_silent "fresh pass by ≠author silent" "bd close $ID2"

# Probe 3: stale verdict (bead mutated after stamp).
ID3=$(bd create --type=task --title="y0c-test: stale probe" --acceptance="probe" --description="test" 2>&1 | grep -oE 'claude-[A-Za-z0-9.]+' | head -1)
PROBES+=("$ID3")
echo "[stale] $ID3"
echo "{\"kind\":\"verdict\",\"issue_id\":\"$ID3\",\"extra\":{\"verdict\":\"pass\"}}" | BEADS_ACTOR=reviewer:fresh-subagent bd audit record --stdin >/dev/null
sleep 1
bd update "$ID3" --design="stale-mutation" >/dev/null
assert_warns "stale verdict warns" "bd close $ID3" "stale verdict"

# Probe 4: FAIL verdict latest → warn.
ID4=$(bd create --type=task --title="y0c-test: fail probe" --acceptance="probe" --description="test" 2>&1 | grep -oE 'claude-[A-Za-z0-9.]+' | head -1)
PROBES+=("$ID4")
echo "[fail] $ID4"
echo "{\"kind\":\"verdict\",\"issue_id\":\"$ID4\",\"extra\":{\"verdict\":\"fail\"}}" | BEADS_ACTOR=reviewer:fresh-subagent bd audit record --stdin >/dev/null
assert_warns "verdict:fail warns" "bd close $ID4" "verdict:fail"

# Probe 5: latest-wins (fail then pass → silent per 5f1.4.4 D3 as edited 2026-05-12).
ID5=$(bd create --type=task --title="y0c-test: latest-wins probe" --acceptance="probe" --description="test" 2>&1 | grep -oE 'claude-[A-Za-z0-9.]+' | head -1)
PROBES+=("$ID5")
echo "[latest-wins fail→pass] $ID5"
echo "{\"kind\":\"verdict\",\"issue_id\":\"$ID5\",\"extra\":{\"verdict\":\"fail\"}}" | BEADS_ACTOR=reviewer:fresh-subagent bd audit record --stdin >/dev/null
sleep 1
echo "{\"kind\":\"verdict\",\"issue_id\":\"$ID5\",\"extra\":{\"verdict\":\"pass\"}}" | BEADS_ACTOR=reviewer:fresh-subagent bd audit record --stdin >/dev/null
assert_silent "fail-then-pass silent (latest wins)" "bd close $ID5"

# Probe 6: empty acceptance_criteria → silent.
ID6=$(bd create --type=task --title="y0c-test: empty-acceptance probe" --description="test" 2>&1 | grep -oE 'claude-[A-Za-z0-9.]+' | head -1)
PROBES+=("$ID6")
echo "[empty-acceptance] $ID6"
assert_silent "empty acceptance silent" "bd close $ID6"

# Probe 7: self-review (verdict actor == created_by).
ID7=$(BEADS_ACTOR=alice bd create --type=task --title="y0c-test: self-review probe" --acceptance="probe" --description="test" 2>&1 | grep -oE 'claude-[A-Za-z0-9.]+' | head -1)
PROBES+=("$ID7")
echo "[self-review] $ID7"
echo "{\"kind\":\"verdict\",\"issue_id\":\"$ID7\",\"extra\":{\"verdict\":\"pass\"}}" | BEADS_ACTOR=alice bd audit record --stdin >/dev/null
assert_warns "self-review warns" "bd close $ID7" "self-review"

# Multi-ID + quoted-string + reason flag — should not produce jq errors or warn-spam.
echo "[multi-id-with-reason]"
assert_warns "multi-id batched warns only on real IDs" \
  "bd close --reason='see also bd close fix' $ID1 $ID4" "verdict:fail"
out=$(echo "{\"tool_input\":{\"command\":\"bd close --reason='see also bd close fix' $ID1 $ID4\"}}" | "$HOOK" 2>&1)
if echo "$out" | grep -qF 'jq:'; then
  echo "  ✗ jq error leaks to output: $out"
  FAIL=$((FAIL+1))
else
  echo "  ✓ no jq error leakage"
  PASS=$((PASS+1))
fi

# Non-close bd commands → silent.
echo "[non-close]"
assert_silent "bd ready silent" "bd ready"
assert_silent "bd list silent" "bd list --status=open"
assert_silent "bd update silent" "bd update foo --status=in_progress"

# bd close with global flag before subcommand → still triggers.
echo "[bd -C ... close]"
assert_warns "bd -C /tmp close <id> still triggers" "bd -C /tmp close $ID1" "no verdict"

# bd close with no args (uses last-touched).
echo "[no-args]"
bd show "$ID1" >/dev/null  # update last-touched to ID1
assert_warns "bd close (no args) checks last-touched" "bd close" "no verdict"

# Nonexistent bead ID → silent (no jq error spam).
echo "[nonexistent]"
assert_silent "nonexistent bead silently skipped" "bd close claude-nosuchbead"

echo
echo "Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ]
