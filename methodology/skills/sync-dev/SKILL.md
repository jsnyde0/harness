---
name: sync-dev
description: Sync feature branch with latest dev (merge or rebase)
---

Sync your feature branch with the latest `dev`. Merges by default, suggests rebase when signals point that way. Auto-resolves trivial conflicts, triages the rest with you.

**Arguments:** `$ARGUMENTS` → `[strategy-override]`
- strategy-override: optional — `merge` or `rebase` to skip strategy analysis

## Process

### 1. Pre-flight checks

- Confirm we're NOT on `dev` or `main` (abort if so — "nothing to sync, you're on dev/main")
- Confirm there are no uncommitted changes (abort if so — "commit or stash first")
- `git fetch origin dev`

### 2. Divergence analysis

Gather the branch topology:
- Commits ahead of dev: `git log origin/dev..HEAD --oneline`
- Commits behind dev: `git log HEAD..origin/dev --oneline`
- If 0 commits behind → "Already up to date with dev" and exit

Report the divergence: "Your branch is N commits ahead, M commits behind dev."

### 3. Strategy selection

If a strategy-override argument was provided, use it. Otherwise, analyze signals.

**Default: merge.** Merge is always the safe choice. But rebase can be better in some situations. Use signals, not rules.

#### Rebase signals (reasons rebase might be better)
- Branch history is linear (no merge commits already present)
- All commits are your own work (not shared with others)
- Conflicts are few or zero (dry-run shows clean or near-clean)
- The result would be a clean, readable history on top of dev

#### Merge signals (reasons to stick with merge)
- Branch already contains merge commits (rebase would flatten/complicate them)
- Branch has been pushed and others may have based work on it
- Many conflicts expected (rebase resolves per-commit, merge resolves once — less painful)
- Complex history where rewriting would lose meaningful structure

These are smells, not rules. When signals conflict, name the tradeoff and recommend one.

**Present the recommendation:**
- If signals clearly favor one strategy → recommend it with reasoning, ask to confirm
- If signals are mixed → present both with the tradeoffs, ask the human to pick
- If strategy-override was given → skip this, just proceed

### 4. Dry run

Before executing, preview what will happen:

**For merge:**
```bash
git merge --no-commit --no-ff origin/dev
```

**For rebase:**
```bash
git rebase --no-autosquash origin/dev --exec "echo ok"
```
(abort after to just preview, then re-run for real)

Inspect the result:
- If clean (no conflicts) → report "Clean merge/rebase, no conflicts" and proceed
- If conflicts → go to conflict resolution (step 5)

### 5. Conflict resolution

#### Trivial conflicts (auto-resolve)

These can be resolved without asking:
- **Formatting/whitespace:** Indentation, trailing commas, blank lines, import sorting
- **Non-overlapping additions:** Both sides added different items to the same area (imports, list items, switch cases). Take both.
- **Obvious "take theirs":** Your branch didn't intentionally change a section, but it conflicts because of nearby edits. Use diff context to determine intent — if your side's change is incidental (e.g., a reformat that touched adjacent lines), take dev's version.

Report all auto-resolutions: "Auto-resolved N trivial conflicts: [brief summary]"

#### Non-trivial conflicts (triage with human)

For each remaining conflict:
1. **Show the conflict** with surrounding context (enough to understand the area)
2. **Explain both sides:** What your branch did vs what dev did, and why they clash
3. **Suggest a resolution** with rationale (take ours, take theirs, combine, rewrite)
4. **Ask human to confirm** or provide alternative resolution

After all conflicts are resolved, complete the merge/rebase.

### 6. Verify

Run the full test suite to catch merge-induced breakage. Same stack-awareness as `/pr` — skip stacks that weren't touched by the combined changes.

**Frontend** (from `app/frontend/`):
```bash
yarn --cwd app/frontend typecheck
yarn --cwd app/frontend lint
yarn --cwd app/frontend vitest run
```

**Backend** (from `app/backend/functions/api/`):
```bash
cd app/backend/functions/api && uv run pytest
```

**Migration validation** (if the merge introduced migration changes):
```bash
bash scripts/validate-migrations.sh
```
Only run if the merged commits include files under `app/backend/functions/api/migrations/`. The script auto-starts its Docker container (`migration-test-pg`) — no manual setup needed.

**If tests fail:**
- Report what broke
- Iterate: fix the failures, re-run tests, repeat until green
- These are merge-induced issues — fix them as part of the sync, don't leave them for later

### 7. Report

```
Synced with dev via [merge/rebase].
- N commits from dev integrated
- X conflicts auto-resolved, Y resolved with you
- Tests passing: [results summary]
```

## Aborting

At any point before the merge/rebase completes, the user can say "abort". Clean up:
- `git merge --abort` or `git rebase --abort`
- Report: "Sync aborted, branch unchanged."

If the merge is already committed but tests are failing and can't be fixed:
- Offer: "Want me to undo the merge? (`git reset --hard HEAD~1` to go back to before the merge)"
- Only do this with explicit user approval — it's destructive
