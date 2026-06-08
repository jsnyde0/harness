---
name: secrets-via-stdin
description: Use a secret from .env (or any file/env var) in a command without the value landing in Claude's context, transcript, or process argv. Use when the user says things like "don't read the password", "use this secret without seeing it", "I put it in .env", "pipe it instead of reading it", or any time a secret has to be sent to a tool but should stay invisible to the agent. Also use proactively whenever you're about to read a file that contains a secret you only need to forward to a command (do NOT read the line; pipe it).
---

# Secrets via stdin

Forward a secret to a command **without** the value passing through:

1. Claude's read window (no `Read`/`cat`/`tail`/`head` of the line)
2. Process argv (no `-d "$SECRET"` on the command line — visible via `/proc` and shell history)
3. stdout/stderr (no `echo`, no commands that echo back the secret)

## When this applies

- User explicitly asks you not to read a secret (most obvious trigger).
- You need to send a secret to an API but only the response matters.
- You're rotating, injecting, or comparing a secret you don't need to see.
- A subagent or future you should not see the value either.

If you only need to *check* a secret exists (not its value), `grep -q '^VAR=' .env` is enough — never read the value.

## The pattern

The shell extracts the secret, a tool builds the payload, and the consuming tool reads from stdin. The agent never sees the value.

```bash
#!/bin/bash
set -euo pipefail

# 1. Targeted extract — only the vars we need.
#    cut -d= -f2- preserves any '=' inside the value.
#    tr -d '\r' guards against CRLF .env files.
SECRET=$(grep '^MY_SECRET=' .env | head -1 | cut -d= -f2- | tr -d '\r')
TOKEN=$(grep '^MY_TOKEN=' .env  | head -1 | cut -d= -f2- | tr -d '\r')
export SECRET TOKEN  # only if a child process needs them via env

# 2. Build payload with proper escaping (jq handles any chars in the secret).
# 3. Pipe to the consumer's stdin — value never enters argv.
jq -n --arg s "$SECRET" '{password: $s}' \
| curl -sS -X POST 'https://api.example.com/v1/endpoint' \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary @-

# 4. Wipe locals (defense in depth).
unset SECRET TOKEN
```

Run it via `bash /tmp/foo.sh`. Don't `cat` the script back to verify (it doesn't contain the secret, but the habit matters).

## Variants by tool

| Tool | Stdin flag |
|---|---|
| `curl` | `--data-binary @-` (or `-d @-`) |
| `psql` | `psql -f -` or `PGPASSWORD=$X psql ...` (env, not argv) |
| `gh auth login` | `--with-token` reads stdin |
| `docker login` | `--password-stdin` |
| `op` (1Password) | already isolates — use `op read` directly, don't echo |
| `aws` | use env vars `AWS_*`, not flags |
| `git credential` | `git credential approve` reads key=value from stdin |

For tools that *only* accept argv: use `env -i`-style sandboxing or accept argv exposure but make sure the value doesn't echo back.

## Anti-patterns — do NOT

- ❌ `Read` the file with offset/limit that *might* include the secret line — line numbers shift; you'll bleed the secret into context.
- ❌ `cat .env`, `tail -n5 .env`, `head -n50 .env` — same risk.
- ❌ `echo "$SECRET"` for "verification" — straight to transcript.
- ❌ `-d "$(jq …)"` — argv exposure on Linux (`/proc/<pid>/cmdline` readable by same UID); macOS argv is also readable by same-uid procs.
- ❌ `set -a; source .env; set +a` — fails on any unquoted value with spaces (e.g., `IMPRESSUM_NAME=Jane Doe` → `Doe: command not found`). Use targeted `grep+cut`.
- ❌ `bd remember "the password is X"` — memories are persisted to disk; secrets do not belong there.
- ❌ Verifying success by re-reading `.env` — extract once, use, drop.

## If a secret slipped into context anyway

Disclose immediately. Then offer to rotate via the system's rotation primitive (e.g., `reset_password` API action, `gh auth refresh`, regenerating a token). The new value goes through this same skill — never read.

## Hand-back to user

If you cannot avoid argv or stdout exposure with the available tools, **stop and explain** rather than improvising. Sometimes the right answer is: the user pastes the value into a tool you cannot see, or runs the command themselves with `! <cmd>` in the prompt.
