# ADR-006: Workflow Modernization — ADRs Stay Markdown, Beads Are the Work Substrate

**Status:** Accepted (updated in place 2026-04-24) (revised 2026-05-13)
**Date:** 2026-04-23 (initial); 2026-04-24 (updated after workflow-loop brainstorm)
**Design:** [Workflow Loop Design (current picture)](../../history/2026-04-24-workflow-loop-design.md). Earlier: [`2026-04-23-workflow-modernization-design.md`](../../history/2026-04-23-workflow-modernization-design.md) (superseded).
**Related:**
- [ADR-005](ADR-005-beadify-redesign.md) — beadify organize+target
- [ADR-007](ADR-007-primitive-loop.md) — primitive loop state machine + review rigor
- [ADR-008](ADR-008-adr-predicates-and-plan.md) — ADR predicates + WHY-aware PLAN
- [ADR-009](ADR-009-loop-composability.md) — epic composability
- [ADR-004](ADR-004-soldier-proof-skill.md) — skill hardening discipline

## Context

`bd` has matured into a system that can hold the content previously split across three media. Epics with auto-numbered children, a dedicated `--design` field, appendable `--notes`, `--acceptance`, per-field Dolt-backed history, and `bd comment` collectively cover what a `history/*-design.md` file was doing.

Keeping design content in markdown costs: (a) dual source of truth — beads reference rot-prone paths, (b) follow-up bugs require ceremony (new design? new beadify?), (c) review findings fragment across a separate fixes file, (d) cross-bead design visibility is weak because children don't carry parent context automatically.

ADRs do not have this problem. They are small, read-often, edited rarely, and valuable as markdown. Beads offer no advantage for ADR content — no diff UI, no template enforcement, no markdown render.

This ADR records the decisions that move **design** onto the epic while keeping **ADRs** as in-place-updated markdown. It also updates ADR-005's D3 and D5 to fit the new architecture.

## Decisions

### D1: Design narrative lives on the epic's `--design` field

**Firmness: FIRM** *(was FIRM 2026-04-23, demoted to EXPLORATORY 2026-04-24, re-promoted to FIRM 2026-04-25 with chosen direction)*

The design narrative for any change — large or small — lives on the originating bead's `--design` field. No markdown design doc. Markdown render still works since `--design` content is markdown text rendered through any viewer.

**Rationale:** Workflow uniformity dominates markdown-ergonomics. A planned epic from `/brainstorm` and a small follow-up bead filed mid-iteration go through the same machinery: both are beads, narrative on `--design`, paired ADR referenced from bead notes. `bd show` is the single context lookup for any subagent. The dual-source-of-truth and link-rot costs of a separate markdown doc are real and recurring; the markdown-render cost is a one-time ergonomic adjustment. Metaswarm's preference for markdown was driven by their stack, not a structural argument that survives our beads-as-substrate choice.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Narrative on `--design` (chosen) | Uniform pipeline for any-size work; single source of truth per change; Dolt history; cheap follow-ups; `bd show` is the only context lookup | Markdown rendering requires a viewer that handles `bd show` output; diffs via `bd history` rather than `git diff` |
| Narrative in markdown + epic carries acceptance only | Renderable prose; operational precedent (metaswarm) | Dual source of truth; link rot; small-bead/big-epic asymmetry. **direct:** work-product design→bead pairs — dual source created rotting paths that beads referenced long after the design doc moved |
| Hybrid — TLDR on `--design`, full narrative in markdown | Keeps both strengths in theory | Decision on where the split lives is itself non-trivial; ergonomics worse than either extreme. **reasoned:** a hybrid requires a policy for which content goes where; that policy is non-trivial and creates its own maintenance surface, yielding worse ergonomics than either pure approach |

**What would invalidate this:** If the epic's `--design` field consistently stays empty or stale because authors find writing into a bead too friction-heavy, the choice has lost. Watch for `bd list` showing epics with blank or trivially short `--design` fields as a recurring pattern — when that surfaces, the substrate is wrong for narrative. Counter-signal: if subagents routinely need a markdown companion to do their job, the rendering ergonomics are blocking — reconsider hybrid.

### D2: ADRs stay markdown at `docs/decisions/ADR-*.md`, updated in place — **scope is cross-cutting load-bearing decisions across any domain (Anchored Decision Records)**

**Firmness: FIRM** *(scope broadened 2026-05-08 per ADR-012 D2 — was "architectural ground truth", now "cross-cutting load-bearing decisions across any domain"; acronym rebranded to Anchored Decision Records)*

ADRs remain markdown files at their current path. Changed decisions are **rewritten in place** to represent current reality. No "Superseded by ADR-XXX" chains. The ADR corpus is the **decision** ground truth at any point in time, across all domains where load-bearing cross-cutting decisions occur (architecture, workflow, ops, marketing posture, content strategy, etc.). Per ADR-012 D2's write filter, an entry earns ADR status only if (a) revising it would require argument and (b) it is cross-cutting (constrains more than one bead/domain/subsystem). Lower-signal observations route to ADR-012 D4's lighter memory layer (`bd remember`).

