# ADR-005: Beadify Redesign — Organize + Target, not Prescribe

**Status:** Accepted (D8 + D9 superseded 2026-04-28) (revised 2026-05-13)
**Date:** 2026-04-23
**Design:** [Beadify Redesign Design](../../history/2026-04-23-beadify-redesign-design.md)
**Related:** [ADR-004](ADR-004-soldier-proof-skill.md) (soldier-proof pattern used to validate `/harness compose` before composition)

## Revisions

- **2026-04-28** — D8 (N=1 default; idempotent passes target a complete pass-1 artifact) and D9 (single plan-writer dispatch shape with orchestrator pre-decided structure) superseded by the forthcoming text-until-convergence redesign (ADR-010, in flight; brainstorm summary at `/tmp/design-v2/beadify-v2-text-until-convergence-20260428-1156.md`). Original D8/D9 framing preserved below as WHY-history per project ADR convention. Operational rules from D9 that survive unchanged (parent-first hierarchy, Haiku ADR pre-filter, integration-test rule for multi-bead changes, file-conflict detection) carry forward into the successor ADR's dispatch shape; only the single-plan-writer-role claim and the N-as-target framing are superseded.

## Context

The `/beadify` skill currently leans on `superpowers:writing-plans` to produce beads with exact file paths, complete code examples, and step-by-step instructions. This methodology targets engineers with zero codebase context. Inside the `/send-it` pipeline, that premise fails: the implementer has the design doc, the paired ADR, and full repo access.

Empirical analysis of three recent work-product design→bead pairs showed the prescribed detail was either ceremonial or actively harmful — wrong keyword values, wrong SQL that blew up on foreign-key constraints, line-number checklists that still missed critical docstrings. In every case the `/review` pass caught what mattered; the bead detail did not.

This ADR records the decisions that redirect `/beadify` away from code prescription and toward two leaner responsibilities: organizing work into units, and attaching a falsifiable iteration target per bead. Companion design doc at `history/2026-04-23-beadify-redesign-design.md`.

## Decisions

### D1: Drop `superpowers:writing-plans` dependency entirely

**Firmness: FIRM**

`/beadify`'s subagent no longer invokes or follows `superpowers:writing-plans`. The zero-context-engineer methodology is not a fit inside `/send-it`, where design + ADR + repo are all available to the implementer.

**Rationale:** The writing-plans methodology optimizes for a specific premise — the implementer will not read the repo. That premise is false inside `/send-it`. Following it anyway produces prescriptions that (a) add tokens, (b) go stale between beadify and implement, and (c) introduce wrong concrete values under the false confidence of precision.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Drop entirely (chosen) | Removes the actively-harmful source of over-prescription; simpler prompt | Loses a fallback for doc/config-only beads (mitigated: `/harness` handles those) |
| Keep as optional fallback | Safety net for edge cases | Subagents will reach for it; gravitational pull toward over-prescription persists. **reasoned:** subagent tool selection is attracted to available options; removing the option removes the pull |
| Rewrite writing-plans to be context-aware | Preserves one skill | Out of scope; skill is valid for its actual use case outside `/send-it`. **reasoned:** the scope for this ADR is `/send-it` internals; fixing the skill's premise for a different use case is a separate concern |

**What would invalidate this:** If `/harness compose` fails to produce useful targets for a meaningful fraction of beads, we'd need a fallback methodology. Watch for `bd show` revealing `--acceptance` fields that are unrunnable or vacuous as a recurring pattern across recent beadify runs — when that surfaces, the composition isn't earning its keep and a fallback is needed.

### D2: Bead pattern uses `bd` native quality gates

**Firmness: FIRM**

Beads are created with `bd create --validate --design=<design-doc-section-ref> --acceptance=<runnable check>`. No new `Target:` field or invented structure. The description captures *what* and *why*; `--design` points to design-doc content; `--acceptance` carries the runnable iteration target.

