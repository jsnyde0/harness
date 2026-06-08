#!/usr/bin/env bash
# Hook: warn on `bd close` when a closing bead lacks a fresh adversarial-review verdict.
# Substrate landing for the close-time verdict design / ADR-012 D3 / reviewer-identity design D4 (warn-not-block).
#
# Trigger: PreToolUse on Bash, command runs `bd close` or `bd done` (possibly with
# preceding env-var assignments and/or bd global flags).
#
# Behavior: emits a non-blocking warning via JSON systemMessage + permissionDecision:allow
# for each bead with non-empty acceptance_criteria where any of:
#   - no kind=verdict audit entry exists in .beads/interactions.jsonl, OR
#   - latest verdict entry's extra.verdict == "fail", OR
#   - verdict-add actor equals bead's created_by (self-review), OR
#   - bead.updated_at > latest_verdict.created_at (stale).
#
# Beads with empty acceptance_criteria, non-existent IDs, or unparseable tokens are
# silently skipped. exit 0 always; bd close proceeds in all cases.
#
# Per the reviewer-identity design bead D3 (as edited in-place 2026-05-12 per ADR-011 D1): latest-verdict-wins
# semantics — fail-then-pass closes silently. The earlier "conjunctive" reading was
# over-restrictive (broke /adversarial-review's retry-to-pass flow).
#
# Dual-write contract (recipes own — see adversarial-review SKILL.md "Verdict dual-write"):
#   BEADS_ACTOR=<role> bd update <id> --add-label=verdict:pass
#   echo '{"kind":"verdict","issue_id":"<id>","extra":{"verdict":"pass"}}' \
#     | BEADS_ACTOR=<role> bd audit record --stdin

set -u

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Cheap pre-filter: command must contain `bd ... close|done` with arbitrary
# global flags between `bd` and the subcommand (e.g. `bd -C /path close <id>`,
# `BEADS_DB=/x bd --db=/y close <id>`). Use a permissive look.
echo "$COMMAND" | grep -qE '\bbd(\s+-{1,2}[A-Za-z][A-Za-z0-9-]*(=\S+|\s+\S+)?)*\s+(close|done)\b' || exit 0

# Extract positional ID args.  Token rules:
#   - Skip env-var assignments (FOO=bar) before bd.
#   - Skip the literal `bd` and any global flags (anything starting with `-`, plus
#     value-taking flags' values).
#   - After matching `(close|done)`, collect non-flag tokens that look like bd IDs.
# Bead-ID shape: <prefix>-<suffix> where prefix is [a-z]+ and suffix is alnum/.;
# this excludes shell tokens like "bd", "close", "fix", quoted-string fragments, etc.
BEAD_IDS=$(echo "$COMMAND" | perl -ne '
  my $line = $_;
  # Drop trailing pipes/chains/redirects (best-effort; compound-commands hook usually blocks).
  $line =~ s/[|&;].*$//;
  # Match the bd ... close|done segment; greedy so we get the latest close in the line.
  if ($line =~ /\bbd(?:\s+(?:-{1,2}[A-Za-z][A-Za-z0-9-]*(?:=\S+)?|\S+))*?\s+(?:close|done)(\s+.*)?$/) {
    my $args = defined($1) ? $1 : "";
    my @toks = split /\s+/, $args;
    my %value_flags = map { $_ => 1 } qw(-r --reason --reason-file --session --db -C --directory --dolt-auto-commit);
    my @ids;
    while (@toks) {
      my $t = shift @toks;
      next if $t eq "";
      if (exists $value_flags{$t}) { shift @toks; next; }
      next if $t =~ /^-/;
      push @ids, $t if $t =~ /^[a-z]+-[A-Za-z0-9.]+$/;
    }
    print "$_\n" for @ids;
    # Marker: empty positional args means `bd close` (no IDs) → uses last-touched.
    print "__LAST_TOUCHED__\n" if !@ids;
  }
')
[ -z "$BEAD_IDS" ] && exit 0

# Resolve __LAST_TOUCHED__ marker to .beads/last-touched contents if found.
if echo "$BEAD_IDS" | grep -q '^__LAST_TOUCHED__$'; then
  LAST_TOUCHED_FILE=""
  DIR="$PWD"
  while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
    if [ -f "$DIR/.beads/last-touched" ]; then
      LAST_TOUCHED_FILE="$DIR/.beads/last-touched"
      break
    fi
    DIR=$(dirname "$DIR")
  done
  if [ -n "$LAST_TOUCHED_FILE" ]; then
    LAST_ID=$(tr -d '[:space:]' < "$LAST_TOUCHED_FILE")
    if [ -n "$LAST_ID" ]; then
      BEAD_IDS=$(echo "$BEAD_IDS" | sed "s|^__LAST_TOUCHED__$|$LAST_ID|")
    else
      BEAD_IDS=$(echo "$BEAD_IDS" | grep -v '^__LAST_TOUCHED__$')
    fi
  else
    BEAD_IDS=$(echo "$BEAD_IDS" | grep -v '^__LAST_TOUCHED__$')
  fi
fi
[ -z "$BEAD_IDS" ] && exit 0

# Locate nearest .beads/interactions.jsonl by walking up from CWD.
INTERACTIONS=""
DIR="$PWD"
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -f "$DIR/.beads/interactions.jsonl" ]; then
    INTERACTIONS="$DIR/.beads/interactions.jsonl"
    break
  fi
  DIR=$(dirname "$DIR")
