#!/bin/bash
# Claude Code notification hook
# Only fires when CLAUDE_NOTIFY env var is set
# Usage: Launch priority session with CLAUDE_NOTIFY=1 claude

[ "$CLAUDE_NOTIFY" = "1" ] || exit 0

SOUND="${CLAUDE_SOUND:-$HOME/.claude/sounds/pop.mp3}"
afplay "$SOUND" &
