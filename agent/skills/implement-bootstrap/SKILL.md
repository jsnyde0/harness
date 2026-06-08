---
name: implement-bootstrap
description: Bootstrap implementation workflow for Pi. Implements one bead at a time in the main/orchestrator session with verification, review, bead updates, and optional commit/close.
---

# Implement Bootstrap

## Purpose

Implement a bead end-to-end before the subagent-powered `implement-v2` workflow exists.

Unlike future `implement-v2`, this bootstrap skill allows the orchestrator/main Pi agent to make code and documentation changes directly. It preserves the important workflow discipline:

- one bead at a time
- read bead state first
- respect ADR/design constraints
- verify before claiming done
- review the diff before closing
- do not fix adjacent discovered work in the same bead
- leave clear audit notes

## Inputs

Invoke `/skill:implement-bootstrap <bead-id> [--no-commit] [--no-close]`.

- `<bead-id>` is required.
- `--no-commit` leaves changes uncommitted after successful verification/review.
- `--no-close` leaves the bead open after successful verification/review.
- Unknown arguments: stop and ask the user to clarify.

## Outputs

On success:

- code/docs changed as needed
- validation run and reported
- review performed, preferably with `review-bootstrap --mode=implementation`
- bead notes updated with implementation summary
- bead closed unless `--no-close`
- changes committed unless `--no-commit`
- final line exactly:

```text
COMMIT_SHA: <sha>
```

If `--no-commit` is used, final line exactly:

```text
COMMIT_SHA: uncommitted
```

On failure, final line exactly:

```text
BLOCKED: <reason>
```

No trailing text after the final contract line.

## Algorithm

### 0. Preflight

1. Run `bd show <bead-id>`.
2. If the bead is missing, stop with `BLOCKED: Bead <id> not found`.
3. If the bead is closed, stop with `BLOCKED: Bead <id> is already closed`.
4. Inspect current git state:
   - `git status --short`
   - if unrelated uncommitted changes exist, ask the user before proceeding
5. Read bead:
   - title
   - design/description
   - acceptance criteria
   - notes
   - dependencies
   - children

### 1. Parent bead handling

If the bead has children, do not implement the parent directly.

1. Mark the parent `in_progress` if appropriate.
2. Run `bd ready --parent=<parent-id>` or inspect the child dependency graph.
3. Work ready children one at a time with this same skill.
4. Stop immediately if any child blocks.
5. Close the parent only after all children are closed and the parent acceptance/integration checks pass.

Bootstrap mode is serial by default. Do not attempt parallel child execution.

### 2. Claim and understand the leaf bead

For a leaf bead:

1. Claim or mark in progress:

```bash
bd update <bead-id> --status=in_progress
```

2. Read relevant ADRs from `## ADRs consulted` in notes.
3. Inline-scan `docs/decisions/ADR-*.md` for clearly relevant ADRs if the bead notes are incomplete.
4. Extract:
   - red/green target from acceptance
   - scope boundaries
   - forbidden/rejected alternatives
   - expected validation commands
   - likely files/surfaces, if stated by the bead or design

### 3. Plan minimally

Write a short implementation plan in conversation before editing:

- acceptance target
- constraints/ADRs
- expected files/surfaces
- validation commands
- risk/rollback note

If the acceptance is vague or impossible to verify, stop with `BLOCKED: acceptance is not runnable/inspectable` and ask for bead refinement.

### 4. Implement with red/green discipline

1. If a test or structural check can fail before implementation, run it first and capture the failure.
2. Make the smallest coherent changes needed for the bead.
3. Do not broaden scope into adjacent issues.
4. If an adjacent issue is discovered:
   - create a separate bead with `bd create`
   - relate/depend it on the current bead as appropriate
   - do not fix it in this iteration unless the user explicitly changes scope
5. Keep edits focused and reversible.

### 5. Verify before review

Run all relevant checks:

- the bead acceptance command/check, if explicit
- targeted tests
- lint/typecheck/build when code changes warrant it
- documentation/skill validation greps when changing workflow skills
- `bd status`/`bd show` checks when changing bead state

If a required check cannot run, record why and decide whether that is acceptable. If the acceptance target cannot be verified, stop with `BLOCKED: verification unavailable for acceptance target`.

### 6. Review the implementation

Perform a bootstrap implementation review before closing:

- Prefer loading and following `review-bootstrap` with `--mode=implementation`.
- If you do not invoke it as a separate skill step, still apply its checks inline:
  - acceptance satisfied
  - diff scoped to bead
  - no contradiction with in-scope FIRM ADRs
  - no rejected alternative implemented
  - validation evidence present
  - no obvious code-level bug introduced

If review fails:

1. Apply one focused fix cycle if the fix is clear and in scope.
2. Re-run validation and review.
3. If it still fails, stop with `BLOCKED: implementation review failed after fix cycle`.

Bootstrap retry cap: one initial implementation plus one fix cycle. Escalate after that.

### 7. Update bead notes

Append an implementation summary to bead notes:

```markdown
## Implementation bootstrap summary
- Files changed: <list>
- Acceptance/validation: <commands and pass/fail>
- ADRs consulted: <list or none>
- Review: PASS/FAIL, summary
- Discovered follow-up beads: <ids or none>
```

Preserve existing notes; append rather than overwriting unless intentionally editing a known section.

### 8. Close and commit

If verification and review pass:

1. If not `--no-close`, close the bead:

```bash
bd close <bead-id> --reason "implemented and verified"
```

2. If not `--no-commit`, commit all intended changes:

```bash
git status --short
git add <intended files>
git commit -m "<type>: <short bead title>"
git rev-parse HEAD
```

Use an appropriate commit type (`feat`, `fix`, `docs`, `chore`, `test`, etc.). Do not include unrelated changes.

If commit is skipped, report `COMMIT_SHA: uncommitted`.

## TDD / verification guidance

Prefer true red/green when feasible:

- add or identify a failing test/check
- observe failure
- implement minimal change
- observe pass

For structural-only or documentation/skill beads, use an equivalent inspectable check:

- grep for forbidden terms
- parse frontmatter shape
- check skill directories exist
- run relevant CLI help/status commands
- inspect generated markdown sections

## Parent/epic completion

When all children of a parent are closed:

1. Run the parent acceptance/integration check.
2. Run `review-bootstrap --mode=implementation` on the parent if there is a parent-level diff or artifact state to review.
3. Close the parent only when the parent acceptance is satisfied.
4. Commit parent closure/metadata changes if they are tracked.

If any child fails, leave the parent open or in progress and report the blocker.

## Forbidden

- **Delegating implementation.** Do not call another agent/model/process to implement or review. This bootstrap skill is main-session only.
- **Skipping verification.** Never claim done without command output or precise inspection evidence.
- **Closing on failure.** Do not close a bead unless acceptance and review pass.
- **Committing unrelated changes.** Stage only intended files.
- **Fixing discovered adjacent work in the same bead.** File follow-up beads instead.
- **Unlimited retries.** One focused fix cycle, then escalate.
- **Implementing a parent epic directly while children exist.** Work children first.
- **Overwriting bead notes wholesale.** Preserve audit history; append summaries.

## Bootstrap note

This skill exists to break the bootstrapping cycle for building the Pi subagent primitive. Once the subagent primitive and `implement-v2` exist, prefer `implement-v2` for normal workflow implementation unless main-session-only execution is explicitly desired.
