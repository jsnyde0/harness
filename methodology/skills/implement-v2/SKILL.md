---
name: implement-v2
description: 'Heavy-recipe TDD-disciplined implementation orchestrator with implementer + reviewer subagents. Reference composition for genuinely-large code work; superseded as default by thesis-v2 TDD primitive + judgment-routed dispatch (ADR-012).'
disable-model-invocation: true
---

## Purpose

Implement one bead end-to-end with TDD discipline. The main skill agent is orchestrator only — it never writes code directly. It dispatches an implementer subagent (Sonnet, TDD) and a code-reviewer subagent (Sonnet, reviews + closes + commits). Inputs a single leaf bead ID; outputs a committed changeset, a closed bead, and a reported commit SHA.

---

## Inputs

- **Bead ID** (required positional) — either a leaf bead or a parent/epic bead. Leaf beads proceed to the standard implementer + code-reviewer flow. Parent beads trigger the per-child dispatch loop (see Step 3).

---

## Orchestrator algorithm

The orchestrator (main skill agent) is orchestrator only. It never writes code directly. All code-writing and code-reviewing happens inside subagents.

### Step 0 — Pre-flight check

Run `bd show <bead>`. If bead not found (404): emit `"Bead <id> not found. Check ID and retry."` and exit.

Verify bead is in expected state:
- If bead is already closed: emit `"Bead <id> is already closed. Nothing to implement."` and exit.
- If bead is not a leaf (has children): proceed to Step 3 (parent-bead dispatch).

### Step 1 — Read bead state

```
bd show <bead>
```

Read bead `--acceptance`, `--notes`, and whether the bead has children.

### Step 2 — Haiku ADR pre-filter

Dispatch a cheap Haiku subagent (`model: 'claude-haiku-4-5'`, falls back to session model) to scan `docs/decisions/ADR-*.md` and return ≤3 in-scope ADR paths (per ADR-008 D3). Subsequent subagents receive only the filtered set.

### Step 3 — Parent-bead dispatch

If the bead has children (i.e., it is a parent/epic): mark the epic in_progress (`bd update <epic-id> --status=in_progress`), then execute the following per-child loop. Do not proceed to Steps 4–6 for the epic itself; those steps are executed per-child inside this loop.

#### Step 3a — Analyze children

```
bd show <epic-id>
```

Read all child bead IDs listed under the epic. For unblocked children, also run:

```
bd ready --parent=<epic-id>
```

Group children by dependency structure:

- **Parallel siblings**: children that share no dependencies among themselves (can run concurrently).
- **Serial chains**: children where one depends on another (must complete in order).

#### Step 3b — Execute children

Apply the standard 2-subagent flow (implementer then code-reviewer) to each child. The same forbidden items, max-2-implementer-dispatches cap, discovered-from rule, no-partial-commits, and no-bead-closure-on-failure rules apply per-child exactly as they do for leaf beads.

**For parallel siblings (no shared dependencies):**

1. Dispatch ALL implementer subagents in a single message (multiple `Task()` calls). Each implementer gets a brief identical in shape to Step 4 (leaf bead brief), scoped to its own child bead ID.
2. Wait for ALL implementer `Task()` calls to complete.
3. Dispatch ALL code-reviewer subagents in a single message (multiple `Task()` calls). Each code-reviewer gets a brief identical in shape to Step 5 (leaf bead brief), scoped to its own child bead ID. Parallel reviews are safe — each reviews and commits different files.
4. Wait for ALL code-reviewer `Task()` calls to complete.

**For serial chains (dependencies between children):**

For each child in dependency order:

1. Dispatch implementer subagent (`Task()`). Brief: Step 4 shape, scoped to this child's bead ID.
2. Wait for implementer to complete.
3. Dispatch code-reviewer subagent (`Task()`). Brief: Step 5 shape, scoped to this child's bead ID.
4. Wait for code-reviewer to complete.
5. Only after the full implement+review cycle succeeds does the next child in the chain begin.

#### Step 3c — Handle child results

On any child failure (implementer or code-reviewer reports BLOCKED or Critical/Important issues after max-2 implementer dispatches):

- Stop execution immediately. Do not start any subsequent children.
- Leave the epic status as `in_progress`. Do NOT close the epic.
- Report clearly: which children succeeded (with commit SHAs), which child failed, and the reason.
- Escalate to the user to decide next steps.

#### Step 3d — Complete epic

After ALL children succeed (all code-reviewers report clean and have closed + committed their respective child beads):

```
bd close <epic-id>
git commit -m "feat: complete <epic title>"
```

Emit the epic completion summary per **Checkpoint output format** below — anchor at the top, child commit SHAs and the epic-closure SHA in the mechanical detail section, brief status + next-step recommendation at the tail.

### Step 4 — Dispatch implementer subagent

For leaf beads, dispatch an implementer subagent (Sonnet). The implementer brief must include:

- The bead's `--acceptance` as the red→green target.
- The in-scope ADR set (FIRM = hard constraints; FLEXIBLE = changeable with explanation).
- TDD discipline: write tests first, run them red, implement minimal code, run green, then verify lint and typecheck. The implementer loads `superpowers:test-driven-development` + `superpowers:verification-before-completion` + `superpowers:systematic-debugging`. **For beads whose `--acceptance` is a structural-check script rather than a unit test suite, the implementer runs the `--acceptance` script itself as the red→green target** (make it fail first, then pass). Lint and typecheck are only required when the bead produces code files; structural-only beads need only the `--acceptance` script green.
- Discovered-from rule: if an adjacent issue surfaces during work, file `bd create --parent=<epic>` with `bd dep add <new-bead> discovered-from <current-bead>` and do not fix it in the same iteration. Defer to a separate bead.
- Hard forbidden for the implementer: commit, close the bead, or claim done without verification evidence.

Wait for the implementer to report files changed and verification passing (tests green, lint clean, typecheck clean).

### Step 5 — Dispatch code-reviewer subagent

Dispatch a code-reviewer subagent (Sonnet). The code-reviewer brief:

- Review the diff for code-level concerns: bugs, naming, edge cases, security, test coverage.
- Reviewer reports findings with severity labels (Critical / Important / Minor) — these are advisory characterizations, not the ship-or-fix gate.
- **Orchestrator gating rule (countermand test):** the orchestrator decides ship-vs-fix-cycle by asking *"Would the user push back on shipping this commit as-is?"* of each finding.
  - **No on every finding** → ship: `bd close <bead>`, then `git add -A && git commit -m "<descriptive message>"`, then report the commit SHA back to the orchestrator. Severity-Minor findings typically fall here; severity-Important findings may also fall here when the orchestrator judges them not-ship-blocking (e.g. naming nits in non-public surface). Including any would-be-Minor leftovers in the commit message body is allowed for visibility.
  - **Yes on any finding** → fix cycle: dispatch at most one fix subagent (a fresh implementer `Task()` with the ship-blocking findings as input), then re-dispatch the code-reviewer. If the code-reviewer still surfaces ship-blocking findings after the fix cycle, escalate to the user and stop. Severity-Critical findings always fail the countermand test; severity-Important usually do, but the orchestrator may ship when the test honestly returns no.
- **Maximum 2 implementer dispatches per bead (Phase-A policy — see Phase-A-only deviations below).** No partial commits, no bead closure on failure.
- **Acceptance-vs-design tension — apply countermand test (review-v2 pattern).** If the reviewer's findings indicate the gap lies in the bead's contract (`--acceptance` contradicts `--design` or an in-scope FIRM ADR) rather than in the implementation, do not auto-escalate. Apply the countermand test — *"would the user countermand my resolution if I acted without asking?"*:
    - **Reconcile autonomously** when `--design` or a FIRM ADR has clear precedence and the `--acceptance` text is overreach — pass the clarified target to the fix-cycle implementer and log the reconciliation in `--notes` for audit. (The user would not countermand this call.)
    - **Escalate** only when the contradiction reflects a genuine design-level choice with multiple sensible resolutions. A fresh implementer cannot resolve a contract-level ambiguity; only the user can.

    Default toward reconciling. Escalation is a last resort, not a first instinct — keep the agent autonomous unless the call genuinely requires the user.

### Step 6 — Report

Report success with the commit SHA, or report the blocker clearly and stop.

---

## Trivial-bead exception

For beads that are ALL of the following:

- (a) Fewer than 10 lines of straight-line change (`<10 lines` total)
- (b) No cross-directory writes
- (c) No methodology-home mutations
- (d) A clear example pattern — typo fix, one-config-line tweak

The orchestrator may use a single combined subagent that implements + self-reviews + commits + closes. This is the **only** allowed bypass of the orchestrator-dispatches rule.

**Beads writing under the methodology home do NOT qualify for the trivial-bead exception** regardless of size. They get the full implementer + code-reviewer flow.

**Phase-A-only deviation:** the trivial-bead exception's commit semantics (combined subagent commits) differ from the standard code-reviewer-commits flow. Phase B unifies these commit paths once the subagent pair has operational data behind it.

---

## Subagent dispatch shape

| Subagent | Model | Role |
|---|---|---|
| Haiku ADR pre-filter | Haiku | Cheap scope-filter; returns ≤3 in-scope ADR paths |
| implementer | Sonnet | TDD implementation; forbidden from commit/close/claiming-done |
| code-reviewer | Sonnet | Reviews diff; commits + closes on clean; reports findings on failure |
| combined (trivial path only) | Sonnet | Implements + self-reviews + commits + closes; only when bead satisfies all 4 trivial criteria |

Each subagent gets a fresh `Task()` — zero memory of prior findings or prior iterations. If the implementer is re-dispatched for a fix cycle, the fix subagent gets a fresh context with the code-reviewer's findings as explicit input.

---

## Phase-A-only deviations