**Rationale:** `bd` already has first-class support for these fields, enforced by `bd lint` and `bd preflight` (both already in the `/send-it` orchestration surface). Inventing a new field duplicates infrastructure and misses the enforcement. Using native fields also means `bd doctor --check=conventions` catches drift automatically.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| bd native `--acceptance`/`--design` (chosen) | Native enforcement via lint/preflight; zero new infra; `bd doctor` catches drift | Field semantics (acceptance as *runnable* check) are soft — not machine-enforced |
| New `Target:` field in bead pattern | Dedicated semantics | Duplicates `--acceptance`; invents infrastructure; not enforced. **reasoned:** adding infra that duplicates an existing first-class field adds maintenance surface with no new capability |
| Prose "Done when:" block only (status quo) | No change needed | Not verifiable; not enforced by lint; degrades to ceremony. **reasoned:** prose-only targets are indistinguishable from aspirational text; they survive review without ever being checked |

**What would invalidate this:** If `bd` removes or deprecates `--acceptance`/`--design`, revisit. Not expected.

### D3: Whole-change acceptance contracts live on the epic's `--acceptance` field

**Firmness: FIRM**

Whole-change acceptance contracts — falsifiable end-state conditions expressed as observable checks (Given/When/Then or input → expected output) — live on the epic bead's `--acceptance` field. Per-bead runnable targets live on each child bead's `--acceptance` (D2). No design-doc template section.

**Rationale:** Per-bead `--acceptance` targets are *derivations* of whole-change contracts. The contracts need a stable upstream home so beadify has something to derive from. The epic's `--acceptance` is that home: co-located with the design narrative (on the same bead), reviewable by `/review-design`, and enforced by `bd lint`. ([ADR-006](ADR-006-workflow-modernization.md) D4 retired the design-doc-template variant of this decision; content moved to the epic.)

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Epic `--acceptance` (chosen) | Co-located with design narrative; `bd lint`-checked; native field | Format soft — not mechanically guaranteed runnable |
| Design-doc template section | Co-designed with architecture | Requires the design doc to exist (retired by ADR-006 D1). **direct:** ADR-006 D1 retired design docs as the design narrative home; this option reintroduces the artifact being retired |
| Only in the paired ADR | Keeps epic lean | ADR is about decisions, not end-state contracts; semantic mismatch. **reasoned:** ADRs record *why* decisions were made, not observable end-states; mixing the two conflates decision rationale with acceptance verification |

**What would invalidate this:** If epic `--acceptance` consistently gets filled with per-child targets rather than whole-change contracts, revisit. Watch for `bd show <epic>` revealing acceptance fields that read as verbatim copies of child targets rather than whole-change contracts — when that pattern surfaces, the field isn't earning its keep.

### D4: ADR template sharpens "What would invalidate this" + optional inline mechanical check

**Firmness: FLEXIBLE**

The `**What would invalidate this:**` field in the ADR template gains guidance: each decision must surface at least one observable, falsifiable signal that would prove the decision wrong. Additionally, decisions may carry an optional adjacent `**Invalidation check (mechanical, optional):**` block containing a single shell invocation that exits non-zero when the ADR is violated. Prose rationale stays; the mechanical block is strictly optional.

**Rationale:** The current field accepts vague conditions ("if requirements change"). Falsifiable disproofs turn ADRs into load-bearing contracts — they can be monitored, sampled, and actually invalidate when data contradicts them. Per Alexandre Castro's fitness-function retrospective (captured in `history/2026-04-24-workflow-loop-brainstorm-research.md`), the check must live **inside** the ADR, not in a sidecar file — sidecars die from sync drift. The loop (see [ADR-007](ADR-007-primitive-loop.md) + [ADR-008](ADR-008-adr-predicates-and-plan.md)) runs any such checks during PLAN and re-runs them after IMPLEMENT.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Inline optional mechanical block (chosen) | Co-evolves with the decision; no sync drift; loop-runnable; optional for non-checkable decisions | Some decisions genuinely resist falsification; may feel forced if misused as mandatory |
| Separate fitness-function files (`.fitness/`) | Cleaner separation of prose and code | Sync drift — Alexandre Castro abandoned this pattern after real use. **external:** Alexandre Castro fitness-function retrospective (`history/2026-04-24-workflow-loop-brainstorm-research.md`): separate sidecar files die from sync drift |
| Mandatory mechanical check | Forces discipline | Produces fake checks for decisions that genuinely resist mechanical verification. **reasoned:** mandating checks for uncheckable decisions produces noise that undermines the signal value of genuine checks |
| Leave as-is (prose only) | No change needed | ADRs drift toward aspirational prose; loop has no cheap stop-check. **reasoned:** without mechanical gates, the loop must trust prose self-reports, which is the exact failure mode ADR-007 D2 closes |

