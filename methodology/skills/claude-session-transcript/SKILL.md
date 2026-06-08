---
name: claude-session-transcript
description: MANDATORY when working with Claude Code JSONL files. Extracts readable transcripts from session or subagent JSONL files. If the task involves reading, parsing, analyzing, or extracting from a .jsonl file containing Claude Code conversation data — USE THIS SKILL. Do NOT write custom Python scripts or compound commands to parse JSONL. This skill has a tested extraction script that handles all cases.
---

# Claude Session Transcript Extraction

Extract a compact, readable transcript from a Claude Code session JSONL file. Useful for reviewing subagent runs, analyzing tool call patterns, or feeding transcripts to review agents.

**IMPORTANT:** Do NOT write custom Python scripts to parse JSONL files. The extraction script below handles all cases — agent narrative, tool calls, tool results, and line numbering. Use it directly.

## Locating the JSONL

Claude Code stores session data as JSONL files:

| Session type | Path pattern |
|---|---|
| Main conversation | `$CLAUDE_HOME/projects/{project-slug}/{conversation-id}.jsonl` |
| Subagent | `$CLAUDE_HOME/projects/{project-slug}/{conversation-id}/subagents/agent-{agentId}.jsonl` |

**Finding a subagent JSONL by agent ID:** The Agent tool returns an `agentId` when a subagent completes. Use it to locate the file:

```bash
find $HOME/.claude -name "agent-{agentId}.jsonl" -type f
```

## Extracting the transcript

Run this to produce a readable transcript at the desired output path:

```bash
uv run python - <<'PYEOF'
import json, sys

jsonl_path = "INPUT_PATH"
output_path = "OUTPUT_PATH"

with open(jsonl_path) as f:
    lines = [json.loads(line) for line in f]

with open(output_path, "w") as out:
    out.write("# Session Transcript\n\n")
    for line_num, entry in enumerate(lines, 1):
        msg = entry.get("message", entry)
        role = msg.get("role", "?")
        content = msg.get("content", [])
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "text" and block.get("text", "").strip():
                prefix = "Agent" if role == "assistant" else "System"
                out.write(f"## {prefix} [line {line_num}]\n{block['text'].strip()}\n\n")
            elif btype == "tool_use":
                name = block.get("name", "?")
                params = json.dumps(block.get("input", {}), ensure_ascii=False)
                if len(params) > 500:
                    params = params[:500] + "..."
                out.write(f"## Tool: {name} [line {line_num}]\n**Params:** {params}\n\n")
            elif btype == "tool_result":
                sub = block.get("content", "")
                if isinstance(sub, str):
                    text = sub
                elif isinstance(sub, list):
                    text = " ".join(b.get("text", "") for b in sub if isinstance(b, dict))
                else:
                    text = str(sub)
                size = len(text)
                preview = text[:200].replace("\n", " ")
                out.write(f"**Result:** ({size:,} chars) {preview}\n\n")

print(f"Transcript written to {output_path} ({len(lines)} JSONL lines)")
PYEOF
```

Replace `INPUT_PATH` and `OUTPUT_PATH` with actual paths.

## What the transcript contains

| Element | Content | Truncation |
|---|---|---|
| Agent text | Full reasoning narrative between tool calls | None (these are short) |
| System text | Skill loads, tool results rendered as user messages | None |
| Tool calls | Name + JSON params | Params truncated at 500 chars |
| Tool results | Size in chars + 200-char preview | Preview only |
| Line numbers | `[line N]` on every entry | — |

## Deep-diving into specific tool calls

The `[line N]` references point to the source JSONL line. When you need the full untruncated tool input or output:

```bash
# Readable view via CASS
cass view {jsonl_path} --line {N} --context 2

# Or read the JSONL directly and parse line N
uv run python -c "
import json
with open('{jsonl_path}') as f:
    lines = f.readlines()
print(json.dumps(json.loads(lines[{N}-1]), indent=2))
"
```

## Common uses

- **improve-iteratively**: Extract test agent transcript for the review agent (Step 1b)
- **Debugging a subagent**: See exactly what it did, which tools failed, where it got stuck
- **Sharing context**: Produce a readable summary of a session for another agent or human
