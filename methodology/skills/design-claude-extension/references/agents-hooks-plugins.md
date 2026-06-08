# Subagents, Hooks, Commands & Plugins Reference

**Status:** Exploratory — patterns observed as of March 2026
**Sources:** Official Claude Code docs, diet103/claude-code-infrastructure-showcase, community articles

---

## Subagents (`.claude/agents/`)

### What They Are

Markdown files with YAML frontmatter that define specialized AI assistants running in **their own context window** with a custom system prompt, specific tool access, and independent permissions.

### When to Use

- **Context isolation** — Keep verbose output (test logs, large datasets) out of main conversation
- **Tool restriction** — Limit what the agent can do (read-only, specific MCP servers only)
- **Parallel work** — Spawn multiple agents for independent investigations
- **Skill injection** — Preload specific skills into an isolated context

### Configuration

Defined in `.claude/agents/<name>.md`. Scopes (priority order):
1. `--agents` CLI flag (session override)
2. `.claude/agents/` (project)
3. `$CLAUDE_HOME/agents/` (user/global)
4. Plugin's `agents/` directory

### Key Frontmatter Fields

```yaml
---
name: my-agent
description: "When to spawn this agent — same description engineering rules as skills"
model: sonnet  # or opus, haiku — defaults to parent model
tools:
  - Read
  - Glob
  - Grep
  - mcp__geo-mcp__query
disallowedTools:
  - Edit
  - Write
skills:
  - mpoi-analysis
  - entity-dedup
  - h3-utils
mcpServers:
  - poi-mcp                     # reference by name (already configured)
  - type: stdio                 # or define inline (scoped to this agent only)
    command: npx
    args: ["-y", "my-server"]
permissionMode: plan            # bypassPermissions, plan, acceptEdits, full
maxTurns: 50
memory: project                 # user, project, or local
isolation: worktree             # git worktree isolation
background: true                # run concurrently, pre-approve permissions
---
```

### Hard Constraints

- **Subagents cannot spawn other subagents** — no nesting. Chain from main conversation instead.
- **Subagents do NOT inherit skills from parent** — must explicitly list in `skills:` field.
- **Built-in agents (Explore, Plan) cannot access skills at all** — they only see MCP tools + server instructions.
- **Plugin subagents cannot use `hooks`, `mcpServers`, or `permissionMode`** — security restriction. Copy to `.claude/agents/` if you need these.
- **Subagent files loaded at session start** — manually added files require session restart or `/agents` to reload.

### Foreground vs Background

| Mode | Behavior | Permissions | Use when |
|------|----------|-------------|----------|
| Foreground | Blocks main conversation | Prompts pass through to user | You need results before continuing |
| Background | Runs concurrently | Pre-approved only, auto-denies rest | Independent work, parallel research |

Ctrl+B backgrounds a running foreground task.

### Design Patterns

Subagent design follows **flat composition**: agents are leaf nodes that do one focused thing. Coordination logic (sequencing, fan-out, result aggregation) lives in the main conversation or in a recipe — not inside agents. This enforces the hard constraint that subagents cannot spawn subagents.

**Specialist agent with skills:**
```yaml
---
name: geospatial-analyst
description: "Agent for MPOI analysis, entity dedup, and spatial workflows"
skills:
  - mpoi-analysis
  - entity-dedup
  - h3-utils
mcpServers:
  - poi-mcp
  - geo-mcp
---
Follow the mpoi-analysis skill for workflow patterns...
```

**Read-only researcher:**
```yaml
---
name: code-researcher
description: "Research codebase questions without modifying files"
tools:
  - Read
  - Glob
  - Grep
  - Bash(read-only commands)
disallowedTools:
  - Edit
  - Write
---
```

**Inline MCP server** (scoped to agent, invisible to main conversation):
```yaml
mcpServers:
  - type: stdio
    command: npx
    args: ["-y", "specialized-server"]
    env:
      API_KEY: "${API_KEY}"
```

---

## Hooks (`settings.json`)

### What They Are

Shell commands that execute automatically in response to Claude Code events. Defined in `settings.json` under the `hooks` key.

### Hook Events

| Event | Fires when | Input (stdin) | Can block? |
|-------|-----------|---------------|------------|
| `UserPromptSubmit` | User sends a message | `{ prompt, session_id }` | Yes (non-zero exit) |
| `PreToolUse` | Before any tool runs | `{ tool_name, tool_input, session_id }` | Yes |
| `PostToolUse` | After a tool completes | `{ tool_name, tool_input, tool_output, session_id }` | No |
| `Stop` | Claude finishes responding | `{ session_id }` | Yes (forces continue) |

