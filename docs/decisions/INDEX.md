# Anchored Decision Records — Index

Navigable index of harness ADRs. Mechanism ADRs (001–003) govern the cross-harness infrastructure. Methodology ADRs (004–014) govern the agentic-engineering workflow methodology. Firmness is **per-decision** (`FIRM` / `FLEXIBLE` / `EXPLORATORY` / `PROPOSED`), not per-document — scan the ADR for the firmness of a specific decision (Dn).

**How to consult:** scan the table for the scope you're touching, open the ADR, and check the relevant decision's firmness before contradicting it. Decisions evolve **in place** — git history carries predecessor wording; there are no supersession chains. ADRs link upstream via a `## canonical_refs` section.

> Per [ADR-012 D2](ADR-012-substrate-thick-process-thin.md), ADRs cover **cross-cutting load-bearing decisions across any domain** — not only architecture. This index is the discoverability layer: scan it before contract authoring or design work.

## Conventions

- **Cross-cutting write filter** ([ADR-012 D2](ADR-012-substrate-thick-process-thin.md)): an entry earns ADR status only if (a) revising it would require argument and (b) it is cross-cutting (constrains more than one bead, domain, or subsystem).
- **Firmness** is per-decision inside each ADR (FIRM / FLEXIBLE / EXPLORATORY / SUPERSEDED), not on the ADR as a whole.
- **In-place evolution** ([ADR-011](ADR-011-adrs-reflect-target-architecture.md)): when a decision evolves, edit the ADR in place. Git carries the WHY-trail.
- **Bead linkage:** beads constrained by ADRs reference them in their `--notes` field as `ADRs: ADR-NNN, ADR-MMM`.

## Mechanism ADRs (001–003) — cross-harness substrate

| ADR | Title | Scope | Status | Summary |
|---|---|---|---|---|
| [001](ADR-001-minimal-pi-subagent-subprocess-primitive.md) | Minimal Pi Subagent Subprocess Primitive | subagent | Accepted (revised 2026-06-03) | `subagent` extension spawns child pi processes. D2 evolved: inline-only → inline **or** named-role (additive role-loader, EXPLORATORY). D3 evolved: modelTier → explicit provider/model slugs (see ADR-002 D4). D4 final-line contracts, D5 bounded parallel, D6 least-privilege remain. |
| [002](ADR-002-cross-harness-substrate.md) | Cross-Harness Substrate — Topology & Thin-Waist | cross-harness | Proposed (EXPLORATORY) | pi-primary harness topology (D1); thin-waist shared-asset architecture (D2); shared role-brief library + role registry (D3); explicit provider/model slugs (D4); CLI-first/no-MCP (D5); compile/install as an agent-run skill (D6); open-source distribution posture (D7 — public core + private overlay, one-way reference rule). Targets CC + pi + Codex. |
| [003](ADR-003-factory-orchestration-model.md) | Orchestration Model for the Self-Driving Bead Factory | orchestration | Proposed (all FLEXIBLE/EXPLORATORY, dogfood-pending) | Runtime orchestration model for the self-driving bead factory. D1 orchestrator lifecycle = exit-and-resume; D2 HITL surfacing = single `agent_end` chokepoint; D3 two planes — factory vs cockpit; D4 cockpit surfaces. |

## Methodology ADRs (004–014) — agentic-engineering workflow

| # | Title | Scope | Notes |
|---|---|---|---|
| 004 | [Soldier-Proof Skill](ADR-004-soldier-proof-skill.md) | `workflow` | Skill hardening discipline via subagent isolation. |
| 005 | [Beadify Redesign](ADR-005-beadify-redesign.md) | `workflow` | Foundational beadify shape decisions. |
| 006 | [Workflow Modernization](ADR-006-workflow-modernization.md) | `workflow` | Workflow-loop modernization arc. |
| 007 | [Primitive Loop](ADR-007-primitive-loop.md) | `workflow` | Convergence-loop primitive for review/refine cycles. |
| 008 | [ADR Predicates and Plan](ADR-008-adr-predicates-and-plan.md) | `workflow` | ADR predicates required per decision. |
| 009 | [Loop Composability](ADR-009-loop-composability.md) | `workflow` | Composable loop primitives across skills. |
| 010 | [Beadify-v2 Text-Until-Convergence](ADR-010-beadify-v2-text-until-convergence.md) | `workflow` | Four-phase beadify pipeline (reference-only per ADR-012 D5). |
| 011 | [ADRs Reflect Target Architecture](ADR-011-adrs-reflect-target-architecture.md) | `workflow` | In-place updates for decision evolution; no supersession chains. |
| 012 | [Substrate-Thick, Process-Thin](ADR-012-substrate-thick-process-thin.md) | `workflow` | Thesis-v2.1: ADR rebrand to Anchored, six primitives, default-on adversarial review, bicameral compounding spine, v2 demoted to reference. EXPLORATORY pending dogfooding bar. |
| 013 | [Memory Layer Architecture](ADR-013-memory-layer-architecture.md) | `workflow` | Three layers by lifecycle (L1 raw / L2 mutable working / L3 canonical). L2 splits by decay-behavior (L2A decaying observations+calibrations; L2B non-decaying procedural-knowledge+anchors+references). Impl-agnostic spec. |
| 014 | [bd Storage Model](ADR-014-bd-storage-model.md) | `tooling` | Personal bd repos run Dolt embedded; `issues.jsonl --include-memories` is the cross-machine carrier. All FIRM. |

## When to consult

- **Before contract authoring** for a new bead → scan ADR titles + one-line descriptions for in-scope constraints.
- **Before design or architectural decisions** → check existing ADRs for already-decided territory.
- **Before bead execution** → read ADRs linked in the bead's `--notes` (`ADRs: ADR-NNN`).

## Maintenance

This index is updated whenever an ADR is added or has its scope/firmness change. Keep entries to one line; the ADR file itself carries the detail.