**Rationale:** ADRs are read far more often than they are written; they benefit from stable paths, grep-ability, PR diffs, and templated structure. `bd` offers no equivalent. "In-place update" matches how the user actually treats ADRs (current reality, not history) and avoids the supersede-chain archaeology that Michael Nygard-style ADRs accumulate. The scope broadening reflects that the same compounding mechanism (durable rationale + firmness + alternatives) applies to any load-bearing decision, not only architecture; the cross-cutting filter prevents corpus sprawl that would silently degrade INDEX.md as a routing surface.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| In-place update (chosen) | ADR corpus = current reality; no archaeology; greppable | Lose per-decision audit trail (mitigated by git history) |
| Supersede chain | Preserves original decisions verbatim | Reader has to reconstruct current state; encourages fossilized bad calls. **external:** Michael Nygard-style ADR supersession chains — well-documented pattern that turns ADR corpus into archaeology requiring pointer-chasing to reconstruct current state |
| Move to beads | Single system | No diff UI; no template enforcement; no native render. **reasoned:** `bd` has none of the read-ergonomics that make ADRs useful (grep, PR diffs, stable paths, templated structure); the medium-fit advantage is zero |

**What would invalidate this:** If contributors can't reliably identify that an ADR represents current reality vs. an older snapshot. Watch for ADRs contradicting deployed architecture without anyone noticing — when that surfaces, revisit (possibly add a "last-audited" footer).

### D3: Bead → ADR is the primary link; ADR → bead is optional historical context

**Firmness: FIRM** *(reversed direction 2026-04-25)*

ADRs are one-to-many with beads — one ADR governs the originating epic *and* every future bead that touches its scope. The structural link runs **bead → ADR**, not the other way:

- **Authoritative:** each bead's `## ADRs consulted (iteration N)` section in `--notes` lists the in-scope ADRs for that work (per [ADR-008](ADR-008-adr-predicates-and-plan.md) D2). This is the live source of truth for "which ADRs apply to this work right now."
- **Optional:** the ADR header may carry an `Originated from: <bead-id>` line as historical context (which epic birthed this decision). It is not load-bearing — readers do not navigate ADR → bead to find current usage.

**Rationale:** Pinning each ADR to a single bead via `**Epic:** <bead-id>` (the prior decision) made a one-to-many relationship structurally one-to-one — wrong shape. ADRs outlive epics; many future beads reference the same ADR. Bead-side references are the natural location: they live on the work that's currently in scope, and `bd show <bead>` surfaces them as part of the bead context any subagent already reads.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Bead → ADR primary, ADR → bead optional (chosen) | Matches one-to-many cardinality; bead-side references are live and contextual | Reading an ADR doesn't immediately surface its current callers |
| ADR pinned to one epic (`**Epic:** <bead-id>`) | Each ADR has a clear owner | One-to-one shape forced on one-to-many reality; ADR header rots as scope expands beyond the originating epic. **direct:** ADR-006 header previously carried `**Epic:** <bead-id>` in the prior decision; each bead after the originating epic had no way to register itself on the ADR |
| File path on ADR pointing at design doc | Familiar | Rots on rename/move; design doc itself retired by D1. **direct:** D1 of this ADR retires the design doc; any ADR-to-design-doc link is dead at the point D1 takes effect |
| No structural link either direction | Zero coupling | Subagents have no programmatic way to know which ADRs apply to a given bead. **reasoned:** without structural links, ADR applicability depends on subagent memory or manual instruction — neither survives context resets |

**What would invalidate this:** If beads consistently fail to surface in-scope ADRs in their notes (the live link is missing in practice), the structural reliance on bead-side references is wrong — reintroduce some form of reverse index. Watch for `bd list --status=done` entries whose notes lack an `## ADRs consulted` section on beads where ADRs clearly apply — when that pattern surfaces repeatedly, the bead-side discipline isn't holding.

### D4: Acceptance Contracts live on the epic's `--acceptance` field; "acceptance met" is a two-part conjunction

**Firmness: FIRM** *(Two-part acceptance-met semantics added 2026-05-22 with FIRM user confirmation; prior decision restated acceptance bullets only. References ADR-012 D3 for `## Harness target` shape and named-skip pattern.)*

Whole-change acceptance contracts (observable end-state conditions, Given/When/Then or input→output) live on the epic's `--acceptance`. Per-bead runnable targets still live on each child bead's `--acceptance` (ADR-005 D2 unchanged).

**"Acceptance met" is a two-part conjunction:**

(a) **Prose acceptance bullets** — every `--acceptance` bullet is observable-green (each stated condition is verifiably satisfied).

(b) **`## Harness target` Signal green** — the bead's `## Harness target` Signal is green per the Expected-green criterion defined in that section.

