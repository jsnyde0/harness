---
name: review-v2
description: 'Heavy-recipe rigor-disciplined review with convergence loop and ternary verdict. Reference composition for genuinely-large reviews; superseded as default by thesis-v2 adversarial-review primitive (ADR-012).'
disable-model-invocation: true
---

## Purpose

Provide a rigor-disciplined review of a bead artifact. One skill, three modes:

| Mode | Artifact reviewed | When used |
|---|---|---|
| `--mode=design` | Epic `--design` narrative + paired ADR | Phase A pre-loop (manual) |
| `--mode=plan` | Bead iteration plan in `--notes` | Phase B (REVIEW-PLAN gate) |
| `--mode=implementation` | Bead diff + bead state, architectural alignment only | Phase A post-implement (manual) |

**Note: `--mode=design` reviews epic `--design` fields and paired ADRs only. It cannot review SKILL.md files — those have no `--design` field.**

## Inputs

- `$ARGUMENTS` (positional-first, then flags): `<bead-id> [--mode=<mode>] [--N=<n>]`
  - `<bead-id>` (required): the bead or epic ID to review.
  - `--mode` (optional): `design`, `plan`, or `implementation`. Overrides mode detection. When omitted, mode is inferred via **Step 0a** below.
  - `--N` (optional): **round floor** — minimum rounds before the orchestrator may exit on PASS. Default 1. Hardcoded **ceiling = 3 rounds**. Values above 3 are clamped. Mode-agnostic.
  - Unrecognized arguments → ask user to clarify (do NOT silently default).

---

## Step 0a — Mode detection

Run this algorithm when `--mode` is **not** supplied. When supplied, skip to Step 0 (pre-flight).

**Signals (check all three via `bd show <id>`):**

| Signal | Inferred mode |
|---|---|
| Bead has uncommitted diff against `git merge-base origin/main HEAD` or recently-closed children | `implementation` |
| Bead `--notes` contains `## Iteration plan` | `plan` |
| Bead `--design` field is non-empty | `design` |

**Precedence:** `implementation` > `plan` > `design`.

1. Run `bd show <id>`. Check each signal in order.
2. If no signal matched: emit `"Cannot infer review mode for bead <id>. Pass --mode=design|plan|implementation explicitly."` and exit non-zero.
3. Report inferred mode before proceeding: `"No --mode supplied — inferred mode=<mode> from bead state."`

---

## Common orchestrator steps (all modes)

**Step 0 — Pre-flight check:**
- Run `bd show <id>`. If not found: emit `"Bead <id> not found. Check ID and retry."` and exit.
- `--mode=design`: ID must be an epic with `--design` populated. `--mode=implementation`: bead must not be closed. On mismatch, report and ask for confirmation.