1. **Parent-bead dispatch in scope for Phase A** (Step 3) — Phase C replaces the manual grouping with ADR-009 D1's nested-loop machinery; per-child flow shape stays.
2. **Max-2-implementer-dispatches** is a conservative Phase-A retry guard; replaced by ADR-007 D5's `bd label retry:N` machinery in Phase B.
3. **Trivial-bead exception commit semantics** (combined subagent commits) differ from the standard code-reviewer-commits path; Phase B unifies them.

---

## Outputs

- Code changes committed (`git commit` performed by the code-reviewer subagent).
- Bead closed (`bd close <bead>` performed by the code-reviewer subagent).
- Commit SHA reported to the user.
- Any discovered-from beads filed (`bd create` + `bd dep add discovered-from`) during implementation.

## Output contract

The final line of skill output is exactly one of:

```
COMMIT_SHA: <sha>
```

on success (the `<sha>` is the full commit SHA from `git rev-parse HEAD`), or:

```
BLOCKED: <reason>
```

on failure (e.g., `BLOCKED: code-reviewer FAIL after 2 implementer cycles — escalate to user`). No trailing whitespace. No additional text on that line. Phase B's orchestrator greps for this exact string to drive state-machine transitions.

---

## Checkpoint output format

When emitting a moment that needs the user's input or signals end-of-phase (e.g. BLOCKED escalation, completion summary, contract-vs-design tension surfacing), structure the human-facing message as:

- **Anchor** what work this is and what just happened (1 line).
- `---`
- Mechanical detail (file:line refs, reviewer findings verbatim, transcript pointers) — drill-up content.
- `---`
- **The ask** in plain language, framed by what the system would do differently — not by mechanism.
- **Options** (≤3, one phrase each, in observable-behavior terms).
- **One-line recommendation.**

**Why this shape:** the user reads chat tail-first — the most recent visible line is what they act on, not the top. Anchor at the top orients on first-read; the ask at the tail is what their attention lands on when switching between parallel agents. Mechanical detail in the middle is drill-up if needed.

**Anti-pattern:** the wall-of-X summary — captured state enumerated through the body, the actual ask diluted into a closing question that gets drowned by everything above it. Signal density at the tail is what makes a checkpoint actionable.

Reference IDs — bead IDs, ADR/decision codes, file:line refs, finding IDs (F1, R2…) — are breadcrumbs for the drill-up section, never the ask at the tail. Collapse correlated decisions to the root choice; don't make the user re-derive interdependencies. Findings that don't need user input get one summary line, not an enumeration.

When the orchestrator's recommendation contradicts a reviewer evidence-finding (file:line cited), quote the finding verbatim in the escalation message and verify it (run the relevant test) before recommending — paraphrasing reviewer evidence into a softer "future risk" hypothetical is the named go-soft failure mode.

This shapes the human-facing message only; the `COMMIT_SHA: ...` / `BLOCKED: ...` contract line per **Output contract** above is unchanged.

---

## Forbidden

- Orchestrator writes code directly. The orchestrator is orchestrator only — never write code directly. (Trivial-bead exception is the single allowed bypass, with tightened criteria.)
- Partial commits on failure. No partial commits — commit only when the code-reviewer declares clean.
- Bead closure on failure. No bead closure on failure — the code-reviewer closes only when clean.
- Fixing discovered-from beads in the same iteration. If an adjacent issue is found: file a new bead via `bd create` + `bd dep add <new> discovered-from <current>` and defer to that bead. Do not fix in the same iteration.
- Skipping verification before claiming done. The implementer must run tests (red→green), lint, and typecheck (or `--acceptance` script if structural-only) and provide evidence before reporting completion.
- More than 2 implementer dispatches per bead without escalating to user. The max-2 cap is firm for Phase A; token economy and signal that the bead is harder than estimated.
- Reusing subagent context across dispatches. Every subagent is fresh (`Task()` with zero memory of prior runs).
- Closing the epic on child failure. If any child fails, stop immediately, leave the epic in_progress, and escalate. Do not close the epic until all children succeed.
- Depending on Phase B/C machinery (loop state machine, retry-cap labels, auto-acceptance execution between phases). This skill runs in isolation.

---

## ADRs consulted

- **ADR-006 D6** — beadify creates children via `--parent=<epic>`; this skill consumes those child beads as its primary input shape.
- **ADR-006 D9** — follow-up work in-flow via `bd create + discovered-from`; the discovered-from rule applied by the implementer subagent derives from this decision.
- **ADR-007 D2** — orchestrator runs validators directly (not trusting subagent self-reports); the verification discipline applied here mirrors this trust model per-skill in Phase A.
- **ADR-007 D3** — fresh `Task()` per subagent; every implementer and code-reviewer dispatch is a clean context.
- **ADR-007 D6** — stateless re-prompt: each iteration reads bead state from disk, no context carryover. *(D6 is an orchestrator-loop concern deferred to Phase B; `/implement-v2` runs in isolation per §Scope. Referenced for Phase B continuity.)*
- **ADR-008 D4** — `discovered-from` dep; newly-filed beads are not worked in the same iteration. The implementer subagent brief enforces this rule.