Either part absent or unmet → acceptance not met. The two parts are AND, not OR.

**Trivial-work named-skip clause.** When a bead's `## Harness target` section carries a one-line named skip with rationale (per ADR-012 D3: "trivial — no harness needed; <rationale>"), that counts as part (b) met. The named skip is the substrate residue that distinguishes "judged trivial" from "forgot to compose." Non-trivial work without an explicit `## Harness target` (either a green signal or a one-line named skip) fails part (b) — there is no implicit-skip path for non-trivial work.

**Rationale:** ADR-005 D3 put acceptance contracts in a design-doc section; with the design doc retired, the obvious home is the epic's `--acceptance`. Same semantics, better location. Preserves the upstream-testability benefit while removing the intermediate artifact. **This rewrites ADR-005 D3** (updated in place). The two-part conjunction adds the harness side: prose bullets meet the "what does done look like?" bar; the `## Harness target` Signal meets the "can we falsify done?" bar. A bead with prose-met but harness-absent (or harness-red on non-trivial work) is not shipped — the harness is not a soft recommendation layer on top of prose acceptance, it is an equal-weight condition.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Epic `--acceptance` with two-part conjunction (chosen) | Consolidates with rest of epic; `bd lint` can check presence; harness makes the load-bearing portion falsifiable | Format is soft text — not machine-enforced to be runnable |
| Epic `--design` prose section | One less field to update | Mixes narrative with contracts; weakens lint signal. **reasoned:** `bd lint` checks `--acceptance` presence specifically; inlining contracts into `--design` prose loses the dedicated lint target |
| Keep in design-doc template | Familiar | Reintroduces the very doc we're retiring. **direct:** D1 of this ADR retires the design doc; placing acceptance contracts there reintroduces the exact artifact D1 eliminates |
| Prose-only acceptance (prior shape) | Simpler contract surface | **reasoned:** prose bullets meet "what does done look like?" but not "can we falsify done?" — without a harness signal, acceptance-met is a judgment call that varies by agent/reviewer; the harness side makes the load-bearing portion binary-observable. **direct:** ADR-012 D3 acceptance-semantics note: "A bead's `--acceptance` is met when both the executable/observable harness target is green and prose acceptance criteria are met. Harness signal does not displace prose acceptance — it makes the load-bearing portion falsifiable." |

**What would invalidate this:** If epic `--acceptance` consistently ends up a dumping ground for per-child targets rather than whole-change contracts, revisit (maybe reintroduce a sub-field). Watch for `bd show <epic>` revealing acceptance fields that are verbatim copies of child targets rather than whole-change contracts — when that surfaces as a recurring pattern, reconsider. For the harness side: if the named-skip pattern becomes a lazy catch-all (non-trivial work routinely stamped "trivial"), the two-part conjunction has lost its force — tighten by requiring `adversarial-reviewer` to countermand trivial-skip rationales on non-trivial beads (per ADR-012 D3 lazy-trivial-drift invalidation signal).

### D5: Brainstorm creates the epic at convergence

**Firmness: FLEXIBLE** *(revised 2026-04-30 per `history/2026-04-29-pipeline-reordering-design.md` D2/D3 — brainstorm-v2 now creates the bead atomically at convergence; design-v2 no longer creates the bead)*

The `brainstorm-v2` skill holds state in the conversation during exploratory questioning and only creates the **epic bead** at convergence (user signals "converge", or design reaches structural completeness). The bead carries `--design` (the decisions narrative) and `--acceptance` (the observable contract); the artifact-shape decision (epic-only vs ADR-paired) is one of the decisions on `--design`. **The paired ADR (when warranted) is written separately by `design-v2` after `review-v2 --mode=design` PASS** — brainstorm-v2 does not write ADRs. No draft files on disk. Abandoned-before-convergence brainstorms produce no artifact; abandoned-after-convergence beads are closeable via `bd close --reason=abandoned`.

**Rationale:** Premature epic creation leaves zombie stubs in `bd list`. In-conversation state during exploration is cheap and already how brainstorm works. Scratch files in `/tmp/` were tried as a brainstorm→design handoff but failed the "session survives device reboot" test (macOS clears `/tmp` on reboot); the bead is the durable handoff. Splitting bead-create (brainstorm-v2) from ADR-write (design-v2) lets `review-v2 --mode=design` run on the bead before any ADR is committed — review-before-merge for decisions.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Create epic at convergence; ADR after review PASS (chosen, revised 2026-04-30) | Clean `bd list`; bead is durable handoff across sessions; review runs before ADR commitment | Splits previously-atomic crystallization into two steps (bead-create + ADR-write) |
| Create epic + ADR atomically at convergence (prior shape, pre-2026-04-30) | One atomic crystallization moment | Inverts review-before-merge — fold-ins mutate committed ADR. **direct:** `history/2026-04-29-pipeline-reordering-design.md` D1/D5: this was the prior shape; it forced review to treat a committed ADR as mutable, contradicting ADR-011's in-place-update discipline |
| Create epic early, iterate | Persistent across sessions | Zombies; cluttered epic list. **reasoned:** premature creation leaves partial artifacts in `bd list` indefinitely; `bd list` becomes unreliable as a "what needs work" signal |
| Scratch file `history/drafts/*.md` | Persistent + visible | Third artifact type; cleanup burden. **direct:** scratch files in `/tmp/` were tried and failed the session-survives-reboot test (macOS clears `/tmp` on reboot); persistent scratch files would be a third artifact class requiring their own lifecycle management |

