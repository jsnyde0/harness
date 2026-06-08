# MCP Server & Tool Design Reference

**Status:** Exploratory — patterns observed as of March 2026, expect to evolve
**Sources:** design brainstorms + industry research

This is a cheat sheet, not a rulebook. The MCP ecosystem is young and best practices are still forming. Consult when designing MCP tools, companion skills, or deciding what belongs where.

## The Four Layers

| Layer | Audience | Scope | Example |
|---|---|---|---|
| **MCP tools** | Any MCP client (Claude Code, Cursor, VS Code, custom apps) | Atomic operations with rich schemas | `mpoi_fetch`, `query`, `create_mapbook` |
| **Server instructions + docstrings** | Any MCP client (injected automatically) | Cross-tool workflow hints, per-tool guidance | "Use mpoi_fetch BEFORE query to get data files" |
| **Claude Code skills** | Claude Code only | Generalized knowledge, principles, decision frameworks, mental models | `mpoi-analysis`, `mapbook-admin`, `entity-dedup` |
| **Recipes** | Claude Code only | Prescriptive step-by-step workflows for known, specific scenarios | "Deploy hotfix to prod", "Onboard new dataset" |

**Rule of thumb:** Tools do things. Instructions/docstrings teach basics. Skills teach how to think. Recipes tell you exactly what to do.

Recipes compose tools and apply skill knowledge to a concrete situation. They're disposable and context-specific — when the scenario changes, replace the recipe, not the tools or skill.

## When to Use Each

### Put it in an MCP tool when:
- It's an atomic operation any agent should access
- It needs structured input/output (schemas, validation)
- It interacts with external systems (DB, API, file system)

### Put it in server instructions when:
- It's cross-tool workflow guidance (~200 words max)
- It helps any MCP client, not just Claude Code
- Example: "This server provides POI data tools. For analysis, install the companion geo MCP server."

### Put it in tool docstrings when:
- It's specific to one tool's usage
- Use **WHEN/WHAT/NEXT** format:
  - **WHEN** to use this tool in a workflow
  - **WHAT** outcome it produces
  - **NEXT** what to do after calling it

### Put it in a Claude Code skill when:
- It captures generalizable knowledge, principles, or decision frameworks
- It requires domain expertise beyond what docstrings can convey
- It needs conditional logic ("if X, do Y; otherwise Z")
- It's a multi-step pattern that agents consistently get wrong without guidance

### Put it in a recipe when:
- It's a concrete, step-by-step workflow for a known, recurring scenario
- Context-specific values (env names, file paths, flags) are baked in
- The workflow composes tools without the tools needing to know about each other
- You'd otherwise write the same instructions repeatedly in different conversations

## MCP Tool Design Principles

### Tools are building blocks, not workflows

MCP tools should be composable primitives — they do one thing well without encoding opinions about what comes before or after. Workflow logic belongs in recipes or skills, not in tools.

**Signs a tool has leaked workflow assumptions:**
- It calls other tools internally to "help" the agent
- Its name implies a sequence ("first_fetch_then_filter")
- Its behavior changes based on assumed prior tool calls
- Its docstring says "always call X first" (put that in a recipe or skill instead)

Tools that are free of workflow opinions can be composed in any order, reused across recipes, and called from any MCP client — not just Claude Code.

### Fewer, outcome-oriented tools > many fine-grained tools

**Evidence:**
- Queen's University research: thin API wrappers require **5.3x more tool invocations**
- Notion V1 (28+ tools, 1:1 API mapping) → V2 (6 consolidated tools): dramatically better agent performance
- Each tool costs **550-1,400 tokens** for its schema; 15 tools can consume 15-20K tokens before the agent starts working

**Guideline:** 5-8 tools per server. If you need more, consider dynamic discovery (Speakeasy pattern) or splitting into multiple servers.

**Philipp Schmid (Hugging Face):** Instead of `get_order()` + `get_tracking()` + `get_customer()`, expose one `track_order(email)` that returns what the agent actually needs. Design around agent outcomes, not your API surface.

### Token-efficient I/O

