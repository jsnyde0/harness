---
name: brainstorm
description: Substrate-thick Socratic exploration that lands a unit of work into the bead substrate. At convergence, produces a bead with `--design` and `--acceptance` (canonical_refs live in `--design` per ADR-008 D5; no `--notes` content by default); defers ADR canonicalization to `/adr-write` and pipeline decisions to the orchestrator. Use when a topic needs design exploration before it can be scoped to implementable work.
---

## Purpose

Drive open-ended Socratic exploration of a topic and, at convergence, land the result into the bead substrate as a single durable artifact. `brainstorm` does **not** prescribe what comes next — the orchestrator (`/send-it`) decides whether to `/adversarial-review`, `/decompose`, `/adr-write`, or `/implement` against the resulting bead. Brainstorm produces substrate; composition is somebody else's job.

## Inputs

- **`<free-text topic>`** — what to explore
- **`<bead-id>`** — continue exploration on an existing draft bead (rare; used when an earlier session left a partial `--design`)
- **empty** — will ask "what would you like to explore?"

## Precondition — `/recall` before exploring

Before opening the Socratic loop on this topic, ensure `/recall` has tier-routed across L3 ADRs / L2A CASSMS / L2B bd memories / skills for *this topic* in *this session window*. If it hasn't, run `/recall` first — the Methodology section's `/scout-adrs` covers L3 only and leaves L2A calibrations, L2B procedural-lessons / anti-patterns / user-prefs, and the skills survey dark. Self-judge from conversation state ("have I pulled `bd memories` / `cm context` against this topic yet?"); if yes, skip — don't re-run.

## Methodology

Light Socratic loop via `superpowers:brainstorming`:

- One question at a time
- Multi-choice options where possible
- 2-3 approaches with tradeoffs before committing to a direction
- Hold state in conversation; no `/tmp/` files persist beyond the exchange

ADR-awareness is governed globally (see the global agent instructions file → "Decisions and designs"): check the bead's existing `canonical_refs` and any ADRs already in session context first. **Default-on for fresh topics: invoke `/scout-adrs` rather than self-reasoning from the INDEX.** Skip only when the topic is clearly outside any ADR's surface (e.g., trivial UI tweak with no architecture implications) and say so out loud. If `/scout-adrs` is unavailable (dispatched-subagent context), substitute a direct `docs/decisions/INDEX.md` read and surface the substitution. Surface returned ADRs as candidate `## canonical_refs`; don't pre-decide overlaps.

## At convergence

Wait for **explicit** user signal to converge ("yes" / "converge" / equivalent). Do not auto-converge — the user must have a chance to redirect before the bead is committed.

On confirmation, **re-scout ADRs against the final decision set** before composing `--design` — invoke `/scout-adrs` (or substitute `docs/decisions/INDEX.md` read in dispatched-subagent context). Cold-start scout caught the opening framing; decisions may have drifted scope during the Socratic loop (e.g., started "dashboard," landed on "memory enum extension"). Cheap haiku call; catches load-bearing ADRs the cold scout missed.

Then:

1. **Audit the `## Decisions` set for cross-cutting markers** (see "ADR routing" below). If any decision matches, dispatch `/adr-write` **before** `bd create`; the resulting `ADR-NNN` lands in the bead's `## canonical_refs`. The audit runs unconditionally at convergence — it is part of the brainstorm exit contract, not an optional check. Stranding a cross-cutting decision in bead `--design` is the canonical failure (event-visibility tiers, 2026-05-18: crystallized into a brainstorm bead's `--design` but never lifted to an ADR; surfaced 3 days later as an ADR gap during `/scout-adrs`). No substrate hook enforces this — the safety net for skips is `/compound`'s Promote-recognition (see compound/SKILL.md (methodology home) → Promote-candidate recognition patterns).
2. Compose the **`--design`** narrative. Structure:
   - `## Context` — what we're working on and why now
   - `## Decisions` — each decision with firmness (FIRM / FLEXIBLE / EXPLORATORY), rationale, alternatives table with warrant-tagged rejection reasons (per ADR-006 D10: `direct:` source-evidence quote / `reasoned:` causal argument / `external:` cited source), "what would invalidate this" (per ADR-008 D1)
   - `## Acceptance contract` — observable / falsifiable end-state
   - **`## Harness target`** — goal-faithful falsifiable observable, authored before `bd create` (mandatory per ADR-012 D3; see below)
   - `## canonical_refs` — every referenced ADR and external spec by full path (per ADR-008 D5); if none, write `none — self-contained`
3. Compose the **`--acceptance`** — concise observable contract, restated from the design (Given/When/Then or input→output)
4. **Author `## Harness target` before `bd create`** — mandatory per ADR-012 D3. Compose a goal-faithful falsifiable observable using the four-field predicate structure (ADR-008 D1):
   - **Signal** — what runs, or what observable to inspect.
   - **Expected green** — the binary pass criterion (green = done, not-green = not done).
   - **Rationale** — why this altitude / signal best captures the design's intent vs alternatives at neighboring altitudes (e.g., "unit tests would pass even if the integration is wired wrong — the integration probe is the goal-faithful altitude for this bead").
   - **Invalidation** — what would invalidate this harness choice, signal-shaped per ADR-008 D8 (no numeric thresholds).

   Before authoring, **consult `.claude/harness.md`** inventory if it exists — select or adapt an existing mechanism if the inventory names a faster goal-faithful signal at the same or better altitude. Surface the mechanism name in the Rationale. If no inventory exists, note the absence.

   Trivial work (typo, single-config-line, mechanical rename) writes one line: `trivial — no harness needed; manual diff review.` The named-skip-with-rationale is the substrate residue that distinguishes "judged trivial" from "forgot to compose."

   **Anti-pattern to avoid:** Generic fields like "Signal: tests pass; Expected green: tests pass; Rationale: tests verify correctness; Invalidation: tests fail" are templated, not goal-faithful. The Signal must name the specific mechanism; Expected green must state the specific observable criterion; Rationale must explain why this signal captures THIS bead's intent.