**What would invalidate this:** If sessions die mid-brainstorm frequently enough that users lose meaningful exploration work, reconsider early epic creation with a `status=draft` convention. If post-convergence abandonment turns out to clutter `bd list` despite the convergence gate, revisit by adding a `status=abandoned` filter convention.

### D6: Beadify creates children via `--parent=<epic>`; no path refs in children

**Firmness: FIRM**

Each bead beadify creates is a child of the epic: `bd create --parent=<epic> --title=<slice> --acceptance=<runnable check>`. The child's `--design` field is optional; when present, it carries a **scoped sub-design** for non-trivial bead work (not a copy of the epic's design). No `Design: history/...` file-path references.

**Rationale:** Parent-child gives automatic architecture inheritance via `bd show` traversal. Removing file-path references eliminates the rot surface. ADR-005 D6 (organize+target, not prescribe) is preserved and reinforced.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| `--parent=<epic>` (chosen) | Native hierarchy; implicit context propagation | None meaningful |
| Siblings with `bd dep add` | More flexible graph | Loses implicit architecture inheritance. **reasoned:** sibling relationships via `bd dep add` require explicit traversal; parent-child traversal via `bd show --parent` gives implicit context propagation to subagents without extra wiring |
| Flat, tag-based grouping | Simpler queries | Loses hierarchy semantics. **reasoned:** tags can't encode parent-child ordering or dependency direction; the structural relationship is not representable in a tag model |

**What would invalidate this:** If `bd` deprecates parent-child or changes the inheritance semantics. Not expected.

### D7: `/review-v2 --mode=design` runs on the epic bead before any ADR is written; on PASS it auto-invokes `design-v2` for ADR materialization — **applies only when v2 is explicitly invoked**

**Firmness: FIRM** *(scope narrowed 2026-05-08 per ADR-012 D5 — auto-chain is now opt-in via explicit `/review-v2 → /design-v2` invocation only; v2 skills carry `disable-model-invocation: true` and do not auto-trigger. Revised 2026-04-30 per `history/2026-04-29-pipeline-reordering-design.md` D1/D5/D7.)*

**Scope under thesis-v2.1:** The auto-chain semantics described below apply when the user explicitly invokes `/review-v2 --mode=design` for genuinely-large design work. For typical design work, ADR-012 D3's adversarial-review primitive replaces this binding gate; default-on adversarial review is substrate-enforced via the bead schema (ADR-012 D3), not via skill auto-chaining.

`/review-v2 --mode=design` is a **pre-loop, pre-ADR** artifact review distinct from the primitive loop's REVIEW-PLAN and REVIEW-CODE gates (see [ADR-007](ADR-007-primitive-loop.md)). It runs once `brainstorm-v2` (or any other entry point) produces an epic bead with `--design` populated and an artifact-shape decision present — **but before the paired ADR (if any) is written**. Findings flow to the bead's `--design` (the narrative artifact under D1 direction A): orchestrator triages findings into Fold-in / Defer / Raise / Discard buckets per the post-2026-04-29 review-v2 protocol, applies fold-ins by rewriting `--design` in place, and emits one of three verdicts. On `VERDICT: PASS`, review-v2 auto-invokes `design-v2` in the same agent context; design-v2 runs overlap/evolution detection, writes the paired ADR (if `shape=ADR-paired`) or no-ops (if `shape=epic-only`), and the chain reaches a quiescent terminal state. `VERDICT: FAIL` and `VERDICT: NEEDS_DECISION` block auto-invocation; the user (or parallel-session orchestrator) addresses the surfaced findings before re-invoking review-v2.