- Return summaries and structured text, not raw JSON blobs (Notion's Markdown I/O pattern)
- "Found 47 POIs: restaurants (23), cafes (12), parks (8)" > dumping 47 GeoJSON features
- Include diagnostic metadata in responses (row count, bounds, columns) so agents don't need a separate `describe` tool

### Error messages are agent UX

Instead of "400 Bad Request", return:
```
Error: Value 'coffee_shop' not found in overture_group_secondary.
Did you mean: cafe, coffee, tea_house?
Load the mpoi-config skill for filter discovery.
```

Include: what went wrong, whether it's retriable, and what to try instead.

### Tool description = agent instruction

Every piece of text in a tool schema is part of the agent's context. Treat descriptions as direct instructions, not documentation for humans.

**Bad:** "List H3L3 partitions for an MPOI region with center coordinates and row counts."

**Good:** "Find which geographic areas have POI data in a region. Use this BEFORE mpoi_fetch to select specific areas (e.g., the partition containing Berlin). Returns partition IDs needed by mpoi_fetch's h3l3 parameter, plus center coordinates for matching to known locations."

### Defense in depth

Validate at multiple layers — skill guides correct usage, MCP tool validates inputs, HTTP API enforces security. Redundancy prevents silent failures.

## Industry Patterns Worth Knowing

### Notion (best documented evolution)
- V1: 1:1 REST-to-MCP mapping, raw JSON I/O → poor agent performance, token bloat
- V2: 6 high-level tools, Markdown I/O, single-call complex object creation
- Lesson: **Agents struggle with multi-step object assembly.** One tool with a rich input schema beats a sequence of fine-grained tools.

### Mapbox (two-server split)
- Data server: geocoding, directions, isochrones (consumption)
- DevKit server: token management, style creation (building)
- Lesson: **Data consumption and platform building are different audiences** with different tool shapes.

### CARTO (workflow-as-tool)
- Users publish multi-step Workflows (200+ spatial components) as single MCP tools
- Agent calls "site selection analysis," not "buffer + join + filter"
- Lesson: **Expose composed workflows as tools** when the pattern is stable and commonly needed.
- **Composability nuance:** This works because the composed workflow is itself an atomic, reusable unit with a clear input/output contract — not because the tool encodes incidental workflow opinions. The distinction: a "site_selection_analysis" tool is a legitimate high-level primitive; a "fetch_then_filter_for_berlin" tool is a leaked recipe. When in doubt, ask whether this workflow composition belongs in a recipe (disposable, context-specific) or truly warrants a permanent tool.

### Block ("MCP is UI for a non-human user")
- Apply product thinking to tool descriptions
- Treat tool schemas like you'd treat a user interface — clear labels, sensible defaults, helpful errors

### Figma (Skills alongside MCP)
- Ships Claude Code skills (SKILL.md) alongside MCP server
- Skills for Claude Code power users; tools-only with good descriptions for everyone else
- Lesson: **Two-tier approach** — deep guidance for your best client, baseline for all others.

### AWS Strands (SOPs as prompts)
- Registers markdown playbooks as MCP prompts
- Lesson: **Workflow knowledge can be protocol-native**, not just in skills. Worth revisiting when MCP prompt client support matures.

### Cloudflare Code Mode (radical minimalism)
- 2 tools: `search()` + `execute()`. Agent writes TypeScript against generated SDK.
- 32-81% token reduction vs direct tool calling
- Lesson: **Interesting extreme** but requires sandboxed execution. Not practical for most servers.

### Speakeasy Dynamic Toolsets (progressive discovery)
- Meta-tools let agents discover available tools on demand
- 96% input token reduction for large API surfaces
- Lesson: **Escape hatch if tool count grows beyond ~15.** Not needed at 5-8 tools per server.

## Security Patterns

- **HTTP API as security boundary**: MCP server calls your API, never touches DB directly. Prompt injection can't become SQL injection.
- **Read/write separation**: Default to read-only. Write operations need explicit design and ideally human-in-the-loop for destructive actions.
- **Input validation at MCP layer**: Validate before forwarding to API. Use `Literal` types for constrained fields. Structured errors for invalid values.
- **43% of early MCP servers had command injection vulnerabilities** (Invariant Labs, 2025). Don't accept arbitrary strings where structured input is possible.

## Anti-Patterns

| Anti-pattern | Why it fails |
|---|---|
| 1:1 API-to-MCP mapping | 5.3x more invocations, token bloat, poor agent reasoning |
| Raw JSON in tool I/O | Wastes tokens, agents hallucinate structure |
| "400 Bad Request" errors | Agent can't self-correct without actionable context |
| All tools loaded at once | 40 tools = 40K tokens before first query |
| Mixing audiences in one server | Builder tools and consumer tools have different shapes |
| Direct DB access from MCP | Prompt injection → SQL injection risk |

## Recipe: secrets from `.env` via `dotenv-cli`

When an MCP server in `.mcp.json` needs secrets from `.env`, wrap the command with `dotenv-cli`:

```json
"command": "npx",
"args": ["dotenv-cli", "-e", ".env", "--", "npx", "actual-mcp-server"]
```

- `.mcp.json` is committed to git — never hardcode secrets there.
- The npm package is `dotenv-cli`, NOT `dotenv`. `npx dotenv` fails with "could not determine executable to run".
- Non-secret env vars (like `MCP_MODE`) can go directly in the `env` block.
- `.env` path is relative to the working directory where Claude Code runs.
