#!/usr/bin/env bash
# SessionEnd hook: commit learned-memory state to git-tracked files (no push).
#
# Cross-machine memory sync — the COMMIT half. Counterpart: sync-memory-in.sh.
# Runs once when the session closes (SessionEnd fires once per session, unlike Stop).
#   - bd memories: export the current repo's .beads/issues.jsonl (WITH memories —
#     bd 1.0.4 excludes them unless --include-memories), then commit JUST that file.
#   - cm playbook: the store now lives IN the repo at memory-sync/cass-store/, so
#     there is NO export step — playbook.yaml IS the tracked file. We just commit it
#     directly if it changed (only playbook.yaml is tracked; config/embeddings/logs
#     stay machine-local per .gitignore).
#
# Robot-commit discipline:
#   - Scoped pathspec commit (only the one file) — never sweeps up your working changes.
#   - Gated on actual change (no-op if the file is unchanged vs HEAD).
#   - Skipped if the file is gitignored, or a merge/rebase is in progress.
#   - NEVER pushes (per the global agent instructions file: pushing needs explicit ask). Memories ride
#     your next normal `git push`.
#   - Always exit 0; failures are swallowed (sync is best-effort, never blocks close).
set -u

export CASS_MEMORY_HOME="${CASS_MEMORY_HOME:-$HOME/.claude/memory-sync/cass-store}"

INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "${CWD:-}" ] && CWD="$PWD"

# commit_file <repo-dir> <path-relative-to-repo> <commit-message>
# Stages and commits ONLY the named path, gated and guarded. Best-effort.
commit_file() {
  local repo="$1" rel="$2" msg="$3"
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 0
  # Skip mid-merge / mid-rebase (worktree-safe via --git-path).
  git -C "$repo" rev-parse --verify -q MERGE_HEAD >/dev/null 2>&1 && return 0
  local p
  p=$(git -C "$repo" rev-parse --git-path rebase-merge 2>/dev/null); [ -d "$p" ] && return 0
  p=$(git -C "$repo" rev-parse --git-path rebase-apply 2>/dev/null); [ -d "$p" ] && return 0
  # Skip if the path is gitignored (git add would error / never commit).
  git -C "$repo" check-ignore -q "$rel" 2>/dev/null && return 0
  git -C "$repo" add -- "$rel" >/dev/null 2>&1 || return 0
  # Nothing staged for this path => unchanged => done.
  git -C "$repo" diff --cached --quiet -- "$rel" 2>/dev/null && return 0
  git -C "$repo" commit -q -m "$msg" -- "$rel" >/dev/null 2>&1 || true
}

# bd: export memories+issues for the current repo, then commit the single file.
if command -v bd >/dev/null 2>&1 && [ -d "$CWD/.beads" ]; then
  ( cd "$CWD" && bd export --include-memories -o .beads/issues.jsonl >/dev/null 2>&1 ) \
    || echo "[sync-memory-out] bd export failed in $CWD" >&2
  commit_file "$CWD" ".beads/issues.jsonl" "chore(beads): sync memories+issues [auto]"
fi

# cm: the playbook store lives in-repo (memory-sync/cass-store/), so there's no
# export — just commit playbook.yaml directly if it changed. cm mutates it only on
# rule add/edit or feedback (helpfulCount/feedbackEvents/updatedAt), never on plain
# reads, so this produces meaningful diffs, not per-session noise.
commit_file "$HOME/.claude" "memory-sync/cass-store/playbook.yaml" "chore(cm): sync playbook [auto]"

exit 0
