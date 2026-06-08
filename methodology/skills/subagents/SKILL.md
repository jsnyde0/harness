---
name: subagents
description: Substrate-thick discipline for dispatching subagents — fresh-context preservation, execute-only contract, when to dispatch vs drive directly, parallel-OK iff disjoint file-claims. Use to decide HOW to delegate; what to delegate is /send-it's call.
---

## Why subagents

A subagent is a fresh context window. The orchestrator pays a small dispatch cost to get **frame-distance** — the subagent doesn't carry the orchestrator's biases, partial reads, or rationalizations from the current session. Use subagents when frame-distance matters; drive directly when it doesn't.

This is the only durable principle. Everything below is discipline that protects it.

## When to dispatch vs drive directly

**Dispatch when:**
- The work is non-trivial *and* the orchestrator's context is biased (you authored the bead, you've been arguing for a framing, you have partial reads)
- You need fresh-context judgment specifically (adversarial review, root-cause analysis, harness design at scale)
- The work is a TDD cycle on a leaf bead — `implementer` exists exactly for this

**Drive directly when:**
- The work is trivial (typo, single config line, mechanical rename)
- Orchestrator context is already aligned (you just designed the harness; running it doesn't need a fresh agent)
- Dispatch overhead exceeds the frame-distance benefit

No rule. Judge. Cheapest correct shape wins.

## Execute-only contract

The subagent's job is to satisfy the brief you give it — not to compose other primitives or re-scope the work. Agent definitions in the methodology home's agents/ directory enforce this in their prompts.

If a subagent's brief requires it to make a load-bearing decision the orchestrator hasn't framed (which file-claims? which ADR overrides?), that's a substrate gap. The subagent raises to you; you compose the missing primitive, then re-dispatch.

## Fresh-context preservation

The whole point of dispatch is fresh context. Don't undermine it:

- **Don't pass parent transcripts.** Brief with the bead ID + state references + what to verify. Subagent reads its own context. (ADR-009 D3.)
- **Don't summarize your own findings into the brief.** Summaries anchor. Hand the artifact path and the contract; let it draw its own conclusions.
- **Don't reuse a subagent across retries.** Each retry is a fresh `Task()` dispatch. Anchored re-reviewers find the same findings, not new ones. (ADR-007 D3.)

## Parallel dispatch

Parallel-dispatch is fine — encouraged — when independent work isolates cleanly. The structural constraint is **file-claim disjointness** (two subagents editing the same file race each other and overwrite work).

- Read the parent's `## File-claim map` (per `/decompose` DoD #6) before fan-out.
- Disjoint claims → parallel-OK. Dispatch in a single message; collect results; review each.
- Overlapping claims → serial. Walk children in dep order.
- No file-claim map → serial (cannot verify disjointness).

When in doubt, serial. The disjointness check sits in the orchestrator, not the subagent.

**Override of `superpowers:subagent-driven-development`.** That skill states "Never dispatch multiple implementation subagents in parallel (conflicts)" as a blanket prohibition. We override per ADR-009 D2: parallel is OK iff file-claims are disjoint. The underlying concern (file conflicts) is correct; the prohibition is over-broad. The same skill mandates TodoWrite — we use `bd` per CLAUDE.md; ignore that directive too.

## Subagent index

| Agent | One-line | Notes |
|---|---|---|
| `implementer` | TDD on a leaf bead; cannot commit/close | default for execution |
| `reviewer` | Quality/correctness review; verifies findings | review-only |
| `code-reviewer` | Review + close bead + commit | review with bundled close |
| `debugger` | Root-cause analysis on stuck beads; no fix | orchestrator folds |
| `adversarial-reviewer` | Fresh-context review of own work; PASS/REVISE/REJECT | default-on for own work |
| `harness-designer` | Target spec for big trees or churning leaves | fresh-context harness `/` |
| `plan-writer` | Detailed agent-executable plans | v2-era; rarely needed under substrate-thick |
| `design-scout` / `-refiner` / `-critic` | beadify-v2 Phase A/B/C | reference-only per ADR-012 D5 |

All execute-only. None compose other primitives. The first six are the substrate-thick working set; the rest are reference compositions.

## Canonical refs

- [ADR-007](../../docs/decisions/ADR-007-primitive-loop.md) D3 — fresh `Task()` per reviewer; no reuse.
- [ADR-009](../../docs/decisions/ADR-009-loop-composability.md) D2/D3 — parent dispatch (serial default, parallel-disjoint permitted); strip parent context.
- [ADR-012](../../docs/decisions/ADR-012-substrate-thick-process-thin.md) D3 — primitives + default-on adversarial review for own work.
- agents/ directory (methodology home) — agent definitions (the index above is a navigation aid; agent files are authoritative).
- send-it/SKILL.md (methodology home) — orchestrator that dispatches these.
