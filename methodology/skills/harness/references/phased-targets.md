# Phased Targets: Evolving Verification Across Multi-Step Work

## The Problem

Multi-phase work (design → implement → review → fix) can't have one static iteration target. What you learn in Phase 2 may invalidate Phase 1's assumptions. But making the target fully flexible invites drift — accuracy drops from 90% at turn 5 to 13% at turn 20 in long sessions.

## Pattern: Stable Contract, Flexible Implementation

Define what stays constant (acceptance criteria, interface contracts, test assertions). Let the implementation evolve. The contract is the stable target — it only changes when evidence forces it, not through drift.

**Consumer-driven contracts** (Pact, eBay): The consumer defines what it expects. The provider must fulfill contracts even as it evolves. Extra data is fine; missing expected data is not.

**Executable specifications** (BDD, Gherkin): Given/When/Then specs are both documentation AND tests. When requirements change, specs change, and failures are immediate.

## Pattern: Checkpoint-Based Grounding

Each phase boundary creates a verified snapshot. The next phase starts from that checkpoint, not from accumulated assumptions.

```
Phase 1: Design → [CHECKPOINT: design verified against reality]
Phase 2: Implement → [CHECKPOINT: tests pass, system runs]
Phase 3: Review → [CHECKPOINT: behavior verified, scope checked]
Phase 4: Fix → [CHECKPOINT: regressions caught, fixes verified]
```

The checkpoint is ground truth. If you've been compacted or lost context, you can recover from the last checkpoint.

## Pattern: Bounded State, Not Growing Transcripts

Maintain a compact structured state of what's verified. Don't accumulate a growing narrative.

Agent Cognitive Compressor (ACC): Replaces transcript replay with bounded internal state. Separates artifact recall from state commitment — unverified content doesn't become persistent memory.

Layered memory architecture: goals, constraints, entities, relations — updated selectively as new evidence arrives.

## Pattern: Evidence-Driven Target Updates

If Phase 2 reveals Phase 1's target was wrong, update it — but consciously:
1. What evidence invalidated the target?
2. What's the new target?
3. Does this affect earlier checkpoints?

Hypothesis-driven development: State validation criteria upfront ("we'll know we're right when Y"). If Y doesn't hold, the hypothesis is wrong — don't silently adjust Y.

## Pattern: Progressive Verification (Canary)

Start with the cheapest check, progressively expand:

```
Does it compile?          → fast, catches syntax
Does the API respond?     → medium, catches integration
Does the user flow work?  → slow, catches behavior
Does it perform at scale? → expensive, catches regression
```

Each level assumes the previous level passes. Don't run E2E if it doesn't compile.

Argo Rollouts / Flagger: automated metric-based progression. If metrics pass, advance; if not, rollback.

## Drift Prevention

- **Session-bounded scope**: Shorter iterations with explicit reset points
- **Regular re-grounding**: Re-run the system, re-read actual files, don't trust accumulated understanding
- **Context compaction awareness**: After compaction, recover from the checkpoint file, not from memory
- **TTL on memory**: Auto-prune stale data; what was true 20 turns ago may not be true now
