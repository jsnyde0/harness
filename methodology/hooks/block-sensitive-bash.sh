#!/usr/bin/env bash
# Hook: block Bash commands that would print secret-bearing env files or process env.
#
# Read/Edit/Write access to .env is blocked by restrict-sensitive-paths.sh, but
# Bash can bypass file-tool hooks. This hook denies common read/dump patterns
# while still allowing local CLIs to load .env internally.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Strip quoted strings for rough operator/command detection without exposing content.
STRIPPED=$(printf '%s' "$COMMAND" | perl -0777 -pe 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Deny obvious env-dump commands. These can expose API keys inherited by tools.
if printf '%s\n' "$STRIPPED" | grep -Eq '(^|[[:space:];|&])(env|printenv)([[:space:]]|$)|(^|[[:space:];|&])export[[:space:]]+-p([[:space:]]|$)|(^|[[:space:];|&])set([[:space:]]|$)'; then
  deny "Blocked: command may dump environment variables, including secrets. Use a targeted existence check or a purpose-built CLI that does not print secrets."
fi

# Deny commands that read env files to stdout or transform broad env-file content.
if printf '%s\n' "$COMMAND" | grep -Eq '(^|[[:space:];|&])(cat|less|more|head|tail|nl|sed|awk|sort|uniq|cut)([[:space:]].*)?([[:space:]]|^)([^[:space:]]*/)?\.env([.[:alnum:]_-]*)?([[:space:]]|$)'; then
  deny "Blocked: command appears to read an .env file into the session. Use a script that loads dotenv internally, or grep -q for existence only."
fi

# Allow targeted existence checks like: grep -q / -qE / -qi '^VAR=' .env
# Match any short-flag cluster containing 'q' (e.g. -q, -qE, -qi, -Eq).
if printf '%s\n' "$COMMAND" | grep -Eq '(^|[[:space:];|&])grep[[:space:]]+-[a-zA-Z]*q[a-zA-Z]*[[:space:]]+'; then
  exit 0
fi

# Deny other grep/ripgrep over .env because output may include secret values.
if printf '%s\n' "$COMMAND" | grep -Eq '(^|[[:space:];|&])(grep|rg)([[:space:]].*)?([[:space:]]|^)([^[:space:]]*/)?\.env([.[:alnum:]_-]*)?([[:space:]]|$)'; then
  deny "Blocked: grep over .env may print secret values. Use grep -q for existence checks only."
fi

exit 0
