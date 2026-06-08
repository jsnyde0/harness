#!/usr/bin/env bash
# Hook: redirect Write/Edit on projects/<slug>/memory/ paths to bd memories (L2B).
#
# Auto-memory under $CLAUDE_HOME/projects/<slug>/memory/ is the file-based tier
# that predates the L2A/L2B split. Per ADR-013 D2/D8 and the substrate-tier
# migration recorded in bd memories key `substrate_tier_migration_consumer_sweep`
# (2026-05-19), this tier has been deprecated — L2B `bd remember` is canonical.
# The "auto memory" section in the Claude Code system prompt still instructs
# agents to write to this dir, so this hook is the substrate-side counterweight.
#
# Decision returns "deny": auto-mode silently passes "ask", and an interactive
# prompt only delays the agent — denial is the automatic counterweight that
# lets the loop keep going and surfaces the redirect in the deny reason.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Normalize
FILE_PATH=$(echo "$FILE_PATH" | sed "s|^~|$HOME|")
FILE_PATH=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# Match paths like $CLAUDE_HOME/projects/<slug>/memory/*
if [[ "$FILE_PATH" == */projects/*/memory/* ]]; then
  REASON="Auto-memory tier ($FILE_PATH) is deprecated per ADR-013 D2/D8. Write to bd memories (L2B) instead. Read bd-memories-write/SKILL.md in the methodology home, then call: bd remember --key=<kebab-key> with frontmatter (kind / scope / created) + Why / How-to-apply body."
  jq -n --arg reason "$REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

exit 0
