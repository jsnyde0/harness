---
name: fix-permissions
description: Diagnose and fix Claude Code permission prompts that shouldn't appear. Use when user says "why am I still getting prompted", "permission keeps asking", "whitelist not working", "approval still showing", "stop asking for approval", "subagent failing silently", "subagent permission denied", or when investigating why a Bash permission rule isn't matching. Also use proactively when you notice a permission prompt for a command that seems like it should be auto-approved, or when background subagents fail without explanation.
---

# Fix Permissions

Diagnose why Claude Code permission prompts appear for commands that should be auto-approved, or why background subagents silently fail on permissions, and apply the right fix.

## Process

1. **Gather context** — get the exact command that prompted, read `$CLAUDE_HOME/settings.json` permissions and hooks
2. **Diagnose** — run through Known Patterns below to identify the cause
3. **Fix** — apply the appropriate solution
4. **Verify** — test the fix (see [hook-development.md](references/hook-development.md) for testing patterns)
5. **Learn** — if this was a new pattern, update Known Patterns below

## Diagnostic Steps

```bash
# 1. Read current permissions and hooks
cat $HOME/.claude/settings.json | jq '.permissions.allow'
ls $HOME/.claude/hooks/

# 2. Check if a permission rule exists for this command
# Look for prefix match — does the allow entry match the start of the command?

# 3. Check if a hook is denying it (use file redirect, NOT pipe)
echo '{"tool_input":{"command":"<THE COMMAND>"}}' > /tmp/hook-test.json
bash $HOME/.claude/hooks/<hook>.sh < /tmp/hook-test.json

# 4. Check all four settings files for conflicts
cat $HOME/.claude/settings.local.json 2>/dev/null | jq '.permissions'
cat .claude/settings.json 2>/dev/null | jq '.permissions'
cat .claude/settings.local.json 2>/dev/null | jq '.permissions'
```

## Known Patterns

Diagnosed causes of unexpected permission prompts. **Update this section** when you resolve a new cause.

### 1. Glob `*` can't match paths with `/`

**Symptom:** `Bash(uv run --directory * pytest:*)` exists but commands with deep paths still prompt.

**Cause:** Bash permission `*` does not match across `/` boundaries.

**Fix:** Use `allow-directory-commands.sh` hook instead. It strips directory flags, verifies trusted roots, checks safe patterns. To extend: add safe patterns in the hook, add trusted roots to `$HOME/.claude/hooks/trusted-paths.conf`.

### 2. Missing permission entry

**Symptom:** Command prompts with no matching allow rule.

**Fix:** Add `Bash(<prefix>:*)` to settings.json. Only whitelist commands that cannot exfiltrate, execute arbitrary code, or destroy files. See the global whitelist security review in the methodology home docs.

### 3. Compound command hook blocking redirects

**Symptom:** Command with `2>&1` gets denied.

**Fix:** Check `block-compound-commands.sh` — it should exclude shell redirects from operator detection.

### 4. Hook deny overriding permission allow

**Symptom:** Permission rule exists and should match, but still prompts.

**Fix:** Test each Bash-matching hook individually to find which one is denying.

### 5. Prefix mismatch

**Symptom:** `Bash(uv run pytest:*)` exists but `uv run -m pytest` prompts.

**Fix:** Add separate entry for each variant: `Bash(uv run -m pytest:*)`.

### 6. Project-level settings overriding global

**Symptom:** Works in one project, prompts in another.

**Fix:** Check all four settings files (global, global local, project, project local).

### 7. Background subagents silently auto-deny unpermitted tools

**Symptom:** Background/worktree subagents fail silently. No prompt appears for user.

**Cause:** Background subagents cannot surface permission prompts. Anything not in the allow list is **silently auto-denied**.

**Fix:** Create **project-level** `.claude/settings.json` with scoped permissions:

```json
{
  "permissions": {
    "allow": [
      "Write(/src/**)", "Write(/tests/**)",
      "Edit(/src/**)", "Edit(/tests/**)",
      "Bash(uv run pytest:*)", "Bash(mkdir:*)"
    ]
  }
}
```

Note: `Write`/`Edit` support `**` (gitignore spec), but `Bash` `*` does NOT cross `/`.

### 8. Bash glob fails for path arguments (not just directory flags)

**Symptom:** `Bash(mkdir:*)` exists but `mkdir -p /deep/nested/path` prompts.

**Fix:** For subagents, use project-level settings with broader rules. For interactive use, just approve when prompted.

### 9. Multi-line commands (HEREDOCs) break hook parsing

**Symptom:** `git -C /path commit -m "$(cat <<'EOF'...)"` not auto-allowed by hook.

**Fix:** Hook must parse only first line for directory flag extraction. Fixed in `allow-directory-commands.sh`.

## Security Guardrails

Before adding new permissions, check against the global whitelist security review in the methodology home docs:

- **Never globally whitelist** arbitrary code execution: `uv run`, `python`, `node`, `bash`
- **Never globally whitelist** network commands: `curl` (non-localhost), `wget`, `ssh`
- **Never globally whitelist** destructive commands: `rm`, `mv`
- **For "sometimes safe" commands:** use a hook with pattern matching, not a blanket allow
- When deciding if a command is safe: read [security-threat-model.md](references/security-threat-model.md)
- When building/modifying hooks: read [hook-security-pitfalls.md](references/hook-security-pitfalls.md)

## References

- [security-threat-model.md](references/security-threat-model.md) — threat model, command classification (safe/critical/high/medium), known attack chains, remaining gaps
- [hook-security-pitfalls.md](references/hook-security-pitfalls.md) — path traversal, realpath, regex anchoring, git subcommand scoping
- [hook-development.md](references/hook-development.md) — JSON formats, testing patterns, Write/Edit vs Bash glob differences, settings precedence

## Self-Update Protocol

When you resolve a permission issue not covered above:

1. Add a new numbered section under Known Patterns (keep it to Symptom + Fix)
2. If the fix involved a non-obvious security lesson, add it to `references/hook-security-pitfalls.md`
3. If the fix involved new hook development patterns, add to `references/hook-development.md`
