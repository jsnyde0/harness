#!/usr/bin/env bash
# Block harvest.sh from running without explicit user confirmation.
# This hook is a PreToolUse hook on Bash commands.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only intercept actual execution of harvest.sh — not file-argument mentions
# (e.g., `git add harvest.sh`, `cat harvest.sh`, `rg harvest.sh`).
# Matches: `./harvest.sh`, `bash harvest.sh`, `sh ./harvest.sh`,
#          `$CLAUDE_HOME/harvest.sh`, `/abs/path/harvest.sh` at start of a command.
if echo "$COMMAND" | grep -Eq '(^|[;&|]|&&|\|\|)[[:space:]]*((bash|sh|zsh)[[:space:]]+([^[:space:];|&]*/)?harvest\.sh|(\.?/|~?/)[^[:space:];|&]*harvest\.sh)([[:space:];|&]|$)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "About to run harvest.sh — this copies all work repo assets into the methodology home. Proceed?"
    }
  }'
else
  exit 0
fi
