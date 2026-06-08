# Harness Design Patterns

## Fowler's Framework: Guides and Sensors

**Agent = Model + Harness.** The harness has two control mechanisms:

- **Guides (feedforward):** Anticipatory controls that steer before action. Context, conventions, instructions provided upfront. CLAUDE.md, AGENTS.md, system prompts, tool schemas.
- **Sensors (feedback):** Observation after generation that triggers self-correction. Linter output, test failures, diff analysis, type errors.

Three regulatory dimensions:
1. **Maintainability harness** — code quality (linting, formatting, complexity)
2. **Architecture fitness harness** — performance, observability, design constraints
3. **Behavior harness** — functional correctness (the least developed)

## LangChain's Middleware Pipeline (+13.7 points, zero model changes)

Four middleware components that wrap agent actions:

**LocalContextMiddleware:** Runs at startup. Maps working directory, discovers tools, injects directory structure into context. Prevents agents from wasting effort discovering their environment.

**LoopDetectionMiddleware:** Tracks per-file edit counts via tool call hooks. After N edits to the same file, injects: "consider reconsidering your approach." Catches agents stuck in repetitive failure patterns (commonly 10+ identical edits).

**PreCompletionChecklistMiddleware:** Intercepts before task completion. Forces verification pass against task spec. Prevents agents from marking "done" based on compilation rather than actual test success.

**Reasoning Sandwich:** Variable reasoning budgets — xhigh for planning, high for implementation, xhigh for verification. Performance: 66.5% vs 53.9% at constant xhigh.

## Spotify Honk Architecture

**Content-driven verifier activation:** Verifiers trigger based on project contents, not agent choice. Agent is unaware which verifiers exist.
- `pom.xml` → Maven verifier
- `package.json` → Node verifier
- `go.mod` → Go verifier

**Deterministic verifier pipeline:** Format/lint → build → test. Each runs independently, in sequence. Output parsed via regex — only relevant errors surface to the agent.

**Three-state feedback:**
1. **Pass** → short success message
2. **Recoverable failure** → specific error + code location
3. **Unrecoverable failure** → escalate to human (after retry limit)

**LLM-as-judge (secondary):** Evaluates diffs against original prompt. Catches scope violations. Vetoes ~25% of sessions. Agents self-correct ~50% after rejection.

**Scale:** 1,000+ merged PRs every 10 days. 60-90% time savings.

## Factory.ai: Linters as Executable Architecture

Seven lint rule domains that encode architecture directly:
1. **Grep-ability** — Named exports (no default) → `ripgrep` can find code
2. **Glob-ability** — Predictable file organization → agents place code deterministically
3. **Architectural boundaries** — Module isolation via import allowlists/denylists
4. **Security/Privacy** — Block secrets, require validation, prevent unsafe functions
5. **Testability** — Colocate tests, enforce async patterns
6. **Observability** — Structured logging with metadata standards
7. **Documentation signals** — TSDoc comments, ADR links

"Achieving 'lint green' becomes the definition of Done."

## Meta-Harness: Automatic Harness Optimization

Harnesses themselves can be optimized automatically:
- Filesystem-based history: full harness candidates, execution traces, scores
- Agentic proposer: coding agent reads history, proposes new harnesses
- Results: Claude Opus 4.6 76.4% (vs hand-engineered 74.7%), Haiku 4.5 37.6% (#1 among all published solutions)

Key insight: richer access to prior experience enables more effective harness engineering than scalar feedback.

## OpenDev: Scaffolding vs. Runtime

**Scaffolding (pre-execution construction):**
- System prompts and tool schemas built at initialization
- SubAgent specs with filtered tool access
- Three-phase factory: skills discovery → subagent compilation → main agent construction

**Harness (runtime orchestration):**
- Extended ReAct loop: pre-check → thinking → self-critique → action → execution → post-processing
- Dual-mode: Plan Mode (read-only) vs Normal Mode (read-write)

**Context engineering (four subsystems):**
1. Dynamic prompt composition — priority-ordered conditional sections
2. Adaptive context compaction — five-stage progressive compression
3. Dual-memory — episodic (conversation) + working (immediate)
4. Tool result optimization — per-tool summarization and large-output offloading

## HumanLayer's Practical Findings

**What works:**
- Start simple; add harness on actual failure
- Sub-agents as "context firewalls" for complex problems
- Surface failures, silence successes
- Hooks for control flow without polluting agent context

**What doesn't work:**
- Auto-generating CLAUDE.md files (underperform)
- Pre-installing MCP servers/skills
- Running full test suites after every agent action
- "Frontend engineer" + "backend engineer" sub-agent split
- Designing ideal configurations theoretically before real failures

Mitchell Hashimoto: "Anytime you find an agent makes a mistake, engineer a solution so it never makes that mistake again."

## Progressive Disclosure

Don't overload agents upfront. Reveal capabilities selectively based on context. The agent doesn't need to know about all verification options — surface the relevant one when it matters.
