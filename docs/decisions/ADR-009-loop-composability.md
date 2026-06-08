# ADR-009: Loop Composability — Epics Are Parent Beads Worked by the Same Primitive Loop

**Status:** Accepted (revised 2026-05-13)
**Date:** 2026-04-24
**Design:** [Phase 3 Design](../../history/2026-04-24-workflow-loop-phase3-design.md); parent picture [Workflow Loop Design](../../history/2026-04-24-workflow-loop-design.md)
**Research basis:** [`2026-04-24-workflow-loop-brainstorm-research.md`](../../history/2026-04-24-workflow-loop-brainstorm-research.md) — OpenHands `DelegateTool` + PR #4327, CrewAI PR #2068 `allowed_agents`, LangGraph infinite-handoff failure mode, metaswarm Phase 3.5 cross-unit review, nested-loop research.
**Related:**
- [ADR-007](ADR-007-primitive-loop.md) — the primitive this composes
- [ADR-008](ADR-008-adr-predicates-and-plan.md) — scope-resolution + discovered-from (inherited by each level)
- [ADR-006](ADR-006-workflow-modernization.md) — bead-as-substrate, `--parent` hierarchy

## Context

ADR-007 defines a blocking state-machine loop on a single bead. ADR-008 adds WHY-aware PLAN and scope mechanics. Both work for leaf beads. Epics — beads that decompose into multiple children — need a composition rule.

