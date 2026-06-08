# ADR-012: Substrate-Thick, Process-Thin — Workflow Shift to Judgment-Routed Primitives

**Status:** Accepted (decisions are EXPLORATORY pending dogfooding bar in D6)
**Date:** 2026-05-08 (revised 2026-05-22)

**Related:**
- [ADR-005](ADR-005-beadify-redesign.md), [ADR-006](ADR-006-workflow-modernization.md), [ADR-007](ADR-007-primitive-loop.md), [ADR-008](ADR-008-adr-predicates-and-plan.md), [ADR-009](ADR-009-loop-composability.md), [ADR-010](ADR-010-beadify-v2-text-until-convergence.md), [ADR-011](ADR-011-adrs-reflect-target-architecture.md) — the v2 workflow stack this ADR reframes as reference-only.

## Context

The v2 skill stack (`brainstorm-v2` → `review-v2` → `design-v2` → `beadify-v2` → `implement-v2`) was built as a rigor-disciplined mandatory pipeline. In dogfooding it has felt heavy and prescriptive, optimized for worst-case (large new-product builds) at the cost of friction on ~90% of work that is smaller, often non-software (research, doc updates, marketing tactics, ops choices).

Two external comparisons sharpened the critique:
- **claude-caliper** (mining report, 2026-05-08): well-structured but heavily-gated, encodes rigor as machinery. Its best ideas — machine-readable success criteria, parallel scope reviews with reconciliation, handoff notes — point at *substrate*, not process.
- **compound-engineering-plugin** (EveryInc): wider catalog of narrow specialists glued by judgment, plus a real learnings loop. Per-task overhead is *smaller* than ours despite a larger surface. Their bet — trust the model + many cheap specialists + learnings compound — runs counter to "rigor in the orchestrator."

