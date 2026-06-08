---
name: design-v2
description: 'Heavy-recipe ADR materialization with overlap detection and evolution routing per ADR-011. Reference composition for genuinely-large design work; superseded as default by thesis-v2 ADR-write primitive (ADR-012).'
disable-model-invocation: true
---

## Purpose

Take a **vetted bead** (already passed `review-v2 --mode=design`) and materialize the ADR layer:

1. If the bead's artifact-shape decision says **epic-only**: invoke `/harness compose` to propose mechanical invalidation checks for FIRM decisions; record them on the bead. No ADR file written.
2. If the bead's artifact-shape decision says **ADR-paired**: run ADR overlap/evolution detection, write or in-place-edit the paired ADR, add the bead↔ADR link, propose `/harness`-composed invalidation checks, run the discoverability check.

Design-v2 is the **mechanical materialization step** in the post-2026-04-30 pipeline. The exploration (brainstorm-v2), bead creation (brainstorm-v2 at convergence), and decision validation (review-v2 mode=design) all happen upstream. By the time design-v2 runs, the decisions, the artifact-shape call, and the bead's `--design` are already vetted.

This skill **never emits a verdict** — verdicts are review-v2's concern. Design-v2 either succeeds (ADR written or no-op for epic-only) or **silently chains back to review-v2** with the contradicted ADR force-injected if it detects a FIRM-ADR contradiction review-v2 missed.

See ADR-006 D5/D7 and ADR-006 D11/D12.

## Inputs

`$ARGUMENTS` is a **bead id**. Design-v2 reads bead state via `bd show <id>` — it does **not** extract decisions from conversation context (the pre-2026-04-30 case-2/case-3 behavior is retired; brainstorm-v2 is now the only path that produces decision sets, and it produces them on the bead). If `$ARGUMENTS` is empty and the agent context implies a bead-id from a recently-PASSed review-v2 run, design-v2 may use that; otherwise it asks the user.

**Calling contexts:**
- **Auto-invoked from `review-v2 --mode=design` on `VERDICT: PASS`** — the standard path. Same agent context.
- **Manually invoked by the user** for a bead that already passed review-v2 — equivalent path.
- **Re-invoked from itself** (recursive chain) — only via the contradiction → force-injected re-review path; this is review-v2 calling design-v2 again after re-running, not design-v2 calling itself directly.

## Outputs

- **For `shape=ADR-paired`:**
  - Paired ADR at `docs/decisions/ADR-NNN-<topic>.md` (new file) **or** in-place edit of an existing ADR (per evolution check, ADR-011 D1).
  - Bead `--notes` updated with `## ADRs consulted` listing the paired ADR (and any prior ADRs referenced during decision-making — copied forward from `--design ## canonical_refs` per ADR-008 D5).
  - `**Invalidation check (mechanical, optional):**` blocks proposed by `/harness compose` per FIRM decision, with **countermand-style triage** — obvious-mechanical proposals auto-accepted silently (recorded on `--notes ## Artifact decisions`); ambiguous proposals raised to user (accept/edit/reject); decisions with no mechanical surface skipped.
  - Discoverability check run; suggested edits surfaced to the user (not auto-applied).
- **For `shape=epic-only`:**
  - No ADR file. Bead `--design` remains the authoritative home for decisions; if FIRM decisions exist, append a `## Decisions (summary)` block with `/harness compose`-proposed invalidation checks (same countermand-style triage as ADR-paired).
  - No discoverability check (no ADR to discover).
- **Auto-accept audit trail.** Every harness-compose outcome (auto-accepted, user-accepted, user-edited, user-rejected, skipped) is recorded on the bead's `--notes ## Artifact decisions` block so wrong auto-accepts are recoverable later.
- **No verdict.** Design-v2 has no `VERDICT: ...` output line. Verdicts are review-v2's protocol.

## Algorithm

