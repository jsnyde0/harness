---
name: harness
description: Design feedback infrastructure for a task or project. Use /harness to compose a harness for the current task, /harness compose to author a `## Harness target` block for a specific bead scope (invoked from bead-authoring primitives like /brainstorm and /decompose), or /harness audit to scan a repo and produce a harness inventory. Also handles targeted additions to an existing inventory when the user knows something is missing. If the project has a `.claude/harness.md` file, that's the canonical inventory of verification mechanisms — consult it when picking a feedback loop. Triggers on "harness", "iteration target", "feedback loop", "what should I verify against", "how do I test this", "verification strategy", "harness target", "compose a harness target", "add X to the harness", "missing from harness.md", "this should be in our harness inventory".
---

# Harness Engineering

**Agent = Model + Harness.** The harness is everything except the LLM itself: the feedback loops, verification targets, and iteration infrastructure that let agents self-correct against reality. A good harness 2-3x the quality of the final result. LangChain gained +13.7 benchmark points by changing *only* the harness, zero model changes.

A harness is a **composed collection** of feedback mechanisms — not just one check, but a suite selected and arranged for the situation. Sometimes one fast signal is enough; sometimes you need a smorgasbord spanning static analysis, runtime probes, log inspection, and custom scripts.

## Core Principle

**Get yourself a feedback signal before theorizing.** Set up a feedback loop — something you can run, observe, adjust, and run again. The HOW varies:

- **Build** — when no feedback mechanism exists yet (probe scripts, test fixtures, throwaway spikes, minimal repros)
- **Connect** — when feedback exists but you're not plugged in (tail logs, curl APIs, query databases, use MCP tools, check dashboards)
- **Configure** — when the system can tell you more if you ask (debug logging, strict mode, verbose output, type checking)
- **Reduce** — when the problem is too big to iterate on (minimal repro, strip to smallest failing case, isolate subsystem)

Prefer the **fastest, most deterministic signal** available:

```
FAST / DETERMINISTIC SLOW / SEMANTIC
───────────────────────────────────────────────────────────────────→
compile → typecheck → lint → unit test → integration → E2E → LLM judge → human
```

## Recipes

- **[`/harness`](recipes/quick.md)** — Compose a harness for the current task. **Inventory-first:** before picking a signal, consult `.claude/harness.md` in the current project. If the inventory names a faster goal-faithful signal at the same or better altitude than what you'd propose cold, use that signal and cite the inventory entry in the Rationale. Push back against the inventory only when the faster signal genuinely doesn't capture the bead's intent — and name why. If no inventory exists, scan and propose; note the absence so the caller can decide whether to run `/harness audit` first.
- **[`/harness compose`](recipes/compose.md)** — Author a `## Harness target` block for a specific bead scope, returning the four-predicate structure (Signal / Expected green / Rationale / Invalidation). The canonical surface invoked by bead-authoring primitives (`/brainstorm` at convergence, `/decompose` at child authoring). Caller is responsible for persisting the returned block to the bead's `--design` — `/harness compose` returns the block, it does not write to bead substrate.
- **[`/harness audit`](recipes/audit.md)** — Scan a repo and produce (or update) the repo's `.claude/harness.md` inventory (always this path — nested as `.claude/.claude/harness.md` in the methodology home repo itself) of all available feedback mechanisms, structured with **per-category fit profiles** ("for X kind of work in this repo, prefer Y mechanism because Z"). One-time investment per repo that future sessions reference. Also covers targeted single-entry additions when the user points out something the scan missed.

**Recipe-authoring note.** Both recipes consult substrate (bd memories, ADRs, CASSMS) before composing or scanning. When authoring or evolving a recipe step that says "consult substrate", document BOTH paths: the canonical `/recall` invocation AND surrogate reads (`bd memories <keyword>`, scan `docs/decisions/INDEX.md`) for execute-only subagent contexts where the `Skill` tool isn't available. See bd memory `skill-recipe-recall-surrogate-fallback` for the why.

## Harness target review criteria (for `adversarial-reviewer`)

When reviewing a `## Harness target` section, apply criteria **in this order** — alignment is load-bearing; presence is necessary but not sufficient:

1. **Alignment** — does the target capture the bead's intended outcome / end-state? The Signal must be goal-faithful: it should fail if the bead's actual intent is not met, and pass when it is. A test suite that would pass even if the integration is wired wrong is misaligned. A linter check on a bead whose intent is behavioral change is misaligned. This is the load-bearing question — push for iteration if the signal is misaligned even when all other criteria pass.
2. **Presence** — section exists with all four predicate fields (Signal / Expected green / Rationale / Invalidation), each non-empty (a named-skip-with-rationale satisfies presence for trivial work).
3. **Falsifiability** — Signal + Expected green together form a binary observable. "Tests pass" with no named test is not falsifiable. "grep returns non-empty matches in convergence-exit-contract region" is.
4. **Fit vs inventory** — if `.claude/harness.md` names a faster goal-faithful signal at the same or better altitude, push back. The Rationale field should name why the chosen signal was preferred over the inventory alternative.
5. **Rationale + Invalidation populated** — not templated. Rationale explains why this altitude best captures the design intent; Invalidation is signal-shaped — this is a hard rule: no numeric thresholds, no "if tests fail" circular statements.
6. **Conjunction coverage** (for `/decompose` trees) — children's harness targets jointly cover the parent's harness target coverage. A parent whose Signal covers the full flow must have children whose individual Signals together span that flow.

**Gradient, not proof.** These six criteria grade the Signal as a verification *proxy* — the hillclimbing gradient, not proof the bead is done. Even a perfectly aligned Signal covers only the executable slice of acceptance. Where the bead's acceptance carries prose no Signal can reach, a target whose framing implies green-Signal = acceptance-met is itself a finding: the Signal is necessary, not sufficient (done = harness green AND acceptance met).

## Anti-Patterns

| Signal | Anti-pattern | Fix |
|--------|-------------|-----|
| Accumulating understanding without validating | **Research spiral** | Build a probe, connect to logs, query the DB, reduce to minimal repro |
| Tests pass but feature doesn't work | **Mock trap** | Run the real system, not mocks. Before claiming done, trace what fires when this code runs — callbacks, middleware, observers, event handlers. Require ≥1 integration test with real objects, not mocks. |
| "All tests pass" without executing them | **Claimed done** | Actually run verification before claiming |
| Long session, contradicting earlier decisions | **Context drift** | Re-ground against external state |
| Agent reads its own wrong output as fact | **Context poisoning** | Reality checkpoints against external sources |
| Changes aren't producing new information | **Dead loop** | Redesign the feedback loop — different signal, granularity, or re-ground |

## References

- [references/hierarchy.md](references/hierarchy.md) — Verification hierarchy in depth
- [references/phased-targets.md](references/phased-targets.md) — Evolving targets, checkpoints, contracts
- [references/anti-patterns.md](references/anti-patterns.md) — What goes wrong without a harness
- [references/design-phase.md](references/design-phase.md) — Grounding before code exists
- [references/harness-design.md](references/harness-design.md) — Fowler, LangChain, Spotify Honk, Factory.ai
- [references/sources.md](references/sources.md) — All research sources
