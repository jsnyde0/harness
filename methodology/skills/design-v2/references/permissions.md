# Permissions / friction note

ADR creation under the methodology home's `docs/decisions/` may trigger per-edit approval prompts in Claude Code. If friction is high during design-v2 ADR writes, pre-allow `Write($CLAUDE_HOME/docs/decisions/**)` in `$CLAUDE_HOME/settings.json`.

This is one-time operator setup, not runtime guidance — design-v2 itself does not check or modify permission settings.
