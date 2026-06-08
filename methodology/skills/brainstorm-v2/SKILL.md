---
name: brainstorm-v2
description: 'Heavy-recipe Socratic-exploration brainstorm with bead creation. Reference composition for genuinely-large new design work; superseded as default by thesis-v2 (ADR-012). For typical brainstorming use /brainstorm.'
disable-model-invocation: true
---

## Purpose

Drive the **Socratic exploration** half of the ideation entry-point for the Phase A workflow. Brainstorm-v2 uses `superpowers:brainstorming` to run the question-by-question loop with the user — one question at a time, multi-choice where possible, 2–3 approaches with tradeoffs.

At convergence, brainstorm-v2 **atomically creates the epic bead** with `--design` (decisions narrative), `--acceptance` (observable contract), and `--notes` (including the artifact-shape decision among the captured decisions). The bead is the durable handoff — it survives device reboot, unlike `/tmp/` files. The paired ADR (when warranted) is **not** written here; it is written by `design-v2` after `review-v2 --mode=design` PASSes the bead.

This separation supports review-before-merge semantics: reviewing decisions on a still-mutable bead `--design` is cheaper than mutating committed ADR files. See ADR-006 D5/D7 and ADR-006 D11.

No files on disk during exploration. State lives in conversation context until convergence; at convergence the bead is created via `bd create`.

## Outputs

- An **epic bead** with:
  - `--design` = the decisions narrative (markdown). Includes the artifact-shape decision as one decision among the others (with firmness, rationale, alternatives, warrant tag, "what would invalidate" — same predicates as every other decision per ADR-008 D1).
  - `--acceptance` = observable / falsifiable end-state (Given/When/Then or input→output).
  - `--notes` = no brainstorm-v2 output by default. ADRs referenced during decision-making live in `--design ## canonical_refs` (per ADR-008 D5), not `--notes`. Design-v2 may later append `## ADRs consulted` here for bead↔ADR linkage (ADR-006 D3) when shape=ADR-paired.
- **No paired ADR** — written by `design-v2` later (if shape=ADR-paired).
- **No `/tmp/` files** — the bead is the handoff.

## Orchestrator algorithm

1. **Input:** check `$ARGUMENTS` for an optional description string.
   - If empty, ask: "What would you like to explore?"
   - If provided, use it as the opening context.

2. **Exploration loop:** invoke `superpowers:brainstorming` to drive the Socratic design loop.
   - One question at a time.
   - Offer multi-choice options where possible.
   - Present 2–3 approaches with tradeoffs before the user commits to a direction.
   - Hold all state in conversation; no files on disk during exploration.
   - Surface the **artifact-shape decision** explicitly during the convergence approach: ask the user to confirm whether the decisions warrant a paired ADR or are epic-only, applying the **re-derivability test** (imagine all implementation is deleted and a fresh agent is handed only the ADR set — would these decisions need to be there for them to rebuild correctly?). The artifact-shape decision is captured with the same predicates as every other decision (firmness, rationale, alternatives table with warrant tags, "what would invalidate"). It is not a preview; it is binding input to design-v2.

3. **Convergence check:** after each exchange, evaluate whether all four criteria are present (purpose, design shape, acceptance, key decisions including the artifact-shape decision). When the orchestrator believes they are, OR when the user signals convergence ("converge"):
   - Confirm convergence per **Checkpoint output format** below. The user's decision here is binary: commit these decisions to a new epic bead, or keep exploring. The decisions narrative, artifact-shape call, and acceptance contract are *drill-up content* — they go in the mechanical detail section, not the ask at the tail.
   - Wait for explicit confirmation. Do NOT auto-converge.

