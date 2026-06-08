#!/usr/bin/env bash
# SessionStart hook: merge bd prime (L2B parking-lot) + cm context (L2A CASSMS playbook)
# into prime-time injection.
#
# Per ADR-013 D4 build item #2: SessionStart hook merging bd memories + cm context.
# Per ADR-012 D3: substrate-thick principle — both L2 surfaces surface at session open.
#
# Behavior:
#   1. Run `bd prime` and emit its output.
#   2. Detect cm: if missing, skip cm section (fall back to bd-only, no error).
#   3. Run `cm context "$task"` where task derives from:
#      - $CM_PRIME_TASK env var if set, OR
#      - basename of $PWD as a weak workspace signal.
#   4. If cm output is non-empty and useful (non-trivial content), emit under
#      a "## L2A — CASSMS context" section header so it's distinguishable.
#   5. If either tool fails, emit a one-line warning to stderr but continue.
#   6. Always exit 0 — do not block session start.
#
# Override task scope:
#   export CM_PRIME_TASK="implement user auth feature"

set -u

# Pin the cm store to the in-repo location (memory-sync/cass-store/) so this read
# path agrees with the synced playbook. Without this, cm resolves its store
# per-machine: via XDG_DATA_HOME where set, else the legacy ~/.cass-memory — a
# machine resolving elsewhere would read a stale/empty store and surface no L2A.
# Also set in ~/.zshenv; this is defense-in-depth for non-login hook contexts.
export CASS_MEMORY_HOME="${CASS_MEMORY_HOME:-$HOME/.claude/memory-sync/cass-store}"

# ────────────────────────────────────────────────────────────────────────────
# Filter: trim bd prime output to header-anchors.
# Cuts:
#   - "# 🚨 SESSION CLOSE PROTOCOL" block and everything below (Core Rules,
#     Essential Commands, Common Workflows) — pure reference material; bd --help
#     and CLAUDE.md serve the same purpose without taxing every session.
#   - Persistent-memory full-text bodies — replaced with `bd memories` index.
#
# Anchor-miss behavior: emits a warning at the TOP of injected content
# (visible to the agent) and falls through to unfiltered output rather than
# silently degrading. If bd prime upstream reformats and breaks anchors, the
# agent will surface the warning to the user instead of swallowing the bloat.
# ────────────────────────────────────────────────────────────────────────────
filter_bd_prime() {
  local input="$1"
  local mem_anchor='## Persistent Memories'
  local scp_anchor='# 🚨 SESSION CLOSE PROTOCOL'

  if ! printf '%s\n' "$input" | grep -q "^${mem_anchor}"; then
    printf '⚠️  bd-prime filter degraded: "%s" anchor missing. Emitting unfiltered output. Surface this to user — `bd prime` format may have shifted; check bd-prime-with-cm.sh in the methodology home hooks.\n\n' "$mem_anchor"
    printf '%s\n' "$input"
    return
  fi
  if ! printf '%s\n' "$input" | grep -q "^${scp_anchor}"; then
    printf '⚠️  bd-prime filter degraded: "%s" anchor missing. Emitting unfiltered output. Surface this to user.\n\n' "$scp_anchor"
    printf '%s\n' "$input"
    return
  fi

  local trimmed
  trimmed=$(printf '%s\n' "$input" | awk '/^# 🚨 SESSION CLOSE PROTOCOL/{exit} {print}')

  local preamble
  preamble=$(printf '%s\n' "$trimmed" | awk '/^## Persistent Memories/{exit} {print}')

  printf '%s\n' "$preamble"
  printf '## Persistent Memories (index — use `bd memories <keyword>` to retrieve full body)\n\n'
  if command -v bd >/dev/null 2>&1; then
    bd memories 2>/dev/null
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Step 1: Run bd prime, filter, emit
# ────────────────────────────────────────────────────────────────────────────
BD_OUTPUT=""
if command -v bd >/dev/null 2>&1; then
  BD_OUTPUT=$(bd prime 2>/dev/null) || {
    echo "[bd-prime-with-cm] WARNING: bd prime failed" >&2
    BD_OUTPUT=""
  }
else
  echo "[bd-prime-with-cm] WARNING: bd not found; skipping bd prime" >&2
fi

if [ -n "$BD_OUTPUT" ]; then
  filter_bd_prime "$BD_OUTPUT"
fi

# ────────────────────────────────────────────────────────────────────────────
# Step 2: Detect cm; if missing, done
# ────────────────────────────────────────────────────────────────────────────
if ! command -v cm >/dev/null 2>&1; then
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────────
# Step 3: Derive task scope
# ────────────────────────────────────────────────────────────────────────────
if [ -n "${CM_PRIME_TASK:-}" ]; then
  TASK="$CM_PRIME_TASK"
else
  # Use workspace basename as a weak signal
  WS_NAME=$(basename "$PWD")
  TASK="work in $WS_NAME"
fi

# ────────────────────────────────────────────────────────────────────────────
# Step 4: Run cm context and filter for useful output
# ────────────────────────────────────────────────────────────────────────────
CM_JSON=""
CM_JSON=$(cm context "$TASK" --json 2>/dev/null) || {
  echo "[bd-prime-with-cm] WARNING: cm context failed for task: $TASK" >&2
  exit 0
}

# Check if cm returned anything useful.
# Useful = at least one of: relevantBullets, antiPatterns, historySnippets is non-empty.
HAS_BULLETS=$(echo "$CM_JSON" | jq -r '(.data.relevantBullets | length) + (.data.antiPatterns | length) + (.data.historySnippets | length)' 2>/dev/null || echo "0")

if [ "$HAS_BULLETS" = "0" ] || [ -z "$HAS_BULLETS" ]; then
  # Empty playbook — no useful content to inject; skip gracefully (no garbage)
  exit 0
fi

# Emit the cm context section in markdown format (more readable for the agent)
CM_MD=""
CM_MD=$(cm context "$TASK" --format markdown 2>/dev/null) || {
  echo "[bd-prime-with-cm] WARNING: cm context markdown render failed" >&2
  exit 0
}

if [ -n "$CM_MD" ]; then
  echo ""
  echo "---"
  echo ""
  echo "## L2A — CASSMS context (cm context: $TASK)"
  echo ""
  echo "$CM_MD"
fi

exit 0