5. `bd create --type=<task|feature|epic> --title=<verb-first imperative> --design-file=<path> --acceptance="<contract>"` — single atomic invocation. For long narratives, stage the design markdown in `/tmp/brainstorm/<topic>-design.md` and pass `--design-file`; the temp file is input to `bd create`, not a persisted artifact.

The bead-id is the durable handoff. Brainstorm's job ends there — the orchestrator decides what comes next (typically `/adversarial-review` on the `--design`, then `/send-it <bead-id>` to drive execution; or `/decompose` first if the bead reads bigger-than-atomic).

## ADR routing

**Procedural gate before `bd create`.** Scan the `## Decisions` set for cross-cutting markers; any match dispatches `/adr-write` first. Markers (positive signals — surface, don't hand-wave away):

- **Tier enums on a domain object** — e.g. `public / semi-public / private` event visibility; severity tiers governing handler routing; trust tiers on identity. Any enum that other beads will reference as a constraint.
- **Default-policy rules** — "X is Y by default"; "anonymous read enabled"; "all events are public unless marked." Decisions that govern behavior absent explicit override.
- **Scope-boundary calls** — what counts as in-scope vs out-of-scope for a domain, surface, or behavior class.
- **"For all X do Y" policies** — rules that span multiple beads or constrain future bead authoring.

If any decision matches, dispatch `/adr-write` and place the resulting `ADR-NNN` into the bead's `## canonical_refs` before `bd create`. The gate is procedural, not advisory — an unlifted cross-cutting decision strands in bead `--design` text, disappearing from L3 discoverability for any future agent who doesn't already know which bead to read.

`/adr-write` owns the alignment-question discipline, overlap detection vs existing ADRs (ADR-008 D7), evolution-in-place (ADR-011 D1), and firmness routing (ADR-013 D3). Brainstorm hands the decision over with its rationale + warrant; the alignment question fires in `/adr-write`, not here.

Do **not** write ADR prose inline — see Anti-patterns. The routing is *to* `/adr-write`, not *around* it.

## Raise conditions

Halt and surface to the user when:

- **Topic is too vague to brainstorm productively** — surface the vagueness and ask the user to name a slice. Do **not** auto-derive 3+ narrowing options from observed context (parent session, filesystem, prior work) — that is structure-improvisation, not narrowing. The raise is a HALT: emit one short sentence asking for a slice and stop.
- **A decision under consideration would violate a FIRM ADR** — surface the conflict (which ADR, what it decided, what the proposed decision implies). Do not silently override. The user may want `/adr-write` to evolve the ADR in place, or may redirect.

## Anti-patterns

- **Writing ADRs inline.** Brainstorm never touches `docs/decisions/`. Route load-bearing decisions through `/adr-write`.
- **Writing durable files to `history/`, `docs/`, or `/tmp/` as artifacts.** The bead is the durable artifact. Temp files exist only as input to `bd create`.
- **Auto-chaining to `/review-v2`, `/design-v2`, `/beadify`, `/decompose`, or any downstream primitive.** Brainstorm hands off by creating the bead; the orchestrator decides what comes next.
- **Auto-converging without explicit user confirmation.** Convergence is the gate. Until the user says "yes," the bead does not exist.
- **Skipping the `## canonical_refs` section.** Per ADR-008 D5, mandatory on `--design`. If no ADRs are referenced, write `none — self-contained`; do not omit the section.
- **Updating a brainstorm-task bead in place at convergence — the bridge-bead footgun.** When `<bead-id>` is supplied and the bead's `--acceptance` reads as "the brainstorm has been done" / "decisions captured" / "design ready" (Pattern 2 in bd memories key `brainstorm-bead-bridge-footgun`), completing the brainstorm SATISFIES that acceptance. Do NOT update `--design` in place and hand off to `/decompose` against the same bead — that strands the brainstorm-task bead as a decomposed parent and the design output never gets its own impl-shaped acceptance. The move is **close-and-spawn**: close the brainstorm-task bead at convergence, then `bd create` a new bead carrying `--design` = brainstorm output and `--acceptance` = impl-shape (system-state, observable, falsifiable). Detection cue at invocation against a pre-existing bead-id: does `--acceptance` read "the brainstorm has been done" (Pattern 2 → close-and-spawn) or "the system does X" (Pattern 1 or a post-brainstorm successor → update-in-place is fine)? See send-it/SKILL.md (methodology home) "Pausing after fan-out for confirmation" for the orchestrator-side counterpart.

## Canonical refs

- [ADR-012 D1/D2](../../docs/decisions/ADR-012-substrate-thick-process-thin.md) — substrate-thick / process-thin discipline; output produces substrate (bead), composition is the orchestrator's call.
- [ADR-008 D1, D5](../../docs/decisions/ADR-008-adr-predicates-and-why-aware-plan.md) — bead `--design` predicates (firmness, rationale, alternatives, invalidation) and the mandatory `## canonical_refs` section.
- [ADR-011 D1](../../docs/decisions/ADR-011-adrs-reflect-target-architecture.md) — ADRs evolve in place; relevant to delegation to `/adr-write`.
- adr-write/SKILL.md (methodology home) — handoff target for ADR canonicalization.
- scout-adrs/SKILL.md (methodology home) — light substrate-lookup primitive for `canonical_refs` surfacing during exploration.
- `superpowers:brainstorming` — the question-by-question Socratic methodology this skill drives.