4. **Atomic bead creation at convergence:**
   - Compose the decisions narrative as the `--design` markdown. Structure: `## Context`, `## Decisions` (with each decision's title, firmness label, rationale, alternatives table with warrant-tagged rejection reasons, and "what would invalidate"), `## Acceptance contract`, `## canonical_refs` (per ADR-008 D5: list every referenced ADR and external spec by full path; if none, write `none — this design is self-contained`).
   - Run `bd create --type=epic --title=<verb-first imperative phrase> --design-file=<path> --acceptance="<contract>"` using a single atomic invocation. For long narratives, write `--design` to `/tmp/brainstorm-v2/<topic>-design.md` and pass `--design-file <path>`; the temp file is an input to `bd create`, not a persisted artifact (it can be deleted after the bead is created).
   - For `--notes`, brainstorm-v2 has no default content to write — the bead-id is the handoff. ADRs referenced during decision-making live in `--design ## canonical_refs` (above), not here; design-v2 will populate `--notes ## ADRs consulted` later for bead↔ADR linkage if shape=ADR-paired (per ADR-006 D3).
   - **Bead title:** verb-first imperative (e.g. topic "demographics dataset rollout" → title "roll out demographics dataset to staging then prod").

5. **Hand off to `/review-v2 --mode=design`:**
   - Emit the handoff per **Checkpoint output format** below. The user's decision here is whether to start review now or defer it; the bead-id and review command are drill-up content, not the ask at the tail.
   - Do NOT invoke review-v2 directly from brainstorm-v2. The user (or a parallel-session orchestrator) chooses when to start review.

6. **No `Task()` calls in normal flow.** `superpowers:brainstorming` is a skill invoked in the main agent context, not a subagent. No parallel dispatch during brainstorm.

**Versioning note:** behavior assumes `superpowers:brainstorming` v3.6.x (one-question-at-a-time + create-at-convergence). Re-validate on major version bumps.

## Checkpoint output format

When emitting a moment that needs the user's input or signals end-of-phase (e.g. convergence summary, hand-off to `/review-v2`, BLOCKED, NEEDS_DECISION), structure the human-facing message as:

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

## Forbidden

- **Writing ADRs.** Brainstorm-v2 never touches `docs/decisions/`. ADR routing (overlap detection, evolution vs new, in-place edit vs new file), ADR write, and the discoverability check are all `design-v2`'s responsibility — invoked by review-v2 on PASS.
- **Skipping the artifact-shape decision.** It is a first-class decision per ADR-006 D11. Convergence without it is incomplete. Do NOT auto-decide it inside brainstorm without surfacing to the user — it must carry the same warrant predicates as every other decision so review-v2 can adjudicate it.
- **Creating the bead pre-convergence.** Convergence is the gate. Beads created before convergence are draft stubs and violate ADR-006 D5. The bead is created at the convergence moment, atomically, never earlier.
- **Skipping the user-confirmation step at convergence.** Auto-converging without explicit "yes" leaves the user with no chance to redirect — and once the bead is created, fold-ins from review-v2 are still cheap (they mutate `--design`) but redirecting the entire decision set is not. Always prompt and wait.
- **Writing `/tmp/design-v2/` handoff files.** The handoff to design-v2 is the bead, not a file.
- **Inlining ADR overlap detection / evolution routing.** Those run in design-v2 (after review PASS), against the codebase's ADR corpus. Brainstorm-v2 captures the decision; design-v2 places it.

## ADRs consulted

- **ADR-005 D9** — beadify dispatch shape; informs the epic bead structure that brainstorm-v2 produces (parent-first hierarchy, integration-test rule).
- **ADR-006 D1** — narrative on `--design`; the design narrative the brainstorm produces lands on the bead's `--design` field, not in standalone files.
- **ADR-006 D5** — brainstorm-v2 creates the epic atomically at convergence; design-v2 no longer creates the bead. Bead is the durable handoff.
- **ADR-006 D7** — review-v2 mode=design runs on the bead before any ADR is written; on PASS, design-v2 auto-fires.
- **ADR-008 D1** — ADR predicates (firmness + rationale + alternatives + invalidation) required on every decision, including the artifact-shape decision.
- **ADR-008 D5** — mandatory `## canonical_refs` section on `--design` (consumed by PLAN/REVIEW).
- **ADR-006 D11** — artifact-shape decision (epic-only vs ADR-paired) is a first-class decision on `--design`.
