#!/usr/bin/env bash
# END-TO-END test: verify the REAL install.sh-emitted dcg adapter fires on codex exec.
#
# This test was redesigned after the prior version was rejected as a TAUTOLOGY:
#   - Prior: fired a bespoke hand-written hook, never invoked the install.sh-emitted adapter
#   - Prior: used --dangerously-bypass-hook-trust instead of the production trusted_hash mechanism
#
# This test MUST:
#   (a) Run the ACTUAL install.sh into a throwaway CODEX_HOME (auth.json symlinked)
#   (b) Test the adapter contract: pipe denied JSON → dcg-codex-hook.sh → assert Codex wire shape
#   (c) Run codex exec WITHOUT --dangerously-bypass-hook-trust, relying on seeded trusted_hash
#   (d) Use DCG_CONFIG with a custom block rule to deny "echo CODEX_HOOK_SENTINEL" (harmless)
#   (e) Attribution probe: also run with bypass flag to determine which mechanism fires the adapter
#
# GREEN = sentinel is BLOCKED by the real dcg adapter + codex.hooks.run fires
# RED   = CODEX_HOOK_SENTINEL appears in output (hook inert / hash wrong / adapter untouched)
#
# Safety invariants:
#   - ONLY "echo CODEX_HOOK_SENTINEL" as deny target via a TEST DCG_CONFIG — zero blast radius
#   - auth.json SYMLINKED from real ~/.codex — bytes never read
#   - Throwaway CODEX_HOME; real ~/.codex/config.toml NEVER mutated
#   - Verified at exit: real config.toml unchanged
#   - D2 invariant: agent/extensions/hooks/{core.mjs,index.ts} untouched

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTPI_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REAL_CODEX_CONFIG="$HOME/.codex/config.toml"
REAL_CODEX_CONFIG_CHECKSUM=""

PASS=0
FAIL=0
TOTAL_ASSERTIONS=0

# ── Assertions ──────────────────────────────────────────────────────────────────

check() {
  local label="$1"
  local result="$2"
  TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + 1))
  if [ "$result" = "ok" ]; then
    echo "  PASS [$TOTAL_ASSERTIONS]: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL [$TOTAL_ASSERTIONS]: $label"
    echo "         reason: $result"
    FAIL=$((FAIL + 1))
  fi
}

# ── Throwaway home ──────────────────────────────────────────────────────────────

THROWAWAY_HOME="/tmp/dotpi-e2e-sentinel-$$"
THROWAWAY_CODEX="$THROWAWAY_HOME/.codex"
DCG_TEST_CONFIG="/tmp/dotpi-dcg-sentinel-$$.toml"

cleanup() {
  local exit_code=$?
  echo ""
  echo "--- Cleanup ---"
  rm -rf "$THROWAWAY_HOME" 2>/dev/null || true
  rm -f "$DCG_TEST_CONFIG" 2>/dev/null || true

  # Verify real ~/.codex/config.toml is unchanged
  if [ -f "$REAL_CODEX_CONFIG" ] && [ -n "$REAL_CODEX_CONFIG_CHECKSUM" ]; then
    current_checksum=$(shasum -a 256 "$REAL_CODEX_CONFIG" | awk '{print $1}')
    if [ "$current_checksum" = "$REAL_CODEX_CONFIG_CHECKSUM" ]; then
      echo "  VERIFIED: real ~/.codex/config.toml is UNCHANGED (checksum matches)"
    else
      echo "  ERROR: real ~/.codex/config.toml was MODIFIED! This is a safety violation."
      exit 2
    fi
  fi
  echo "  Cleaned up $THROWAWAY_HOME"
  if [ $exit_code -ne 0 ] && [ "$FAIL" -eq 0 ]; then
    echo "  Script exited with unexpected error code $exit_code"
  fi
}
trap cleanup EXIT

echo "=== Codex hook sentinel — END-TO-END real adapter test ==="
echo "Throwaway CODEX_HOME: $THROWAWAY_CODEX"
echo "DCG test config: $DCG_TEST_CONFIG"
echo ""

# ── 0. Pre-flight: Snapshot real config.toml checksum ────────────────────────────

if [ -f "$REAL_CODEX_CONFIG" ]; then
  REAL_CODEX_CONFIG_CHECKSUM=$(shasum -a 256 "$REAL_CODEX_CONFIG" | awk '{print $1}')
  echo "Real ~/.codex/config.toml checksum: $REAL_CODEX_CONFIG_CHECKSUM"
else
  echo "WARNING: no real ~/.codex/config.toml found — skipping mutation check"
fi