**Step 1 — Haiku ADR pre-filter:**
Dispatch one cheap Haiku subagent (`claude-haiku-4-5`, falls back to session model) to scan `docs/decisions/ADR-*.md` and return ≤3 in-scope ADR paths. Subsequent subagents receive only the filtered set. (The ≤3 cap is review-v2's internal scoping choice, not derived from ADR-008 D3 — see ADRs consulted note. Design-v2 may force-inject an ADR per ADR-006 D7.)

**Steps 2–N — Convergence loop (rounds 1..ceiling=3):**

Each round runs the following sequence:

1. **Dispatch** one reviewer subagent (fresh Task() — no shared context, no memory of prior findings, no reuse across rounds or retries). Model: Opus or Sonnet per cost/judgment tradeoff. Build reviewer brief per mode-specific section below, including the **Reviewer brief constants** block verbatim.
2. **Collect** the findings list from the reviewer. (Reviewers do not emit a verdict — see brief constants rule 2.)
3. **Triage** findings into 4 buckets using the **countermand test** — *"Would the user countermand this if I acted without asking?"*
   - **Fold-in** — *No, this is the obvious move.* Orchestrator applies to artifact. Pending fold-ins are applied before any verdict is emitted, regardless of round count or exit reason. Size is not the test: a multi-line rewrite that executes the obvious next step is Fold-in; a one-line tweak that touches an intentional design choice is Defer.
   - **Discard** — *No, this isn't worth doing.* Wrong, redundant, or overengineered. Silently dropped, one-line rationale logged.
   - **Defer** — *Maybe — there's a real choice here.* Multiple sensible answers, or touches an intentional design choice without contradicting a FIRM ADR. Noted for the **final report only**; no mid-loop user input.
   - **Raise** — *Yes — a FIRM ADR already says otherwise.* Presented to the user as a Decision Challenge before proceeding. Raises are the only bucket that prompts the user. The orchestrator may not reclassify a FIRM-ADR contradiction as Fold-in or Discard.
4. **Apply fold-ins** in place: rewrite the artifact coherently after fold-ins (epic `--design` for design mode; `## Iteration plan` section of `--notes` for plan mode; no rewrite for implementation mode — the artifact is the git diff). No `## Review findings (round N)` residue in the primary artifact. Audit residue goes in `--notes` under `## Review findings (round N)` via `bd update <id> --append-notes "$(cat /tmp/review-v2/findings-rN.md)"`.
5. **Judge round-continuation** based on the bucket distribution from this round:
   - Raises queued → present to user before continuing; after resolution, count any new fold-ins and re-judge.
   - Round count below floor (`--N`) → continue to next round regardless of bucket mix.
   - Ceiling reached (round 3) → exit loop; emit verdict per Final step.
   - All findings were Fold-in and/or Discard (orchestrator was confident on every call) → converged; exit with PASS without re-review.
   - Any Defer remains (orchestrator wasn't fully confident on at least one call) → not converged; continue if below ceiling. At ceiling, exit and emit FAIL — Defers signal the artifact still has unresolved judgment calls.

**Final step — Emit verdict:**
Apply all pending fold-ins, then emit exactly one of:

- `VERDICT: PASS` — artifact converged; no Raises queued; final round produced only Fold-ins and/or Discards.
- `VERDICT: FAIL` — ceiling hit with Defers still surfacing (artifact has unresolved judgment calls), no Raises queued.
- `VERDICT: NEEDS_DECISION` — Raises queued requiring user input. Phase B's outer loop interprets this as a `waiting:human` transition.

**Audit residue rule (always-emit).** After the verdict line, append `## Review record (round N): VERDICT=<verdict>` to `--notes` via `bd update --append-notes`. Always emit — including on clean first-round PASS — so design-v2's cross-session gate at step 2 can read the verdict from bead state. (Per ADR-006 D5/D7.)

---

## Output contract

The final line of skill output is exactly one of:

```
VERDICT: PASS
VERDICT: FAIL
VERDICT: NEEDS_DECISION
```

No trailing whitespace. No additional text on that line. Phase B's orchestrator greps for this exact string.

Example paths: round 1 produces only Fold-ins/Discards → `VERDICT: PASS`; ceiling hit with Defers still surfacing → `VERDICT: FAIL`; FIRM-ADR contradiction queued → `VERDICT: NEEDS_DECISION`.

---

## Checkpoint output format

When emitting a moment that needs the user's input or signals end-of-phase (e.g. NEEDS_DECISION, PASS/FAIL summary, Raise presentation), structure the human-facing message as:

- **Anchor** what work this is and what just happened (1 line).
- `---`
- Mechanical detail, citations, finding-by-finding breakdown — drill-up content.
- `---`
- **The ask** in plain language, framed by what the system would do differently — not by mechanism.
- **Options** (≤3, one phrase each, in observable-behavior terms).
- **One-line recommendation.**

**Why this shape:** the user reads chat tail-first — the most recent visible line is what they act on, not the top. Anchor at the top orients on first-read; the ask at the tail is what their attention lands on when switching between parallel agents. Mechanical detail in the middle is drill-up if needed.

**Anti-pattern:** the wall-of-X summary — captured state enumerated through the body, the actual ask diluted into a closing question that gets drowned by everything above it. Signal density at the tail is what makes a checkpoint actionable.

Reference IDs — bead IDs, ADR/decision codes, file:line refs, finding IDs (F1, R2…) — are breadcrumbs for the drill-up section, never the ask at the tail. Collapse correlated decisions to the root choice; don't make the user re-derive interdependencies. Findings that don't need user input (Fold-ins, Discards, Defers) get one summary line, not an enumeration.

This shapes the human-facing message only; the `VERDICT: ...` contract line per **Output contract** above is unchanged.

---

## Reviewer brief constants (verbatim in every dispatched brief)

These four rules appear **word-for-word** in every reviewer subagent prompt. The orchestrator must inject this entire block verbatim — no paraphrase, no abbreviation:

1. **Evidence or silence.** Every finding must cite file:line. "Looks correct" is not a valid finding. If you can't cite a file path + line number, do not make the claim.
2. **Findings only — no verdict.** End with the findings list. Do NOT emit `VERDICT: PASS` / `VERDICT: FAIL`. Do NOT label severity (no Critical/Important/Minor). Do NOT propose fix implementations. Do NOT rationalize ADR violations as exceptions. The orchestrator owns the verdict and triage; your job is to surface findings. Empty findings list = nothing surfaced. Proposing fixes makes reviewers invested in violations being benign.
3. **Err to surface.** When in doubt, surface the finding. The orchestrator's triage will sort it; do not pre-filter on your own judgment of importance.
4. **Adversarial stance.** Your starting hypothesis is that the artifact does NOT meet its goal — the burden is on codebase evidence to falsify that hypothesis, not on you to find a problem. Reviewer go-soft failure modes (do not exhibit any of these): trusting summary bullets without reading the code; assuming a passing test means the goal was met; rationalizing a finding as "probably fine"; treating a missing claim as "must have been intended"; deferring to the producer's framing of what's in scope.

---

## Mode-specific algorithms

### mode=design

**Note:** mode=design now reviews the bead `--design` *before* any paired ADR is written. The paired ADR is materialized by `design-v2` after PASS (per ADR-006 D7 revised 2026-04-30). Reviewer briefs no longer expect a paired ADR file on disk.

**Pre-flight (emit `VERDICT: NEEDS_DECISION` and exit *without dispatching a reviewer* on any of these):**
- `--design` empty → emit `"Bead has no --design field. Populate via /brainstorm-v2 (or skip to /beadify-v2 if pre-decisional)."` and exit `VERDICT: NEEDS_DECISION`.
- `--design` has no decisions section / contains only a problem statement (e.g. trivial bug bead) → emit `"--design has no decisions to review. Run /brainstorm-v2 to populate, or skip to /beadify-v2 if this is a trivial fix."` and exit `VERDICT: NEEDS_DECISION`.
- `--design` has decisions but no **artifact-shape decision** (epic-only vs ADR-paired) → emit `"--design lacks an artifact-shape decision. Run /brainstorm-v2 (or amend the bead) to add one — it is a first-class decision per ADR-006 D11."` and exit `VERDICT: NEEDS_DECISION`.
- `--design` lacks the mandatory `## canonical_refs` section (per ADR-008 D5 FIRM) → emit `"--design is missing the mandatory ## canonical_refs section. Per ADR-008 D5 every design must list referenced ADRs by full path (or 'none — this design is self-contained' if no refs were consulted); silent omission is forbidden. Run /brainstorm-v2 (or amend the bead) to add it."` and exit `VERDICT: NEEDS_DECISION`.

These pre-flight failures **are not** reviewer findings — they are pre-dispatch structural failures, parallel to mode=implementation's `--acceptance` pre-check. The user populates the missing piece and re-invokes review-v2.

**Reviewer brief contents:**
- The `--design` text + filtered ADR set. (No paired ADR file — it doesn't exist yet.)
- **Reviewer brief constants** block verbatim (all 4 items).
- **Design-mode DoD checklist:**
  1. Testability: does the acceptance criteria describe an observable, falsifiable end-state?
  2. Alternatives completeness: every decision has ≥1 rejected alternative with a rejection reason carrying a warrant tag.
  3. ADR-conflict scan: does the design contradict any FIRM decision in scope?
  4. Artifact-shape soundness: does the artifact-shape decision (epic-only vs ADR-paired) cohere with the substantive decisions? E.g., if a substantive decision binds future code architecture, the shape call should be ADR-paired (re-derivability test).

**Post-PASS auto-invocation:**
On `VERDICT: PASS`, mode=design **automatically invokes `design-v2` with the bead-id** in the same agent context (no user prompt between). Design-v2 reads bead state via `bd show <id>` and runs from there — ADR-007 D6 stateless re-prompt does not apply because skill-to-skill chaining is not subagent dispatch. See ADR-006 D7.

`VERDICT: FAIL` and `VERDICT: NEEDS_DECISION` exit normally **without** chaining to design-v2; the user (or parallel-session orchestrator) addresses the surfaced findings before re-invoking review-v2.

### mode=plan

**`--notes` carve-up:** orchestrator rewrites only `## Iteration plan`. Audit residue lives under `## Review findings (round N)` — not removed after triage.

**Reviewer brief contents:**
- Plan text from `## Iteration plan` + bead `--acceptance` + filtered ADR set.
- **Reviewer brief constants** block verbatim (all 4 items).
- **Plan-mode DoD checklist:**
  1. ADRs-consulted section exists in `--notes`.
  2. Plan does not implement a rejected ADR alternative.
  3. Plan covers acceptance: every acceptance criterion has a traceable step.

### mode=implementation

**Scope:** architectural alignment only. Code-level concerns (bugs, naming, edge cases, test coverage) are handled inside `/implement-v2` — this mode does NOT duplicate that work.

**Pre-check:** orchestrator runs the bead's `--acceptance` check itself before dispatching any reviewer. If it fails: emit `VERDICT: FAIL` and do not dispatch reviewers.

**Reviewer brief contents:**
- `git diff` output + filtered ADR set + scope manifest (expected files from bead description).
- `git diff --name-only` for scope-creep check.
- **Reviewer brief constants** block verbatim (all 4 items).
- **Implementation-mode DoD checklist:**
  1. Architectural alignment: does the diff align with FIRM decisions in-scope ADRs? Does it implement a rejected alternative?
  2. Scope creep: does `git diff --name-only` show any file outside the bead's stated scope?
  3. No architectural regressions: does the diff introduce structural patterns contradicting current ADR guidance?
  4. Acceptance coverage: does `--acceptance` cover happy path, ≥1 edge case, ≥1 error path, and ≥1 integration scenario where applicable?
- **Explicit out-of-scope reminder** (verbatim): "Code-level concerns (bugs, naming, edge cases, security, test coverage) are out of scope for this review. Architectural alignment only."

No artifact rewrite for this mode (the artifact is the git diff — immutable at review time).

---

## Forbidden (cross-reference)

Rules already prohibited by the body above — short list for quick audit:
- Reviewers emitting verdicts, labeling severity, proposing fixes, or rationalizing FIRM-ADR violations (brief constants rule 2 + Raise bucket).
- `--mode=implementation` doing code-level review; reviewer context reused across rounds (ADR-007 D3).
- `## Review findings (round N)` left in primary artifact; Reviewer brief constants omitted from any brief.
- Skipping `--acceptance` pre-check in `--mode=implementation`.

---

## ADRs consulted

- **ADR-007 D3+D4+D7+D8** — fresh-Task-per-round (D3), three rigor rules (D4), convergence-loop + 4-bucket triage + ternary verdict + floor/ceiling semantics (D7), adversarial-stance + named go-soft failure modes (D8).
- **ADR-008 D1+D2** — ADR predicates (D1), WHY-aware checks (D2). D3 distinction is internal — see Step 1.
- **ADR-008 D5** — mandatory `## canonical_refs` on `--design`; mode=design pre-flight emits `VERDICT: NEEDS_DECISION` when the section is absent. Authoritative source of in-scope ADRs for downstream PLAN/REVIEW.
- **ADR-006 D7** — mode=design runs on the bead before any paired ADR is written; on PASS, design-v2 is auto-invoked.
- **ADR-005 D2+D3** — bead-first artifact discipline: design narrative on epic `--design` (D2), per-bead acceptance on `--acceptance` (D3).
