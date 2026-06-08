# CLI Tool Design for Agent Use

Guide for designing CLI tools that agents (and humans) can use reliably. CLIs are first-class assets alongside MCP tools and skills — build them when portability matters.

## When to Build a CLI (vs. Pure MCP)

| Situation | Prefer |
|-----------|--------|
| Only Claude Code needs this operation | MCP tool |
| Humans, CI, scripts also need this | CLI tool |
| The operation is a self-contained program others might install | CLI tool |
| You want to wrap an existing CLI for Claude | MCP tool wrapping CLI |
| Operation needs Claude-native context (conversation state) | MCP tool |

**Common pattern:** Build the CLI first with agent-first design, then optionally wrap it as an MCP tool for richer Claude integration.

## The Two DX Philosophies

> Human DX optimizes for **discoverability and forgiveness**.
> Agent DX optimizes for **predictability and defense-in-depth**.

Design for both — machine-readable by default, human-readable on request.

## Seven Axes of Agent-First CLI Design

Use this as a design checklist AND a validation rubric (score 0–3 per axis, 21 = fully agent-first).

### 1. Machine-Readable Output
Agents parse stdout — don't force them to write custom parsers.

- **0**: Human-prose output only
- **1**: Structured but inconsistent (mixed formats)
- **2**: JSON by default for piped output, human text for TTY
- **3**: `--output=json|yaml|table`, schema documented, exit codes consistent

```bash
# Good: detect TTY, default to JSON in pipes
if [ -t 1 ]; then pretty_print; else echo "$result" | jq .; fi
```

### 2. Raw Payload Input
Agents construct full payloads — don't make them translate through flags.

- **0**: Only positional args and flags
- **1**: Some structured input via flags
- **2**: Accepts JSON via `--data='{...}'` or stdin
- **3**: `--input-file=`, stdin, env vars, all documented with schema

```bash
# Good: accept raw payload
mycli create --data='{"name":"x","type":"feature"}'
echo '{"name":"x"}' | mycli create --stdin
```

### 3. Schema Introspection
Agents discover capabilities at runtime — don't make them hallucinate flags.

- **0**: No machine-readable help
- **1**: `--help` only (text)
- **2**: `--help --output=json` returns structured command/flag list
- **3**: `--schema` returns full JSON Schema; commands self-describe accepted inputs

```bash
mycli --schema              # full JSON Schema of all inputs
mycli create --schema       # schema for this subcommand
```

### 4. Context Window Discipline
Agents have token budgets — help them stay within limits.

- **0**: Always returns full verbose output
- **1**: `--quiet` flag to reduce output
- **2**: `--limit=N` and `--fields=a,b,c` to constrain response size
- **3**: Streaming, pagination, explicit "this response was truncated" signals

```bash
mycli list --limit=10 --fields=id,name,status
mycli list --page=2 --page-size=50
```

### 5. Input Hardening
Agents hallucinate — add defenses for agent-specific failure modes.

- **0**: No validation, trusts all input
- **1**: Type validation only
- **2**: Validates enum values, rejects unknown fields, returns structured errors
- **3**: Path traversal prevention, injection defense, allowlist for dangerous ops, `--dry-run` validates without executing

```bash
# Good: structured error output
{"error": "unknown status 'clsoed'", "valid_values": ["open","closed","in_progress"]}
```

### 6. Safety Rails
Agents act without human review — make mistakes recoverable.

- **0**: No dry-run, no confirmation, destructive ops execute immediately
- **1**: `--dry-run` flag exists
- **2**: `--dry-run` shows exact changes; destructive ops require explicit flag
- **3**: Output sanitized against prompt injection; `--confirm=hash` pattern for irreversible ops

```bash
mycli delete beads-123 --dry-run          # shows what would be deleted
mycli delete beads-123 --confirm=abc123   # requires computing the hash first
```

Watch for **prompt injection** in output — if your CLI echoes user content or data from external systems, strip or escape it before returning.

### 7. Agent Knowledge Packaging
Agents need structured guidance — ship it with the CLI.

- **0**: README only, no machine-readable docs
- **1**: `--help` covers common cases
- **2**: `--examples` subcommand or examples in `--help --output=json`
- **3**: Ships a skill file (`.claude/skills/`) that agents can consume; common multi-step workflows ship as recipes (`.claude/skills/<tool>/recipes/`) rather than being baked into the CLI itself; `man` page or structured docs

```bash
mycli --agent-guide    # prints skill/guidance for Claude to consume
```

## Scoring Guide

| Score | Category | Interpretation |
|-------|----------|----------------|
| 0–5   | Human-only | Agents will struggle or fail |
| 6–10  | Agent-tolerant | Functional but token-inefficient |
| 11–15 | Agent-ready | Solid support, minor gaps |
| 16–21 | Agent-first | Comprehensive agent-centric design |

**Minimum viable for agent use:** Score ≥ 11 (axes 1, 2, 5, 6 non-zero).

## Output Format Patterns

### Consistent exit codes
```
0  = success
1  = user error (bad input, not found)
2  = system error (network, permissions)
3  = dry-run (would have executed, did not)
```

### Structured error envelope
```json
{
  "error": "issue not found",
  "code": "NOT_FOUND",
  "id": "beads-999",
  "hint": "Use 'bd list' to see valid IDs"
}
```

### Success envelope
```json
{
  "ok": true,
  "data": { ... },
  "meta": { "total": 42, "page": 1, "truncated": false }
}
```

## Wrapping a CLI as an MCP Tool

When you've built an agent-first CLI and want richer Claude integration:

1. The CLI handles validation, hardening, and output formatting
2. The MCP tool is a thin wrapper that calls the CLI and returns stdout
3. MCP tool docstring uses WHEN/WHAT/NEXT format (see `mcp-design.md`)
4. Keep error handling in the CLI — MCP tool just forwards exit codes

```typescript
// Thin MCP wrapper — CLI does the real work
server.tool("bd_create", schema, async (args) => {
  const result = await exec(`bd create --data='${JSON.stringify(args)}' --output=json`);
  return { content: [{ type: "text", text: result.stdout }] };
});
```

The decision of *when* and *why* to wrap a specific CLI as an MCP tool for a given project belongs in a recipe, not in the CLI or the MCP tool itself. Recipes compose these blocks; blocks stay ignorant of each other.

## Anti-Patterns

- **Colorized output with no escape hatch** — ANSI codes break JSON parsing
- **Spinner/progress bars to stdout** — use stderr for UX, stdout for data
- **Interactive prompts** — agents can't respond; use flags or fail fast
- **Hardcoded pagination** — always expose `--limit` and `--page`
- **Swallowing errors into exit 0** — agents rely on exit codes to detect failure
- **Human-only errors** ("Oops! Something went wrong") — include machine code + hint

## References

- jpoehnelt/skills agent-dx-cli-scale — original 7-axis evaluation framework