**Rationale:** `/review-v2 --mode=design` reviews the *shape of the plan*, not the *shape of each iteration's work*. That's a different job from the loop's REVIEW gates, which check per-bead plans and code. Conflating the two was a source of earlier confusion. Reviewing **before** ADR commitment lets fold-ins mutate a still-mutable bead `--design` rather than a committed ADR file — review-before-merge semantics for architectural decisions. Auto-invoking design-v2 on PASS supports the multi-session-parallelism use case (5–10 concurrent pipelines): every per-session keystroke pause fragments user attention, so the chain runs to a quiescent terminal state without hand-holding. ADR-007 D6's "stateless re-prompt" rule does not apply because skill-to-skill chaining in the main agent is not orchestrator→subagent dispatch; design-v2 reads its inputs from `bd show <id>` regardless of whatever conversation context review-v2 leaves behind.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Pre-ADR review on bead `--design`; auto-invoke design-v2 on PASS (chosen, revised 2026-04-30) | Fold-ins mutate still-mutable artifact; bead is durable cross-session handoff; multi-session use case supported | Requires bead to exist before review (handled by D5 revised); requires explicit clarification that ADR-007 D6 doesn't constrain in-context skill chaining |
| Pre-loop review on `--design` + paired ADR (prior shape, pre-2026-04-30) | One atomic crystallization moment before review | Inverts review-before-merge; fold-ins mutate committed ADR. **direct:** `history/2026-04-29-pipeline-reordering-design.md` D1: this was the prior shape and it was replaced precisely because fold-ins needed to mutate a still-mutable artifact |
| Fold `/review-v2 --mode=design` into the loop's REVIEW-PLAN | Fewer skills | Wrong scope — REVIEW-PLAN checks one bead's plan, not the whole epic design. **reasoned:** REVIEW-PLAN's scope is one bead's implementation plan; design-mode review checks the whole epic's decision shape — different artifacts, different contracts, different reviewer expertise required |
| File review findings as a separate review bead | Audit trail in bead list | Noise; bead list bloat; harder triage. **reasoned:** review findings are ephemeral artifacts that shouldn't persist as first-class work items; they exist to be triaged and folded, not tracked as independent beads |
| Skip pre-loop review | Simplest | Weak designs enter the loop; waste cycles on bad plans. **direct:** metaswarm v0.4.0 pivot documents that skipping review gates under time pressure is the exact failure mode the loop was designed to prevent |
| Manual user-invocation of design-v2 after review PASS (no auto-chain) | Keeps user in the loop | Multi-session-parallelism friction tax; per-session keystroke pause fragments user attention across 5–10 concurrent sessions. **reasoned:** with 5–10 concurrent sessions, every per-session pause compounds; the chain should run to a quiescent terminal state without requiring per-session intervention |

**What would invalidate this:** If the loop's REVIEW-PLAN gate consistently catches what `/review-v2 --mode=design` should have caught earlier, the design-mode focus needs strengthening (or it's being skipped). If design-v2's contradiction-detection chains back to review-v2 frequently (>20% of pipelines), the auto-chain becomes a usability tax — revisit by gating auto-invocation on `shape=epic-only` and keeping `shape=ADR-paired` on manual invocation. If multi-session parallelism turns out to be a rare use case in practice (most users run one session at a time), the load-bearing argument for auto-invoke weakens and manual-invoke becomes preferable.

### D8: Entry-point resolver picks work by bead ID or title fuzzy match

**Firmness: FIRM**

The loop's entry point (currently `/send-it`; whatever replaces it per [ADR-007](ADR-007-primitive-loop.md)) resolves its target via: (a) exact bead ID match, (b) `bd list` filter by title slug fuzzy match, (c) `bd ready` pick if no argument given, (d) fail loud with "No bead found" if explicit input matches nothing. No file globs. State (if any) uses `bead_id` as the canonical key.

**Rationale:** Bead IDs are stable tokens; file paths rot. The loop accepts any bead — leaf or epic — as input (see [ADR-009](ADR-009-loop-composability.md)). This decision covers resolution only; what happens after the bead is identified is defined by the primitive loop ADRs.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| ID / title match + `bd ready` fallback (chosen) | Stable; native to bd; supports ambient work picking | Fuzzy match can be ambiguous — require confirmation on multi-match |
| File glob (status quo pre-modernization) | Current behavior before rollout | Rot surface; inconsistent with bead-as-substrate principle. **reasoned:** file globs are path-based and rot on any rename or move; bead IDs are stable immutable identifiers |
| Require bead ID always | Unambiguous | User has to remember IDs; worse UX. **reasoned:** requiring raw IDs breaks ambient work-picking (`bd ready`) and creates a cognitive load that defeats the ergonomic goal of the loop |

**What would invalidate this:** If fuzzy title match hits too many false positives. Watch for resolver misfires surfacing in loop runs — if the wrong bead is worked because the title match resolved ambiguously, tighten matching rules.

### D9: Follow-up work is in-flow via `bd create --parent` or `discovered-from`; no return-to-brainstorm

**Firmness: FIRM** *(upgraded from FLEXIBLE 2026-04-24; confirmed as core workflow shape)*

Bugs, improvements, or follow-ups are filed in-flow, never requiring a return to `/brainstorm`:
- **Human-filed** or pre-planned follow-ups: `bd create --parent=<epic>` if related to current work, or `bd create --type=epic` for separate concerns.
- **Agent-discovered** mid-loop: `bd create --parent=<epic>` + `bd dep add <new> discovered-from <current>` (see [ADR-008](ADR-008-adr-predicates-and-plan.md) for the full rule, including "do not fix in the same iteration"). `bd ready` surfaces the new bead naturally on a subsequent iteration.