Research surfaced failure modes specific to multi-level agent loops:
- **Infinite handoff** (LangGraph): A→B→C→A when no agent "owns" the task. The canonical fix is: parent re-runs its own gap-check after child returns "done."
- **Context explosion / parent-thought leakage** (OpenHands PR #4327): child prompts that include parent reasoning cause quadratic context growth and anchoring.
- **Unbounded delegation** (CrewAI PR #2068): missing `allowed_agents` causes choice paralysis.
- **CrewAI manager-worker failures** (TDS critique): when delegation is LLM reasoning (not a tool call), agents fail to delegate at all.
- **Metaswarm validates same-primitive recursion** (swarm-of-swarms): 3 weeks of operational data shows the pattern holds.

This ADR composes ADR-007 with itself: an epic is a parent bead worked by the same primitive loop.

## Decisions

### D1: Epic is not a special primitive — it is a parent bead worked by the same state machine — **applies when the primitive-loop recipe is invoked**

**Firmness: FLEXIBLE** *(demoted from FIRM 2026-05-08 per ADR-012 D3 — the loop composability is the recipe-level pattern when ADR-007 D1's loop is invoked on a multi-child bead. Under thesis-v2.1, decomposition is a primitive that may also compose with other recipes (judgment-routed dispatch), not only the 4-state loop. The "same primitive, recursive" property holds when the loop recipe is invoked.)*

When the primitive loop recipe from ADR-007 D1 runs on a bead that has children (or `--type=epic` with children), it uses the same four-state machine (PLAN → REVIEW-PLAN → IMPLEMENT → REVIEW-CODE). The behavior of each state adapts based on whether the bead has children; there is no separate "epic orchestrator" skill or agent.

**Rationale:** (C)+(D) in the working picture: one primitive + composability. Simpler mental model, simpler implementation, single code path for hardening. Metaswarm validates this with 3 weeks of production data on nested orchestration. Avoids the CrewAI failure surface where a dedicated manager agent fails to delegate properly.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Same loop, behavior branches on children (chosen) | Single primitive; composable; metaswarm-validated | Each state needs parent-branch logic |
| Dedicated epic-orchestrator skill | Clean separation | Duplicates core loop; drift risk; CrewAI-style failure surface. **external:** CrewAI manager-worker analysis — dedicated manager agents fail to delegate when delegation is LLM reasoning rather than a tool call; a separate skill introduces the same failure surface |
| Flatten epics into ordered child queue with no parent-state | Simplest | Loses parent-level acceptance check; no cross-child review. **reasoned:** a flat queue has no parent contract to verify against after children close; infinite-handoff vulnerability emerges when no level owns the terminal closure signal |

**What would invalidate this:** If the parent-branch logic in each state grows beyond ~30% of the state's total logic, the "same primitive" claim is weakening — consider splitting. If epics work meaningfully differently from leaves in practice (e.g. different retry caps, different review rigor), the composition abstraction is leaking.

### D2: Parent IMPLEMENT = dispatch-and-wait; serial by default, parallel permitted iff child file-claims are disjoint — **applies when the primitive-loop recipe is invoked on a parent bead**

**Firmness: FLEXIBLE** *(demoted from FIRM 2026-05-08 per ADR-012 D3 — serial dispatch-and-wait is the recipe-level dispatch pattern when ADR-007 D1's loop runs on a parent bead. Refined 2026-05-14 in-place per ADR-011 D1: parallel-dispatch is permitted when child file-claims are disjoint per the parent's `## File-claim map` — the original "explicitly out of scope" wording was over-broad. The serial-by-default safety property is preserved; the parallel-disjoint exception is added.)*

When the primitive loop recipe runs on a parent bead, the IMPLEMENT state does not write code. It repeatedly:

1. `bd ready --parent=<epic>` — pick the next ready child(ren).
2. If none, break out of the dispatch loop.
3. Spawn a fresh `Task()` to run the full primitive loop on the next child (serial) — OR spawn a batch of fresh `Task()` dispatches in a single message, one per disjoint-file-claim child (parallel, see below).
4. Wait for DONE or `waiting:human` (serial: one outcome; parallel: one outcome per dispatched child).
5. Go to 1.

**Serial is the default; parallel is permitted under one structural constraint.** Two subagents editing the same file race each other and overwrite each other's work; this is the real cost of parallel dispatch, not LLM reasoning failure. Parallel-dispatch is permitted iff:

- The parent's `## File-claim map` (per `/decompose` DoD #6, beadify-v2 design) names the files each child will touch.
- The selected children's claimed file sets are pairwise disjoint.
- The orchestrator dispatches them in a single message (parallel `Task()` tool calls).

Any overlap → fall back to serial. No file-claim map → fall back to serial (cannot verify disjointness). When in doubt, serial. The structural check sits in the orchestrator, not the subagent — `superpowers:subagent-driven-development`'s blanket "never parallel implementers" is over-broad and is overridden by this decision; the underlying concern (file conflicts) is addressed by the disjointness gate.

**Rationale:** OpenHands `DelegateTool` treats delegation as a tool call, not LLM reasoning — eliminates the CrewAI manager-worker failure mode. Serial over parallel because: (a) simpler control flow and debugging, (b) matches Ralph's "one activity, one goal per iteration," (c) parallelism is an optimization that adds failure modes (race conditions, coordinated-retry semantics) we don't need yet. Arize data shows multi-agent parallel adds only 2.1pp accuracy at 2x cost on typical tasks.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Serial by default, parallel iff disjoint file-claims (chosen, 2026-05-14 in-place edit) | Simple safe default; structural exception when the substrate predicate (disjoint claims) is met; avoids both serial-wall-clock-tax and unguarded race conditions | Requires `## File-claim map` to be populated by `/decompose` — when missing, falls back to serial |
| Serial only (original chosen, superseded 2026-05-14) | Simplest; no race-condition surface | Wall-clock tax on independent epics; ignores that file-claim disjointness is a substrate property the orchestrator can verify cheaply |
| Parallel via `Promise.all` always | Faster wall-clock | Race conditions; coordinated retry; needs inter-child isolation tooling. **external:** Arize data — multi-agent parallel adds only 2.1pp accuracy at 2x cost on typical tasks; the marginal accuracy gain doesn't justify the race-condition and coordinated-retry complexity when claims overlap |
| LLM-decides-when-to-delegate | Flexible | CrewAI failure surface; manager doesn't delegate. **external:** CrewAI PR #2068 — when delegation is LLM reasoning rather than a tool call, agents fail to delegate at all; OpenHands `DelegateTool` treats delegation as a tool call specifically to avoid this |
| Push-based queue with worker pool | Elastic | Premature; no infrastructure for it. **reasoned:** a worker pool requires infrastructure for task routing, failure isolation, and result coordination that doesn't exist and isn't worth building for current scale |

**What would invalidate this:** (a) Parallel-disjoint runs routinely produce race conditions despite the disjointness check — meaning `## File-claim map` doesn't capture the real coupling (shared imports, schema migrations, generated artifacts), and the substrate predicate is too weak. (b) The disjointness check is so rarely satisfied in real epics that the parallel path never fires — collapse back to serial-only and accept the wall-clock tax. (c) `/decompose` consistently fails to populate the file-claim map, leaving the parallel path unreachable — fix `/decompose`, not this decision.

### D3: Child prompt contains only the child's bead ID — strip all parent context

**Firmness: FIRM**

The `Task()` invocation that dispatches a child loop passes only: the child bead's ID and the orchestrator's state-machine instructions. It does **not** include:
- Parent bead's description, notes, or acceptance
- Parent loop's transcripts or reviewer findings
- Any "chain of thought" from higher levels

The child reads its own context via `bd show` and resolves its own in-scope ADRs (ADR-008 D3). Isolation by design.

**Rationale:** OpenHands PR #4327: strip parent thoughts to avoid context leakage and anchoring. Quadratic context growth is the observed failure mode when prompts cascade downward. Isolation forces the child to be a well-scoped bead (if it isn't, that's an ADR-005 beadify bug surfacing early — good signal).

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Strip everything, child reads own state (chosen) | Structural isolation; OpenHands-validated | Child must be self-contained — enforces beadify discipline |
| Pass parent acceptance to child | "Helpful context" | Leaks scope; child drifts outside its own slice. **reasoned:** a child that knows the parent's acceptance may try to satisfy the parent's contract directly instead of its own slice, producing scope drift that the parent-level REVIEW-CODE then flags |
| Pass full parent transcript | Maximum information | Quadratic growth; anchoring. **external:** OpenHands PR #4327 — strip parent thoughts to avoid context leakage and anchoring; passing full parent transcripts causes quadratic context growth and anchoring on parent decisions |
| Summarize parent and pass summary | Middle ground | Summaries lose/add signal; agents anchor on them. **reasoned:** summaries are lossy compressions; agents anchor on the framing in the summary while missing what the summary dropped, combining signal loss with anchoring bias |

**What would invalidate this:** If children repeatedly fail because they lack context that the parent would have provided, the beadify organize+target step (ADR-005 D6) isn't producing well-scoped beads — fix beadify, not this decision. Watch for child PLAN FAILs whose REVIEW-PLAN findings cite "insufficient scope" or "missing context" — when that surfaces as a recurring failure mode across multiple children, beadify's output is the culprit.

### D4: Depth cap 3 — no deeper nesting

**Firmness: FLEXIBLE**

The primitive loop supports at most 3 levels of `--parent` nesting. Epic → sub-epic → leaf is the maximum. Beyond depth 3, the orchestrator errors out and escalates to human.

**Rationale:** Empirical cap from nested-loop research: production systems observe max useful depth around 3. Deeper nesting usually indicates a design problem (poor epic splitting, missing abstraction). Hard cap prevents pathological recursion and runaway cost. FLEXIBLE because we may learn some legitimate 4-level case exists.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Hard cap at 3 (chosen) | Prevents runaway; matches production data | Arbitrary ceiling for unusual cases |
| No cap | Maximally flexible | Runaway cost; depth deadlock risk. **reasoned:** unbounded nesting creates pathological recursion risk; without a cap, a poorly decomposed epic can exceed any practical token budget |
| Cap at 2 | Tighter | Blocks legitimate epic-of-epics pattern. **external:** nested-loop production data — max useful depth is around 3; depth 2 blocks legitimately structured epics with sub-epics |
| Dynamic cap based on token budget | Adaptive | Complex; budget semantics murky. **reasoned:** token budget semantics at nesting-time are unclear (current operation cost vs remaining budget); the complexity of dynamic capping is not justified when a fixed cap at an empirically-correct depth works |

**What would invalidate this:** If legitimate 4-level hierarchies emerge more than occasionally, raise to 4. If depth-3 loops are still too expensive in practice, lower to 2. Watch for the depth-3 error surfacing in real use on tasks that are genuinely well-scoped (not a design mistake) — when that happens more than as a rare one-off, raise the cap.

### D5: Parent re-runs its own acceptance + ADR invalidation checks after all children close — **applies when the primitive-loop recipe is invoked on a parent bead**

**Firmness: FLEXIBLE** *(demoted from FIRM 2026-05-08 per ADR-012 D3 — parent re-check is the infinite-handoff mitigation for the primitive-loop recipe. Under thesis-v2.1, the equivalent discipline at the recipe level is: any decomposition primitive's parent must re-verify acceptance after dispatched children close. The mechanism is recipe-level, not pipeline-level.)*

When the primitive loop recipe runs on a parent bead, after the parent's IMPLEMENT state exits (all children DONE or any hit `waiting:human`), the orchestrator does not immediately move to REVIEW-CODE. It first re-verifies at the parent level:

1. All children are closed (not `waiting:human`). If any is `waiting:human`, the epic inherits `waiting:human` and exits.
2. The epic's own `--acceptance` command passes (orchestrator-run; ADR-007 D2 trust model).
3. All in-scope ADR invalidation checks (ADR-008 D1) pass on the cumulative diff of child work.

Any FAIL at these checks → back to IMPLEMENT on the parent, which means filing a new child bead to close the gap. Retry cap (ADR-007 D5) applies to the parent IMPLEMENT state independently.

**Rationale:** This is the infinite-handoff mitigation. LangGraph research surfaced this failure mode clearly: without a parent re-check, A→B→C→A where children all report "done" but the parent's acceptance still doesn't hold, and the loop can't close. Parent re-check forces the closure signal to originate at the level that owns the contract. Metaswarm's Phase 3.5 "Final Comprehensive Review" implements the same principle.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Parent re-runs acceptance + ADR checks (chosen) | Closes the infinite-handoff gap; authoritative contract check at the right level | Adds another validator run per epic |
| Trust children's DONE signals | Simpler | Infinite-handoff vulnerability — documented failure mode. **external:** LangGraph infinite-handoff failure mode — without a parent re-check, A→B→C→A where children all report done but the parent's acceptance still doesn't hold; the loop can never close |
| Cross-child integration review only (no acceptance re-run) | Lighter | Misses cases where acceptance fails even when children pass local review. **reasoned:** integration review checks cross-child interactions, not parent-level acceptance; a parent contract can fail even when all cross-child reviews pass |
| Human gate after all children | Safe | Eliminates automation benefit for epics. **reasoned:** requiring human confirmation after each epic's children close converts what should be a background-capable loop into an interactive one; the whole point of parent-level re-check is to automate the closure signal |

**What would invalidate this:** If parent re-checks never FAIL (always pass after children), they're ceremony — but keep them anyway as defense-in-depth, since the cost is low and the failure mode is severe. If they FAIL so often that epics hit `waiting:human` routinely at the parent level, the children aren't covering the epic's acceptance properly — beadify's decomposition is weak. Watch for `bd list --status=waiting:human --label=retry` showing epics that stalled specifically at the parent re-check gate — when that pattern surfaces, beadify's output needs work.

## Related

- ADR-007 — the loop this composes.
- ADR-008 D4 — `discovered-from` beads filed by a child become siblings under the parent, picked up by the parent's next IMPLEMENT iteration.
- Parallelism is deferred indefinitely; when revisited, it becomes a new ADR layered here (not a modification of D2).
