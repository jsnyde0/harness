---
name: implement
description: Execute bead implementation (handles children via subagents)
---

Implement a bead using superpowers:tdd discipline.

**Arguments:** `$ARGUMENTS` → `<bead-id>`
- bead-id: required (ask if missing)

## CRITICAL RULE

**YOU (the orchestrator) MUST NEVER write code or implement beads directly.**

- You are the ORCHESTRATOR, not the implementer
- You DISPATCH subagents to do the work
- You NEVER touch code files yourself

This is not optional. This is not a guideline. This is a hard rule.

### Exception: Trivial beads

For **truly trivial** work (typo fix, single config change, <10 lines total), the orchestrator MAY use a single combined subagent that implements + self-reviews + commits. Use judgment—if there's any complexity, use the standard 2-subagent flow. Even here the done-bar is the bead's contract (see the briefs below): trivial beads usually carry a named-skip harness and small acceptance, but the combined subagent must still confirm acceptance is met — not just that the diff compiles.

### Common rationalizations that mean you're about to violate this rule:
- "This is a serial chain, so I'll just do it myself" → WRONG. Dispatch subagents one at a time.
- "This is simple/quick" → WRONG. Dispatch a subagent (maybe combined for trivial).
- "I already understand the task" → WRONG. Dispatch a subagent.
- "It's faster if I do it" → WRONG. Dispatch a subagent.

## Process

### 1. Check bead structure
- Get bead details: `bd show <id>`
- Identify if it has children or is a leaf bead
- Look for related design context:
  - Plan doc: check bead description for `Plan:` reference
  - Design doc: check for `Design:` reference in bead or plan
  - Paired ADR: docs/decisions/ADR-*-{design-name}.md (if design doc exists)
- Either way, YOU dispatch subagents - you never implement directly

**When ADR exists:**
- Pass ADR path to subagents so they understand design rationale
- Respect FIRM decisions — they encode prior discussion and tradeoff analysis
- Disagree? Raise it — don't silently deviate, state the conflict and wait for alignment

