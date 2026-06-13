---
name: dogfood-workflow
description: Substrate-thick / process-thin workflow audit of a Claude Code session. Reads a session JSONL through the dogfooding lens — skill-invocation pattern, friction points, substrate-layer touches (L2A/L2B/L3 dark layers), juncture-awareness misses, ADR firmness conflicts. Returns evidence-cited findings. Use when given a session path or id and asked to analyze workflow behavior, identify primitives that got hand-rolled, audit dogfooding of the substrate, or find friction points substrate could absorb. Triggers on "dogfood this session", "analyze workflow", "session audit", "audit dogfooding", "did we use primitives here", "how did the workflow hold up". Substrate-improvement recommendations only — process-thickening is the flagged anti-pattern.
---

# /dogfood-workflow

Workflow audit of one Claude Code session against the substrate-thick / process-thin discipline. Goal: surface where the session honored substrate-thick behavior, where it silently absorbed work that a primitive should have done, and what (if anything) the substrate itself could absorb to make the right primitive invocation cheaper than re-implementation next time.

Not a code review. Not a /compound run. Workflow-behavior analysis only.

## When to invoke

- User points at a session (JSONL path, session id, or recent-session reference) and asks for a dogfood analysis.
- User asks "did we use the right primitives", "what should have been delegated", "where did we hand-roll", "is this workflow working".
- After closing a substantial unit of work when retrospective focus is the workflow itself, not the work product — analogous to /compound but lens-specific to skill-invocation + substrate-touch patterns rather than memory residue.

Distinct from /compound (which produces Record/Promote/Retire across memory substrate) and /adversarial-review (which judges a single artifact).

## Required grounding (read first)

The agent must ground itself in the canonical substrate before analysis. Don't cite from memory — read fresh; the documents evolve.

- global agent instructions file — `## Brain of the loop`, `## Substrate orientation`, `## Workflow primitives`
- methodology home — substrate-thick / process-thin thesis and primitive shape pattern
- memory layer architecture ADR — behavioral-contract shape, residue-before-gate, juncture-awareness

## Mandatory tool

`claude-session-transcript` skill — MANDATORY for JSONL extraction. Do not write custom Python or one-off parsers.

Dispatch a subagent for the transcript reading — token-volume work, keep the orchestrator's context on judgment per CLAUDE.md "Brain of the loop." The orchestrator does the analysis; the subagent does the reading.

## Analysis axes

1. **Skill-invocation pattern.** Primitives that fired via the Skill tool vs raw Task dispatches that duplicated a primitive's shape vs hand-rolled equivalents. Skipped primitives whose SKILL.md triggers matched the agent's own narration.
2. **Friction points.** Manual re-orientation after compaction or self-checkpoint, hand-rolled summaries matching /compound's output shape, sed-patching or git plumbing that a primitive could absorb, repeated context-recovery moves.
3. **Substrate touches.** L2A (cm playbook), L2B (bd memories), L3 (ADR reads/writes). Flag dark layers — substantive sessions where one or more substrate layers got zero touches.
4. **Juncture-awareness.** Did the agent re-survey the primitive inventory at named junctures — entry, post-compaction or self-checkpoint resumption, scope shift mid-work, pre-substrate-write (`bd create`, ADR or skill edit), pre-close-summary? Silent absorption at any juncture is a finding.
5. **ADR firmness conflicts.** Cases where an ADR was silently contradicted vs where a FIRM conflict was surfaced and resolved. The latter is positive substrate behavior worth noting; the former is a finding.

## Output shape

Under 600 words. Evidence-cited (line numbers, message indices, bd commands run, ADR sections quoted). Structured by the 5 axes above. Distinguish positive findings ("good substrate behavior worth keeping") from negative ones ("silent absorption").

End with a short "what the substrate could absorb" section — substrate-improvement candidates only. If nothing surfaces, say so — the analysis isn't required to produce recommendations.

## Anti-pattern: process-thickening recommendations

The flagged anti-pattern in this analysis is **process-thickening**. Substrate-thick / process-thin means the model composes by judgment over a small set of primitives — not by following a fixed sequence.

Recommendations MUST be substrate-shape, not process-shape:

- **Substrate-shape (allowed):** recognition-widening (trigger phrasing in SKILL.md descriptions), behavioral contracts (juncture-awareness family), juncture-list extensions, moving content to compaction-durable surfaces (CLAUDE.md), making invocation cheaper than re-implementation.
- **Process-shape (disallowed):** "add this step to that skill's checklist," "sequence X before Y," "before doing Z, the agent must…," any sequenced multi-step protocol inside a primitive.

If a recommendation reads as a sequenced checklist or per-primitive mandatory ordering, back it out — that's the recipe-leak the primitive-shape guard exists to prevent. The "Recipe-leak posture" section of the juncture-awareness ADR names the exact shape to avoid.

If you catch yourself drafting a "before doing X, first…" sequence, flag it and back out. Substrate fixes the recognition gap; process tries to script around it.

## What this skill is NOT

- Not /compound — that surfaces L2A/L2B/L3 candidates with countermand reasoning; this audits workflow behavior.
- Not /adversarial-review — that judges an artifact (design/plan/decomposition); this audits a session-as-process.
- Not a code review — workflow behavior, not work product.
- Not an authorship primitive — does not write ADRs, beads, or memory entries. Findings only; the user folds.

## Canonical refs

- global agent instructions file `## Brain of the loop`, `## Substrate orientation` — orchestrator-identity framing
