# ADR-010: Beadify-v2 Text-Until-Convergence Redesign

**Status:** Accepted
**Date:** 2026-04-28
**Brainstorm:** [/tmp/design-v2/beadify-v2-text-until-convergence-20260428-1156.md](/tmp/design-v2/beadify-v2-text-until-convergence-20260428-1156.md)
**Supersedes:** [ADR-005](ADR-005-beadify-redesign.md) D8 + D9 (marked SUPERSEDED 2026-04-28).
**Related:** ADR-005 (predecessor — operational rules from D9 carry forward unchanged: parent-first hierarchy, Haiku ADR pre-filter, integration-test rule, file-conflict detection); [ADR-006](ADR-006-workflow-modernization.md) D1 (epic `--design` substrate this redesign re-architectures how to populate); [ADR-008](ADR-008-adr-predicates-and-plan.md) D3 (Haiku scope cap; preserved in this design's 3-tier dispatch fallback).

## Note

May overlap with ADR-006 D1 — both touch how the epic `--design` field is populated. Cross-reference rather than consolidate: ADR-006 D1 says narrative lives on `--design`; this ADR says how the orchestrator produces and writes that narrative for beadify-v2 specifically.

## Context

`/beadify-v2` (the v1→v2 redesign captured in ADR-005, hardened by `/soldier-proof` on 2026-04-28 — see history/2026-04-28-sp-beadify-v2.md) runs an N-pass loop that writes child beads on pass 1 and refines via `bd update`/`bd dep add` between passes, with a post-write structural sweep catching same-file parallels, cross-bead-no-dep, acceptance overlap, and missing-integration. Yesterday's hardening folded six refinements but left two structural concerns visible:

1. **Partial-state pollution.** A failed pass leaves real beads in the DB. The F3 fold (existing-children → BLOCKED) is a workaround that punts cleanup to the operator. Re-runs are deterministic but inflexible.
2. **Single-orchestrator pre-decision.** Step 0a-tree has the orchestrator decide structure alone with no exploration of alternatives. The N-pass sweep tries to compensate but only catches problems *after* writes.

A peer skill in the private dotpi substrate (at `agent/skills/beadify-v2/SKILL.md` in that repo) solves both via three named subagent roles (decomposition scouts, acceptance refiners, whole-tree critic) and a critic gate that runs *before* `bd create`. This ADR records the decisions that align our beadify-v2 toward that shape while preserving wins (leaf path as first-class outcome, fallback tiers for missing dispatch tools, ADR seed from epic notes, deterministic semantics for autonomous mode).

## Decisions

### D1: Flip beadify-v2 to text-until-convergence

**Firmness: FIRM**

Hold the canonical bead graph in orchestrator memory across all phases of `/beadify-v2`; only materialize to bd at the end (after critic-PASS). Replace the current "write children pass 1, refine via `bd update` between passes" model.

**Rationale:** A whole-tree critic comparing slots side-by-side in one context window catches structural problems before they pollute bd. Materializing once on a validated graph is cheaper than `bd update`-driven refinement and eliminates partial-state recovery. The "graph held in orchestrator context" cost only bites for huge epics, which should be re-shaped at design stage rather than handled by beadify producing 15 children.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Keep incremental bd writes (ADR-005 D9 model) | Lower per-pass context cost; allows iterative `bd update` refinement | **Rejected** — direct: history/2026-04-28-sp-beadify-v2.md F3 fold shows partial-state recovery is undefined; we punted to BLOCKED rather than solving it |
| Hybrid (write on pass 1, refine in memory after) | Splits the difference | **Rejected** — reasoned: hybrid has the worst of both: pass-1 still pollutes bd on failure, and the orchestrator must reconcile DB state with in-memory revisions. Pick one model |

**What would invalidate this:** A single beadify run produces a graph that exceeds orchestrator context window before critic can see it (>~10 children with rich `--design` per child). If that happens, the epic should have been reshaped upstream.

### D2: Three-role subagent split with final-line contracts

**Firmness: FIRM**

Replace the single plan-writer dispatch shape (ADR-005 D9) with three named roles, each with a parseable terminator:

- **Decomposition scouts** propose tree graphs in fresh context. Final line: `TREE_PROPOSAL: ready` | `TREE_PROPOSAL: blocked`.
- **Acceptance refiners** sharpen `--acceptance` text per-child in parallel. Final line: `ACCEPTANCE_REFINED: yes` | `ACCEPTANCE_REFINED: no`.
- **Whole-tree critic** audits the canonical graph before materialize. Final line: `TREE_VERDICT: PASS` | `TREE_VERDICT: FAIL`.

**Rationale:** Each role has a distinct cognitive job: scouts explore (fresh context, can't see siblings), refiners sharpen (per-child, focused), critic audits (whole-tree gate). Each emits a parseable terminator so orchestrator triage is deterministic, not prose-reading.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Keep single plan-writer role (ADR-005 D9) | Simpler dispatch shape | **Rejected** — direct: dotpi beadify-v2 §"Subagent roles" demonstrates clearer separation of concerns; conflating roles in one N-pass loop loses the "fresh context for exploration" win |
| Two roles (planner + critic), drop refiner | Lighter | **Rejected** — reasoned: per-child acceptance sharpening is a different cognitive job from whole-tree audit. Folding it into critic forces the critic to do both whole-tree-structural and per-child-acceptance work in one pass |

**What would invalidate this:** If orchestrator synthesis cost (reading scout outputs + producing canonical graph) consistently exceeds the value of multi-scout exploration, drop scouts and have orchestrator decide alone (ADR-005 D9 model).

**Invalidation check (mechanical, optional):** n/a — qualitative.

### D3: `--N` becomes minimum sharpen iterations (floor), not target

**Firmness: FIRM**

Reframe `--N` from "default-target" (ADR-005 D8) to "minimum-iterations floor with convergence gate."

- `--N` default: 1.
- Convergence = sweep finds no issues **AND** K ≥ N. Then advance to critic.
- Hard cap = 5 sharpen iterations (ceiling).
- At cap with sweep still suggesting changes → advance to critic anyway, log warning in audit notes.

The "idempotent passes" principle from ADR-005 D8 is preserved — each pass runs the same holistic prompt. Only N's role changes.

**Rationale:** Empirically (ADR-005 D8 framing + soldier-proof iter-1 evidence), agents declare convergence too quickly. Forcing a minimum number of self-scrutiny passes catches refinements they'd otherwise skip. Hard cap prevents infinite loops when sweep keeps suggesting tweaks.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Drop `--N` entirely; converge when sweep finds nothing | Cleaner | **Rejected** — direct: brainstorm 2026-04-28: agents think too quickly they've converged but new iterations do find refinements |
| Keep `--N` as max (ADR-005 D8 framing) | Status quo | **Rejected** — reasoned: max works against quality. Floor + cap together expresses "do at least N, but stop runaway" which is what we want |

**What would invalidate this:** If `--N=1` (default) consistently produces graphs that critic accepts on first try, the floor isn't load-bearing and could be dropped. Track via critic-PASS-on-first-attempt rate after rollout.

### D4: `--scouts` orchestrator-decided by default with reasoning signals

**Firmness: FLEXIBLE**

When `--scouts` is not passed explicitly, the orchestrator decides scout count (0/1/2/3) by reading the epic's `--design`, `--acceptance`, and ADRs in scope, then choosing based on the signals below. `--scouts=N` is an explicit override; orchestrator records its choice and reasoning in audit notes.

- Leaf path (Step 0a chose leaf) → 0 scouts (Phase A short-circuits).
- Decompose path → 1, 2, or 3 scouts. Cap at 3.

**Reasoning signals (NOT hard rules — orchestrator weighs them):**
- Independence and breadth of `--acceptance` clauses.
- Sprawl of `--design` (single concern vs multiple).
- Number and centrality of in-scope ADRs.
- Variance in risk profiles (safe refactor + behavioral change suggests more exploration).
- Familiarity of the change type (novel architectural moves benefit more from multi-scout than well-trodden patterns).

**Rationale:** Hard rules ("4+ acceptance clauses → bump to 2") are brittle and overconstrain agent reasoning. Better to give the orchestrator signals to weigh and let it produce a count + rationale. User retains explicit override.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Hard-rule triggers (e.g. ≥4 acceptance clauses → 2 scouts) | Predictable | **Rejected** — direct: brainstorm 2026-04-28: hard constraints tend to be brittle, our agents are good at reasoning |
| Always 1 scout (no multi-scout exploration) | Simplest | **Rejected** — reasoned: high-ambiguity epics benefit measurably from independent proposals; forcing 1 collapses the explore-vs-exploit knob |
| Always `--scouts=N` required, no orchestrator default | Forces caller intent | **Rejected** — reasoned: caller often doesn't know how ambiguous the epic is until reading it. Orchestrator already reads `--design`, `--acceptance`, ADRs — better positioned to decide |

**What would invalidate this:** If orchestrator's auto-chosen scout count is consistently wrong (always picks 1 when 2 would have helped, or always picks 2 unnecessarily), revert to user-required-flag.

### D5: Existing open children loaded as a "first proposal"

**Firmness: FLEXIBLE**

When `/beadify-v2` is re-run on an epic with existing open children, those children are loaded into Phase A scout briefs as a candidate tree input rather than triggering BLOCKED. Orchestrator diffs the canonical graph against existing IDs at materialize and applies the right operations (`bd update`, `bd close`, `bd create`).

- `closed` children: ignored (carried forward from prior beadify-v2 behavior).
- `open` children: loaded into scout briefs as `existing-id=<id> title=<title> acceptance=<text>`. Scouts may keep, modify, replace, or drop them in their proposals.
- `in_progress` children: **frozen.** Canonical graph must keep their title/scope intact (acceptance may be sharpened by refiner only if substantive scope is unchanged). If canonical graph implies modifying or closing an `in_progress` child → BLOCKED with operator message.

**Rationale:** The yesterday F3 fold made existing-children → BLOCKED for deterministic semantics. With text-until-convergence + diff-and-apply materialize (D7), we can do better: feed existing children to scouts as a starting candidate tree. Re-runs reuse work rather than requiring clean-restart.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Keep BLOCKED on existing children (current F3 fold) | Deterministic; no diff complexity | **Rejected** — direct: brainstorm 2026-04-28: we can take existing children like a first proposal |
| Ask user (augment/replace/stop) (dotpi behavior) | Most flexible | **Rejected** — direct: incompatible with autonomous mode (/send-it); needs interactive input |

**What would invalidate this:** If diff-and-apply produces inconsistent state (e.g. orphaned dep edges, stranded `in_progress` children) in real runs, revert to BLOCKED.

### D6: Per-child parallel refiners (Option A only)

**Firmness: FIRM**

Acceptance refiners dispatch one-per-child in parallel. They are blind to siblings; the sweep + critic catch sibling concerns.

**Rationale:** Simpler dispatch shape, parallelizable, blind-to-siblings is fine because the sweep + critic catch sibling concerns. Sweep already does cross-bead reference checks and acceptance overlap. Adding a whole-graph refiner role doubles dispatch complexity for marginal gain.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Whole-graph sequential refiner (Option B from dotpi) | Catches sibling overlap inline | **Rejected** — direct: brainstorm 2026-04-28: drop B and keep A to keep it simpler; sweep + critic already handle cross-bead concerns |
| Hybrid (A by default, B when scouts flag tight coupling) | Adaptive | **Rejected** — reasoned: branch complexity on a default that the sweep/critic already cover. KISS wins |

**What would invalidate this:** If sibling-overlap regressions slip past sweep + critic in real runs, revisit Option B.

### D7: Diff-and-apply materialize step

**Firmness: FLEXIBLE**

Phase D (Materialize) reconciles the canonical graph with existing DB state rather than always `bd create`-ing from scratch.

- For each canonical slot, orchestrator includes a `kept-from-existing: <id>|new` field in the canonical graph.
- `kept-from-existing: <id>`: `bd update <id>` for any title/design/acceptance changes; verify dep edges match.
- `kept-from-existing: new`: `bd create --parent=<epic>` with full content.
- For each existing child not present in canonical graph: `bd close <id> --reason="superseded by /beadify-v2 re-decomposition"`. (Only `open` children — `in_progress` would have BLOCKED per D5.)
- Dep edges: diff existing `bd dep tree` against canonical; `bd dep add` missing edges.

**Rationale:** Direct consequence of D1 (text-until-convergence) + D5 (existing children as first proposal). Phase D produces the right bd operations to reconcile the canonical graph with existing DB state.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Always `bd create` from scratch (require BLOCKED on existing children) | Simpler materialize | **Rejected** — direct: D5 chose to support existing children as input. Materialize must support diff |

**What would invalidate this:** If `bd dep remove` is unavailable, stale-edge cleanup needs a workaround (close+recreate the bead, or document the limitation). May simplify D7 scope.

**Invalidation check (mechanical, optional):**
```bash
bd help dep | grep -E "(remove|delete|rm)" || echo "no-dep-removal"
```

### D8: Critic gate with 2-pass retry max

**Firmness: FIRM**

Phase C (Critique) runs the whole-tree critic once. If `TREE_VERDICT: FAIL`, orchestrator triages findings (fold-in / discard / decision-challenge / surface), applies revisions to canonical graph in memory, re-dispatches critic. If second critic returns FAIL → emit `BLOCKED: <critic findings>`. Do not retry beyond two passes.

**Rationale:** Critic is the structural quality gate before materialize. Single pass + retry-once gives orchestrator one chance to fold critic findings before BLOCKED, without unbounded retry loops.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Single critic pass, no retry | Simpler | **Rejected** — reasoned: critic findings often actionable; folding then re-critiquing is cheap and catches the cases where the orchestrator's first synthesis missed something the critic surfaced |
| Unbounded critic retries | Maximize quality | **Rejected** — reasoned: cost; if critic fails twice the issue likely needs human attention, not more orchestrator iteration |

**What would invalidate this:** If 2nd-pass critic-FAIL rate is high, increase the cap or surface earlier.

### D9: Coverage map mandatory in scout output and critic-validated

**Firmness: FIRM**

Each scout proposal includes a `## Coverage map` section: a table mapping each epic acceptance clause to the slot ID(s) covering it. The critic validates coverage in Phase C — uncovered clauses are an automatic FAIL with finding "epic acceptance clause N has no covering slot."

**Rationale:** The current sweep catches missing-integration and same-file conflicts but doesn't enforce that every epic acceptance criterion maps to a child slot. Coverage map makes this structural — orchestrator notices if any epic clause is uncovered before refiner/critic see the graph.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Rely on sweep + critic to catch missing coverage | Current behavior | **Rejected** — direct: dotpi §"Coverage map" makes this an explicit table; structural-by-construction beats catch-it-later |

**What would invalidate this:** If coverage-map output is consistently boilerplate (one slot covers each clause cleanly with no ambiguity), it adds noise without value.

### D10: Richer audit notes template (replaces one-line decision)

**Firmness: FIRM**

Replace the current one-line decomposition decision in epic `--notes` with a structured audit block:

```markdown
## Decomposition (beadify-v2 iteration <N>)

decision: <leaf|decompose>
rationale: <one line>
scout-count: <0|1|2|3> — <orchestrator reasoning OR "user override --scouts=N">
sharpen-iterations: <K> (min=<N>, cap=5)

Scout dispatches:
- scout-1: TREE_PROPOSAL: <ready|blocked> [<one-line summary of proposal>]
- scout-2: ...

Synthesis notes (when scouts ≥ 2):
- <major disagreements + orchestrator resolution>

Refiner dispatches:
- refiner-<slot>: ACCEPTANCE_REFINED: <yes|no>

Critic dispatches:
- critic-1: TREE_VERDICT: <PASS|FAIL> [<findings if FAIL>]
- critic-2: TREE_VERDICT: PASS  (if first FAIL'd and re-critiqued)

Created/updated/closed:
| Op | Bead ID | Title | Why |
|---|---|---|---|

ADRs consulted: <comma-separated paths>
```

**Rationale:** With three subagent roles + multi-scout, the "what happened in this run" has more shape; the audit trail should reflect it. Useful for `/review-v2` looking back and for debugging failed runs.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Keep one-line decision | Minimal | **Rejected** — reasoned: with three subagent roles + multi-scout, the audit trail needs shape to be useful for review and debug |

**What would invalidate this:** If the rich template bloats `--notes` past readability with no review/debug benefit, trim back.

### D11: Post-materialize graph verification

**Firmness: FIRM**

After `bd create`/`bd update`/`bd close`/`bd dep add` operations complete in Phase D, the orchestrator runs verification commands and confirms the result before emitting the contract line.

**Invalidation check (mechanical, optional):**
```bash
bd dep tree <epic-id>
bd dep cycles
bd list --parent=<epic-id>
```

Expected: created children appear under the epic; dep edges are in the intended direction; no cycles; ready children are unblocked; integration bead (if any) is blocked by the implementation children it validates.

**Rationale:** Cheap verification after writes catches mis-pointed `bd dep add` immediately rather than at implement time.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Skip verification (current behavior) | Cheaper | **Rejected** — direct: dotpi §9 demonstrates value; cost is three bd reads |

**What would invalidate this:** Verification finding zero issues for many runs = noise. Keep until proven boilerplate.

### D12: Leaf path stays first-class (preserved from prior beadify-v2)

**Firmness: FIRM**

Phase A short-circuits when Step 0a chooses leaf: zero subagents dispatched (no scouts, no refiners, no critic), no Phase B/C/D. Orchestrator records the decomposition decision on the epic's `--notes` and emits `EPIC_ID: <id> CHILDREN:` (empty children list). This is a normal outcome, not BLOCKED.

**Rationale:** Yesterday's `/soldier-proof` (history/2026-04-28-sp-beadify-v2.md iter 2 PASS) validated this is load-bearing for atomic single-file changes. Phase A short-circuits before scouts when leaf is decided.

**Alternatives considered:**

| Option | Why considered | Verdict |
|---|---|---|
| Always run Phase A scouts even on leaf | Uniform | **Rejected** — direct: history/2026-04-28-sp-beadify-v2.md iter 2 PASS confirms zero-subagent leaf path is correct |

**What would invalidate this:** If real-world epics flagged as leaf would have benefited from decomposition, tighten Step 0a leaf criteria. Not a leaf-path-itself problem.

## Related

- [ADR-005](ADR-005-beadify-redesign.md) — predecessor; D1+D2+D3+D6+D7 preserved unchanged; D8 + D9 superseded by this ADR.
- [ADR-006](ADR-006-workflow-modernization.md) D1 — narrative on `--design`; this ADR re-architects how the orchestrator produces and writes that narrative for beadify-v2.
- [ADR-008](ADR-008-adr-predicates-and-plan.md) D3 — Haiku scope cap; preserved in this ADR's scout dispatch fallback tier (cap=5 ADRs for beadify whole-epic context).
- history/2026-04-28-sp-beadify-v2.md — soldier-proof session that surfaced the gaps this ADR addresses.
- The private dotpi substrate's `agent/skills/beadify-v2/SKILL.md` — peer skill that demonstrates the three-role + critic-gate pattern this ADR adopts.