**Rationale:** This is the specific workflow friction the user named as most painful. The primitive loop accepts any bead as input; once discovery can file work as beads, no routing through design docs is ever required. Upgraded to FIRM because the loop shape (ADR-007/008/009) depends on this — the loop's composability and mid-iteration discipline both assume beads are the universal work substrate.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| In-flow creation + `discovered-from` (chosen) | Zero friction for discoveries; preserves iteration focus; loop picks up naturally | Risk: epic grows unbounded with loosely-related children — mitigated by ~15-child split heuristic |
| Require `/beadify` re-run for new scope | Enforces scope discipline | Ceremony; the friction we're eliminating. **direct:** this is the specific workflow friction the user named as most painful in the original brainstorm; /beadify is a design-phase tool, not an in-loop tool |
| New epic for every follow-up | Clean separation | Fragments the narrative; hides related work; same ceremony. **reasoned:** a separate epic severs the contextual link between the follow-up and the work that spawned it, making cross-bead review harder and losing the `discovered-from` lineage |

**What would invalidate this:** If epics accumulate so many in-flow children that they become unreadable, or if discovered-from beads consistently get worked in the same iteration they were discovered (violating ADR-008's anti-tangent rule). Falsifiable check: any epic exceeding ~15 children is a split signal; any iteration's diff touching a discovered-from bead's scope is a scope-creep bug.

### D10: Every alternative in an Alternatives table carries an explicit warrant tag

**Firmness: FIRM** *(added 2026-04-27, CE fold-in #4)*

**Source:** `ce-ideate/SKILL.md` Phase 2 (generation rules); Wave 7 research capture (workflow-loop brainstorm research, 2026-04-24, in the methodology history archive) §7.5 item 8.

Every alternative emitted by `brainstorm-v2` in an ADR or design doc Alternatives table must carry an explicit warrant tag on its rejection reason. Three valid tags:

- `direct:` — cite a specific file, line, issue, or quote from the codebase or prior conversation (e.g., `direct: ADR-007 D3; a prior work-product bead showed this approach failed`).
- `external:` — cite prior art: paper, blog, library, or framework convention (e.g., `external: Agentless §3.2 shows embeddings hurt LLM hierarchical selection`).
- `reasoned:` — first-principles argument; no external grounding required, but the reasoning itself is the warrant (e.g., `reasoned: sync drift — co-located checks evolve with the decision; sidecars don't`).

No floating speculation. Every alternative must have a grounding tag. An alternatives entry with only a vague rejection reason (e.g., "Cons: complicated") is invalid and must be strengthened to carry one of the three tags.

**Rationale:** Warrant tags serve PLAN's Rule P (ADR-008 D2). When PLAN reads an Alternatives table and decides a rejected option is now valid again, the warrant is the evidence it must rebut. Vague rejection reasons ("complicated") are trivially rebutted; warrant-grounded rejections require substantive counter-argument. The three-tag system mirrors CE's `ce-ideate` observation that every idea must have external grounding, codebase grounding, or first-principles reasoning — no floating speculation survives adversarial review. This pairs with ADR-005 D5 (Alternatives completeness) — D5 requires alternatives exist; D10 requires they have warranted rejection reasons.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Three warrant tags on every rejection (chosen) | Makes rejections rebuttable-at-the-right-level; PLAN can decide if counter-evidence overrides | Adds authoring discipline at convergence | `direct:` ADR-005 D5 already requires alternatives exist; D10 upgrades quality of what's there |
| Prose rejection reasons only (status quo) | No format change | Vague rejections ("complicated") don't carry weight for PLAN's Rule P; trivially overridden | `reasoned:` first-principles: PLAN uses rejections as constraints; weak constraints are not constraints |
| Mandatory external citation only | Highest rigor | Not every rejection has an external source; forces invented citations for first-principles choices | `reasoned:` over-constraining the tag set causes fake citations, same failure mode as mandatory mechanical checks (ADR-008 D1) |
| Add warrant requirement only to FIRM decisions | Focused | Leaves FLEXIBLE/EXPLORATORY alternatives unwarranted; PLAN reads all alternatives regardless of firmness | `reasoned:` Rule P applies to all alternatives regardless of firmness label; partial enforcement creates gaps |

**Falsifiable check:** Pick any ADR in `docs/decisions/` and check that every Alternatives table row's "Cons/Rejection" column begins with `direct:`, `external:`, or `reasoned:`. If any row has an unwrapped rejection reason, the warrant discipline isn't holding.

**What would invalidate this:** If `reasoned:` becomes a catch-all escape hatch (every rejection tagged `reasoned:` with minimal reasoning), strengthen the authoring guidance to require that `reasoned:` carries at least two sentences. If PLAN consistently ignores warrant-grounded rejections anyway, the value-add of the tags is lower than expected — revisit whether the warrant should go into ADR bodies rather than Alternatives table cells.

### D11: Artifact-shape (epic-only vs ADR-paired) is a first-class decision on the bead's `--design` — **applies when v2 is explicitly invoked**

**Firmness: FIRM** *(scope narrowed 2026-05-08 per ADR-012 D5 — applies in the v2 pipeline only; thesis-v2.1's primitive workflow does not require an upfront artifact-shape decision since ADR write is its own primitive invoked by judgment. Added 2026-04-30 per `history/2026-04-29-pipeline-reordering-design.md` D4.)*

The epic-only-vs-ADR-paired call lives as one of the decisions on `--design`, with the same predicates (firmness/rationale/alternatives/what-would-invalidate) as every other decision. It is set during brainstorm-v2 via the re-derivability test (would a fresh agent need these decisions in the ADR set to rebuild correctly?), reviewed by review-v2 mode=design, and consumed by design-v2 to choose ADR write vs no-op.

**Rationale:** Pre-2026-04-30 design-v2 made the call autonomously inside its own triage logic, hiding it from review. Promoting it to a first-class decision makes it visible to review-v2 mode=design, which can catch contradictions like "D2 binds future architecture but the artifact-shape decision says epic-only." That's exactly the adversarial check review should catch.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| First-class decision on `--design` (chosen) | Reviewable; uniform shape with other decisions; visible warrant | Adds one decision-authoring slot at convergence |
| Autonomous triage inside design-v2 (pre-2026-04-30) | Less work for brainstorm | `reasoned:` hides a reviewable call from review-v2; review-v2 is the layer that catches contradictions between decisions, including meta-decisions |
| Always create ADR (no triage) | Removes the call entirely | `direct:` design-v2 SKILL.md's prior triage logic (`skills/design-v2/SKILL.md:69-79`) distinguished epic-only ("operational, sequencing, transient — once shipped, no future-work consultation") from ADR-paired; removing triage generates ADRs for purely operational decisions |

**What would invalidate this:** if review-v2 reviewers consistently miss artifact-shape findings (false-PASS on contradiction cases), the call may need stronger upfront enforcement than reviewer judgment.

### D12: Design-v2 invokes `/harness compose` for FIRM-decision invalidation checks, with countermand-style triage — **applies when v2 is explicitly invoked**

**Firmness: FLEXIBLE** *(scope narrowed 2026-05-08 per ADR-012 D5 — applies in the v2 pipeline only. Under thesis-v2.1, `/harness compose` is invoked by judgment when authoring an ADR with a FIRM mechanical-checkable decision; no auto-invocation. Added 2026-04-30 per `history/2026-04-29-pipeline-reordering-design.md` D8.)*

For each **FIRM** decision being materialized into an ADR, design-v2 invokes `/harness compose` to propose a mechanical falsifier (BUILD/CONNECT/CONFIGURE/REDUCE per `skills/harness/SKILL.md`). FLEXIBLE/EXPLORATORY decisions skip the harness invocation (too tentative to mechanically lock in). Countermand-style triage applies to each proposal:

- **Auto-accept** if the proposal is a single, well-formed check on a clear mechanical surface and harness signals high confidence (or, absent a confidence signal, the proposal shape is unambiguous: one check, no variants offered, no question marks in the falsifier text). Append the block silently; record on `--notes ## Artifact decisions` as `harness compose: auto-accepted (<one-line summary>)`.
- **Raise to user** if harness reports low confidence, offers multiple variants, or the proposal is judgment-laden. Present accept/edit/reject; record the user's call on `--notes`.
- **Skip** if harness can't produce a check at all (no mechanical surface). Do NOT fabricate one; do NOT force a user choice. The decision goes uncovered, and that's fine.

**Rationale:** Pre-2026-04-30 design-v2 left invalidation blocks user-supplied (and they were almost always empty), so ADRs decayed into prose nobody reads. /harness compose is the right framework for proposing mechanical checks. Countermand-style triage (parallel to review-v2's finding triage) preserves D7's multi-session-parallelism property — typical case (one FIRM decision, mechanical) → zero pauses; ambiguous case → one *real* decision moment, not rubberstamp. Auto-accepted checks remain auditable on `--notes ## Artifact decisions` so wrong auto-accepts are recoverable. Pairs with [ADR-008](ADR-008-adr-predicates-and-plan.md) D8 (signal-shaped invalidation): harness proposes mechanical checks where they fit; D8 says don't fabricate them where they don't.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| /harness compose + countermand triage (chosen) | Produces ADR enforcement at scale; preserves parallelism property; auditable | Depends on harness output shape supporting auto-accept inference (heuristic until a structured confidence flag exists) |
| Leave invalidation blocks user-supplied (status quo pre-2026-04-30) | No new skill chaining | `direct:` design-v2 SKILL.md marked the block "optional"; in practice it was almost always empty — ADRs without checks aren't enforced |
| Raise every harness proposal to user (no auto-accept) | Maximum user oversight | `direct:` D7's load-bearing argument is multi-session parallelism (5–10 concurrent sessions); a guaranteed per-FIRM-decision pause re-introduces the rubberstamp friction D7 closed for review→design auto-invoke |
| Have brainstorm-v2 propose checks at convergence | Earlier in pipeline | `direct:` design-v2 owns ADR materialization; brainstorm-v2's "no artifacts during exploration" rule is the load-bearing reason design-v2 was extracted in the first place (`history/2026-04-27-sp-design-v2.md`) |
| Build a separate /invalidate-v2 skill | Single responsibility | `reasoned:` /harness compose already does this work; new skill duplicates capability |

**What would invalidate this:** if /harness compose's BUILD/CONNECT/CONFIGURE/REDUCE framework turns out to be wrong-grain for ADR-level invalidation (too coarse, too codebase-specific), build a thin wrapper or revisit the composition target. Or, if auto-accepted checks surface as wrong in non-obvious ways during dogfooding — not the occasional one-off but a recurring pattern the user notices when reviewing `--notes ## Artifact decisions` (signal-shaped per ADR-008 D8: no fixed rate threshold) — tighten the auto-accept criteria or revert to per-decision raise.

### D13: Bug-fix and follow-up beads have three supported paths through the pipeline — **applies when v2 is explicitly invoked**

**Firmness: FLEXIBLE** *(scope narrowed 2026-05-08 per ADR-012 D5 — applies in the v2 pipeline only. Under thesis-v2.1, bug-fix and follow-up beads are routed by judgment over the six primitives; no fixed three-path taxonomy. Added 2026-04-30 per `history/2026-04-29-pipeline-reordering-design.md` D9.)*

Beads created mid-implementation (bug found in unrelated code, follow-up tracking) typically arrive with a problem statement but no decisions. Three paths cover the realistic cases:

1. **Trivial bug** (e.g., off-by-one in `foo.py:42`) → bead's `--design` has no real decisions; user routes the bead to beadify-v2 → implement-v2 directly, *skipping review-v2 mode=design entirely*. If review-v2 mode=design is invoked anyway, its pre-flight emits `VERDICT: NEEDS_DECISION` ("no decisions on `--design` — populate via brainstorm-v2, or skip to beadify-v2 if this is a trivial fix") without dispatching a reviewer. No design-v2 invocation; no ADR.
2. **Architectural bug** (root cause unclear, fix-shape contested) → user runs brainstorm-v2 *with the bead as context*; brainstorm augments the existing bead's `--design` via a small "augment existing bead" extension. Then review-v2 → design-v2 → beadify-v2 as normal.
3. **Future: /debug-v2** as a focused diagnosis-and-decide skill specialized for bug context. Out of scope here; revisit after Phase A dogfooding shows how often path 2 is heavy enough to justify a specialized skill.

This is distinct from D9 (in-flow follow-up *filing* via `bd create --parent` / `discovered-from`): D9 governs *how follow-ups get filed*; D13 governs *how those bug-shaped beads then traverse the brainstorm→review→design→beadify pipeline*.

**Rationale:** The pipeline assumes decisions exist before review runs; bug-shaped beads often don't. Forcing all bug beads through brainstorm-v2 is friction without benefit for trivial fixes; promoting review-v2 to a generator (proposing solutions when no decisions exist) inverts review's adversarial contract. Three paths cover the realistic distribution.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Three paths (chosen) | Trivial fixes skip pipeline weight; architectural bugs get full treatment; specialized /debug-v2 stays optional | Path 2 depends on a brainstorm-v2 "augment existing bead" mode not yet formally specced |
| Have review-v2 propose solutions when `--design` is empty | Single skill handles bug-fix flow | `direct:` review-v2's contract is adversarial (tests claims, doesn't generate them); ADR-007 D8 names "rationalizing a finding as 'probably fine'" as a failure mode review must avoid — promoting review to generator inverts that discipline |
| Always require brainstorm-v2 (path 2 only) | Uniform pipeline | `reasoned:` trivial off-by-one fixes don't need decision exploration; uniformity is friction without benefit |
| Build /debug-v2 now (path 3) | Specialized skill for the case | `reasoned:` premature; paths 1+2 cover real cases; specialize after dogfooding reveals the gap |

**What would invalidate this:** if path 1 generates frequent NEEDS_DECISION pre-flights from review-v2 mode=design (the user doesn't actually want review to run on this kind of bead), routing needs to happen earlier — e.g., a bead-type field signals "bug, skip design phase" and the pipeline auto-routes to beadify-v2 without `/review-v2` invocation.

---

## Related

- [Workflow Modernization Design](../../history/2026-04-23-workflow-modernization-design.md) — full design narrative
- [ADR-005](ADR-005-beadify-redesign.md) — D3 and D5 rewritten in place as part of this ADR's rollout
- [ADR-004](ADR-004-soldier-proof-skill.md) — soldier-proof discipline for skill hardening (precedent for this rollout's implementation)
