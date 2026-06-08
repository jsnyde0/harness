# ADR-001: Minimal Pi subagent subprocess primitive

Date: 2026-04-27
Originated from: the pi subagent subprocess primitive design bead

## Status

Accepted (revised 2026-06-03 — D2 and D3 evolved by ADR-002; see those decisions)

## Context

Pi needs a small delegation primitive for future workflow skills such as `review-v2`, `beadify-v2`, and `implement-v2`. The desired capability is fresh-context subprocess execution with bounded, parseable results. Prior exploration considered agent definitions and Claude-agent-style role ports, but those would pull in unported skills, registry/trust questions, and prompt-maintenance complexity before the primitive itself exists.

## Decisions

### D1: Build `subagent` as a minimal subprocess runner, not a platform

- **Firmness:** FIRM
- **Decision:** Implement a single Pi extension/tool named `subagent` that spawns child Pi processes for delegated tasks and returns structured results.
- **Rationale:** The immediate missing capability is fresh-context delegated execution, not a full multi-agent platform. Staying close to Pi's subprocess-example shape minimizes surface area while preserving the high-value workflow primitive.
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | Build a full subagent platform with registry, UI, background jobs, steering, and worktrees | More complete long-term multi-agent system | **Rejected** — reasoned: overbuilds before the workflow primitive is proven and introduces many trust/lifecycle problems unrelated to the first use cases. |
  | Depend on Claude Code-style `Task()`/MCP behavior | Familiar from prior Claude workflow | **Rejected** — direct: this is a Pi-native extension design; Pi should not assume Claude-specific APIs exist. |

- **What would invalidate this:** Repeated real usage shows most value comes from durable/interactive/background subagents rather than bounded fresh-context calls.

### D2: Role briefs may be inline OR loaded from a named-role registry

