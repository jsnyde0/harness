# Skills Design Reference

Source: "The Complete Guide to Building Skills for Claude" (Anthropic, January 2026).
This file supplements the marketplace `skill-creator:skill-creator` — fundamentals, folder structure, YAML frontmatter, and testing/eval workflows are handled there.

---

## Use Case Categories

Before designing a skill, identify which category it falls into — this shapes your approach.

**Category 1: Document & Asset Creation** — Creating consistent, high-quality output (documents, presentations, apps, designs, code).
Key techniques: embedded style guides, template structures, quality checklists before finalizing. Typically uses Claude's built-in capabilities, no external tools required.

**Category 2: Workflow Automation** — Multi-step processes that benefit from consistent methodology, including coordination across multiple MCP servers.
Key techniques: step-by-step workflow with validation gates, templates for common structures, built-in review and improvement suggestions, iterative refinement loops.

**Category 3: MCP Enhancement** — Workflow guidance to enhance the tool access an MCP server provides.
Key techniques: coordinates multiple MCP calls in sequence, embeds domain expertise, provides context users would otherwise need to specify, error handling for common MCP issues.

## Problem-first vs. Tool-first Framing

Think of it like Home Depot — you might walk in with a problem ("I need to fix a kitchen cabinet") or pick out a tool and ask how to use it.

- **Problem-first:** "I need to set up a project workspace" → Skill orchestrates the right MCP calls in the right sequence. Users describe outcomes; the skill handles the tools.
- **Tool-first:** "I have Notion MCP connected" → Skill teaches Claude optimal workflows and best practices. Users already have access; the skill provides expertise.

Most skills lean one direction. Knowing which framing fits your use case helps choose the right pattern below.

## Design Patterns

> **Skill vs. recipe distinction:** A skill encodes durable principles and mental models — the "how to think" layer. A recipe encodes a specific workflow for a known scenario — the "what to do" layer. Patterns 1-2 below describe recipe shapes; your SKILL.md should teach the principles, not embed the step-by-step workflow. Put concrete ordered workflows in `recipes/`.

### Pattern 1: Sequential Workflow Orchestration *(recipe shape)*

**Use when:** Multi-step processes must run in a specific order with dependencies between steps.

This is a **recipe**, not skill content. Your SKILL.md should explain *when* sequential ordering matters and *why* (dependencies, rollback risk, state passing). The actual steps belong in a recipe file.

Key principles to encode in SKILL.md: when to enforce ordering vs. allow parallelism, how to pass state between steps, what warrants a rollback instruction, where validation gates add value vs. add noise.

### Pattern 2: Multi-MCP Coordination *(recipe shape)*

**Use when:** A workflow spans multiple services (e.g. Figma → Drive → Linear → Slack handoff).

This is a **recipe**, not skill content. Concrete service names, phase sequences, and data-passing specifics belong in `recipes/`. Multiple services means context-specific values (folder names, team assignments, channel names) that have no place in a generalized skill.

Key principles to encode in SKILL.md: phase separation to isolate failures, validation before advancing phases, where to centralize error handling, how to surface data dependencies between MCPs explicitly.

### Pattern 3: Iterative Refinement

**Use when:** Output quality improves through multiple passes rather than a single generation.