### Configuration

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/my-hook.sh"
      }]
    }],
    "PostToolUse": [{
      "matcher": "Edit|MultiEdit|Write",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/post-edit.sh"
      }]
    }]
  }
}
```

The `matcher` field (regex) filters which tools trigger `PreToolUse`/`PostToolUse` hooks.

### Hook-Based Skill Activation (diet103 Pattern)

> **Recipe-level pattern.** This is a prescriptive workflow for a specific scenario (enforced skill discipline), not a general hook building block. If you implement it, it belongs in a recipe, not a shared skill.

An advanced pattern where a `UserPromptSubmit` hook analyzes each prompt against a `skill-rules.json` config to auto-suggest or block until a skill is loaded.

**How it works:**
1. User sends prompt → `skill-activation-prompt.sh` fires
2. Script reads prompt, loads `skill-rules.json`
3. Matches via **keyword** (substring) and **intent patterns** (regex)
4. Can also match on **file triggers** (path globs + content patterns)
5. Returns a message telling Claude to load the skill

**Three enforcement levels:**
- `suggest` — "consider this skill" (non-blocking)
- `warn` — "you should use this" (non-blocking with emphasis)
- `block` — stops execution until skill is loaded (guardrail)

**Example rule:**
```json
{
  "frontend-dev-guidelines": {
    "enforcement": "block",
    "priority": "high",
    "promptTriggers": {
      "keywords": ["component", "react", "MUI", "frontend"],
      "intentPatterns": [
        "(create|add|build).*?(component|UI|page|modal)"
      ]
    },
    "fileTriggers": {
      "pathPatterns": ["frontend/src/**/*.tsx"],
      "pathExclusions": ["**/*.test.tsx"]
    },
    "blockMessage": "BLOCKED - Load frontend skill before editing React code",
    "skipConditions": {
      "sessionSkillUsed": true,
      "fileMarkers": ["@skip-validation"]
    }
  }
}
```

**Assessment — when this is worth the complexity:**
- Guardrails for dangerous operations (block-level enforcement)
- File-type triggers that should always load domain skills
- Teams where skill discipline needs to be enforced

**When it's overkill:**
- Skills with good descriptions already trigger reliably via Claude's native matching
- Maintenance burden: every skill needs hand-curated keywords + regex in a separate file
- Adds latency (hook runs on every prompt)
- Regex patterns are fragile — miss natural variations, over-trigger on others

### Other Useful Hook Patterns

**Post-edit file tracker** — tracks which files/repos were modified, useful for targeted builds:
```json
{
  "PostToolUse": [{
    "matcher": "Edit|MultiEdit|Write",
    "hooks": [{ "type": "command", "command": "post-tool-use-tracker.sh" }]
  }]
}
```

**Stop hook for validation** — runs TypeScript checks or builds when Claude stops:
```json
{
  "Stop": [{
    "hooks": [
      { "type": "command", "command": "tsc-check.sh" },
      { "type": "command", "command": "trigger-build-resolver.sh" }
    ]
  }]
}
```

**PreToolUse for read-only SQL enforcement:**
```json
{
  "PreToolUse": [{
    "matcher": "mcp__geo-mcp__query",
    "hooks": [{ "type": "command", "command": "validate-readonly-sql.sh" }]
  }]
}
```

---

## Commands (`.claude/commands/`)

### What They Are

Markdown files that provide slash-command shortcuts. Simpler than skills — no frontmatter, no auto-triggering. The user explicitly types `/command-name`.

Commands are **user-triggered recipes**: prescriptive, context-specific, disposable. A command file can directly reference a recipe (`See recipes/my-workflow.md`) or inline the steps. Keep reusable knowledge in skills; keep the specific workflow in the command/recipe.

### When to Use

- Frequently-used workflows that benefit from a shortcut
- Wrappers that invoke subagents or skills with specific parameters
- Quick-reference prompts (e.g., `/dev-docs` to generate documentation)

### Structure

File: `.claude/commands/my-command.md`
```markdown
Generate structured development documentation for the current task.

1. Identify the current task context
2. Create three files:
   - `[task]-plan.md` — Strategic overview
   - `[task]-context.md` — Key decisions and critical files
   - `[task]-tasks.md` — Checklist format
3. Save to `docs/dev/`
```

User invokes with `/my-command`. The file content becomes the prompt.

### Commands vs Skills

| Aspect | Command | Skill |
|--------|---------|-------|
| Invocation | Explicit (`/name`) | Auto-triggered by description match |
| Frontmatter | None | Required (name, description) |
| Progressive disclosure | No (full content = prompt) | Yes (L1→L2→L3) |
| Best for | Shortcuts, wrappers | Domain knowledge, workflows |

---

## Plugins

### What They Are

The distribution mechanism for sharing skills, agents, commands, and hooks across teams and projects. Installed from marketplaces.

### Structure

```
my-plugin/
  skills/
    my-skill/
      SKILL.md
      references/
  agents/
    my-agent.md
  commands/
    my-command.md
  recipes/           # optional: prescriptive step-by-step workflows
    my-workflow.md
  plugin.json       # metadata
```

### Key Constraints

- Plugin subagents **cannot** use `hooks`, `mcpServers`, or `permissionMode` fields (security restriction)
- To unlock those fields, copy the agent definition to `.claude/agents/`
- Enterprise-managed skills override all other scopes (personal, project, plugin)

### When to Create a Plugin

- Sharing a workflow/skill across multiple repositories
- Distributing MCP server configurations + companion skills as a unit
- Team-wide standards (coding guidelines, review workflows)

### Distribution Methods (priority order for teams)

1. **Repository commit** — Place in `.claude/skills/`, anyone who clones gets them. Simplest, best for project-specific skills.
2. **Plugin marketplace** — `clone + install` workflow. Best for cross-repo distribution.
3. **Enterprise managed settings** — Admin-deployed, highest priority, overrides all others.

### Cheap Foresight

Even if you're not building a plugin today, structure your skills/agents as if you might distribute them later:
- Keep skills self-contained (no hard-coded paths)
- Use relative references within the skill folder
- Document MCP server dependencies in SKILL.md