**What would invalidate this:** If, after 6 months, <20% of ADR decisions have runnable disproofs *and* the loop's mechanical stop-check meaningfully catches drift, the guidance isn't landing — either remove or redesign. Counter-signal: if every ADR ends up with a mechanical block including obviously-fake ones, the optionality isn't being respected — strengthen authoring guidance.

### D5: `/review-design` gains testability + Alternatives-completeness focus

**Firmness: FLEXIBLE**

The review-design subagent prompt gains two focus bullets:
1. **Testability** — Does each goal have an observable success criterion on the epic's `--acceptance` field? Flag goals with no runnable check.
2. **Alternatives completeness (WHY-preservation)** — Does each ADR decision have an "Alternatives Considered" entry with at least one rejected option and a stated rejection reason? Flag any decision whose alternatives table is empty or whose rejections lack reasons.

**Rationale:** `bd lint` checks `--acceptance` presence but not substance, and does nothing about WHY. Making both first-class review focuses means weak contracts and WHY-gaps are flagged before the primitive loop (see [ADR-007](ADR-007-primitive-loop.md)) runs on them. The loop's PLAN phase (see [ADR-008](ADR-008-adr-predicates-and-plan.md)) reads Alternatives tables to prevent agents re-choosing rejected approaches — which means empty tables are silent holes in WHY-preservation. Matches the existing pattern (Assumptions, Gaps, Alternatives, Dependencies, Risks + Testability + Alternatives-completeness). ([ADR-006](ADR-006-workflow-modernization.md) D1 contested the design-narrative location; Testability still applies to whichever artifact holds the narrative.)

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Add both to review-design focus (chosen) | Enforces acceptance substance AND WHY-completeness; single place to update | Requires review-design subagent prompt change |
| Only testability (original D5) | Simpler | Leaves WHY-gaps silent; loop's Rule P (no-rejected-alternative) has no upstream enforcement. **reasoned:** Rule P (ADR-008 D2) depends on alternatives being present; a check that only enforces testability leaves empty alternatives tables to slip through |
| Lint-style check in beadify | Catches the same thing | Later in pipeline; waste of review-design cycles if ADRs are weak. **reasoned:** catching structural gaps after beadify has already decomposed the work wastes the decomposition cycles |
| Don't check | Simpler | `--acceptance` becomes optional-by-practice; Alternatives tables drift to empty. **reasoned:** without enforcement, these fields fill with ceremony rather than substance, defeating their purpose |

**What would invalidate this:** If review-design consistently flags testability/alternatives but they're always already addressed (noise), demote. If the loop's PLAN phase repeatedly catches rejected-alternative reasoning that review-design should have prevented (empty Alternatives tables slipping through), strengthen the check or make it blocking.

### D6: Beadify methodology is organize + target, not prescribe

**Firmness: FIRM**

Beadify's subagent prompt reframes the job as: (1) split/merge work into beads by file ownership and logical coupling, (2) attach a runnable acceptance target per bead. It explicitly does NOT produce file-path lists, code examples, or step-by-step instructions. The design doc reference (`--design`) carries architectural intent; the acceptance check (`--acceptance`) carries falsifiable end-state.

