#!/usr/bin/env bash
# Hook: Auto-allow safe commands that use directory flags
#
# Problem: Claude Code's Bash permission globs use `*` which doesn't match
# across `/` boundaries. So `Bash(uv run --directory * pytest:*)` can't match
# `uv run --directory $HOME/deep/nested/path pytest -v`.
#
# Solution: Extract the directory path from flags (--directory, -C, --git-dir),
# verify it's under a trusted root, strip the flag, check if the base command
# matches a known-safe pattern, and return "allow" if so.
# Unknown commands or untrusted paths get no decision (fall through to prompt).
#
# Trusted paths configured in: $CLAUDE_HOME/hooks/trusted-paths.conf
#
# Replaces: block-git-dash-c.sh (which denied -C to force CWD retry)
# Replaces: broken permission glob entries for uv run --directory * pytest

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
TRUSTED_PATHS_FILE="$HOOK_DIR/trusted-paths.conf"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$COMMAND" ] && exit 0

# --- Extract directory paths from flags ---
# Only parse the first line to avoid multi-line commands (HEREDOCs) polluting the path

DIR_PATH=""
FIRST_LINE=$(echo "$COMMAND" | head -1)

# uv --directory <path> or uv run --directory <path>
if echo "$FIRST_LINE" | grep -qE '\-\-directory[= ]+'; then
  DIR_PATH=$(echo "$FIRST_LINE" | sed -E 's/.*--directory[= ]+("([^"]*)"|([^ ]+)).*/\2\3/')
fi

# git -C <path>
if echo "$FIRST_LINE" | grep -qE '^\s*git\s+-C\s'; then
  DIR_PATH=$(echo "$FIRST_LINE" | sed -E 's/.*-C[= ]*("([^"]*)"|([^ ]+)).*/\2\3/')
fi

# git --git-dir=<path> or --git-dir <path>
if echo "$FIRST_LINE" | grep -qE '\-\-git-dir[= ]'; then
  DIR_PATH=$(echo "$FIRST_LINE" | sed -E 's/.*--git-dir(=| +)("([^"]*)"|([^ ]+)).*/\3\4/')
fi

# If no directory flag found, this hook has nothing to do
[ -z "$DIR_PATH" ] && exit 0

# --- Verify directory is under a trusted root ---

# Reject paths containing .. (path traversal)
if echo "$DIR_PATH" | grep -qF '..'; then
  exit 0  # fall through to permission prompt
fi

# Resolve symlinks and relative paths
# If realpath fails (path doesn't exist), reject — we can't verify the actual target
RESOLVED_PATH=$(realpath "$DIR_PATH" 2>/dev/null)
if [ -z "$RESOLVED_PATH" ]; then
  exit 0  # fall through to permission prompt
fi

TRUSTED=false
if [ -f "$TRUSTED_PATHS_FILE" ]; then
  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    # Trim whitespace and trailing slash for consistent matching
    root=$(echo "$line" | sed 's/[[:space:]]*$//;s/\/$//')
    # Expand a leading $HOME token so the conf stays portable across machines.
    root="${root/#\$HOME/$HOME}"
    if [[ "$RESOLVED_PATH" == "$root"/* || "$RESOLVED_PATH" == "$root" ]]; then
      TRUSTED=true
      break
    fi
  done < "$TRUSTED_PATHS_FILE"
fi

if [ "$TRUSTED" = false ]; then
  # Path not under any trusted root — fall through to permission prompt
  exit 0
fi

# --- Strip directory flags and extract base command ---

BASE="$COMMAND"

# uv --directory <path> or uv run --directory <path>
BASE=$(echo "$BASE" | sed -E 's/--directory[= ]+("[^"]*"|[^ ]+) ?/ /g')

# git -C <path>
BASE=$(echo "$BASE" | sed -E 's/-C[= ]*("[^"]*"|[^ ]+) ?/ /g')

# git --git-dir=<path> or git --git-dir <path>
BASE=$(echo "$BASE" | sed -E 's/--git-dir(=[^ ]+| +("[^"]*"|[^ ]+)) ?/ /g')

# Normalize whitespace
BASE=$(echo "$BASE" | tr -s ' ' | sed 's/^ //;s/ $//')

# --- Check base command against safe patterns ---

# Safe git subcommands (read-only + staging/committing in trusted repos)
SAFE_GIT="^git (rev-parse|log|diff|show|status|tag|remote|stash list|add|commit)( |$)"
# git branch: only allow read-only flags, block -D, -d, -m, -M, --delete, --move, --copy
SAFE_GIT_BRANCH="^git branch( -[avr]+| --list| --contains| --merged| --no-merged| --sort=.*)*$"

# Safe uv subcommands (no arbitrary code execution)
SAFE_UV="^uv (sync|lock|tree|version|init)( |$)"
SAFE_UV_PYTHON="^uv python (list|find)( |$)"
SAFE_UV_RUN="^uv run (-m )?pytest( |$)"

ALLOWED=false
if echo "$BASE" | grep -qE "$SAFE_GIT"; then
  ALLOWED=true
elif echo "$BASE" | grep -qE "$SAFE_GIT_BRANCH"; then
  ALLOWED=true
elif echo "$BASE" | grep -qE "$SAFE_UV"; then
  ALLOWED=true
elif echo "$BASE" | grep -qE "$SAFE_UV_PYTHON"; then
  ALLOWED=true
elif echo "$BASE" | grep -qE "$SAFE_UV_RUN"; then
  ALLOWED=true
fi

if [ "$ALLOWED" = true ]; then
  jq -n --arg cmd "$BASE" --arg path "$RESOLVED_PATH" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: ("Safe command with directory flag auto-approved. Base: " + $cmd + " Path: " + $path)
    }
  }'
else
  # Not a known-safe command — no decision, falls through to normal permission prompt
  exit 0
fi