# ── 1. Create throwaway CODEX_HOME ──────────────────────────────────────────────

mkdir -p "$THROWAWAY_CODEX"

# Symlink auth.json from real home (NEVER read its bytes)
if [ -f "$HOME/.codex/auth.json" ]; then
  ln -s "$HOME/.codex/auth.json" "$THROWAWAY_CODEX/auth.json"
  echo "Symlinked auth.json from real ~/.codex/auth.json"
  check "auth.json symlinked (bytes not read)" "ok"
else
  echo "WARNING: no ~/.codex/auth.json — codex exec will likely fail (no auth)"
  check "auth.json symlinked (bytes not read)" "no auth.json found — codex exec may fail"
fi

# ── 2. Create DCG test config: blocks CODEX_HOOK_SENTINEL ────────────────────────

cat > "$DCG_TEST_CONFIG" << 'DCGEOF'
# Test-only dcg config: denies "echo CODEX_HOOK_SENTINEL" for e2e hook-fire proof.
# This is NOT a real dcg config — it only exists for the duration of this test.
[overrides]
block = [
    { pattern = "CODEX_HOOK_SENTINEL", reason = "dotpi-sentinel-test: blocked by test dcg policy" },
]
DCGEOF

# Verify the test config actually denies the sentinel
dcg_test_output=$(DCG_CONFIG="$DCG_TEST_CONFIG" dcg test --format json "echo CODEX_HOOK_SENTINEL" 2>&1 || true)
if echo "$dcg_test_output" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('decision')=='deny' else 1)" 2>/dev/null; then
  check "DCG test config denies 'echo CODEX_HOOK_SENTINEL'" "ok"
else
  check "DCG test config denies 'echo CODEX_HOOK_SENTINEL'" "dcg did not deny: $dcg_test_output"
fi

# Verify normal dcg (without test config) ALLOWS the sentinel (baseline)
dcg_baseline=$(dcg test --format json "echo CODEX_HOOK_SENTINEL" 2>&1 || true)
if echo "$dcg_baseline" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('decision')=='allow' else 1)" 2>/dev/null; then
  check "Normal dcg ALLOWS 'echo CODEX_HOOK_SENTINEL' (baseline — not a real dcg deny)" "ok"
else
  check "Normal dcg ALLOWS 'echo CODEX_HOOK_SENTINEL' (baseline — not a real dcg deny)" "dcg denied unexpectedly: $dcg_baseline"
fi

echo ""
echo "--- Step 3: Run ACTUAL install.sh into throwaway home ---"

# ── 3. Run the ACTUAL install.sh into throwaway home ────────────────────────────

INSTALL_OUTPUT=$(DOTPI_TEST_TARGET="$THROWAWAY_HOME" bash "$DOTPI_ROOT/install.sh" 2>&1) || INSTALL_EXIT_STATUS=$?
echo "$INSTALL_OUTPUT"
echo ""

if [ -z "${INSTALL_EXIT_STATUS:-}" ]; then
  check "install.sh completed successfully" "ok"
else
  check "install.sh completed successfully" "exit code $INSTALL_EXIT_STATUS"
fi

# Verify the adapter was generated
ADAPTER_PATH="$THROWAWAY_CODEX/dcg-codex-hook.sh"
if [ -f "$ADAPTER_PATH" ] && [ -x "$ADAPTER_PATH" ]; then
  check "dcg-codex-hook.sh adapter generated and executable" "ok"
else
  check "dcg-codex-hook.sh adapter generated and executable" "not found or not executable: $ADAPTER_PATH"
fi

