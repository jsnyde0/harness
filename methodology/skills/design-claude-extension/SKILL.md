---
name: design-claude-extension
description: Design Claude Code extension points — skills, MCP servers/tools, CLI tools, subagents, hooks, commands, and plugins. Use when deciding WHICH extension type to build, designing a new MCP server or tool surface, creating a CLI tool for agent use, creating a subagent definition, planning hook-based automation, or structuring a plugin for distribution. Triggers on "should this be a skill or MCP tool", "design an MCP server", "create a subagent", "build an agent definition", "hook pattern", "plugin", "extension point", "which layer should this live in", "build a CLI", "CLI tool", "agent-first CLI", "CLI for agent". Also triggers on "create a skill", "build a skill", "skill for X" — for skill creation, this skill provides the design guidance while marketplace skill-creator:skill-creator provides eval/iteration machinery.
---

# Design Claude Extension

Guide for choosing and designing Claude Code extension points. Start here when building anything that extends Claude's capabilities.

## Extension Point Decision Tree

Ask these questions in order:

**1. Does Claude need to DO an atomic operation?** (call an API, query a DB, navigate a browser, manipulate the file system)
  - **Default: CLI tool**, even when only Claude will use it. A folder of small executables + a short discovery doc usually beats an MCP server. See `references/cli-design.md`.
  - **Escalate to MCP tool when**: the operation needs OAuth/token refresh, long-lived sessions, structured streaming, schema-typed results that benefit non-Claude clients (Cursor, etc.), or you genuinely need cross-client portability through the MCP protocol. See `references/mcp-design.md`.
  - **Heuristic:** *local + no auth + no streaming → CLI. Authenticated SaaS or persistent stateful connection → MCP.*

**1.5. Does this operation need to be portable?** (usable from the terminal by humans, scripts, CI, or non-Claude agents)
  - Yes → **CLI tool** with agent-first design. See `references/cli-design.md`

### Why CLI is the default — the token-cost lens

MCP servers carry a fixed discovery-overhead cost: every tool's schema and description is loaded into context, whether used or not. CLI tools amortize discovery into one short doc the agent reads only when relevant.

