---
name: rollback
description: Revert a release and tag a rollback patch version
---

Revert a broken release on `main` by undoing its commits and publishing a new patch version.

**Arguments:** `$ARGUMENTS` → `[version-to-revert]`
- version-to-revert: optional — the version to roll back (defaults to current version)

## When to Use

This is the **emergency option** — use when a release is fundamentally broken and the fix isn't obvious. If the fix is known and small, prefer a hotfix forward (`/release patch`) instead.

## Process

### 1. Pre-flight checks

- Confirm we're on `main` (abort if not — "switch to main first")
- Confirm there are no uncommitted changes (abort if so — "commit or stash first")
- `git fetch origin main`
- Confirm local main is up to date with remote (abort if behind — "pull first")

### 2. Identify what to revert

- Read current version from `VERSION` file
- If version-to-revert argument provided, verify it matches a tag and is reachable
- If not provided, use the current version
- Find the previous version tag (the one before the version being reverted)
- List the commits between the two tags: `git log v<previous>..v<current> --oneline`

Present the situation clearly:
```
Current version: v1.1.0
Previous version: v1.0.0
Commits to revert (N):
  abc1234 feat: add new feature X
  def5678 feat: add new feature Y
  ghi9012 release: v1.1.0
```

### 3. Scope selection

Not all changes in a release may be broken. Ask the user:

- **Full rollback** — revert everything since the previous version tag
- **Partial rollback** — select which commits/merge to revert (user picks from list)

For full rollback, revert the merge commit that brought dev into main (if it was a merge), which undoes all changes in one revert.

For partial rollback, revert only the selected commits. Warn if this may leave the codebase in an inconsistent state.

### 4. Confirm

Show exactly what will happen:
```
This will:
  1. Revert [N commits / the merge commit] on main
  2. Bump version: v1.1.0 → v1.1.1
  3. Create rollback changelog
  4. Tag v1.1.1 and push

The v1.1.0 tag will remain as historical record.
Proceed? (yes/no)
```

**Do NOT proceed without explicit confirmation.** This is a destructive operation on the main branch.

### 5. Revert

For a merge commit (most common — dev was merged into main):
```bash
git revert -m 1 <merge-commit-hash> --no-edit
```

For individual commits:
```bash
git revert <hash1> <hash2> ... --no-edit
```

If there are conflicts:
- Show each conflict with context
- Ask user how to resolve (same approach as `/sync-dev` conflict resolution)
- Do NOT auto-resolve rollback conflicts — every resolution needs user eyes

### 6. Ask for rollback reason

Ask the user: "Why is this release being rolled back?"

This goes into the changelog and commit message for future reference.

### 7. Generate rollback changelog

Create `docs/docu/changelog/v<new-version>.md`:

```markdown
# v<new-version> — YYYY-MM-DD (rollback)

## Rollback

Reverts v<reverted-version>: <reason from user>

### Reverted Changes

- **Feature/Fix Name** — reverted because <reason>

### Preserved Changes

- **Feature/Fix Name** — kept, unaffected by rollback
```

Only include "Preserved Changes" section for partial rollbacks.

Present for review before writing.

### 8. Update VERSION file

Bump the patch version (e.g., 1.1.0 → 1.1.1).

The rollback is a new version, not a return to the old version number. Version numbers only move forward.

### 9. Update docs

Check if `features.md` or `datasets.md` reference anything that was just reverted. If so, suggest reverting those doc entries too (same approve/reject flow as `/release`).

### 10. Commit and tag

Stage all changed files:
- `VERSION`
- `docs/docu/changelog/v<new-version>.md`
- `docs/docu/features.md` (if updated)
- `docs/docu/datasets.md` (if updated)
- Any files changed by the revert

Commit:
```
release: v<new-version> (rollback of v<reverted-version>)

<reason from user>
```

Create annotated git tag:
```bash
git tag -a v<new-version> -m "Rollback of v<reverted-version>: <reason>"
```

### 11. Push

```bash
git push origin main
git push origin v<new-version>
```

### 12. Report

```
Rolled back v<reverted-version> → released v<new-version>

Reason: <reason>
Reverted: N commits
Changelog: docs/docu/changelog/v<new-version>.md

Docs:
  - features.md: updated / no changes needed
  - datasets.md: updated / no changes needed

Git:
  - Tag: v<new-version>
  - Pushed to origin/main

Note: v<reverted-version> tag preserved as historical record.
```

## Important

- **Version numbers only go forward.** A rollback of v1.1.0 becomes v1.1.1, never back to v1.0.0.
- **Tags are never deleted.** The broken release tag stays for auditability.
- **History is never rewritten.** No `git reset`, no force push on `main`.
- **Always get explicit confirmation** before reverting on `main`.
