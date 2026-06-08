---
name: cass
description: "Search past Claude Code conversations using CASS (Coding Agent Search & Synthesis). Use when the user asks to recall, find, or remember something from a previous session, says 'we discussed', 'we talked about', 'last time', 'previous session', 'remember when', or 'how did we do X'. Also use when you need context from prior work to answer a question. CASS indexes all local Claude Code sessions and provides full-text search — always prefer it over reading raw JSONL files."
---

# CASS — Searching Past Sessions

CASS indexes all local Claude Code conversation history and provides full-text search. Use it whenever you need to find what was discussed or decided in a previous session.

## Pre-flight Check (skip if CASS worked recently)

If this is the first CASS use in a while, check health:

```bash
cass health --json
```

If unhealthy (exit code 1) or index is stale, run:

```bash
cass index        # incremental re-index
cass doctor --fix # if index is corrupted
```

If CASS has been working in recent sessions, skip straight to searching.

## Core Workflow

### Step 1: Scan (find the right session)

Use `--json` with `--fields summary` to get structured, scannable output:

```bash
cass search "health endpoint" --json --limit 10 --fields summary
```

This returns JSON with `source_path`, `line_number`, `agent`, `title`, and `score` for each hit.

**WARNING: Do NOT use `--robot-format toon --fields minimal`.** This combination silently returns `count: 0` even when matches exist (confirmed bug in CASS 0.3.1). Always use `--json` instead.

**How to identify the right session:**
- Your **current session ID** will appear many times (it matches because you're discussing the same topic). Skip it.
- The session with the **most hits from a different ID** is your target. Commit to it — don't scatter across multiple sessions.
- The `source_path` contains the workspace name (e.g., `my-project`) to help narrow down.

**Critical rules:**
- **Always use `--json`** — reliable output format that actually returns hits.
- **Use `--fields summary`** to keep output compact. Omit `--fields` only when you need full content.
- **Do NOT use `--robot-format toon`** — broken with `--fields minimal`, returns 0 hits.
- **Do NOT use `--until`** — it triggers the broken FTS backend with 3+ query terms, and it excludes same-day conversations you may need.
- **Do NOT use `--workspace`** — it requires the FTS backend which is often broken (exit code 9). Instead, scan `source_path` in results.
- **Do NOT use `$(date +%F)` or any `$()`** — triggers permission prompts.
- **Do NOT pipe through `grep`** — you lose context.

**Keep queries short (1-2 terms).** `"health endpoint"` not `"health check endpoint API"`. More terms increase the chance of triggering the broken FTS backend. If you get exit code 9, try a single-term query or different terms.

### Step 2: Commit to the top-hit session and read it

**The session with the most search hits is almost always the right one.** Don't scatter across multiple sessions — commit to the top-hit session first and read enough of it before looking elsewhere.

**Start by exporting a large chunk** of the highest-hit session:

```bash
cass export /path/to/top-hit-session.jsonl | head -500
```

This gives you the full narrative flow in one call. Do NOT use `cass expand` on individual lines when a session has 3+ hits — one export replaces 4-5 separate expand calls.

**Only use `cass expand` if the session has just 1-2 hits:**

```bash
cass expand /path/to/session.jsonl --line 180 --context 15
```

**CRITICAL: Do not dismiss the top-hit session based on early content.** Conversations follow a natural arc: problem → investigation → solution. If you're looking for "health check endpoint" and the export starts with a "production outage" discussion, **the health check was the solution designed later in that same session**. Export more lines (`head -800`, `head -1000`) before concluding it's wrong. If a session has the most hits for your query, it contains your answer — you just haven't read far enough.

### Step 3: Summarize for the User

After reading the relevant session, provide a clear summary of:
- What was discussed / decided
- What was implemented (if applicable)
- Any key decisions or rationale

## Search Strategy

If the first search doesn't surface the right session:

1. **Try different 2-term queries** — e.g., `"health endpoint"` → `"smoke test"` → `"deploy 404"`
2. **Increase `--limit`** to 20 or 30 (output stays compact with `--fields minimal`)
3. **Use `--since` or `--days`** for time bounds (these work reliably unlike `--until`)
4. If exit code 9 occurs, reduce query to 2 terms and remove any filter flags

**Do NOT:**
- Add more terms to the query (triggers FTS bugs)
- Loop on `cass doctor --fix` (rarely fixes the FTS table)
- Pipe through `grep` (loses context from already-compact output)
- Give up after 2-3 tries — try different 2-term combinations first

## Fixing a Broken Index

If `cass index` fails with exit code 9 and `FOREIGN KEY constraint failed`, the incremental index has corrupt relational data. This is distinct from FTS/search exit-code-9 errors.

**Symptoms:**
- `cass index` exits 9 with `index failed: FOREIGN KEY constraint failed`
- `cass status` still shows "stale" after indexing
- `cass doctor --fix` reports "All checks passed" but doesn't fix it

**Fix: full rebuild**

```bash
cass index --full
```

This drops and rebuilds the entire database from raw JSONL files. Takes a few minutes for large histories (6000+ sessions) but reliably resolves FK issues. A regular `cass index` (incremental) will NOT fix it — it hits the same FK error each time.

**When to use `--full`:**
- After any FK constraint error from `cass index`
- After a CASS version upgrade that changes the DB schema
- If `cass doctor --fix` passes but `cass index` still fails

## Command Reference

| Task | Command |
|------|---------|
| Scan for sessions | `cass search "query" --json --limit 10 --fields summary` |
| Read around a hit | `cass expand /path/to/session.jsonl --line N --context 10` |
| Export full session | `cass export /path/to/session.jsonl` |
| View raw at line | `cass view /path/to/session.jsonl --line N --context 10` |
| Health check | `cass health --json` |
| Re-index | `cass index` |
| Fix broken index | `cass doctor --fix` |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using `--robot-format toon --fields minimal` | Silently returns 0 hits (bug in CASS 0.3.1). Use `--json --fields summary` instead |
| Using `--until` | Triggers FTS bugs with 3+ terms, excludes same-day conversations. Don't use it |
| Using `--workspace` | Requires broken FTS backend. Scan `source_path` in results instead |
| Using `$(date +%F)` | Triggers permission prompts. Don't use shell substitution in commands |
| Piping through `grep` | Output is already compact with `--fields minimal`. Read it directly |
| Queries with 3+ terms | Can trigger broken FTS backend. Stick to 2 key terms |
| Dismissing a high-hit session as "wrong topic" | Conversations have arcs (problem → solution). The session with the most hits is almost always right — read further forward |
| Multiple `cass expand` calls on same session | Use `cass export ... \| head -500` instead — one call replaces 4-5 expands |
| Looping on `cass doctor --fix` | If it fails once, move on. Reduce query terms and drop filter flags |
| Reading raw `.jsonl` with `cat` | Use `cass export` for markdown output |
| Using `cass show` | Command doesn't exist — use `cass view` or `cass export` |

## Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | — |
| 2 | Usage error | Check arguments |
| 3 | Missing index/db | Run `cass index` |
| 5 | Data corrupt | Run `cass doctor --fix` once |
| 9 | Broken FTS (search) | Reduce to 2 query terms, drop `--workspace`/`--until` |
| 9 | FK constraint (index) | Run `cass index --full` to rebuild from scratch |

## Tips

- Search results include `source_path` and `line_number` — use these with `cass expand`
- Sessions with many hits for your query are more likely to be the target conversation
- Your current session ID is in the environment or can be inferred from repeated `source_path` entries
- CASS indexes Claude Code, Codex, Cursor, Copilot, and other agent sessions automatically