A worked example (Zechner, ["What if you don't need MCP?"](https://mariozechner.at/posts/2025-11-02-what-if-you-dont-need-mcp/), 2025-11-02): a 5-script Puppeteer browser-automation toolkit (`start`, `nav`, `eval`, `screenshot`, `pick`) advertised by a ~225-token README replaces Playwright/Chrome-DevTools MCP servers that cost 13,000–18,000 tokens of always-loaded schemas — a ~60× reduction with comparable capability.

CLI also composes better: outputs are files on disk, agents already know how to pipe and chain them, and adding a new tool is "drop a new script in the folder" rather than "extend a server."

**When this lens does NOT apply** — MCP earns its overhead when one of these is true:
- **Cross-client reach** matters: Cursor, Zed, ChatGPT, custom clients all need the same surface. Only MCP delivers protocol-level portability.
- **Long-lived shared state** is required: DB connection pool, websocket subscription, browser session reused across calls, in-memory cache. A CLI-per-invocation has to cold-start every time.
- **Streaming / incremental results** matter. CLI stdout works for batch; MCP gives you proper streaming semantics.
- **The MCP server already exists and is well-maintained** (official Asana, Gmail, Notion servers). Re-implementing in CLI is busywork; just use what's there.

**Auth alone is not a strong reason to choose MCP.** Most OAuth flows are one-time CLI logins (`gh auth login`, `gcloud auth login`, Asana PAT in `.env`) — after that, any CLI script reads the same token from `~/.config/...` or the env. Token *refresh* is more annoying in pure CLI (you'd need a wrapper that writes back the refreshed token), but it's still tractable. Auth is a cost multiplier on a build-vs-reuse decision, not a clean tiebreaker.

For example, integrations like calendar, email, or analytics are often MCP primarily because the servers already exist and offer cross-client value — not because "they have auth." Local file ops, repo introspection, screenshotting, and similar local-only operations belong in skill-documented CLI scripts.

**2. Does Claude need to KNOW how to approach a domain?** (principles, decision frameworks, conditional logic)
  - Yes → **Skill**. See `references/skills-design.md`
  - If the skill has multiple distinct workflows for the same domain → add **Recipes** (`recipes/`). See "The Recipes Pattern" below.

**3. Does Claude need ISOLATION?** (separate context, restricted tools, parallel work)
  - Yes → **Subagent** (`.claude/agents/`). See `references/agents-hooks-plugins.md`

**4. Does the user need a SHORTCUT to trigger a workflow?**
  - Yes → **Command** (`.claude/commands/`). See `references/agents-hooks-plugins.md`

**5. Does an action need to run AUTOMATICALLY on an event?** (every prompt, after edits, on stop)
  - Yes → **Hook** (in `settings.json`). See `references/agents-hooks-plugins.md`

**6. Does this need to be DISTRIBUTED to others?**
  - Yes → **Plugin** (bundles skills + agents + commands + hooks). See `references/agents-hooks-plugins.md`

### Quick Reference

| Extension | What it does | Audience | Persistence |
|-----------|-------------|----------|-------------|
| MCP tool | Atomic operations with schemas | Any MCP client | Always available |
| CLI tool | Portable shell tool, agent-first design | Humans + any agent | Installed binary |
| Skill | Domain knowledge, principles, decision frameworks | Claude Code only | Auto-loaded by description match |
| Recipe | Prescriptive workflows for known scenarios | Claude Code only | On-demand from skill's `recipes/` |
| Subagent | Isolated context, restricted tools | Claude Code only | Spawned on demand |
| Command | Slash-command shortcut | Claude Code only | Manual invocation |
| Hook | Event-driven automation | Claude Code only | Runs on every matching event |
| Plugin | Distribution bundle | Claude Code only | Installed from marketplace |

## Visibility Matrix

Critical constraint — not all contexts see all extension types:

| Context | Skills | MCP tools | Server instructions | Hooks |
|---------|:------:|:---------:|:-------------------:|:-----:|
| Main conversation | Yes | Yes | Yes | Yes |
| Custom subagents | **Only if listed in `skills:` field** | Yes | Yes | Yes |
| Built-in agents (Explore, Plan) | **Never** | Yes | Yes | Yes |
| Other MCP clients (Cursor, etc.) | **Never** | Yes | Yes | No |

**Implication:** If your knowledge must reach subagents or non-Claude-Code clients, it cannot live only in a skill. Use the layered approach below.

## The Knowledge Architecture

```
Layer 4: Recipes         → Claude Code only, prescriptive workflows (~1-2k tokens on-demand)
Layer 3: Skills          → Claude Code only, generalized knowledge & principles (~5k tokens on-demand)
Layer 2: Server instructions + docstrings → any MCP client (~800 tokens always loaded)
Layer 1: MCP tools       → any client, atomic operations (~550-1400 tokens/tool)
```

**Rule of thumb:** Tools do things. Instructions teach basics. Skills teach how to think. Recipes tell you what to do.

Figma pattern: skills for Claude Code power users; good tool descriptions for everyone else. This two-tier approach gives deep guidance to your best client and baseline guidance to all others.

## Description Engineering

Applies to skills, subagents, MCP tools — anything that Claude selects by matching descriptions.

**Description quality is the #1 determinant of reliable triggering.** Generic descriptions fail.

### WHEN / WHEN NOT pattern

```yaml
description: >
  Stakeholder context for Project X when discussing product features,
  UX research, or stakeholder interviews. Auto-invoke when user mentions
  Project X, product lead, or UX research. Do NOT load for general
  stakeholder discussions unrelated to Project X.
```

### For skills — be "pushy" with triggers

Include explicit user phrases: "Use when user says 'make a skill', 'build a skill', 'skill for X'". List file types, tool names, and domain terms that should trigger loading.

### For MCP tool docstrings — use WHEN/WHAT/NEXT format

```
Find which geographic areas have POI data in a region. Use this BEFORE
mpoi_fetch to select specific areas (e.g., the partition containing Berlin).
Returns partition IDs needed by mpoi_fetch's h3l3 parameter, plus center
coordinates for matching to known locations.
```

### Debug tip

Ask Claude: "When would you use the [name] skill?" — it quotes the description back, revealing what's missing.

## Progressive Disclosure

Keep token costs low by loading content only when needed:

| Level | What loads | Token cost | Content |
|-------|-----------|------------|---------|
| L1: Metadata | Always (session start) | ~100/skill | YAML frontmatter only |
| L2: Instructions | On trigger | <5k tokens | SKILL.md body (generalized knowledge) |
| L3: Recipes | On demand | ~1-2k/recipe | `recipes/` files (prescriptive workflows) |
| L4: Resources | On demand | Unlimited | `references/` files, scripts |

**The 500-line rule:** Individual files over ~500 lines hit context limits. Split into a main file (<500 lines, high-level overview) plus focused resource files (<500 lines each).

**Scripts as resources:** Bundle executable scripts in `scripts/`. Only the output enters context — the code itself never consumes tokens.

## The Recipes Pattern

Separate **generalized knowledge** from **prescriptive workflows** using a recipes layer. This is the "roles vs playbooks" pattern proven across Ansible, Terraform, GitHub Actions, Chef, and API documentation (Diataxis framework).

### The principle

| Layer | Contains | Analogy |
|-------|----------|---------|
| SKILL.md body | Principles, mental models, decision-making guidance | Ansible role / Terraform module / Diataxis "explanation" |
| recipes/ | Step-by-step workflows for known scenarios | Ansible playbook / Terraform root config / Diataxis "how-to guide" |
| Tools (MCP/CLI) | Atomic operations, no workflow opinions | Ansible tasks / Terraform resources |

**Tools do things. Skills teach how to think. Recipes tell you what to do for a specific situation.**

### When to use recipes

Add a `recipes/` folder when a skill or tool surface has **multiple distinct workflows** that compose the same building blocks differently. Signs you need recipes:

- The SKILL.md mixes "understand this" with "now do step 1, step 2, step 3"
- Different scenarios require different sequences of the same tools
- Users keep asking "but what do I do for X specifically?"

### Skill structure with recipes

```
skills/ship-to-prod/
  SKILL.md              ← generalized: what makes a safe release, what to check, principles
  recipes/
    dev-to-main-pr.md   ← prescriptive: PR-based release from dev to main
    hotfix.md           ← prescriptive: emergency hotfix directly to main
  references/           ← deep reference material (unchanged)
  scripts/              ← executable helpers (unchanged)
```

SKILL.md includes an **Available recipes** index so the agent sees the menu:

```markdown
## Recipes
- `recipes/dev-to-main-pr.md` — Standard release: dev → main via PR with migration checks
- `recipes/hotfix.md` — Emergency fix directly to main, skip staging
```

The agent picks a recipe when one fits, or improvises from generalized knowledge when none does.

### Design rules for recipes

Drawn from Ansible, Terraform, Chef, and GitHub Actions ecosystems:

1. **Recipes compose blocks; blocks don't know about recipes.** Tools and SKILL.md knowledge should never assume which recipe called them. Context flows downward (recipe → blocks), never upward.

2. **Flat composition over deep nesting.** A recipe should wire together blocks horizontally. If a recipe calls another recipe which calls another recipe, the abstraction is too deep — flatten it.

3. **Context-specific values live in recipes, not blocks.** Environment names, branch conventions, deployment targets — these belong in recipes. The generalized SKILL.md and tools stay portable.

4. **Simple and many beats configurable and few.** Two simple recipes are better than one recipe with a `mode` parameter. Over-parameterization is the #1 pitfall across all ecosystems studied.

5. **Recipes are disposable; knowledge is durable.** Recipes change when workflows change. The generalized SKILL.md should remain stable even as recipes are added, removed, or rewritten.

### Applies to tools too

MCP servers and CLI tools can also benefit from recipes — common composition patterns documented alongside the tools:

```
mcp-servers/geo-tools/
  server.py             ← tools: fetch, deduplicate, export (atomic, composable)
  recipes/
    country-analysis.md ← "fetch by country → deduplicate → export as GeoJSON"
    city-comparison.md  ← "fetch multiple cities → cross-deduplicate → compare"
```

This keeps tools simple and composable while still giving the agent (or human) ready-made patterns for known use cases.

## Rule-shape vs Signal-shape Guidance

A cross-cutting question for any extension authoring **text-for-an-agent** — skills, subagent prompts, recipes, and (partially) MCP tool descriptions. Hooks, commands, and plugin manifests are deterministic substrates, not text-for-judgment, so this section doesn't apply to them.

- **Rule-shape** prescribes the answer: "must X before Y", "fail if Z > 10%."
- **Signal-shape** names what to attend to and lets the agent judge: "watch for X surfacing", "if a slot grew during refinement, consider splitting", "would you contradict this in some real case?"

**Default to signal-shape.** Rules fire confidently in cases the author didn't anticipate; the author rarely understands a rule's full firing surface at write-time; rules cap the agent at the author's foresight while signals appreciate as models improve.

**Asymmetric default:** for *positive directives*, signal-shape. For *negative/avoidance guardrails* with catastrophic failure modes, rule-shape is more often earned. ([Do Agent Rules Shape or Distort?, arXiv 2604.11088](https://arxiv.org/abs/2604.11088): negative constraints shape; positive directives distort.)

**Tool descriptions are the worked exception** — they pass the rule-shape test (catastrophic-if-Claude-picks-wrong, well-understood firing surface, smarter models still benefit from precise type info). Most skill body content does not.

See `references/rule-vs-signal.md` for the three-part test for when rule-shape is earned, the substrate-rigidity match question, signal-shape patterns (countermand, watch-for, growth-triggered, attention-anchor), and anti-patterns (falsifiability theater, rigidity-substrate mismatch, out-ruling the model, too-vague-to-fire signals, author-info loss).

## Cross-Cutting Knowledge Problem

Some knowledge spans multiple extension points and doesn't belong to any single MCP server:
- Entity deduplication patterns (applies to any dataset)
- H3 spatial indexing utilities (applies to any geo workflow)
- Data quality heuristics (applies to any POI analysis)

**Current approach:** Keep these as Claude Code skills. Accept that they're invisible to subagents unless explicitly listed in agent definitions, and invisible to non-Claude-Code clients entirely. When MCP prompt client support matures, consider publishing as protocol-native prompts.

## Skill Creation Workflow

When the answer to the decision tree is "skill":

1. Apply the design guidance from this skill (decision tree, description engineering, progressive disclosure)
2. Invoke the marketplace `skill-creator:skill-creator` via the Skill tool — it provides eval/iteration machinery (test runners, grading, benchmark viewer, description optimization)
3. Consult `references/skills-design.md` for skill-specific patterns, categories, and troubleshooting

## References

- `references/skills-design.md` — Skill categories, design patterns, troubleshooting, success criteria
- `references/mcp-design.md` — MCP tool design principles, three-layer architecture, industry patterns, security, anti-patterns
- `references/cli-design.md` — Agent-first CLI design, 7-axis evaluation framework, wrapping CLIs as MCP tools
- `references/agents-hooks-plugins.md` — Subagent design, hook-based activation, commands, plugin distribution
- `references/rule-vs-signal.md` — Rule-shape vs signal-shape guidance for text-for-an-agent content (skills, subagent prompts, recipes); three-part test, substrate-match question, patterns, anti-patterns