Key techniques: Define explicit quality criteria upfront (not "good enough" — what passes and what doesn't). Build a validate-then-refine loop. Know your stopping condition before you start. Consider a validation script for deterministic checks rather than relying on LLM judgment alone.

> **See also:** `references/rule-vs-signal.md`. "Explicit quality criteria" leans rule-shape — earned for stopping conditions and binary checks, but watch for falsifiability theater (numeric thresholds with no instrumentation). For criteria that need counting or measurement, the validation script *is* the substrate-match; for fuzzy quality calls, signal-shape often fits better.

### Pattern 4: Context-aware Tool Selection

**Use when:** The same outcome is achievable via different tools, and the right choice depends on context.

Key techniques: Make the decision criteria explicit (file size, access pattern, collaboration needs). Provide fallback options. Be transparent with the user about *why* a tool was chosen — it builds trust and allows correction.

### Pattern 5: Domain-specific Intelligence

**Use when:** The skill's value is embedded knowledge, not just tool orchestration.

Key techniques: Domain rules should gate actions, not follow them (check before acting). Document compliance decisions at the time of decision, not after. Separate the "should I do this?" layer from the "how do I do this?" layer. For high-stakes domains, consider bundling a validation script — code is deterministic where language instructions are not.

> **See also:** `references/rule-vs-signal.md`. The "validation script" advice is the substrate-match question: rules that need counting/measurement need a deterministic substrate. But not all "domain rules" are rule-shape — many are better expressed as signal-shape attention-anchors. Default signal; use rules when the three-part test passes (catastrophic failure mode, well-understood firing surface, doesn't benefit from a smarter model).

## Success Criteria

Aspirational targets — rough benchmarks rather than precise thresholds.

**Quantitative:**
- Skill triggers on 90% of relevant queries (run 10-20 test queries, track auto-load vs. explicit invocation)
- Completes workflow in X tool calls (compare with/without skill enabled)
- 0 failed API calls per workflow (monitor MCP server logs during test runs)

**Qualitative:**
- Users don't need to prompt Claude about next steps
- Workflows complete without user correction (run same request 3-5 times, compare consistency)
- A new user can accomplish the task on first try with minimal guidance

## Troubleshooting

**Skill won't upload:**
- "Could not find SKILL.md" → File must be exactly `SKILL.md` (case-sensitive)
- "Invalid frontmatter" → Check `---` delimiters, proper YAML syntax
- "Invalid skill name" → Must be kebab-case, no spaces or capitals

**Skill doesn't trigger:**
- Revise description field. Debug by asking Claude "When would you use the [skill name] skill?" — it will quote the description back, revealing gaps.
- Checklist: Is description too generic? Does it include trigger phrases users would actually say? Does it mention relevant file types?

**Skill triggers too often:**
- Add negative triggers (e.g., "Do NOT use for simple data exploration (use data-viz skill instead)")
- Be more specific in description, clarify scope

**Instructions not followed:**
- Too verbose → Keep concise, use bullet points and numbered lists, move detail to references/
- Instructions buried → Put critical instructions at the top, use ## Important or ## Critical headers
- Ambiguous language → Be specific (e.g., "Before calling create_project, verify: Project name is non-empty, At least one team member assigned")
- Model "laziness" → Add explicit encouragement: "Take your time to do this thoroughly" (note: adding this to user prompts is more effective than in SKILL.md)
- For critical validations, consider bundling a script rather than relying on language instructions — code is deterministic. (See `references/rule-vs-signal.md`: this is substrate-match — earned for genuinely mechanical checks, but watch for falsifiability theater when the script doesn't actually exist.)

**Large context issues:**
- Move detailed docs to references/, link instead of inline
- Keep SKILL.md under 5,000 words
- If >20-50 skills enabled simultaneously, consider selective enablement or skill "packs"

## Skills via API

For programmatic use cases (building applications, agents, automated workflows):
- `/v1/skills` endpoint for listing and managing skills
- Add skills to Messages API requests via `container.skills` parameter
- Version control and management through the Claude Console
- Works with the Claude Agent SDK for building custom agents
- Skills in the API require the Code Execution Tool beta

**Cross-surface warning:** Skills do NOT sync across surfaces. Claude.ai skills are NOT available via API. API skills are NOT available on Claude.ai. Claude Code skills are filesystem-based and separate from both.

## Quick Checklist

**Before you start:** 2-3 concrete use cases identified, tools identified (built-in or MCP), reviewed patterns above, planned folder structure.

**During development:** Kebab-case folder, SKILL.md exists (exact spelling), YAML frontmatter with `---`, name in kebab-case, description includes WHAT and WHEN, no XML tags anywhere, clear actionable instructions, error handling included, examples provided, references clearly linked.

**Before upload:** Tested triggering on obvious tasks, tested triggering on paraphrased requests, verified doesn't trigger on unrelated topics, functional tests pass, tool integration works (if applicable).

**After upload:** Test in real conversations, monitor for under/over-triggering, collect user feedback, iterate on description and instructions, update version in metadata.
