# /harness audit — Build a Project Harness Inventory

## What to Do

Scan the current repo and produce (or update) a `.claude/harness.md` file — a catalog of all available feedback mechanisms with context that helps agents compose harnesses for specific tasks.

### Step 1: Scan the repo

**Memory beats blank-slate scanning.** Before the filesystem scan, re-survey what's already known about verifying this repo. Invoke `/recall` to tier-route across L3 ADRs + L2B `bd memories` + L2A CASSMS for verification-relevant lessons about this stack and repo. When `/recall` isn't invokable in the execution context (e.g., dispatched subagent without `Skill` tool access), use surrogate reads: `bd memories <repo-name>`, `bd memories <stack-keyword>` (e.g. `bd memories pytest`, `bd memories bigquery`), and a scan of `docs/decisions/INDEX.md` for verification-relevant ADRs. Fold findings into the existing six categories below — memory is the *source*, not a new kind. A "BQ schema probe is the fastest verifier for ingestion bugs" memory lands under runtime/observable, not in a separate from-memory bucket. Memory often informs *where* to look in the filesystem (e.g., "this repo has a custom verifier script at `scripts/verify-X.sh`"), so consulting it before the category scan compounds. Per ADR-013 D11 (juncture-awareness — before substrate write, re-survey what's already known): writing or updating `.claude/harness.md` is the substrate write that triggers this discipline.

**Extensions beat defaults.** Before and during the category scan, ask whether the repo customizes or extends any tool it uses — *including build/dev tools that seem like "just infrastructure"* (dev servers, bundlers, task runners, git hooks). Extensions can turn non-signal tools into signal sources: a dev-server plugin might pipe browser state to the terminal, a conftest might add fixtures, a Husky hook might do more than run lint-staged. When you see a tool's config file — even one you'd normally skip as boilerplate — open it; if it imports repo-local files, read them. A vanilla tool and a heavily-extended one are different harnesses.

Look for verification mechanisms across these categories:

**Static/fast signals** — type checkers, linters, formatters, schema validators, security scanners
- Check: package.json scripts, Makefile/Taskfile targets, pyproject.toml tool configs, CI configs

**Test suites** — unit, integration, E2E, contract, visual regression
- Check: test directories, test configs (jest.config, pytest.ini, vitest.config), CI test steps

**Runtime/observable** — running services, APIs, databases, log outputs, dashboards
- Check: docker-compose.yml, Procfile, MCP server configs, health endpoints

**Tools & CLIs** — project-specific CLIs, MCP tools, build tools, migration tools
- Check: .mcp.json, bin/ or scripts/ directories, Homebrew formulae, installed CLIs

**Grounding & design context** — agent definitions, ADRs, design docs that constrain or inform decisions
- Check: `agents/` or `.claude/agents/` (reviewer/debugger subagents are a feedback mechanism), `docs/decisions/` or `adr/` (ADRs ground current-state assumptions)

**Build-it patterns** — what kinds of things could be built when no existing check fits?
- Consider: the tech stack, the test framework, available REPL/scripting tools

### Step 2: For each mechanism, capture context

Don't just list commands. For each mechanism, include:

- **What it is** — one line describing the mechanism
- **Command** — how to invoke it (if ready-to-run)
- **Speed** — approximate time (seconds/minutes)
- **Catches** — what kinds of problems it reveals
- **Useful when** — positive signals for when this mechanism fits
- **Less useful when** — situations where this mechanism won't help much

This context helps agents select the right mechanisms without prescriptive rules. The agent reads the signals and uses judgment.

If a field doesn't apply to a given mechanism (e.g., a sound-player has no "Catches"), omit it and note why in the "What it is" line — this prevents readers from confusing "author forgot" with "genuinely N/A".

When a tool is available via machine/global install but NOT configured in the repo (e.g., `uvx ruff` works but no ruff config exists), note that explicitly — it changes portability (teammates without the tool installed won't see the same signal) and signals a clear build-it target (add the config).

### Step 3: Note build-it options

List patterns for building feedback mechanisms that don't exist yet. These are strategies, not commands:

- Probe scripts (quick throwaway scripts that poke the system)
- Targeted tests (tests written for a specific change)
- Minimal repros (stripped-down cases that isolate one thing)
- Log injection (adding temporary logging to trace a specific flow)
- Data fixtures (sample datasets that exercise specific paths)

Include context on what tools/frameworks are available for building these (e.g., "pytest is configured, so building a targeted test is straightforward").

Not every repo has a test runner or CI pipeline. The inventory should reflect what actually exists — if the only way to verify something is a manual probe or a live session, that's worth capturing too.

### Step 4: Write the inventory

Write to `.claude/harness.md` — always. This is the canonical location, no exceptions. Even in a repo that *is* the methodology home itself, the inventory goes in the nested `.claude/.claude/harness.md` (the inner `.claude/` holds project-level Claude config for that repo). If `.claude/` doesn't exist yet, create it. If a `harness.md` exists at a non-canonical path (e.g. repo root), move it. If the file already exists at the canonical path, update it — repos evolve, new tools get added, old ones get removed.

The format should be scannable — agents will read this at task time to quickly find relevant mechanisms. Group by speed (fastest first) or by category, whichever makes more sense for the project. Err toward fewer mechanisms with richer context over many thin entries — a well-characterized mechanism is more useful than a name and a command.

**Fit profiles — required, not optional.** For each category of work the repo actually performs, include a fit profile block in the inventory. The schema:

```
### Fit profiles

For [X kind of work] in this repo, prefer [Y mechanism] because [Z reason — what it catches that others miss at lower cost].
```

Examples:
- "For Django view changes in this repo, prefer `pytest tests/views/` over `./manage.py runserver` manual probing because the view test suite is fast (< 10s) and catches auth, permission, and template errors in one pass."
- "For Alpine.js component changes, prefer `soldier-proof`-style dry-run in a live session because Alpine reactivity bugs don't surface under static analysis."
- "For data migrations in this repo, prefer running `./manage.py migrate --run-syncdb` on the test DB before `pytest` because Django may apply the schema differently from what `makemigrations --check` reports."

A fit profile is NOT:
- A bare category listing ("Django: pytest")
- A command reference without the rationale
- A rule that applies universally regardless of repo patterns

The fit profiles are the primary substrate that `/harness` compose consults when selecting a signal (inventory-first discipline). Without fit profiles, compose falls back to cold scanning — slower and less calibrated to actual work patterns in the repo.

**When updating an existing inventory** (not starting fresh): don't stop at "what's changed since last audit." Also:

- Re-run the Step 1 memory consultation — `bd memories` and ADRs accumulate verification lessons between audits; new memory-sourced findings fold into the same six categories, same discipline as a fresh audit.
- Re-scan the repo against the **current** Step 1 categories — the prior author may have written the inventory before a category existed, leaving gaps that aren't git-diff-visible.
- Retrofit existing entries against the current Step 2 field guidance (e.g., apply the omit-and-note pattern to pre-existing thin entries).
- Add or update fit profiles per the schema above, grounded in observed work patterns in this repo — not generic best practices.

Optional sections worth including when they apply:

- **Conventions worth knowing** — non-obvious repo traps a fresh agent would stumble into (blocked commands, inverted-gitignore patterns, sensitive-path rules, required confirmation prompts). These don't fit the per-mechanism template but prevent silent failures.
- **Entrypoints** — pointers to top-level files or directories that orient an agent (e.g., "start here: `CLAUDE.md`, `.beads/`, `skills/`"). Useful in repos with non-standard layouts.

### Step 5: Check .gitignore / CLAUDE.md

- Verify the inventory file is tracked: run `git check-ignore -v <path>` — if it returns a match, the file is being ignored.
- If the repo uses an ignore-everything-by-default `.gitignore` (starts with `*` and un-ignores specific files with `!` entries), add an explicit `!harness.md` entry so the inventory is tracked.
- Consider adding a brief pointer in the project's CLAUDE.md so agents know the inventory exists.

## Adding a single entry (escape hatch)

When the user asks to add a specific mechanism ("add X to the harness inventory", "we're missing Y from harness.md") — a full re-audit isn't needed. This is the path when the user's judgment beats the auditor's scan.

1. Read the existing `harness.md` (or create it fresh if absent — in that case follow Step 4 for location).
2. Inspect the mechanism being added. If it's code (a plugin, middleware, hook, conftest), read the source — don't describe it from its filename.
3. Apply **Step 2**'s per-field treatment: what-it-is, command, speed, catches, useful-when, less-useful-when. Omit-and-note for N/A fields.
4. Insert into the appropriate category and preserve existing ordering.
5. Step 5 still applies — check gitignore and the CLAUDE.md pointer, but usually both are already satisfied.

Don't silently expand scope beyond what the user asked for. If you notice adjacent mechanisms that also look missing, surface them as a question rather than adding them.

## What the Inventory Is NOT

- Not a set of rules ("always run X for Y changes")
- Not a CI pipeline definition
- Not exhaustive — it's a living document that gets updated
- Not a substitute for judgment — agents still compose harnesses per-task

The inventory is a **pantry** — it tells you what ingredients are available. The agent decides what to cook.