done

WARNINGS=""
while IFS= read -r ID; do
  [ -z "$ID" ] && continue

  BEAD_JSON=$(bd show "$ID" --json 2>/dev/null)
  [ -z "$BEAD_JSON" ] && continue
  # bd show returns {"error":"...",...} on missing/invalid IDs (object, not array).
  # Detect and silently skip.
  if echo "$BEAD_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
    :
  else
    continue
  fi

  ACCEPTANCE=$(echo "$BEAD_JSON" | jq -r '.[0].acceptance_criteria // ""' 2>/dev/null)
  if [ -z "$ACCEPTANCE" ] || [ "$ACCEPTANCE" = "null" ]; then
    continue
  fi

  CREATED_BY=$(echo "$BEAD_JSON" | jq -r '.[0].created_by // ""' 2>/dev/null)
  UPDATED_AT=$(echo "$BEAD_JSON" | jq -r '.[0].updated_at // ""' 2>/dev/null)

  LATEST_VERDICT=""
  if [ -n "$INTERACTIONS" ]; then
    LATEST_VERDICT=$(jq -c --arg id "$ID" \
      'select(.issue_id == $id and .kind == "verdict")' \
      "$INTERACTIONS" 2>/dev/null | tail -1)
  fi

  if [ -z "$LATEST_VERDICT" ]; then
    WARNINGS+="  - ${ID}: no verdict — adversarial review not recorded"$'\n'
    continue
  fi

  VERDICT=$(echo "$LATEST_VERDICT" | jq -r '.extra.verdict // ""' 2>/dev/null)
  VERDICT_ACTOR=$(echo "$LATEST_VERDICT" | jq -r '.actor // ""' 2>/dev/null)
  VERDICT_TS=$(echo "$LATEST_VERDICT" | jq -r '.created_at // ""' 2>/dev/null)

  if [ "$VERDICT" = "fail" ]; then
    WARNINGS+="  - ${ID}: verdict:fail (actor=${VERDICT_ACTOR}, at ${VERDICT_TS})"$'\n'
    continue
  fi

  if [ -n "$VERDICT_ACTOR" ] && [ "$VERDICT_ACTOR" = "$CREATED_BY" ]; then
    WARNINGS+="  - ${ID}: self-review — verdict actor (${VERDICT_ACTOR}) equals create-event actor"$'\n'
    continue
  fi

  # Stale check via string lex compare. Normalize first: bd's updated_at has
  # second precision (e.g. "2026-05-12T09:37:01Z"); audit-record created_at has
  # microsecond precision ("...09:37:01.605408Z"). Naïve lex compare flips the
  # order because 'Z' > '.'. Strip fractional seconds and trailing Z to compare
  # consistently at second precision.
  if [ -n "$UPDATED_AT" ] && [ -n "$VERDICT_TS" ]; then
    u_norm="${UPDATED_AT%%.*}"; u_norm="${u_norm%Z}"
    v_norm="${VERDICT_TS%%.*}"; v_norm="${v_norm%Z}"
    if [[ "$u_norm" > "$v_norm" ]]; then
      WARNINGS+="  - ${ID}: stale verdict — bead mutated (${UPDATED_AT}) after verdict stamp (${VERDICT_TS})"$'\n'
      continue
    fi
  fi
done <<< "$BEAD_IDS"

if [ -n "$WARNINGS" ]; then
  REASON=$'bd close: adversarial-review verdict gap (ADR-012 D3):\n'"$WARNINGS"$'\nClose proceeds (warn-not-block). Stamp a fresh verdict via /adversarial-review to silence.'
  # PreToolUse warn-allow shape per Claude Code hook spec: systemMessage + allow.
  # stderr on exit 0 is NOT surfaced to user (per spec); use systemMessage only.
  jq -n --arg msg "$REASON" '{
    systemMessage: $msg,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow"
    }
  }'
fi

exit 0