**Rationale:** The failure modes found in empirical work-product analysis all trace to one root: prescriptions that assume knowledge of details that change between beadify and implement. Removing the prescriptions removes the failure mode. The implementer agent has the intelligence and context to reconstruct the "how"; it only needs the "what slice" and "how will we know."

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Organize + target (chosen) | Removes failure mode; leaner tokens; trusts implementer intelligence | Some implementers may flounder without scaffolding (mitigated: target provides the signal) |
| Keep prescriptions but loosen them | Familiar | Same failure mode, just blurrier. **direct:** empirical dogfood across three work-product design→bead pairs — prescriptions at any specificity level rot between beadify and implement; loosening doesn't change the structural rot surface |
| Prescribe only file paths, drop code examples | Partial fix | Line numbers still rot; false coverage persists. **reasoned:** file paths survive better than code examples but line numbers change with every edit; structural rot is inherent to any prescription that assumes stable file state |

**What would invalidate this:** If implement agents consistently miss the intent without prescriptions, reintroduce targeted scaffolding. Watch for `/review` surfacing structural misses (wrong approach entirely, not just execution bugs) as a recurring pattern — when that surfaces, the design-doc reference isn't carrying enough and prescriptions need reintroducing.

### D7: Bead-authoring primitives invoke `/harness compose` for target design *(revised 2026-05-22)*

**Firmness: FLEXIBLE**

The primitive that authors a bead invokes `/harness compose` to produce a `## Harness target` section:

- **`/brainstorm` at convergence** — authors `## Harness target` in the bead `--design`, capturing the goal-faithful signal at the design's intended end-state.
- **`/decompose` at child authoring** — each child gets its own `## Harness target` section. Children's harness targets must **conjunctively cover the parent's harness target's coverage**: the union of children's signals must span the parent's signal — no observable behavior covered by the parent's harness target may go uncovered by every child's. This extends the existing acceptance-conjunction discipline to the harness side; the canonical source is ADR-012 D3 line 106-107.

Neither primitive inlines harness principles, fast/slow hierarchies, or the build/connect/configure/reduce taxonomy — those live in `/harness`.

The original scope of this decision was beadify-specific. Generalized 2026-05-22 (the all-primitives-generalization bead) to cover all bead-authoring primitives as `/decompose` emerged as the substrate-thick child-authoring path. Beadify-v2 inherits the discipline as a v2 reference composition.

**Rationale:** `/harness compose` was soldier-proofed on 2026-04-23 across 4 iterations covering all HOW modes and both inventory branches. It is the single source of truth for harness thinking. Inlining principles would duplicate logic and fork maintenance. Invoking the skill means harness improvements automatically reach all authoring primitives. The conjunction-coverage clause on children is load-bearing: without it, `/decompose` could produce children that each individually pass their own harness while leaving the parent's harness target uncovered — the canonical conjunction-drift failure mode.

Earlier draft (session 2026-04-23) considered inlining principles pending soldier-proofing; the soldier-proof pass completed same day, unblocking this composition.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Invoke /harness compose (chosen) | Single source of truth; harness improvements flow automatically | Cross-skill invocation overhead; coupling to /harness shape |
| Inline harness principles in beadify/decompose prompts | Self-contained primitives | Duplicate logic; drift risk; longer prompt. **reasoned:** inlining creates two maintenance surfaces per primitive; any improvement to /harness must also be manually applied to each inlined copy |
| Read `.claude/harness.md` inventory directly, no /harness call | Cheaper | Reimplements /harness's selection/composition logic. **reasoned:** the inventory is an input to harness composition, not a substitute for it; reading the inventory skips the composition and selection logic that /harness encapsulates |
| Restrict conjunction-coverage to acceptance only, not harness | Less constraint | Creates conjunction-drift at harness level: children individually green, parent's harness uncovered. **reasoned:** harness targets must be as conjunction-complete as acceptance predicates or the alignment proof at close-time is partial |