- **Firmness:** EXPLORATORY (revised 2026-06-03 — was FIRM "no registry"; the no-registry stance was never actually firm for the author, and ADR-002 D3 introduces the cross-harness role library)
- **Decision:** Callers may pass the full role brief inline in `task` (the original MVP behavior, unchanged), **or** pass a `role` name that the extension resolves from a shared role-brief library (`~/.pi/agent/roles/<name>.md`) and expands — reading+inlining the role's named skills, applying its `model`/`tools`/`output-contract`, and prepending its brief to the caller's task. The role-loader is **additive**; inline-only continues to work.
- **Rationale:** The original "inline-only" call was warranted while no roles were ported and a registry meant trust/discovery complexity. That cost is now paid down by ADR-002's cross-harness goal: a single shared role library is consumed by *both* Claude Code (the methodology home's agents directory) and pi (this loader), so the roles must be named files, not inline strings. ADR-001 D2's own invalidation condition ("inline briefs become repetitive enough that prompt drift dominates") is the trigger that has now fired.
- **Note:** project-local untrusted agent files are still NOT auto-read; the shared role library is author-controlled, not project-controlled (D6's trust boundary is preserved).
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | Port `implementer`, `code-reviewer`, `reviewer`, and `plan-writer` as initial Pi agents | Mirrors prior Claude workflow roles | **Rejected** — direct: the available dotclaude agent files are broken symlinks, and their likely skill dependencies have not been ported. |
  | Keep official example-style markdown agent discovery | Already exists in Pi example and supports reusable roles | **Rejected** — reasoned: project-controlled prompt discovery creates trust policy work and registry semantics that are non-essential to the first primitive. |

- **What would invalidate this:** Inline role briefs become repetitive enough that prompt drift or call-site verbosity dominates maintenance cost.

### D3: Prefer explicit provider/model slugs; `modelTier` retained as optional sugar

- **Firmness:** EXPLORATORY (revised 2026-06-03 — was FIRM "modelTier primary"; superseded as primary mechanism by ADR-002 D4)
- **Decision:** The primary selection mechanism is an **explicit provider/model slug** (`anthropic/claude-sonnet-4.5`, `openai/gpt-5.5`, `moonshotai/kimi-k2.6`), which pi's `--model` resolves verbatim. `modelTier` (`basic`/`medium`/`smart`/`max`) remains available as optional sugar but is no longer the default expectation, and `model` is no longer "escape hatch only."
- **Rationale:** The substrate is now deliberately multi-provider with **per-role model routing as a first-class feature** (ADR-002 D3/D4) — a review role pins Sonnet, an execute role pins Kimi, a brain role pins GPT-5.5. Explicit slugs make that routing honest and pi resolves them natively; the original "don't bake provider IDs into reusable skills" rationale is outweighed once cross-provider routing is the point. See ADR-002 D4 for the full warrant.
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | Use concrete model strings directly in workflow calls | Simple to implement and explicit | **Rejected** — reasoned: bakes local provider/model names into reusable workflow skills and makes future model migration noisy. |
  | Use role-based tiers such as `reviewer` and `implementer` | Matches workflow roles | **Rejected** — reasoned: role is carried by `label`/`task`; tier should encode capability and budget, not job identity. |

- **What would invalidate this:** Pi model configuration gains a native alias system that already solves capability-tier mapping better than extension-local config.

### D4: Support final-line contract validation in the tool

- **Firmness:** FIRM
- **Decision:** Add `expectedFinalLine` and `expectedFinalLinePattern` parameters. The tool validates the last non-empty assistant line and marks contract failures explicitly.
- **Rationale:** Workflow orchestration needs parseable handoff signals such as `VERDICT: PASS` / `VERDICT: FAIL`. Enforcing this in code is more reliable than relying on prompt compliance alone.
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | Ask prompts to end with a specific line but do not validate | Minimal implementation | **Rejected** — reasoned: prompt-only contracts fail silently, which undermines automated review/implementation gates. |
  | Parse rich JSON result schemas from subagents | More expressive contract surface | **Rejected** — reasoned: too much schema complexity for the MVP; final-line checks capture the immediate gate semantics. |

- **What would invalidate this:** Future workflows need multi-field machine-readable outputs often enough that final-line contracts become a bottleneck.

### D5: Include bounded parallel execution but no background jobs

- **Firmness:** FIRM
- **Decision:** Support both single `task` and bounded parallel `tasks[]` calls with maximum task and concurrency caps. Do not support durable background jobs, result polling, or steering in the MVP.
- **Rationale:** Parallel fresh-context review/scouting is high leverage for workflow skills, while background lifecycle management would significantly expand implementation and UX complexity.
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | Single-task only MVP | Simplest implementation | **Rejected** — reasoned: parallel review fanout is a core 80/20 use case and is already close to the official subprocess example. |
  | Durable background jobs with later result retrieval | Useful for long-running tasks | **Rejected** — reasoned: introduces job registry, persistence, steering, and cleanup policy before there is proven need. |

- **What would invalidate this:** Child tasks routinely exceed interactive time budgets and need parent sessions to continue independently.

### D6: Default to least-privilege tool allowlists and no project-controlled prompt surface

- **Firmness:** FIRM
- **Decision:** Default child tools are read-ish (`read`, `grep`, `find`, `bash`); mutating tools such as `edit` and `write` must be explicitly passed. Because there is no agent registry in MVP, project-controlled agent prompt files are not read.
- **Rationale:** Subprocess isolation and fresh context are only useful if the child is also bounded by narrow tools and avoids untrusted prompt-surface expansion.
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | Give child Pi the parent's full tool set by default | Maximizes capability and convenience | **Rejected** — reasoned: violates least privilege and makes review/scout subagents unnecessarily risky. |
  | Allow project `.pi/agents/*.md` immediately with confirmation | Enables per-project roles | **Rejected** — reasoned: useful later, but not needed when inline task briefs are the MVP and trust semantics can wait. |

- **What would invalidate this:** Pi's subprocess tool restriction flags cannot express the intended allowlist, forcing a different safety boundary.

## Consequences

- Workflow skills can call `subagent` with inline role briefs before any Claude-style agents or skills are ported.
- The extension remains small and close to Pi's official subprocess example.
- Call sites may be more verbose initially because role prompts are inline.
- Future agent-registry work remains possible but is not coupled to the MVP.

## Implementation notes

- Extension path: `agent/extensions/subagent/index.ts`.
- Tool name: `subagent`.
- Child command shape: `pi --mode json -p --no-session` plus resolved model/thinking/tools flags where supported.
- Config path: `~/.pi/agent/extensions/subagent/config.json` with extension defaults in source.
- Initial defaults: `defaultModelTier: medium`, read-ish default tools, `maxParallelTasks: 8`, `maxConcurrency: 4`, `timeoutMs: 600000`.