Three subagent reviews of an initial thesis-v2 (skeptic, gap-finder, stress-test) surfaced concrete failure modes for a fully-judgment-routed system: contracts anchor inward and miss neighbor-scope overlap (skeptic's retry/DLQ scenario); rationalizing agents skip adversarial review precisely when needed; bounce-back loops without shared scratchpad lose context; ADRs as catch-all spine produce sprawl or learning-loss.

This ADR records the resulting thesis-v2.1 — substrate-thick, process-thin, with default-on rigor confined to the one place models reliably under-invoke it (review of own work).

## Decisions

### D1: Workflow shifts to substrate-thick, process-thin

**Firmness: EXPLORATORY**

The durable layer (beads as contracts, Anchored Decision Records, harness concept, phase epics, lighter memory layer) is the system's load-bearing surface. The process layer (mandatory pipelines, multi-phase choreography inside skills, work-shape assumptions like "every bead is a code change") is reduced to judgment-invoked composition over a small set of primitives.

The system optimizes for the median task. Heavy machinery is a recipe invoked when complexity demands it, not the default invocation path.

**Rationale:** The substrate gets *more* valuable as models improve — durable contracts, decisions, and learnings outlive any single conversation. Optimizing for the worst-case task imposes a tax on every task. Most tasks aren't worst case. (An earlier framing of this rationale also claimed "process gets less valuable as models rationalize less"; that prong was dropped after the 2026-05-08 review noted ADR-007 D2/D4/D8 carry the opposite empirical finding — autonomy *increases* rationalization risk, so anti-rationalization rigor is preserved as substrate, not relaxed. See `history/2026-05-08-thesis-v2.1-review.md`.)

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Substrate-thick, process-thin (chosen) | Median-task overhead is low; substrate scales with model improvement; heavy recipes available when needed | Fewer hard rails for failure modes (mitigated by D3 default-on review and D6 dogfooding bar) |
| Keep v2 as default, slim individual skills | Continuity; no migration | Doesn't address pipeline-mandate cost; the heavy default still applies to small tasks. **direct:** the v2 stack's overhead was specifically diagnosed as a mismatch for ~90% of work (non-software tasks, smaller changes) in this repo during dogfooding — slimming individual skills doesn't change the pipeline-mandate structure |
| Replace v2 wholesale with compound-engineering-style narrow specialists + judgment | Per-task overhead very low | Throws away beads/ADRs/firmness — substrate that's working — and trades it for a routing layer that's its own complexity. **external:** compound-engineering-plugin (EveryInc) — their per-task overhead is smaller despite a larger surface; their substrate (learnings loop) is what's load-bearing, not their specific routing layer |

**What would invalidate this:** D6 dogfooding ledger shows v2 catches 2+ failures in 5 beads that primitives-only missed. If gating was earning its keep, this thesis is wrong and v2-as-default returns.

---

### D2: ADRs broaden to Anchored Decision Records — load-bearing *cross-cutting* decisions across any domain

**Firmness: EXPLORATORY**

ADR scope expands from architectural choices to load-bearing **cross-cutting** decisions in any domain: workflow, ops, marketing posture, orchestration, content strategy, etc. The acronym is reframed as "Anchored Decision Records" to reflect this. File path (`docs/decisions/`), numbering (`ADR-NNN`), and firmness labels (FIRM/FLEXIBLE/EXPLORATORY) are unchanged for git/link continuity.

**Write filter (the cross-cutting test).** A decision earns ADR status only if **both**:
1. Revising it would require argument (not just noticing) — i.e., it's a load-bearing decision, not an observation or calibration. Lower-signal entries route to D4's lighter memory layer.
2. It is **cross-cutting** — it constrains work in more than one bead, more than one domain, or more than one subsystem. Domain-specific decision logs (e.g., per-campaign marketing calls, per-deploy ops calibrations) live elsewhere with their own routing.

This is a partial walkback of the original "anything load-bearing" framing — necessary because INDEX.md is an O(N) scan with no router predicate, so an unbounded ADR corpus silently degrades discoverability for every primitive that depends on it (see D3 scope-check). Restricting to cross-cutting keeps the corpus small enough to scan reliably.

Edits to companion ADRs to reflect the broadened scope (per ADR-011 D1):
- ADR-006 D2 — in-place edit records the rebrand to Anchored Decision Records and the cross-cutting filter.
- ADR-008 D7 — overlap detection now applies to the broadened scope; the 5-dim rubric is domain-agnostic.
- ADR-008 D6 — discoverability check extends to scan INDEX.md presence in CLAUDE.md.

ADR schema gains two fields adopted (selectively) from Moltbook-style memory practice:
- **Failed attempts / What we ruled out** — already partially present in "Alternatives considered"; formalize when the alternatives include real prior attempts, not just hypothetical options.
- **What would invalidate this** — already present in some ADRs; now mandatory per decision. This is the revision-trigger field.

ADR discoverability uses three layered mechanisms (lightest first):
1. **Index file** at `docs/decisions/INDEX.md` — one line per ADR + scope tag (`workflow`, `arch`, `marketing`, `ops`, etc.). The catalog.
2. **Bead → ADR linkage.** Beads optionally reference ADRs they're constrained by (notes field convention, e.g. `ADRs: ADR-005, ADR-007`). When an agent picks up the bead, those ADRs come along.
3. **CLAUDE.md instruction.** Before contract authoring or design work, scan `INDEX.md` for in-scope ADRs. Before bead execution, read linked ADRs.

**Rationale:** ADRs are the compounding mechanism — preserving *why*, not just *what*. Restricting to architecture loses the compounding benefit for everything else (workflow choices, marketing tactics, ops calibrations) that benefits equally from durable rationale + firmness. Discoverability layers prevent the junk-drawer failure mode by making in-scope ADRs surface naturally during relevant work.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Broaden ADR scope with index + bead linkage (chosen) | One mechanism for all load-bearing decisions; existing tooling continues | Risks sprawl (mitigated by index forcing classification + D4 lighter memory layer absorbing observational/procedural content) |
| Keep ADRs architecture-only; build a parallel "decision log" for other domains | Clean separation by domain | Two systems to maintain; agents must remember which goes where. **reasoned:** two parallel systems for decisions require agents to know which system contains the relevant decision; this knowledge is itself context-dependent and lost across session boundaries |
| Auto-load all ADRs at SessionStart | Maximum discoverability | Context bloat; loads stale ADRs even when irrelevant. **reasoned:** SessionStart context is consumed by every prompt; loading all ADRs unconditionally taxes every interaction with content that's relevant to only a fraction of tasks |

**What would invalidate this:** ADR sprawl materializes — INDEX.md exceeds ~50 entries with no clear scoping discipline, agents start ignoring it. Counter-signal: if the lighter memory layer (D4) absorbs *more* than expected, suggesting the ADR/memory boundary needs sharpening.

---

### D3: Six primitives compose the workflow; adversarial review is the one default-on rule

**Firmness: FLEXIBLE** *(promoted 2026-05-22 from EXPLORATORY on an 8-child substrate-discipline dogfood epic — landed clean; self-test green across four sub-signals (/brainstorm exit, /decompose child authoring, /send-it sink-in, adversarial-reviewer alignment-ordinal-#1); cascading ADR edits (005 D7, 006 D4, 013 D6, 013 D11) and per-repo `.claude/harness.md` seeded without scope drift; user-confirmed at /compound retrospective.)*

Working set of skill-level primitives, each narrow and single-purpose.

**Primitive shape** (the pattern each primitive instantiates — made explicit here so future primitives are derivable, in-place edit 2026-05-12 per ADR-011 D1, surfaced by ADR-013 shape-refinement):

- **Narrow verb, single purpose.** Each primitive produces information OR judges OR splits OR authors — never bundles concerns.
- **Specific output artifact.** Fixed shape (scope-check: 3-section checklist; adversarial-review: PASS/REVISE/REJECT + evidence; decompose: tree of children; compound: 3-section Record/Promote/Retire proposal list). Shape is the constraint; internal steps are judgment.
- **Fresh-context `Task()` dispatch where frame-distance matters.** Three buckets, not two: (a) **dispatches directly** — scope-check, adversarial-review, compound — because the originating frame carries blind spots; (b) **composes with a primitive that dispatches** — decompose calls adversarial-review on the proposed tree; (c) **does not dispatch** — harness-compose, TDD, ADR write — frame-distance isn't load-bearing for them.
- **Orchestrator folds.** Subagent produces; orchestrator decides where each finding lands in substrate. The primitive doesn't write canonical substrate itself; it surfaces for fold.
- **Substrate residue.** Each leaves a legible bd/audit signal — though the shape varies: pass/fail-typed labels (`verdict:*`), presence/absence labels (`scope-checked`, `compounded`), and audit-log `--actor` entries (for verdict and compound). The shared property is *legibility to future readers*, not a uniform residue shape. Future primitives and close-gates can read these.
- **Default-on vs judgment-routed named explicitly.** No vague "use when relevant"; each primitive states its default-on triggers.
- **Composable via recipes**, not bundled into pipelines.

1. **Scope check** — for a proposed bead, list neighbors it likely touches (files, sibling beads, ADRs in scope). Outward-look. Addresses skeptic's overlap-blindness failure mode.
2. **Harness compose** — given scope, author the falsifiable observable target for a bead. Existing `/harness` skill. **Default-on at three junctures**, with `## Harness target` as an always-required permissive bead section.

   *Triggers (default-on):*
   - `/brainstorm` **exit contract.** At convergence, `/brainstorm` authors `## Harness target` in the bead `--design`, capturing the *goal-faithful* signal at the design's intended end-state — not necessarily the highest-altitude e2e test, but whichever signal best captures the design's intent. Lower-altitude harness layers (linters, unit tests, fast-iteration probes) the implementing agent fills in autonomously without user-ask.
   - `/decompose` **child authoring.** Children inherit the discipline; each child gets its own `## Harness target` section. Children's targets must **conjunctively cover the parent's harness target's coverage** — extends the existing acceptance-conjunction discipline (ADR-009 D5) to the harness side.
   - `/send-it` **sink-in.** If a claimed bead arrives without a `## Harness target` section, `/send-it` folds in `/harness` (same composition pattern as folding in `/recall` or `/scope-check`); escalates to user only if `/harness` itself raises (design intent ambiguous, can't pick altitude).

   *Always-required permissive shape.* Every bead carries a `## Harness target` section — no silent skips. Trivial work (typo, single-config-line, mechanical rename) writes one line: "trivial — no harness needed; manual diff review." The named-skip-with-rationale is the substrate residue that distinguishes "judged trivial" from "forgot to compose."

   *Section structure (borrows ADR-008 D1 predicate pattern):*
   - **Signal** — what runs, or what to observe.
   - **Expected green** — binary pass criterion.
   - **Rationale** — why this altitude / signal best captures the design's intent vs alternatives at neighboring altitudes.
   - **Invalidation** — what would invalidate this harness choice (signal-shaped per ADR-008 D8).

   *Harness target = falsifiable observable.* Executable preferred when fit; prose acceptable when executable would force a recipe-leak test (brainstorm-task beads, docs beads, refactor beads where behavior is unchanged). The Rationale field carries the justification when prose-shape is chosen.

   *`.claude/harness.md` is substrate-thick discipline.* The file grows from inventory-only into inventory + project-specific fit profiles ("for X kind of work in this repo, prefer Y mechanism because Z"). **`/harness audit` is a precondition for non-trivial brainstorm authoring** — without inventory, `/brainstorm` has nothing to consult when picking an altitude and `adversarial-reviewer` has no calibrations to push back against.

   *Scope boundary: bead-harness vs brain-harness (added 2026-05-22 in-place per ADR-011 D1; surfaced by a scope-boundary design bead's pushback section and the validation audit-run that blurred the line in practice).*

   - **Bead-harness** = verification mechanisms an implementer can run deterministically against the codebase: tests, lints, runtime probes, harness-target predicates. Lives in per-bead `## Harness target` and per-repo `.claude/harness.md`. Implementer consumes; bead is the unit.
   - **Brain-harness** = orientation discipline for the orchestrator-as-brain: `/recall`, `/scope-check`, `/compound`, session hooks (`brain-of-loop.sh`, `bd-close-verdict-check.sh`), always-loaded skills, CLAUDE.md substrate orientation. Injected at session-default scope per the "Orchestrator-identity injection relocated to main-session default" paragraph above. Brain (orchestrator) consumes; session is the unit.

   Memory tiers (L1 / L2A / L2B / L3) and workflow primitives are **source/substrate** *for* brain-harness, not *categories* *of* bead-harness. `.claude/harness.md` entries categorize by *what-they-do* (static/fast, tests, runtime, tools, grounding, build-it), not by *where-we-learned-them* — memory is the source, citation is the trace, categorization is by-what-it-does. Folding session-start hooks or default-on substrate gap-warning hooks into the per-repo bead-harness inventory is a **category leak**: the items belong in brain-harness; the inventory accidentally captures them when the line isn't named. The same principle blocks adding a "Substrate" or "from-memory" top-level category in `.claude/harness.md` for memory-sourced findings.

   The distinction is load-bearing for two consumers: `/harness audit` (don't blur brain-harness items into per-repo inventory) and `adversarial-reviewer` consulting `.claude/harness.md` (push back when brain-harness items appear in bead-harness scope, or when source-as-category bloats the inventory enum).

   *`adversarial-reviewer` consults `.claude/harness.md`* when reviewing a harness target. Review criteria, in order:
   1. **Alignment** — does the target capture the bead's intended outcome / end-state? (The load-bearing question.)
   2. **Presence** — section exists with the four predicate fields.
   3. **Falsifiability** — Signal + Expected green form a binary observable.
   4. **Fit vs inventory** — push back if `.claude/harness.md` names a faster goal-faithful signal at the same or better altitude.
   5. **Rationale + Invalidation populated** (per ADR-008 D1).
   6. **Conjunction coverage** at parents (for `/decompose` trees) — children's harness targets jointly cover the parent's.

   *Acceptance semantics.* A bead's `--acceptance` is met when **both** the executable/observable harness target is green **and** prose acceptance criteria are met. Harness signal does not displace prose acceptance — it makes the load-bearing portion falsifiable. (ADR-006 D4 holds the contract-location side of this rule; the pairing will be reflected by a deferred in-place edit to D4.)
3. **Decomposition** — split a bead into children with sub-contracts whose conjunction satisfies the parent. Includes a default-on tree-review step *before any subagent dispatches* (closes the inter-child contract gap that beadify-v2's 4-phase critic was solving).
4. **Adversarial review** — fresh-context review of an artifact (design / contract / decomposition tree / implementation). Ternary verdict (PASS / REVISE / REJECT). **Default-on for own work; judgment-invoked otherwise.**
5. **TDD discipline** — test/contract-first, watch fail, make pass. Existing `superpowers:test-driven-development`. Invoked when the work is code with runnable verification.
6. **ADR write** — author or evolve an Anchored Decision Record per ADR-011 in-place rule.
7. **Compound** — inward-look retrospective over a closed unit of work; produces a three-section Record / Promote / Retire proposal list against memory substrate. Scope-check's inward counterpart. Internal design at [ADR-013](ADR-013-memory-layer-architecture.md) D5/D6.

**Default-on rigor rule (substrate-enforced).** *Never review your own contract, plan, or decomposition tree.* The rule is enforced at the bead-schema layer, not as model-honored prose. Substrate-thick here means *legible and unignorable*, not *mechanically blocked* — the orchestrator agent is the executive, bd surfaces the state:

- A contract / plan / decomposition-tree artifact records its reviewer identity via bd's `--actor` field (or `$BEADS_ACTOR` env var) at the moment a `verdict:pass|fail` label is added. The substrate signal is *the audit-log actor on the verdict-add event must differ from the audit-log actor on the bead's create-event* (per design landed in the reviewer-identity design bead).
- `bd close` emits a stderr warning (exit 0) when an authored-but-unreviewed (or self-reviewed, or `verdict:fail`-stamped, or freshness-stale) bead is closed. A bead authored by actor A and not yet `verdict:pass`-ed by an actor ≠ A cannot close silently.
- Substrate-level mechanism (CC1 fix from the 2026-05-08 review): the rule is mechanical, not interpretive — the audit-log actor comparison survives dispatch boundaries where "own work" is otherwise ambiguous. The WARN-default reflects that the orchestrator is trusted; promotion to BLOCK is a follow-up if the warn signal is observably ignored on load-bearing beads.

All other primitive invocations are judgment-routed. **Scope check** is also default-on for any decomposition or new bead authored within a multi-bead epic — overlap-blindness is structural per MemoryArena evidence, not a judgment failure.

**Orchestrator-identity injection relocated to main-session default** *(added 2026-05-14 in-place per ADR-011 D1).* The "you are the brain of this loop / context is the scarce resource / default is dispatch / failure mode is silent absorption" framing previously lived inside `/send-it`'s Premise. Lifted to a SessionStart hook (`brain-of-loop.sh` in the methodology home's hooks directory) so the framing is default posture for the main agent across every session — not just when `/send-it` is invoked. Subagents do not re-trigger SessionStart hooks, so the framing stays out of subagent contexts (preserves fresh-context discipline per `subagents` skill). `/send-it`'s Premise now assumes the framing as loaded and adds only the loop-specific content (validate → repair → re-validate against `--acceptance`). Rationale: orchestrator-as-brain is an identity claim, not a skill-specific recipe — it belongs at session-default scope so absorbing-work failures can't sneak past simply by the user not invoking `/send-it`. Convergent finding from 2026-05-14 orchestration-pattern research across LangGraph / Flock / Gastown / Anthropic Cookbook / community: **subagent = context offload, not just labor offload** — the brain pays for judgment, workers pay for token volume.

**Preserved operational rules** (carried forward from ADR-007/008/009 — these remain FIRM as substrate, even though the *mandatory pipeline* that previously invoked them is demoted by D5):

- Three rigor rules for any reviewer subagent (ADR-007 D4): file:line evidence, binary verdict, err-to-FAIL.
- Adversarial-stance prompt block + named go-soft failure modes for every reviewer (ADR-007 D8).
- Fresh `Task()` per reviewer invocation (ADR-007 D3) — no anchoring across retries.
- Stateless re-prompt for subagents (ADR-007 D6) — context lives in files and bd, not in transcripts.
- Orchestrator runs validators directly when a primitive-loop recipe is invoked (ADR-007 D2).
- Rule P + ADRs-consulted section apply to *any* plan or contract authored by an agent (broadened ADR-008 D2, in-place edited).
- Mid-loop discovery uses `discovered-from` and does not fix in the same iteration (ADR-008 D4).
- `## canonical_refs` mandatory in design narratives (ADR-008 D5).
- 5-dim overlap detection before creating a new ADR (ADR-008 D7), now applied to broadened scope.
- Strip parent context from child subagent prompts (ADR-009 D3).
- Depth cap 3 for parent-child nesting (ADR-009 D4).

**Demoted to recipe-level** (in-place edits applied to home ADRs per ADR-011 D1): the 4-state mandatory loop (ADR-007 D1 → FLEXIBLE), 3-retry cap as termination gate (ADR-007 D5 → FLEXIBLE), parent serial dispatch and parent-re-runs-acceptance (ADR-009 D1/D2/D5 → FLEXIBLE). These remain valid recipes when invoked, not mandatory pipelines.

Recipes (compositions of primitives, used by judgment when their shape fits):
- **Bead authoring:** `scope check → harness compose → bead create`.
- **Epic decomposition:** `decomposition → adversarial review (default-on, substrate-enforced) → dispatch`.
- **Code-shaped bead with runnable acceptance (the ADR-007 loop, now a recipe):** `PLAN → REVIEW-PLAN → IMPLEMENT → REVIEW-CODE` with retry cap and parent re-check when applicable.
- **Epic-close compounding:** `compound (fresh-context, produces Record/Promote/Retire) → orchestrator folds (Record→cm/bd writes; Promote→adr-write composition; Retire→bd forget / cm decay)`. *(Added 2026-05-12 in-place per ADR-011 D1.)*
- **Heavy design work:** v2 skills remain as reference compositions, invoked explicitly per D5.

**Rationale:** Five primitives in the original thesis-v2 missed contract-overlap detection (skeptic's punch) and made adversarial review opt-in (which a rationalizing agent will skip precisely when most needed). Adding scope check and making review default-on closes the two highest-leverage failure modes without bringing back the full pipeline. Recipes are documentation of common compositions, not mandatory invocations.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Six primitives + one default-on rule (chosen) | Minimal mandatory rigor in the place where it's most load-bearing; everything else is judgment | Two failure modes (rationalization on review, overlap-blindness) require structural fixes — but small ones |
| Five primitives, all judgment-routed (original thesis-v2) | Maximally thin | Reviewer concerns landed: rationalizing agents skip review; contracts anchor inward. **direct:** three subagent reviews of the initial thesis-v2 (skeptic, gap-finder, stress-test) surfaced these specific failure modes; skeptic's retry/DLQ scenario showed contract-overlap blindness, gap-finder named the review-skip rationalization |
| Bring back mandatory pipeline gates between primitives | Catches more | Reverts to v2; defeats the thesis. **direct:** D1 of this ADR names the mandatory-pipeline cost as the diagnosis; reimposing gates between primitives reproduces exactly the friction identified as the problem |
| Make every primitive default-on | Strongest discipline | Reproduces v2 process density. **reasoned:** default-on for all primitives means every task pays the full overhead regardless of size; the original critique is that v2 optimized for worst-case at the cost of ~90% of work that doesn't need it |

*Alternatives considered for the `/harness` default-on shape (added 2026-05-22 in-place per ADR-011 D1):*

| Approach | Pros | Cons |
|---|---|---|
| Always-required `## Harness target` section with one-line "trivial" exemption (chosen) | One substrate shape; named-skip is auditable; reviewers see all skip rationale | Risk of lazy "trivial" defaults — addressed in invalidation below |
| Triviality-gated discipline (skip section entirely for trivial work) | Less ceremony on small beads | **reasoned:** silent skips are indistinguishable from forgotten harness composition; the named-skip-with-rationale is itself the substrate residue that lets reviewers and `/compound` retrospect on skip patterns. Removing the section removes the audit surface |
| Source-gated discipline (`/harness` only fires on code-shaped beads) | Avoids prose-target awkwardness on docs/refactor beads | **reasoned:** the goal-faithful-signal question applies equally to non-code work (a docs bead's signal might be "reviewer countermand-test passes," a refactor bead's might be "behavior-preservation test suite still green") — gating on source-shape leaks an implementation assumption into the discipline |
| `bd create` / `bd claim` hook enforcement | Mechanical, unignorable | **reasoned:** moves the discipline from substrate-legible (bead section + reviewer check) to substrate-enforced (refuses to create/claim). The ADR-012 D3 broader pattern is substrate-legible-not-enforced (e.g., the WARN-default on bead-close); hook-enforcement reproduces the v2 pipeline-gate friction this ADR was diagnosing as the problem |
| Fold memory tiers as inventory categories (e.g., L2A / L2B sections, or a "from-memory" top-level category in `.claude/harness.md`) | Single substrate covers both source and structure | **direct:** a scope-boundary design bead rejected this for `/harness audit`'s memory-consultation step on the warrant *"memory is the source, not the kind — categorize by what-it-does, preserve provenance via citation."* The validation audit-run on the methodology home empirically demonstrated the categorization-by-what-it-does pattern works: 11+ memory-sourced entries folded cleanly into the existing six categories with `(source: bd memories key=… \| ADR-…)` inline citations, no category bloat. Adding source-as-category bloats the enum without compounding discriminative power — every new substrate tier would double the category enum. See the "bead-harness vs brain-harness" scope-boundary subsection above for the underlying scope-of-inventory principle. |

**What would invalidate this:** D6 ledger shows >=1 of the 5 beads fails specifically because (a) scope check missed an overlap or (b) default-on review didn't fire. If the failure mode is elsewhere, this primitive set is reasonable; if it's in these two specific spots, the design is wrong and gating logic needs to be revisited.

*`/harness` default-on invalidation signals (added 2026-05-22 in-place per ADR-011 D1):*
- **Lazy-trivial drift.** Across a representative dogfooding window, the proportion of beads stamped "trivial — no harness needed" rises while reviewer-caught misses on those same beads also rise — i.e., the trivial exemption is silently absorbing non-trivial work. Counter-signal: `adversarial-reviewer` starts countermanding "trivial" rationales on non-trivial beads as a recurring finding.
- **Conjunction over-engineering at `/decompose`.** Children's harness targets accumulate redundant low-altitude signals to "cover" the parent's high-altitude target, making child harness sections noisy relative to the design intent they're meant to capture. Counter-signal: `adversarial-reviewer` flags conjunction-padding as a recurring finding on decomposition trees.
- **Brainstorm-authoring blocked by missing harness.md.** `/harness audit` precondition stalls non-trivial brainstorm work in repos that haven't yet built an inventory, producing skip-the-precondition pressure that re-leaks `/brainstorm` exit without a harness target. Counter-signal: orchestrator observes `/brainstorm` runs exiting without `## Harness target` despite the default-on trigger.
- **Bead-harness vs brain-harness drift.** Across a representative dogfooding window, the proportion of `.claude/harness.md` entries that are brain-harness items (session hooks, orientation primitives, substrate-tier consultation discipline, default-on gap-warning hooks) classified as bead-harness rises despite the scope-boundary subsection naming the line — i.e., audit-runs absorb brain-harness items into per-repo inventory regardless of the named distinction. Counter-signal: `adversarial-reviewer` flags blurred categorization as a recurring finding on `.claude/harness.md` audits. If the named line creates friction without payoff (audit quality improves when brain-harness items ARE included in per-repo inventory), the scope-boundary is wrong and `.claude/harness.md` is the right home for orchestrator-orientation discipline too.

---

### D4: Compounding spine = ADRs (decisions) + lighter memory layer (observations)

**Firmness: EXPLORATORY**

> **Sharpened by [ADR-013](ADR-013-memory-layer-architecture.md) (2026-05-12).** The bicameral framing below was the initial sketch; brainstorm 5f1.4.5 expanded it to a three-layer lifecycle architecture (L1 raw / L2A observations / L2B parking-lot / L3 canonical), with substrate adopted from CASS + CASSMS rather than a `bd remember` schema extension. The text below is preserved as the originating thesis-v2.1 framing; treat ADR-013 as canonical for memory-layer questions.

The compounding mechanism is bicameral:
- **ADRs** hold *decisions* — load-bearing choices with firmness and revision conditions. Revising one requires argument.
- **Lighter memory layer** holds *observations and procedural learnings* — calibrations ("agents underestimate webhook scope ~2x"), failed attempts that didn't rise to a decision, environmental notes ("test harness slow on ARM Macs"). Revising requires only noticing.

Substrate for the lighter layer: `bd remember` with light schema additions — `kind` field (one of: observation / calibration / procedural-lesson / failed-attempt) and free-text body. Searchable via `bd memories <keyword>`. Promotion path: a recurring memory may graduate to an ADR when revising it would require argument; retirement path: stale memories drop from search results or get tagged `archived`.

Phase D ("learnings layer") collapses into: extend `bd remember` schema, write the promotion/retirement convention, add a scheduled review primitive (TBD shape, not designed in this ADR). Most of Phase D defers until dogfooding shows what schema is actually load-bearing.

**Rationale:** Folding all compounding into ADRs produces sprawl (every observation becomes an ADR) or learning-loss (only architectural decisions survive). The split is content-shape: decisions go in one place, observations in another. `bd remember` already exists and already partially serves this role. The Moltbook framing (decision + failed-attempts + trigger + evidence + revision-condition) is captured across the two layers, not packed into one.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| ADRs + bd remember as bicameral spine (chosen) | Existing tooling on both sides; clear shape-based split | Boundary requires discipline (when does an observation become a decision?) |
| ADRs only, broadened with Moltbook fields | Single mechanism | Sprawl risk; ADRs become runbooks. **reasoned:** folding all observations into ADRs removes the distinction between decisions (require argument to revise) and observations (require only noticing); the corpus degrades into a mix that's neither searchable as decisions nor maintainable as runbooks |
| New unified memory tool for everything | Cleanest in theory | Builds new infra; throws away `bd remember` and ADR practice. **reasoned:** building a new unified tool requires replacing two working systems with a third; the substrate-thick principle (D1) favors keeping working substrate over building aspirational replacements |

**What would invalidate this:** Promotion/retirement convention proves useless or impossible — entries either never get promoted (memories pile up) or always get promoted (ADRs become memories). Counter-signal: if dogfooding shows the lighter layer is empty after several months, the boundary is wrong and the spine should fold back into ADRs.

---

### D5: v2 skills are reference compositions, not default invocation paths

**Firmness: EXPLORATORY**

The five v2 skills (`brainstorm-v2`, `review-v2`, `design-v2`, `beadify-v2`, `implement-v2`) remain in the repo as reference compositions for genuinely-large work. Each frontmatter carries `disable-model-invocation: true` — the substrate-level flag that prevents Anthropic skill matching from auto-triggering them. They surface only via explicit slash-command invocation (`/brainstorm-v2`, `/review-v2`, etc.).

They are not deleted, not actively maintained, and not the default. When a genuinely-heavy task arrives (new product, large new subsystem, multi-phase build), the user invokes them explicitly.

**Rationale:** v2 represents real thinking about rigor — discarding it loses learnings. But keeping it as default produces the addition spiral we just diagnosed. The original framing of this decision used a `[REFERENCE — do not auto-trigger]` prefix on the description as the dampening mechanism; the 2026-05-08 review noted that prefix relies on the model honoring prose, while skill matching scores the description's keywords *before* instruction-following fires (CC1). The fix is structural: `disable-model-invocation: true` is the supported skill-frontmatter flag for "explicit-only invocation," removing the auto-trigger surface entirely.

Companion in-place edits (per ADR-011 D1) accompany this decision:
- ADR-006 D7 — the `/review-v2 → /design-v2` auto-chain is now opt-in via explicit invocation; the binding gate language is scoped to "when v2 is explicitly invoked."
- ADR-006 D11/D12/D13 — design-v2's default behaviors (artifact-shape decision, `/harness compose` auto-invocation, three-paths bug-fix routing) apply only when v2 is explicitly invoked.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Frontmatter dampening, keep skills (chosen) | Reversible; preserves learnings; zero cost when unused | v2 will bit-rot until invoked |
| Delete v2 skills | Forces commitment | Throws away real design work; hard to undo. **reasoned:** v2 represents real design thinking about rigor; deleting it loses the rationale for its decisions, which are referenced by multiple ADRs as the historical basis for evolved decisions |
| Refactor v2 skills into thesis-v2.1 primitives in-place | Continuity of names | Destroys reference value of v2 as compositions. **reasoned:** v2 skills serve as reference compositions showing how primitives can be combined for large work; refactoring them in-place removes the ability to compare the heavy approach against the lightweight one |

**What would invalidate this:** v2 is never invoked over a meaningful dogfooding period (3+ months), suggesting it has no actual use case. Counter-signal: v2 gets invoked frequently, suggesting the thesis-v2.1 default is too thin and v2 should reclaim default status (or specific v2 phases should be promoted to primitives).

---

### D6: Thesis-v2.1 promotes to FIRM only after a dogfooding ledger of ≥5 beads

**Firmness: FIRM**

This ADR's decisions D1–D5 carry firmness EXPLORATORY pending a concrete dogfooding evaluation:

- **Sample size:** ≥5 real beads run end-to-end on thesis-v2.1 primitives.
- **Coverage:** at least one bead that *should* trigger a bounce (subagent-too-big), at least one with cross-bead overlap with a neighbor.
- **Failure ledger:** for each bead, record (a) what happened, (b) what v2 would have caught that primitives-only missed, (c) which primitives were invoked, (d) outcome (pass / minor friction / failure).

Promotion criteria:
- **Ledger shows 0–1 v2-only catches across 5 beads:** thesis-v2.1 promotes to FIRM. D1–D5 carry their content forward at FIRM.
- **Ledger shows ≥2 v2-only catches:** thesis-v2.1 is wrong as stated; the relevant decisions revise (likely D3 — primitives + default-on rule expand) or the thesis returns to v2-as-default.

The ledger lives at `docs/decisions/thesis-v2.1-dogfood-ledger.md` (path locked-in 2026-05-13 in-place per ADR-011 D1; the "or similar location" hedge is removed). It is updated **inline at the close of every ledger-eligible bead** per the ownership block below; the older "bead-by-bead during dogfooding" framing remains the FIRM mandate, narrowed by the eligibility predicate to *primitive-exercising* beads. Promotion/revision verdicts are recorded as an in-place edit to D1–D5 firmness per ADR-011 D1; the ledger's own prose section is commentary, not the authoritative verdict surface.

**Ledger ownership and write cadence** *(added 2026-05-13 in-place per ADR-011 D1; resolves the underspecification a ledger-substrate bead surfaced. This block is an operational clarification under D6's FIRM mandate — it does not introduce a new firmness label and is not severable as a sub-decision; the FIRM mutation rule continues to govern its evolution.)*

- **Owner: orchestrator inline at bead close.** The agent closing a ledger-eligible bead appends one row before stamping `verdict:pass` (or in the same close-time gesture). Inline matches the FIRM "bead-by-bead" cadence; close-time placement means the row reflects the *final* outcome, not a mid-flight guess.
- **Eligibility predicate.** A bead is ledger-eligible if its execution invoked one of the thesis-v2.1 primitives (`/scope-check`, `/decompose`, `/adversarial-review`, `/compound`, `/adr-write`) OR exercised the bead-substrate close-time check (the close-time verdict design bead). Substrate-legibility honesty: only three of these leave a one-query label residue today (`scope-checked`, `verdict:pass|fail`, `compounded`); `/decompose` and `/adr-write` are inferred from notes/audit-log presence, and the orchestrator's judgment is the seam. No substrate gate enforces eligibility — the close-er decides, matching ADR-012 D3's broader "substrate-legible, not substrate-enforced" pattern.
- **Format: single markdown table.** Columns: `bead-id | date-closed | primitives invoked | outcome | v2-only-catch? | notes`. The four ADR-012 D6 fields map as: (c) primitives invoked → first-class column; (d) outcome → first-class column; (b) v2-only-catch? → first-class column (the promotion-criteria gate at lines 220–221 turns on this column); (a) what happened → `notes`. The (a)-into-notes collapse is intentional — what happened is a narrative; the structured gate is in v2-only-catch?.
- **Row-count discipline.** Distinct `bead-id` values in *data rows* of the table count toward the 5-bead bar. A practical count command: `awk -F'|' '/^\| [a-z]/ {print $2}' thesis-v2.1-dogfood-ledger.md | sort -u | wc -l`. The example/template row is **not** in the data table — it lives in a separate fenced block in the ledger.
- **Append-only with annotation-row reassessment.** Rows are not edited after write except to correct factual errors; if outcome reassessment is warranted, append a new row with the same `bead-id` and a `[reassessment]` prefix in `notes`. The most-recent row for any `bead-id` is authoritative for the v2-only-catch? gate.

**Rationale:** Without an explicit promotion bar, EXPLORATORY ADRs decay into "this is what we said once" — the firmness label loses meaning. A concrete sample size + coverage requirement + failure ledger turns the EXPLORATORY → FIRM transition into evidence-driven. The bar is small enough to be reachable (5 beads, not 50) and structured enough to be honest (named coverage requirements, named comparison against v2).

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Explicit ledger + 5-bead bar (chosen) | Concrete; small; structured | May feel ceremonial — but the ceremony is the discipline |
| Promote when "feels right" | Lightweight | Firmness label becomes meaningless. **reasoned:** without a concrete bar, EXPLORATORY decisions never achieve a revision condition and the firmness label provides no information about when revision is warranted |
| Larger sample (20+ beads) | More evidence | Defers commitment too long; thesis can't guide work in the meantime. **reasoned:** a 20-bead bar means the thesis remains EXPLORATORY for months; the working system needs to operate on this ADR's guidance before the bar is hit, defeating the purpose of having a promotion condition |

**What would invalidate this:** The ledger turns out to be impossible to compare against v2 honestly (e.g., the same task wouldn't have used v2 at all under thesis-v2.1, so "what v2 would have caught" is nonsensical). If so, replace the comparison with absolute outcome quality — was the work good? — and revise D6.

## canonical_refs

*(Added 2026-05-12 in-place per ADR-011 D1 to satisfy ADR-008 D5 mandate on design narratives. The previous `## Related` section is preserved below as supplementary context.)*

- [ADR-008](ADR-008-adr-predicates-and-plan.md) D1 — per-decision predicates (firmness + rationale + alternatives + invalidation). Applied throughout D1–D6; lifted as the section structure for the `## Harness target` bead-section in D3's `/harness` primitive.
- [ADR-008](ADR-008-adr-predicates-and-plan.md) D5 — `## canonical_refs` mandate (this section).
- [ADR-008](ADR-008-adr-predicates-and-plan.md) D8 — signal-shaped invalidation (no bare numeric thresholds); governs the Invalidation field on `## Harness target` sections per D3.
- [ADR-009](ADR-009-loop-composability.md) D5 — acceptance-conjunction discipline (children's `--acceptance` jointly satisfies parent); extended by D3's `/harness` discipline to the harness-target side at `/decompose` child authoring.
- [ADR-011](ADR-011-adrs-reflect-target-architecture.md) D1 — in-place mutation rule; governs how all D1–D6 firmness labels evolve.
- [ADR-006](ADR-006-workflow-modernization.md) D10 — warrant tag convention on Alternatives rejections (noted gap; not yet applied across this ADR's Alternatives tables — see ADR-013 §canonical_refs for the same observation).
- [ADR-013](ADR-013-memory-layer-architecture.md) — sharpens D4 (bicameral compounding spine) into a three-layer memory architecture; introduces `/compound` as primitive #7 in D3.
- [ADR-013](ADR-013-memory-layer-architecture.md) D6 — substrate-residue legibility (cited as downstream evolution target — `/compound` will retrospect on harness-target skip patterns per D3's lazy-trivial invalidation signal).
- [ADR-013](ADR-013-memory-layer-architecture.md) D11 — juncture-awareness behavioral contract; composes with D3's per-primitive triggers (recognition obligation vs invocation declaration). D11's in-band cues paragraph also names `bd close` stderr warnings as juncture-cue substrate, paired with D3's substrate-residue shape. `/recall` evolution to surface `.claude/harness.md` fit profiles at juncture re-survey is a downstream edit target.
- ADR-007, ADR-008, ADR-009 — preserved operational rules cited in D3 ("Preserved operational rules" block) as substrate carrying forward from the v2 chain.
- ADR-010 — beadify-v2 text-until-convergence; demoted to reference per D5.

## Related

- v2 skill files (`{brainstorm,review,design,beadify,implement}-v2/SKILL.md` in the methodology home) — frontmatter dampened per D5.
- `{scope-check,decompose,adversarial-review}/SKILL.md` in the methodology home — the three landed primitives instantiating D3.
- `/harness` skill — the scope check primitive (D3) is a near-neighbor; integration TBD during dogfooding.
- `bd remember` (beads CLI) — L2B substrate per ADR-013 D2.
- `cm` (CASSMS) and `cass` (CASS) CLIs — L2A and L1 substrates per ADR-013 D4.
- Subagent reviews informing D3 — captured in conversation history; key punches: skeptic's retry/DLQ overlap scenario, gap-finder's contract-authoring split, stress-test's design-moment gap in scenario 3.
