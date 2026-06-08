# Hook Development Reference

## Auto-allow hook format
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "reason shown in logs"
  }
}
```

## Auto-deny hook format
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "reason shown to agent"
  }
}
```

## No decision (fall through to normal prompt)
```bash
exit 0  # with no JSON output
```

## Hook input format
```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "the full command string",
    "description": "the agent's description"
  }
}
```

## Testing hooks

Write test input to a file and redirect, or use a test script:

```bash
# Single test via file redirect
echo '{"tool_input":{"command":"<command>"}}' > /tmp/hook-test.json
bash $HOME/.claude/hooks/<hook>.sh < /tmp/hook-test.json

# Full test suite pattern (see /tmp/test-allow-directory-hook.sh for example)
test_case() {
  local description="$1" input="$2" expect_allow="$3"
  output=$(echo "$input" | bash "$HOOK" 2>/dev/null)
  has_allow=$(echo "$output" | grep -c '"permissionDecision": "allow"')
  # ... check expected vs actual
}
```

**Important:** You cannot test hooks by running `echo '...' | bash hook.sh` directly in Claude Code — the pipe `|` triggers the compound-commands hook on the outer command. Use file redirects or a test script instead.

## Key differences: Write/Edit vs Bash glob patterns

- `Write(/src/**)` and `Edit(/src/**)` — `**` works, matches across `/` boundaries (gitignore spec)
- `Bash(mkdir:*)` — `*` does NOT match across `/` boundaries (simple prefix matching)
- So `Bash(mkdir:*)` matches `mkdir foo` but may not match `mkdir -p /deep/nested/path`

## Settings file precedence

Four files, checked in order (later overrides earlier):
1. `$HOME/.claude/settings.json` — global
2. `$HOME/.claude/settings.local.json` — global local (gitignored)
3. `<project>/.claude/settings.json` — project (committed)
4. `<project>/.claude/settings.local.json` — project local (gitignored)