1. **Resolve bead.**
   - Read `$ARGUMENTS` for a bead id; otherwise infer from agent context (e.g., review-v2's PASS handoff).
   - Run `bd show <id>`; if not found, error and exit.

2. **Validate bead is vetted.** The bead must have:
   - Non-empty `--design` with a structured decisions section (per brainstorm-v2's output format).
   - An **artifact-shape decision** (epic-only vs ADR-paired) on `--design` per ADR-006 D11.
   - Evidence of a passed review-v2 mode=design run (e.g., `## Review findings (round N)` audit residue in `--notes`, or a recent `VERDICT: PASS` in the agent context). If review hasn't run yet, error: `"Bead has not been reviewed by /review-v2 --mode=design. Run that first."` and exit.

   Design-v2 does NOT re-validate decision completeness, warrant tags, or alternatives — those are review-v2's responsibility. If review PASSed, design-v2 trusts the validation.

3. **Branch on artifact-shape decision:**
   - `shape=epic-only` → skip to step 8 (harness invalidation checks; no ADR).
   - `shape=ADR-paired` → continue to step 4.

4. **Decision-evolution check (4a — primary, hard rule per ADR-011 D1).** For each decision in the bead's `--design`, ask: does it address the *same underlying question* as a decision in any existing ADR? Same-question is the test (e.g., existing decides "default N=1 as target," new decides "default N=1 as floor with cap" — same question about N's role, evolved answer). Explicit phrases like "supersedes ADR-X D-Y," "replaces," "needs updating," "contradicts," or "restricts firmness of" are corroborating signals when present, but their absence does not mean evolution isn't happening.

   **Evolution forms:** direct contradiction *(see step 6 — different routing)*, scope expansion, scope narrowing, firmness change (FLEXIBLE → FIRM or vice versa), constraint addition.

   Routing:
   - **Refinement evolution** (new answer extends or constrains the old without rejecting it) → **in-place edit** the existing ADR. Rewrite the decision text, alternatives table, rationale, and "What would invalidate this." Add `**Date:** <orig> (revised <new-date>)` to the ADR header. Do NOT use `SUPERSEDED` markers, `## Revisions` blocks, or new-ADR-with-cross-reference patterns as substitutes (per ADR-011 D1, those are Forbidden).
   - **Contradiction** (new answer rejects the old's substantive direction) → see step 6.
   - **No evolution detected** → continue to step 5 for genuinely-new content.

5. **Overlap detection (4b — secondary, applies to genuinely-new content only).** Dispatch a cheap classifier subagent to scan `docs/decisions/ADR-*.md` and score candidate matches against the proposed ADR. Compare on dimensions distinguishing duplicates from genuinely-new ADRs: problem statement, root cause, solution approach, referenced files, prevention/firmness rules. Routing:
   - **High overlap:** treat as a signal that 4a may have missed evolution; re-check the same-question test against the high-overlap ADR. If still genuinely new after re-examination, surface the routing call to the user before proceeding.
   - **Moderate overlap:** create new ADR + flag for follow-up consolidation review (note in ADR header: `## Note: may overlap with ADR-NNN`).
   - **Low/none:** create new ADR normally.
   - **Small-corpus fast path:** if `docs/decisions/` contains fewer than 5 ADR files, perform an inline title-line scan (read the first ~5 lines of each ADR) instead of dispatching a classifier subagent. If the inline scan finds no candidate match, proceed as low-overlap. Record the skip on the bead's `--notes` under `## Artifact decisions` (e.g. `overlap detection: inline scan, 4 ADRs, 0 candidates`). If the inline scan surfaces *any* candidate, dispatch the classifier subagent for full scoring.

6. **Contradiction handling — chain back to review-v2.** If steps 4 or 5 surface a contradiction with an existing FIRM ADR that review-v2 did not see (i.e., the ADR was outside review-v2's filtered set), design-v2 **silently chains back to `/review-v2 --mode=design`** with that ADR force-injected into review-v2's pre-filter set. Mechanism:
   - Note the contradicted ADR id (e.g., `ADR-007 D5`).
   - Invoke the review-v2 skill via the Skill tool, passing the bead-id plus an instruction that includes the contradicted ADR's full path/text in the filtered set for the next reviewer dispatch.
   - **Do NOT emit a verdict.** Design-v2 has no verdict protocol. The terminal verdict belongs to whichever review-v2 round produces it.
   - Review-v2 re-enters its loop from round 1 of the new run; the `--N` floor restarts; ceiling stays at 3.

   See `references/contradiction-chainback.md` for why this gap exists.

7. **Write the paired ADR** (when overlap/evolution routing says new-ADR or moderate-overlap, and no contradiction has triggered step 6):
   - Auto-increment ADR-NNN by scanning existing files.
   - Write `docs/decisions/ADR-NNN-<topic>.md` with all decisions copied from the bead's `--design`, including firmness labels, rationale, alternatives tables (with warrant tags), and "What would invalidate" fields.
   - Honor the [Warrant requirement](#warrant-requirement) on every Alternatives table entry — refuse to write if any rejected alternative lacks a `direct:` / `external:` / `reasoned:` tag (this is a sanity check; review-v2 should already have caught violations).
   - Optional `Originated from: <bead-id>` line in the ADR header (historical context only; bead→ADR linking via `--notes` is primary per ADR-006 D3).

8. **Invoke `/harness compose` for FIRM-decision invalidation checks, with countermand-style triage (per ADR-006 D12).** For each **FIRM** decision (skip FLEXIBLE/EXPLORATORY — too tentative to mechanically lock in), invoke the harness skill via the Skill tool with: the decision text, the rationale, the "what would invalidate" predicate, and a hint that the goal is to propose a mechanical falsifier (BUILD/CONNECT/CONFIGURE/REDUCE per `skills/harness/SKILL.md`).

   For each proposal, apply **countermand-style triage** — the same discipline review-v2 uses to decide which findings reach the user (`skills/review-v2/SKILL.md:48-66`):

   - **Auto-accept** when the proposal is *obvious-mechanical* — single well-formed check on a clear falsifier surface (signature, file path, config key, return type, exit code, CLI flag, env var) and harness signals high confidence. If harness does not emit an explicit confidence signal, judge whether the proposal is obviously-mechanical from its overall shape — a single well-formed check against a clear falsifier surface (signature, file path, config key, exit code, etc.) is the obvious-mechanical pattern. When the judgment isn't crisp, raise to user. The audit trail on `--notes ## Artifact decisions` keeps wrong auto-accepts recoverable. The countermand test is "would the user countermand this if I auto-accepted?" — if the answer is plainly no, auto-accept.
     - Append the block silently as `**Invalidation check (mechanical, optional):**` under the decision in the ADR (ADR-paired) or in a new `## Decisions (summary)` block on `--design` (epic-only).
     - Record on `--notes ## Artifact decisions`: `harness compose: auto-accepted (<one-line summary of the check>)`.
   - **Raise to the user** when (a) harness reports low confidence, (b) harness offers multiple plausible variants, or (c) the proposal is judgment-laden (the falsifier surface isn't mechanical — e.g. requires a behavioral test, subjective threshold, or reads on intent).
     - Present accept / edit / reject in the Checkpoint output format (see below). Include the harness rationale in the drill-up section.
     - On accept or edit: append the resulting block (as above). Record `harness compose: user-accepted` (or `user-edited`) on `--notes`.
     - On reject: skip; record `harness compose: user-rejected (<one-line reason if given>)` on `--notes`.
   - **Skip** when harness can't produce a check at all (no mechanical surface). Do NOT fabricate a check; do NOT raise to user with a forced choice. Record `harness compose: skipped (no mechanical surface)` on `--notes`. The decision goes uncovered, and that's fine — optionality of the mechanical block is load-bearing per ADR-008 D1.

   **Forbidden in step 8:**
   - Auto-accepting a proposal that fails the countermand test (low confidence, multiple variants, or judgment-laden) — that path *must* raise to user.
   - Fabricating a check when harness can't propose one.
   - Skipping the audit-trail record on `--notes`. Every harness invocation outcome (auto-accept, user-accept, user-edit, user-reject, skip) must be recorded so wrong auto-accepts are recoverable later.

9. **Add bead↔ADR link** (ADR-paired only):
   - Update bead `--notes` to include `## ADRs consulted` listing the paired ADR (and any prior ADRs referenced during decision-making, carried forward from `--design`).
   - Use `bd update <id> --append-notes "## ADRs consulted\n- docs/decisions/ADR-NNN-<topic>.md"` (or whatever section is appropriate; consult `bd update --help` for the current notes-append flag).

10. **Discoverability check** (ADR-paired only): grep the user's global Claude instructions file (the methodology home's CLAUDE.md if present) and any project-local `CLAUDE.md` or `AGENTS.md` (search up from the current working directory) for mentions of `docs/decisions/` AND at least one of (`docs/design/`, `history/*-design.md`). When the project root *is* the methodology home (the global file is also the project file), one grep covers both. Pass silently if both surface. If either is missing, output a suggested one-liner edit to add discoverability pointers — but **do NOT modify the instruction files autonomously**. Surface the suggestion to the user and wait for confirmation.

11. **Exit.** No verdict emitted. Emit the exit summary per **Checkpoint output format** below. The user's decision (when there is one — discoverability suggestions, queued harness raises) is the ask at the tail; bead-id, ADR path, harness check count, and other mechanical detail go in the drill-up section.

## Checkpoint output format

When emitting a moment that needs the user's input or signals end-of-phase (e.g. final summary to user, contradiction-detected handoff, harness-proposal review), structure the human-facing message as:

- **Anchor** what work this is and what just happened (1 line).
- `---`
- Mechanical detail, citations, finding-by-finding breakdown — drill-up content.
- `---`
- **The ask** in plain language, framed by what the system would do differently — not by mechanism.
- **Options** (≤3, one phrase each, in observable-behavior terms).
- **One-line recommendation.**

**Why this shape:** the user reads chat tail-first — the most recent visible line is what they act on, not the top. Anchor at the top orients on first-read; the ask at the tail is what their attention lands on when switching between parallel agents. Mechanical detail in the middle is drill-up if needed.

**Anti-pattern:** the wall-of-X summary — captured state enumerated through the body, the actual ask diluted into a closing question that gets drowned by everything above it. Signal density at the tail is what makes a checkpoint actionable.

Reference IDs — bead IDs, ADR/decision codes, file:line refs, finding IDs (F1, R2…) — are breadcrumbs for the drill-up section, never the ask at the tail. Collapse correlated decisions to the root choice; don't make the user re-derive interdependencies. Findings that don't need user input (auto-applied fold-ins, defers) get one summary line, not an enumeration.

This shapes the human-facing message only; any machine-parseable contract line is unchanged.

## Warrant requirement

Every alternative in every Alternatives table written to an ADR must carry an explicit warrant tag on its rejection reason:

- `direct:` — cite a specific file, line, issue, or quote from the codebase or prior conversation.
- `external:` — cite prior art: paper, blog, library, framework convention.
- `reasoned:` — first-principles argument; no external grounding required but the reasoning itself is the warrant.

**Tag-selection preference:** prefer `direct:` whenever source material carries a citable claim. `reasoned:` is the fallback for genuinely first-principles arguments.

Design-v2 refuses to write the ADR if any rejected alternative lacks a warrant tag. This is a safety net; review-v2 mode=design's design-mode DoD checklist already enforces alternatives completeness with warrant tags as part of its review.

## Forbidden

- **Validating decision completeness, warrant tags, or alternatives.** Those are review-v2 mode=design's responsibility. By the time design-v2 runs, validation has already passed. Do NOT re-run validation logic that duplicates review-v2's checks (the warrant-tag sanity check at step 7 is a thin safety net, not a replacement for review).
- **Doing artifact-shape triage.** The artifact-shape decision (epic-only vs ADR-paired) is a first-class decision on the bead's `--design`, vetted by review-v2 mode=design. Design-v2 reads it and acts on it; it does NOT make the call. (Pre-2026-04-30 design-v2 had autonomous triage logic; that has moved upstream per ADR-006 D11.)
- **Creating beads.** Brainstorm-v2 creates the bead at convergence (per ADR-006 D5 revised 2026-04-30). Design-v2 only mutates an existing bead's `--notes` (and possibly `--design` for the epic-only summary block in step 8); it does NOT call `bd create`.
- **Extracting decisions from conversation context.** Pre-2026-04-30 design-v2 had "case 2 (topic hint)" and "case 3 (empty $ARGUMENTS)" inputs that read from conversation context. Those are retired. Design-v2's only input is a bead-id. If the bead lacks decisions, that's a review-v2 pre-flight failure (it should have emitted `VERDICT: NEEDS_DECISION` and never reached design-v2).
- **Emitting a `VERDICT: ...` output line.** Design-v2 has no verdict protocol. Verdicts belong to review-v2 alone (per ADR-007 D7).
- **Mutating bead `--design`.** Review-v2 mode=design owns `--design` mutations (fold-ins). Design-v2 only mutates `--notes` (for ADR linkage and audit) and may append a `## Decisions (summary)` block on `--design` for epic-only beads (step 8). For ADR-paired beads, the per-decision detail lives on the ADR; `--design` may stay prose-only.
- **Auto-accepting harness-compose proposals that fail the countermand test** — auto-accept is for *obvious-mechanical* proposals only; raise to user otherwise. (See step 8.)
- **Fabricating mechanical invalidation checks for decisions with no mechanical surface.** Per step 8 + ADR-008 D1's "What would invalidate" framing, mechanical checks are *optional* — `/harness compose` may legitimately be unable to propose one. Skip the decision; do not invent a check; do not force a user choice with no real falsifier.
- **Skipping the `--notes ## Artifact decisions` audit-trail record** for any harness-compose outcome — every result (auto/user-accept/edit/reject/skip) must be recorded for recoverability. (See step 8.)
- **Auto-modifying instruction files** during the discoverability check. Surface suggested edits; humans approve.
- **Using `SUPERSEDED` firmness markers, `## Revisions` blocks pointing to successor ADRs, or new-ADR-with-cross-reference-to-old as substitutes for in-place ADR editing** when decisions are evolving (per ADR-011 D1 + algorithm step 4). Decision evolution requires in-place update of the existing ADR. The git history is the WHY-trail; the live ADR is the current target.
- **Re-emitting a contradiction without chaining back.** When step 6 surfaces a contradiction, the right move is to chain back to review-v2 with the contradicted ADR force-injected. Do NOT silently skip the contradicted ADR, do NOT write a new ADR ignoring the conflict, do NOT prompt the user to "ignore this contradiction" — the contradiction is review's job to adjudicate.

## ADRs consulted

- **ADR-005 D9** — beadify dispatch shape; informs the bead structure design-v2 reads (parent-first hierarchy, integration-test rule).
- **ADR-006 D1** — narrative on `--design`; design-v2 reads decisions from `--design` and writes them to the ADR file.
- **ADR-006 D3** — bead→ADR linking primary; `--notes ## ADRs consulted` is the structural link direction.
- **ADR-006 D5** — brainstorm-v2 creates the epic at convergence; design-v2 no longer creates the bead.
- **ADR-006 D7** — review-v2 mode=design runs before any ADR is written; on PASS, design-v2 is auto-invoked.
- **ADR-008 D1** — ADR predicates (firmness + rationale + alternatives + invalidation) required on every decision. Design-v2's warrant-tag sanity check at step 7 enforces a thin slice of this.
- **ADR-008 D6** — discoverability gating (algorithm step 10).
- **ADR-008 D7** — ADR overlap detection (algorithm step 5).
- **ADR-011 D1** — ADRs reflect target architecture; decision evolution requires in-place update (algorithm step 4). `SUPERSEDED` markers and new-ADR-with-cross-reference patterns are Forbidden.
- **ADR-006 D11/D12** — artifact-shape decision is first-class on `--design`; design-v2 invokes /harness compose for FIRM invalidation checks with countermand-style triage.