**Third-party source-of-truth (orchestrator-only):**
- If a bead implements against a fast-moving or unfamiliar third-party API (one a model would likely hallucinate), scout the real source *before* dispatching: run `/scout-source` yourself — you're the main loop, so it triggers and you can run it — and bake the grounded snippet + commit SHA into the implementer's brief. Same for `context7` when current docs would settle it more cheaply.
- Why the orchestrator and not the subagent: the `implementer` is execute-only (it won't compose primitives) and dispatched subagents don't auto-load skill descriptions — so it will never reach for `/scout-source` on its own and will guess from stale memory. Feed it ground-truth or it guesses.

### 2. For leaf beads:

Mark bead as in_progress: `bd update <id> --status=in_progress`

#### Step 1: Implement

Dispatch implementation subagent (use `subagent_type: "implementer"`):
```
Implement bead <bead-id>.

1. Read bead details: `bd show <bead-id>` — note the acceptance criteria AND the `## Harness target` block in --design (if present). You implement against both: acceptance is the real target; the harness Signal is your hillclimbing gradient.
2. Implement using TDD discipline (skill is pre-loaded). Where the harness names a Signal, the failing test you write first IS that Signal (or the test that produces it) — make it green. Where the Signal is a new test this bead exists to build, building it is part of the work.
3. Done = the bead's contract met — a conjunction, not a substitution:
   - The harness Signal runs and shows Expected green (a named-skip bead has no Signal — say so, don't invent one).
   - The acceptance criteria are satisfied, INCLUDING the prose parts no Signal reaches.
   - Standard gates (tests, lint, typecheck) pass — necessary, but not the bar by themselves.
4. Do NOT commit or close yet - wait for code review

Report: files changed, the Signal run + its green result, how each acceptance criterion was met.
```

Wait for completion with TaskOutput.

#### Step 2: Review + Close/Commit

After implementation completes, dispatch code-reviewer (combines review and close/commit):
```
Task tool (subagent_type: "code-reviewer"):
  Review bead <bead-id> implementation, then close and commit if passing.

  WHAT_WAS_IMPLEMENTED: [summary from implementation report]
  PLAN_OR_REQUIREMENTS: `bd show <bead-id>` — grade against the bead's CONTRACT, not just code quality:
    - Bind every acceptance criterion to an artifact. For each — especially prose/semantic ones ("each assertion fails on reversal", "provisioning unchanged", "error is actually helpful") — name the specific assertion / code region / diff hunk that establishes it. If a required property has NO artifact that actually exercises it, it is UNMET. "Verified manually" in the report is not an artifact; a same-named or adjacent check is not a proxy. Read what the code does, not what its label or the report claims.
    - Confirm the Signal green via EVIDENCE, not prose. Re-run the `## Harness target` Signal yourself if you can. If you can't, the implementer must have captured inspectable evidence (exact command + exit code + key output matching Expected green) — confirm it's present and consistent. A prose "all green" with no captured evidence is an UNVERIFIED gap that blocks a clean pass; a sentence is not a run.
    - Goal-faithful is broader than the Invalidation clause. A green that is green for a hollow reason — tautological assertion, mock, skipped case, test exercising the wrong thing — fails goal-faithfulness even when the Invalidation clause doesn't trip. Check both.
    Contract = harness green AND acceptance met — a conjunction, never a substitution. (Named-skip beads have no Signal; grade acceptance + the stated skip rationale.)

  1. Review implementation: contract grading (above) + Strengths, Issues (Critical/Important/Minor), Assessment
  2. If Critical/Important issues OR the contract is not met: Report issues, do NOT close or commit
  3. If Clean or Minor only AND the contract is met:
     - Close bead: `bd close <bead-id>`
     - Commit: `git add -A && git commit -m "feat(<scope>): <bead title>"`
     - Report: commit SHA

  Report: contract verdict + Review assessment + action taken (closed/committed OR issues blocking).
```

**On review result:**
- Critical/Important issues: Dispatch fix subagent, then re-dispatch review+close/commit
- Clean or Minor only: Proceed (commit already done by reviewer)

### 3. For parent/epic beads (multiple subagents):

#### Step 1: Analyze children
- Get all children via `bd show <id>`
- Use `bv --robot-plan` to get execution plan
- Mark epic as in_progress: `bd update <epic-id> --status=in_progress`

#### Step 2: Execute children

For each child bead, follow the same 2-subagent flow as leaf beads:
1. **Implement** → dispatch implementation subagent
2. **Review + Close/Commit** → dispatch code-reviewer (reviews, then closes + commits if passing)
3. **Fix** → if issues found, dispatch fix subagent, re-dispatch review+close/commit

**For parallel children (no dependencies):**
- Dispatch ALL implementation subagents in parallel (single message, multiple Task calls)
- After all implementations complete, dispatch ALL review+close/commit subagents in parallel
- Parallel reviews are safe since each reviews/commits different files

**For serial children (dependencies):**
- Complete full cycle (implement → review+close/commit) for each child before starting next

#### Step 3: Handle results
- On success: proceed to next unblocked children
- On failure: see Failure Handling below

#### Step 4: Complete epic
- Before closing, confirm the EPIC's own contract — children-done is necessary, not sufficient. The parent usually carries acceptance the sum of children doesn't guarantee, and often a harness target (frequently an integration-test child `/decompose` creates — confirm that child actually ran its Signal and it's green). Grade the epic's acceptance criteria, including prose. Children passing does not substitute for the epic's contract.
- After the epic's contract is met: `bd close <epic-id>`
- Commit epic closure: `git add -A && git commit -m "feat: complete <epic title>"`
- Report summary: which beads succeeded, commits created, how the epic's contract was met

## Failure Handling

When implementation or review fails:

1. **Leave bead status as `in_progress`** - do NOT close it
2. **Do NOT commit partial work** - incomplete implementations should not be committed
3. **Report the blocker clearly:**
   - Which bead failed
   - What went wrong (contract not met — Signal not green, or acceptance unmet including prose acceptance; test failures; review issues; missing dependencies)
   - What was completed before failure
4. **STOP execution** - do not continue to dependent beads
5. **For epics:** Report which children succeeded and which failed

Stop and escalate to the user. The user can then decide to:
- Fix the issue and re-run `/implement <bead-id>`
- Manually dispatch the debugger agent for root-cause analysis
- Adjust the bead scope and re-run
- Abandon the bead

## Output
- Code changes committed
- Bead(s) marked complete
- Summary of what was implemented
