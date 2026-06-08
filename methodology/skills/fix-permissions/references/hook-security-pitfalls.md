# Hook Security Pitfalls

Lessons learned from building `allow-directory-commands.sh`. **Check these when writing or modifying any allow-hook.**

## Path traversal via `..`

A path like `$HOME/code/myrepo/../../.ssh` passes a naive prefix check against `$HOME/code/` because the raw string starts with the trusted root. But it actually resolves to `$HOME/.ssh`.

**Mitigations (both required):**
- Reject any path containing `..` outright
- Reject when `realpath` fails (nonexistent intermediate dirs mean the path can't be verified)

## `realpath` fallback is dangerous

`realpath` fails on nonexistent paths (exit 1, no output). If you fall back to the raw string (`realpath "$path" || echo "$path"`), you bypass path resolution entirely. **Never use a fallback** — if `realpath` fails, reject the path.

## Regex anchoring for subcommand safety

A regex like `^git branch( -[avr]+)*( |$)` intended to allow only read-only branch flags will incorrectly match `git branch -D main` because:
- The `*` quantifier matches zero groups
- The `( |$)` matches the space before `-D`

**Fix:** Anchor to end-of-string `$` not `( |$)` for patterns that must match the entire command. E.g., `^git branch( -[avr]+| --list)*$`

## Git subcommand scoping for directory-flag hooks

When allowing `git -C <path> <subcommand>`, carefully consider which subcommands belong:
- **Safe with -C:** `log`, `diff`, `show`, `status`, `rev-parse`, `tag`, `remote`, `stash list`, `add`, `commit`, `branch` (read-only flags only)
- **Unsafe with -C:** `push`, `reset`, `checkout`, `switch`, `merge`, `rebase`, `branch -D/-m`
- `add`/`commit` with `-C` enables cross-repo commits — acceptable for trusted repos but be aware of the expanded scope vs CWD-only

## Multi-line commands (HEREDOCs) break parsing

The HEREDOC body becomes part of the command string. Regex patterns using `[^ ]+` (not-space) match across newlines, so directory path extraction grabs the entire multi-line string instead of just the path.

**Fix:** Parse only the first line of the command when extracting directory flags. Use `head -1` before `sed`/`grep` extraction.
