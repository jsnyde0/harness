# /harness — Compose a Harness for the Current Task

## What to Do

Design a feedback infrastructure for the task at hand. The output is a composed harness — a collection of verification mechanisms the agent will use to iterate.

### Step 1: Check for existing inventory

Look for `.claude/harness.md` in the current project. If it exists, read it — it contains the available feedback mechanisms for this repo with context on what each one catches and when it's useful.

If it doesn't exist and the repo is non-trivial, consider suggesting `/harness audit` to build one before composing — especially if the same harness questions are likely to recur across tasks.

### Step 2: Understand the task

What's being changed? What could go wrong? What does "working" look like for this specific change?

If the task framing reveals a research/theorizing loop with no empirical signal yet (e.g. "I've spent an hour reading code forming theories"), the harness itself is the intervention — lead with that reframe before composing. Code-reading generates theories faster than thinking falsifies them; the harness is what converges.

### Step 3: Compose the harness

Select and arrange feedback mechanisms, fastest-signal-first by default. Override the ordering when diagnostic logic requires it (e.g. build a minimal repro before flipping debug flags, because the repro is what the flags will instrument) — and note why. A harness is typically 2-5 mechanisms composed together — each one a distinct feedback signal, though overlap between mechanisms is fine if they catch different aspects. Be concrete enough that you could start executing the first mechanism immediately after approval.

**Draw from four strategies:**

- **Build** — create something that doesn't exist yet (probe script, test fixture, minimal repro, throwaway spike)
- **Connect** — plug into feedback that already exists (tail logs, curl endpoints, query DB, use MCP tools, check dashboards)
- **Configure** — make the system tell you more (debug logging, strict mode, verbose output, enable type checking)
- **Reduce** — make the problem smaller (minimal repro, smallest failing test, isolate one subsystem)

**When `.claude/harness.md` exists, it's a fifth draw-from source on equal footing with the four verbs above.** The strategies above are *verbs* (what to do); the inventory is a *source* (what's already known to be available and useful in this repo). Identify which specific inventory entries — and which fit profiles, if any apply to the task's work category — you're composing on, and name them in the proposal alongside the strategy-driven picks. This closes the read-then-forget gap where Step 1 reads the inventory and Step 4's proposal silently ignores it. If a fit profile in the inventory matches the task's work category, treat its recommendation as the default — overriding requires a stated reason.

If no project inventory exists, scan the repo for available mechanisms and **report what you found** (even if the answer is "nothing"):
- Look for test runners, linters, type checkers, build tools
- Check for running services, MCP tools, CLI tools
- Note what's available to connect to vs what needs to be built

Surface the scan result in a one-liner before composing — e.g. "scanned: package.json ❌, pytest ✓, docker-compose ❌". This forces the scan to happen and exposes stack mismatches (e.g. a Node-flavored prompt against a Python-only repo) before they become silent assumptions in the proposal.

### Step 4: Propose

Present the composed harness to the user. Lead with a concrete proposal — don't ask open questions. For each mechanism in the harness, state:
- What it is and what you'll run/build
- What it catches
- Why it's in the harness for THIS task

The user approves, adjusts, or redirects.

## Example Output

> **Harness for: fixing the data import timeout bug**
>
> 1. **Reproduce** (build): Create a minimal CSV with 10k rows that triggers the timeout — this becomes our iteration target
> 2. **Debug logging** (configure): Set `LOG_LEVEL=DEBUG` on the import service to see where it stalls
> 3. **Targeted test** (build): Write a pytest that imports the minimal CSV and asserts completion under 30s
> 4. **API probe** (connect): `curl -X POST localhost:3000/api/import` with the test file after each change
>
> Iteration loop: change code → run test → check logs → repeat

This is illustrative, not a template. Every harness is different.