# Verify config.toml has [hooks] section
THROWAWAY_CONFIG="$THROWAWAY_CODEX/config.toml"
if [ -f "$THROWAWAY_CONFIG" ]; then
  parse_result=$(uv run python3 -c "
import sys
with open('$THROWAWAY_CONFIG', 'rb') as f:
    import tomllib
    d = tomllib.load(f)
hooks = d.get('hooks', {})
pre = hooks.get('PreToolUse', [])
state = hooks.get('state', {})
print(f'PreToolUse_groups={len(pre)},state_keys={len(state)}')
" 2>&1) || true
  if echo "$parse_result" | grep -q "PreToolUse_groups="; then
    check "config.toml has [hooks] + trust state: $parse_result" "ok"
  else
    check "config.toml has [hooks] + trust state" "parse failed: $parse_result"
  fi
else
  check "config.toml generated" "not found: $THROWAWAY_CONFIG"
fi

# Verify no stale hooks.toml
if [ ! -f "$THROWAWAY_CODEX/hooks.toml" ]; then
  check "No stale hooks.toml (old-wiring artifact removed)" "ok"
else
  check "No stale hooks.toml (old-wiring artifact removed)" "hooks.toml unexpectedly present"
fi

echo ""
echo "--- Step 4: Adapter unit test (criterion b) ---"
echo "Pipe denied tool-call JSON through dcg-codex-hook.sh → assert Codex wire shape"

# ── 4. Adapter contract unit test (criterion b) ─────────────────────────────────
# Pipe a denied tool-call JSON through the REAL generated adapter.
# Use git reset --hard as the denied command (dcg denies it natively — no blast radius:
# we are testing dcg's EVALUATION of the command, not executing it).

DENY_JSON='{"tool_input": {"command": "git reset --hard"}}'

adapter_output=$(printf '%s' "$DENY_JSON" | python3 "$ADAPTER_PATH" 2>&1)
adapter_exit=$?

echo "Adapter input JSON: $DENY_JSON"
echo "Adapter stdout: $adapter_output"
echo "Adapter exit code: $adapter_exit"
echo ""

# Assert: stdout is valid JSON with the correct Codex wire shape
adapter_check=$(echo "$adapter_output" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ho = d.get('hookSpecificOutput', {})
    event = ho.get('hookEventName', '')
    decision = ho.get('permissionDecision', '')
    reason = ho.get('permissionDecisionReason', '')
    errors = []
    if event != 'PreToolUse':
        errors.append(f'hookEventName={repr(event)} (expected PreToolUse)')
    if decision != 'deny':
        errors.append(f'permissionDecision={repr(decision)} (expected deny)')
    if not reason:
        errors.append('permissionDecisionReason is empty')
    if errors:
        print('FAIL: ' + '; '.join(errors))
    else:
        print('ok')
except Exception as e:
    print(f'FAIL: JSON parse error: {e}')
" 2>&1)

if [ "$adapter_check" = "ok" ]; then
  check "Adapter emits Codex wire shape for denied command" "ok"
else
  check "Adapter emits Codex wire shape for denied command" "$adapter_check"
fi

# Assert: the deny reason contains dcg's actual reason (not a hardcoded string)
dcg_reason_check=$(echo "$adapter_output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
reason = d.get('hookSpecificOutput', {}).get('permissionDecisionReason', '')
# Should mention 'git reset --hard' or 'stash' — dcg's real reason
if 'stash' in reason.lower() or 'git reset' in reason.lower() or 'uncommitted' in reason.lower():
    print('ok')
else:
    print(f'reason does not look like dcg real reason: {repr(reason[:120])}')
" 2>&1)

if [ "$dcg_reason_check" = "ok" ]; then
  check "Adapter deny reason is dcg's real reason (not hardcoded)" "ok"
else
  check "Adapter deny reason is dcg's real reason (not hardcoded)" "$dcg_reason_check"
fi

# Assert with SENTINEL + DCG_CONFIG: adapter also denies via custom config
adapter_sentinel=$(printf '{"tool_input": {"command": "echo CODEX_HOOK_SENTINEL"}}' | DCG_CONFIG="$DCG_TEST_CONFIG" python3 "$ADAPTER_PATH" 2>&1)
sentinel_adapter_check=$(echo "$adapter_sentinel" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ho = d.get('hookSpecificOutput', {})
    if ho.get('permissionDecision') == 'deny' and ho.get('hookEventName') == 'PreToolUse' and ho.get('permissionDecisionReason'):
        print('ok')
    else:
        print(f'unexpected output: {d}')
except Exception as e:
    print(f'JSON parse error: {e}: raw={repr(sys.stdin.read()[:200])}')
" 2>&1)
if [ "$sentinel_adapter_check" = "ok" ]; then
  check "Adapter with DCG_CONFIG denies sentinel (hookEventName=PreToolUse, decision=deny, reason non-empty)" "ok"
else
  check "Adapter with DCG_CONFIG denies sentinel (hookEventName=PreToolUse, decision=deny, reason non-empty)" "$sentinel_adapter_check"
fi

echo ""
echo "--- Step 5: D2 invariant check ---"

# ── 5. D2 invariant: runner files must be unchanged ──────────────────────────────

d2_diff=$(git -C "$DOTPI_ROOT" diff agent/extensions/hooks/core.mjs agent/extensions/hooks/index.ts 2>&1)
if [ -z "$d2_diff" ]; then
  check "D2 invariant: agent/extensions/hooks/{core.mjs,index.ts} diff is EMPTY" "ok"
else
  check "D2 invariant: agent/extensions/hooks/{core.mjs,index.ts} diff is EMPTY" "diff NOT empty (D2 violation): $d2_diff"
fi

echo ""
echo "--- Step 6: Attribution probe — does bypass flag fire the REAL adapter? ---"
echo "(This probe empirically determines whether bypass flag or trusted_hash fires hooks)"

# ── 6. Attribution probe: bypass flag variant ────────────────────────────────────
# Run codex exec WITH --dangerously-bypass-hook-trust + no trusted_hash seeds.
# This tells us: does the bypass flag alone make the real adapter fire?
# We use a SECOND throwaway CODEX_HOME that has the hooks config but NO trust seeds.

BYPASS_CODEX="$THROWAWAY_HOME/.codex-bypass-probe"
mkdir -p "$BYPASS_CODEX"
# Symlink auth.json here too
if [ -f "$HOME/.codex/auth.json" ]; then
  ln -s "$HOME/.codex/auth.json" "$BYPASS_CODEX/auth.json"
fi

# Build a config.toml WITH the hooks section but WITHOUT trusted_hash seeds
python3 - "$THROWAWAY_CONFIG" "$BYPASS_CODEX/config.toml" << 'PYEOF'
import sys, re

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    content = f.read()

# Strip the [hooks.state.*] trust seed sections (comment block + all [hooks.state.*] entries)
# Pattern: strip from "# dotpi hook trust seeds" through end of all trust state TOML blocks
content = re.sub(
    r'\n# dotpi hook trust seeds[^\n]*\n(?:[^\n]+\n)*',
    '\n',
    content,
    flags=re.DOTALL
)
# Strip remaining [hooks.state."..."] table entries
content = re.sub(
    r'\n\[hooks\.state\."[^"]+"\]\n(?:.*\n)*?(?=\n\[|\Z)',
    '\n',
    content,
    flags=re.DOTALL
)
content = content.rstrip()

with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write(content)
print("Written bypass-probe config (no trust seeds)")
PYEOF

echo ""
echo "Bypass-probe config.toml (last 20 lines):"
tail -20 "$BYPASS_CODEX/config.toml"
echo ""

echo "Running codex exec WITH --dangerously-bypass-hook-trust (no trusted_hash seeds)..."
BYPASS_OUTPUT=$(CODEX_HOME="$BYPASS_CODEX" \
  DCG_CONFIG="$DCG_TEST_CONFIG" \
  codex exec \
    --dangerously-bypass-hook-trust \
    --skip-git-repo-check \
    -s danger-full-access \
    "Run this exact shell command and show me the output: echo CODEX_HOOK_SENTINEL" \
    2>&1) || true

echo "=== bypass-probe output (first 60 lines) ==="
echo "$BYPASS_OUTPUT" | head -60
echo "========================="
echo ""

if echo "$BYPASS_OUTPUT" | grep -q "CODEX_HOOK_SENTINEL"; then
  BYPASS_SENTINEL_BLOCKED="no"
  echo "ATTRIBUTION: bypass flag variant — sentinel APPEARED (hook did NOT fire with bypass flag alone)"
else
  BYPASS_SENTINEL_BLOCKED="yes"
  echo "ATTRIBUTION: bypass flag variant — sentinel BLOCKED (hook fired with bypass flag)"
fi

echo ""
echo "--- Step 7: END-TO-END — no bypass flag, real trusted_hash (production path) ---"
echo "(This is the DISCRIMINATING test — criterion c)"

# ── 7. End-to-end: no bypass flag, rely on trusted_hash ─────────────────────────
# This is the production trust mechanism. If the hash is wrong → fail-open → sentinel prints → RED.
# RUST_LOG=codex_core::hook_runtime=debug would show codex.hooks.run spans but may not be parseable.

echo ""
echo "Running codex exec WITHOUT --dangerously-bypass-hook-trust (relying on seeded trusted_hash)..."
echo "Command: echo CODEX_HOOK_SENTINEL should be BLOCKED by real dcg adapter"
echo ""

NOHASH_OUTPUT=$(CODEX_HOME="$THROWAWAY_CODEX" \
  DCG_CONFIG="$DCG_TEST_CONFIG" \
  RUST_LOG="codex_core::hook_runtime=debug" \
  codex exec \
    --skip-git-repo-check \
    -s danger-full-access \
    "Run this exact shell command and show me the output: echo CODEX_HOOK_SENTINEL" \
    2>&1) || true

echo "=== no-bypass output (first 80 lines) ==="
echo "$NOHASH_OUTPUT" | head -80
echo "========================="
echo ""

# --- DISCRIMINATING ASSERTIONS ---
# The CODEX_HOOK_SENTINEL text can appear in Codex's deny reason explanation
# (e.g., "blocked... Command: echo CODEX_HOOK_SENTINEL"). What must NOT appear
# is the hook EXECUTING — i.e., the shell running the command and printing output.
# Codex reports a blocked command with "blocked by a `PreToolUse` hook" message.
# Codex reports hook fire with "hook: PreToolUse Blocked" status.

# Assertion 1: The hook must have BLOCKED the command
# Evidence: "hook: PreToolUse Blocked" appears AND Codex says "blocked by a"
if echo "$NOHASH_OUTPUT" | grep -q "Blocked" ; then
  check "E2E [no-bypass]: hook reports 'Blocked' status (command was denied by PreToolUse)" "ok"
else
  check "E2E [no-bypass]: hook reports 'Blocked' status (command was denied by PreToolUse)" \
    "no 'Blocked' in output — hook did NOT fire (hash wrong, hook untrusted, or adapter failed)"
fi

# Assertion 2: The SPECIFIC dcg deny reason must appear (not a loose grep on unrelated messages)
# dcg's reason for sentinel: "dotpi-sentinel-test: blocked by test dcg policy"
if echo "$NOHASH_OUTPUT" | grep -q "dotpi-sentinel-test"; then
  check "E2E [no-bypass]: SPECIFIC dcg deny reason 'dotpi-sentinel-test' present in Codex output" "ok"
else
  check "E2E [no-bypass]: SPECIFIC dcg deny reason 'dotpi-sentinel-test' present in Codex output" \
    "specific deny reason not found — hook may not have fired or reason not propagated to user output"
fi

# Assertion 3: The command must NOT have EXECUTED (no shell output line "CODEX_HOOK_SENTINEL\n")
# "hook: PreToolUse Blocked" means the exec was cancelled — the shell was never run.
# If the sentinel had run, we'd see: "succeeded in 0ms:\nCODEX_HOOK_SENTINEL"
if echo "$NOHASH_OUTPUT" | grep -qE "succeeded in [0-9]+ms:" ; then
  check "E2E [no-bypass]: command did NOT execute (no 'succeeded in Nms:' exec report)" \
    "command was executed — hook failed to block it"
else
  check "E2E [no-bypass]: command did NOT execute (no 'succeeded in Nms:' exec report)" "ok"
fi

# Informational: hook runtime visibility
if echo "$NOHASH_OUTPUT" | grep -qE "hook: PreToolUse"; then
  echo "  INFO: 'hook: PreToolUse' lines visible in output (hook runtime confirmed)"
fi

# ── 8. Attribution conclusion ─────────────────────────────────────────────────────

echo ""
echo "--- Step 8: Attribution conclusion ---"
echo "Bypass flag variant sentinel blocked: $BYPASS_SENTINEL_BLOCKED"

# Determine if trusted_hash path blocked the command
nohash_sentinel_blocked="no"
if echo "$NOHASH_OUTPUT" | grep -q "Blocked" ; then
  nohash_sentinel_blocked="yes"
fi
echo "No-bypass (trusted_hash) variant sentinel blocked: $nohash_sentinel_blocked"
if echo "$NOHASH_OUTPUT" | grep -q "dotpi-sentinel-test"; then
  echo "Specific dcg reason appeared: yes"
else
  echo "Specific dcg reason appeared: no"
fi

if [ "$nohash_sentinel_blocked" = "yes" ]; then
  echo "ATTRIBUTION RESULT: trusted_hash mechanism WORKS — hook fires without bypass flag"
  echo "  The seeded trusted_hash in config.toml grants HookTrustStatus::Trusted on the hook."
  echo "  Production install path is proven: trusted_hash, not bypass flag, is what fires the adapter."
  check "Attribution: trusted_hash is the production mechanism and it fires the real adapter" "ok"
elif [ "$BYPASS_SENTINEL_BLOCKED" = "yes" ]; then
  echo "ATTRIBUTION RESULT: bypass flag fires hook, but trusted_hash does NOT (hash mismatch)"
  echo "  → Finding 4+8 realized: compute_hook_hash reimplementation is wrong"
  check "Attribution: trusted_hash is the production mechanism and it fires the real adapter" \
    "RAISE: trusted_hash does not fire adapter; bypass flag does — hash reimplementation is wrong"
else
  echo "ATTRIBUTION RESULT: NEITHER mechanism fires the hook — fundamental issue"
  check "Attribution: trusted_hash is the production mechanism and it fires the real adapter" \
    "RAISE: neither bypass flag nor trusted_hash fires the real adapter"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL_ASSERTIONS total assertions) ==="

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "FAIL — $FAIL assertion(s) failed"
  exit 1
fi
echo "ALL PASS"
