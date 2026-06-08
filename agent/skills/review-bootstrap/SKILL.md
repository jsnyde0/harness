---
name: review-bootstrap
description: Bootstrap review workflow for Pi. Reviews design, plan, or implementation artifacts entirely in the main/orchestrator session, with evidence tables, 4-bucket triage, and binary verdicts. Use before subagent-powered review-v2 exists.
---

# Review Bootstrap

## Purpose

Provide a bootstrap-safe review primitive for Pi while the real subagent-powered `review-v2` does not exist yet.

This skill reviews one bead artifact in one of three modes:

| Mode | Artifact reviewed | When used |
|---|---|---|
| `design` | Epic `--design` narrative + paired ADR, when present | Before decomposing an epic |
| `plan` | `## Iteration plan` section in bead `--notes` | Before implementation, when a plan exists |
| `implementation` | Current git diff + bead state | After implementation, before close/commit |

The main/orchestrator Pi agent performs the review itself. It may read files, inspect beads, run commands, and apply small fold-ins. It does not require any separate runtime machinery.

## Inputs

The user invokes `/skill:review-bootstrap <bead-id> [--mode=design|plan|implementation]`.

- `<bead-id>` is required.
- `--mode` is optional. If omitted, infer it from bead state using [Mode detection](#mode-detection).
- Unknown arguments: stop and ask the user to clarify. Do not silently default.

## Outputs

- Evidence table with file/path/bead citations.
- 4-bucket triage:
  - **Fold in** — small, unambiguous, in-scope issue the orchestrator can safely apply.
  - **Surface as suggestion** — reasonable but not mandatory improvement; ask user.
  - **Decision Challenge** — contradicts a FIRM ADR or binding design decision; surface distinctly.
  - **Discard** — clearly wrong, out of scope, or overengineered; log one-line rationale.
- Review summary appended to bead notes under `## Review findings (bootstrap iteration N)`.
- Final line exactly one of:

```text
VERDICT: PASS
```

or

```text
VERDICT: FAIL
```

No trailing text after the final verdict line.

## Mode detection

Run this only when `--mode` is absent.

1. Run `bd show <id>`.
2. Infer signals from live state:
   - If there is a relevant uncommitted git diff or recently closed child work, prefer `implementation`.
   - If bead notes contain `## Iteration plan`, prefer `plan`.
   - If the bead has a non-empty `--design` field, prefer `design`.
3. If multiple signals match, use latest-stage precedence:
   `implementation` > `plan` > `design`.
4. If no signal matches, stop with:
   `Cannot infer review mode for bead <id>. Pass --mode=design|plan|implementation explicitly.`
5. Report the inferred mode before continuing.

## Common algorithm

0. **Preflight.**
   - Run `bd show <id>`.
   - If the bead is missing, stop with `Bead <id> not found. Check ID and retry.`
   - For `design`, the bead should be an epic or parent with a populated `--design` field.
   - For `implementation`, the bead should not already be closed.
   - If state and requested mode conflict, report the mismatch and ask whether to continue.

1. **Read the artifact.**
   - Read the bead design, acceptance, notes, children, and status.
   - Read relevant files and ADRs referenced by `## ADRs consulted`.
   - For ADR context, scan `docs/decisions/ADR-*.md` inline and select only the few ADRs that are genuinely in scope. Prefer explicit `## ADRs consulted` links over broad guessing.

2. **Review adversarially, with evidence.** Apply the reviewer constants below to yourself:
   1. **Evidence or silence.** Every finding must cite a file path, ADR path, bead field, command output, or line reference when available. "Looks correct" is not a finding.
   2. **Binary verdict.** End with exactly `VERDICT: PASS` or `VERDICT: FAIL`.
   3. **Err to FAIL.** When in doubt about an unmet acceptance/design requirement, FAIL.
   4. **Separate findings from triage.** First collect evidence-backed findings; then triage them into buckets. Do not hide FIRM-decision conflicts as minor cleanups.
   5. **Adversarial stance.** Start from the hypothesis that the artifact does not meet its goal. The burden is on codebase evidence and bead fields to falsify that hypothesis.

3. **Produce an evidence table.** Use this shape:

```markdown
| # | Check | Verdict | Evidence |
|---|---|---|---|
| 1 | <check> | PASS/FAIL | <path/field/command>: <quote or observed fact> |
```

4. **Triage findings.**
   - Fold in small, safe, in-scope corrections.
   - Surface suggestions and Decision Challenges to the user.
   - Discard only with a short rationale.
   - Any unresolved FAIL finding means overall `VERDICT: FAIL`.

5. **Append audit notes.** Add a `## Review findings (bootstrap iteration N)` section to the bead notes with:
   - mode
   - evidence table summary
   - triage buckets
   - fold-ins applied
   - unresolved suggestions/challenges
   - verdict

6. **Emit final verdict.** The last line must be exactly `VERDICT: PASS` or `VERDICT: FAIL`.

## Mode-specific checks

### design

Review epic `--design` plus paired ADR if present.

Checks:

- The design describes purpose, shape, constraints, and expected outcome.
- Acceptance criteria are observable and falsifiable.
- If a paired ADR exists, every ADR decision has firmness, rationale, at least one rejected alternative with a warrant/reason, and invalidation criteria.
- The design does not contradict in-scope FIRM ADR decisions.
- The bead notes list consulted ADRs when ADRs influenced the design.
- The design is decomposable: it gives enough target shape for `beadify-bootstrap` without prescribing implementation minutiae for every child.

Fold-ins may rewrite the epic `--design` or notes when the correction is small and unambiguous. Do not invent new architecture during review; surface that as a suggestion or Decision Challenge.

### plan

Review the `## Iteration plan` section of bead notes.

Checks:

- The plan covers every acceptance criterion.
- The plan does not implement a rejected ADR alternative.
- The plan names validation to run.
- The plan is scoped to the bead and avoids adjacent work.
- The plan leaves durable audit notes for the next agent/human.

Only rewrite `## Iteration plan` for fold-ins. Preserve review finding sections as audit residue.

### implementation

Review the current diff plus bead state.

Checks:

- Run or inspect the bead acceptance check when possible. If it fails, return `VERDICT: FAIL` immediately with the failing output.
- Inspect `git diff --name-only` for scope creep.
- Inspect `git diff` for contradictions with in-scope FIRM ADRs or rejected alternatives.
- Confirm implementation changes satisfy the bead acceptance criteria.
- Confirm validation evidence is present: relevant tests/checks were run, or the reason they cannot run is explicit.

This mode may include code-level findings because there is no separate bootstrap code-review worker. Keep findings tied to the bead’s acceptance and risk; avoid broad refactors.

## Forbidden

- **Delegated review.** Do not call another agent/model/process to perform the review. This bootstrap skill is intentionally main-session only.
- **Evidence-free findings.** If you cannot cite evidence, do not list it as a finding.
- **Severity labels from nowhere.** Use the 4 buckets instead of Critical/Important/Minor unless a project convention explicitly requires severity.
- **Rationalizing FIRM conflicts.** A conflict with a FIRM ADR or binding decision is a Decision Challenge, not a fold-in or discard.
- **Rewriting large artifacts during review.** Fold in small corrections only. Large changes go back to the user or to a new bead.
- **Closing beads or committing.** Review-bootstrap reports verdicts and may apply small artifact fold-ins; implementation/closure belongs to `implement-bootstrap`.

## Bootstrap note

This skill exists to break the bootstrapping cycle for building the Pi subagent primitive. Once the subagent primitive and `review-v2` exist, prefer `review-v2` for normal workflow review unless a main-session-only bootstrap review is explicitly desired.
