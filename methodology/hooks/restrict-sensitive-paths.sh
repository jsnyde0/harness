#!/usr/bin/env bash
# Hook: Deny Read/Edit/Write access to sensitive files and directories.
#
# Matches against the tool's file_path input. Covers:
# - SSH keys and config
# - Environment/secret files (.env, .envrc)
# - Cloud credentials (AWS, GCP, Azure)
# - Auth tokens (gh CLI, Docker, npm, PyPI)
# - GPG keys
# - Shell history (can contain pasted secrets)
# - netrc (HTTP credentials)
# - Keychain databases
#
# Only blocks Claude's built-in tools. Bash commands (cat, etc.) are
# gated separately by the allow list / DCG.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Normalise: resolve ~ and collapse /./
FILE_PATH=$(echo "$FILE_PATH" | sed "s|^~|$HOME|")
FILE_PATH=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

HOME_DIR="$HOME"

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# --- Exact directory/prefix matches (case-sensitive) ---

SENSITIVE_DIRS=(
  "$HOME_DIR/.ssh"
  "$HOME_DIR/.aws"
  "$HOME_DIR/.azure"
  "$HOME_DIR/.config/gcloud"
  "$HOME_DIR/.gnupg"
  "$HOME_DIR/.gpg"
  "$HOME_DIR/.config/gh"
  "$HOME_DIR/.docker/config.json"
  "$HOME_DIR/.npmrc"
  "$HOME_DIR/.pypirc"
  "$HOME_DIR/.netrc"
  "$HOME_DIR/.kube"
  "$HOME_DIR/Library/Keychains"
)

for dir in "${SENSITIVE_DIRS[@]}"; do
  # Match the path itself or anything under it
  if [[ "$FILE_PATH" == "$dir" || "$FILE_PATH" == "$dir"/* ]]; then
    deny "Access denied: $FILE_PATH is in a protected sensitive directory ($dir). Ask the user to provide the information you need."
  fi
done

# --- Filename patterns (anywhere on disk) ---

BASENAME=$(basename "$FILE_PATH")

# .env files (including .env.local, .env.production, etc.)
if [[ "$BASENAME" == .env || "$BASENAME" == .env.* ]]; then
  deny "Access denied: $FILE_PATH looks like an environment secrets file. Ask the user to provide specific values you need."
fi

# .envrc (direnv)
if [[ "$BASENAME" == ".envrc" ]]; then
  deny "Access denied: $FILE_PATH is a direnv secrets file."
fi

# Shell history files (may contain pasted tokens)
if [[ "$BASENAME" == .bash_history || "$BASENAME" == .zsh_history || "$BASENAME" == .histfile ]]; then
  deny "Access denied: shell history may contain secrets."
fi

# Private key files by extension
if [[ "$BASENAME" == *.pem || "$BASENAME" == *.key || "$BASENAME" == *id_rsa* || "$BASENAME" == *id_ed25519* || "$BASENAME" == *id_ecdsa* ]]; then
  deny "Access denied: $FILE_PATH looks like a private key file."
fi

# Bearer token files
if [[ "$BASENAME" == .bearer_token || "$BASENAME" == .token ]]; then
  deny "Access denied: $FILE_PATH looks like a token file."
fi

# No match — allow
exit 0