**What would invalidate this:** If `/harness compose` regresses (post-soldier-proof drift) or its interface becomes too narrow for bead-scope contexts. Watch for `/harness compose` output requiring manual fix-up as a recurring pattern across recent decompose/brainstorm runs — when that surfaces, the composition is leaking or its interface has narrowed. For the conjunction-coverage clause: if post-close harness audits reveal parent signals uncovered by child signals despite the clause being applied, the "name uncovered behaviors" probe in `/decompose` is performing as a checklist item rather than a real coverage analysis — tighten `/decompose` SKILL.md's probe language.

### D8: N-pass is idempotent, not differentiated; default N=1

**Firmness: SUPERSEDED 2026-04-28** *(default clarified to N=1 on 2026-04-25; superseded by forthcoming ADR-010, which makes `--N` a minimum-iterations floor with convergence gate and hard cap=5, rather than a default-target. Idempotent-passes principle preserved; the change is to N's role: floor, not target.)*

Each beadify pass runs the same holistic prompt: review the whole tree, question structure, question targets, sharpen where helpful. Pass 1 alone should produce a complete, usable artifact. Passes 2+ are fresh-eyes re-challenge — not sequential specialization (structure-then-targets-then-polish). **Default `--N=1`**; users crank up to 2 or 3 for extra paranoia on complex changes.

**Rationale:** Differentiated passes make N=1 mean "incomplete" and force a minimum of N=2. Idempotent passes preserve single-pass viability and match how `/review-design` already works (same prompt, fresh subagent, more scrutiny). N=1 default flows from the same logic — if pass 1 is genuinely complete, the default should reflect that; cranking up is opt-in paranoia. This also matches the broader "stop dialing iterations" philosophy of the loop design (ADR-007: iteration count is emergent, not pre-dialed).

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Idempotent, default N=1 (chosen) | Single-pass viable matches default; cheap baseline; consistent with stop-dialing-iterations philosophy | If pass 1 is unreliable on complex changes, user discovers via review FAILs and dials up |
| Idempotent, default N=3 (status quo for `/send-it --feature`) | Belt-and-suspenders | If pass 1 is complete, passes 2-3 are pure cost; encourages "more passes = more rigor" theater. **reasoned:** iteration count should be emergent (driven by actual need), not pre-dialed; pre-dialing at 3 treats all beads as complex by default |
| Differentiated (pass 1 structure, pass 2 targets, pass 3 polish) | Each pass does something new | N=1 becomes incomplete; forces min 2 passes; more prompts to maintain. **reasoned:** differentiated passes make single-pass viability structurally impossible; ADR-007's stop-dialing-iterations philosophy requires each pass to be independently complete |
| N=1 hardcoded, no `--N` flag | Simplest | Loses refinement value for complex changes. **reasoned:** complex changes may genuinely benefit from additional passes; removing the flag removes the user's ability to opt into extra scrutiny |

**What would invalidate this:** If post-rollout `/review-v2` finds beadify-quality issues (missed structure, vacuous acceptance) on >1 of first 5 N=1 runs, default should bump to 2. If users routinely override to 3 for non-complex changes, the default doesn't match practice — investigate why pass 1 isn't enough.

### D9: Beadify orchestrator pre-decides structure; subagents fill content; integration tests + parent-first

**Firmness: SUPERSEDED 2026-04-28** *(added 2026-04-25; superseded by forthcoming ADR-010. The single-plan-writer dispatch shape is replaced by a three-role shape — decomposition scouts (explore in fresh context), per-child acceptance refiners (parallel), whole-tree critic (pre-write gate). Orchestrator-pre-decides-alone is replaced by orchestrator-decided scout count (0/1/2/3) using reasoning signals + scout synthesis. The text-until-convergence model holds the canonical graph in orchestrator memory until critic-PASS, then materializes once. Operational rules below — parent-first hierarchy, Haiku ADR pre-filter, integration-test rule, file-conflict detection — carry forward unchanged into ADR-010's dispatch shape.)*

The beadify skill (orchestrator + subagents) follows this dispatch shape:

**Step 0a — Orchestrator pre-decides bead tree.** Before dispatching plan-writer subagents, the main agent reads the epic's `--design` and produces an explicit bead tree: which beads exist, parent/child relationships, dependency edges, serial vs parallel, rationale per choice. This output is the contract — subagents fill in *content* (acceptance, scope notes), they do NOT redecide structure. They may flag structural concerns back to the orchestrator, but the orchestrator owns the call.

**Step 0b — ADR pre-filter via Haiku subagent.** A cheap Haiku subagent scans `docs/decisions/ADR-*.md` and returns the ~5 in-scope ADR paths for this epic. Subsequent subagents receive only the filtered set, not all 60+ ADRs. (Same pattern reusable in `/review-v2` and `/implement-v2`.)

**Hierarchy rule:** When creating >1 bead, the parent (epic) is created FIRST, then children with `bd create --parent=<epic>`. Order matters because `bd ready --parent=<epic>` and child traversal depend on the link existing at child-creation time.

**Integration tests:** Multi-bead changes get a final integration-test bead depending on all siblings (`bd dep add <integration-bead> <sibling>` for each). Single-bead changes include integration within. Doc-only / config-only beads use grep / file-existence acceptance via `/harness compose` — no synthetic tests.

**File-conflict detection:** If two beads would modify the same file, prefer merging them. Fallback: serialize via `bd dep add <later> <earlier>`. Parallel children that touch the same file is a structural bug.

**Rationale:** Step 0a is load-bearing — without it, plan-writer subagents drift the structure. Each subagent sees one slice and decides locally; the orchestrator is the only one with whole-tree visibility. Step 0b is a token-economy move; the same Haiku-pre-filter pattern is a workhorse in any skill that needs ADR scope (review modes, plan, implement). Hierarchy + integration + file-conflict rules are operational discipline carried over from the current `/beadify` (each was load-bearing in practice). Codifying them in the ADR keeps them from being lost in the v2 rewrite.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Pre-decided structure + Haiku ADR pre-filter + parent-first + integration + file-conflict (chosen) | Preserves orchestrator authority over structure; bounds context cost; codifies operational rules that were proven in current skill | More steps in the skill prompt; orchestrator carries more logic |
| Subagents decide structure | Parallelizable from the start | Drift across slices; no whole-tree authority. **reasoned:** each subagent sees only one slice; the orchestrator is the only one with whole-tree visibility; local-optimal decisions compound into global-suboptimal trees |
| Pass full ADR corpus to every subagent | No filtering complexity | Token cost scales with ADR count; signal degrades. **reasoned:** ADR-008 D3's top-3 cap is grounded in SWE-bench data showing over-scoping measurably hurts focus; passing all ADRs contradicts that finding |
| Drop integration-test rule | Simpler | Multi-bead changes ship untested cross-component (this was the pain that put the rule in the original skill). **direct:** the integration-test rule was introduced specifically because multi-bead changes were shipping with untested cross-component interactions in practice |
| Allow same-file parallel children | Fewer dep edges | Merge conflicts; loop FAILs at REVIEW-CODE on scope violations. **reasoned:** parallel children touching the same file will produce merge conflicts that are unresolvable without coordination; this is a structural guarantee, not a probabilistic concern |

**What would invalidate this:** If the orchestrator's pre-decided structure gets overridden by subagent flags on >2 of first 10 runs, subagents have signal the orchestrator is missing — either expand orchestrator inputs or accept structure-by-subagent. If Haiku pre-filter returns wrong ADRs (subsequent reviews catch ADR-conflicts the filter missed), tighten the filter prompt or fall back to including all ADRs.

## Related

- [Beadify Redesign Design](../../history/2026-04-23-beadify-redesign-design.md) — full design document
- [ADR-004](ADR-004-soldier-proof-skill.md) — soldier-proof pattern used for `/harness compose` validation, prerequisite for D7
- Three work-product design→bead pairs — empirical grounding for D1, D6 (findings captured in design doc Problem section)
