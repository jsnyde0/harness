#!/usr/bin/env bash
# SessionStart hook: pull learned-memory state INTO local stores (silent side-effect).
#
# Cross-machine memory sync — the IMPORT half. Counterpart: sync-memory-out.sh.
#
# SYNC MODEL (JSONL-carrier, bd 1.0.5 embedded):
#   - Each repo's .beads/issues.jsonl is the cross-machine carrier (git-tracked,
#     exported with --include-memories via sync-memory-out.sh / SessionEnd).
#   - Each machine builds its OWN LOCAL embedded Dolt store from issues.jsonl.
#     The embedded store lives in .beads/embeddeddolt/<db>/ and is gitignored.
#   - This hook is the SessionStart IMPORT half: on a fresh clone (no local
#     embedded store), it self-heals by building a clean store from issues.jsonl.
#     On an existing healthy repo, it runs bd import idempotently.
#
# SELF-HEAL (fresh clone or broken store → embedded mode only):
#   bd 1.0.5 auto-adopts the git origin's refs/dolt/data on plain `bd init`,
#   which on repos with a stale remote dolt history causes a migration crash.
#   To avoid adoption, the self-heal temporarily removes the git origin, runs
#   `bd init` (no origin → no adoption), restores origin, then imports from
#   issues.jsonl. The embedded store is local-only; no dolt push happens.
#
# SAFETY MECHANISMS:
#   - Transient ping retry: bd ping is retried once (after 1s) before self-heal
#     is triggered. Lock contention is typically transient.
#   - Non-destructive move-aside: if a non-empty store dir already exists, it
#     is MOVED to .beads/embeddeddolt.broken-<epoch> (not deleted), so a false-
#     positive self-heal is fully recoverable. Only absent/empty dirs are wiped.
#   - Origin-crash recovery: before removing origin, the URL is written to
#     .beads/.origin-restore. If a prior run crashed mid-operation, the hook
#     restores origin from that sentinel at startup. The sentinel is deleted
#     once origin is successfully re-added.
#   - Concurrency guard: the entire self-heal block is protected by an atomic
#     mkdir-based lock (.beads/.selfheal.lock). If another SessionStart is
#     already self-healing this repo, the new invocation exits 0 silently.
#     Stale locks (older than 120s) are auto-expired. NOTE: macOS ships without
#     flock(1); mkdir is used instead (POSIX-atomic on all local filesystems).
#   - Post-rebuild verification: after bd init + bd import, bd ping is run to
#     confirm the rebuilt store actually opens. On failure a warning is emitted
#     to stderr and the session continues.
#
# DETECTION:
#   Run `bd ping` from INSIDE the repo (cd required — bd uses the process CWD
#   for store location). Exits 0 if the local store opens cleanly; exits 1 if
#   no store found or store fails to open (absent, empty, or stale migration).
#
# DISCIPLINE:
#   - Emits NOTHING to stdout (SessionStart stdout pollutes model context).
#     All normal output to /dev/null; warnings to stderr only.
#   - bd import is additive/idempotent: upsert by id / REPLACE by memory key.
#   - Always exit 0; never block session start.
#   - Mode-aware: only self-heals embedded stores. Server-mode repos just get
#     a best-effort import (the server admin manages the server lifecycle).
set -u

# Pin cm's data dir so both machines resolve the same in-repo store regardless of
# local XDG_DATA_HOME (defense-in-depth; also set in ~/.zshenv). See memory-sync/README.
export CASS_MEMORY_HOME="${CASS_MEMORY_HOME:-$HOME/.claude/memory-sync/cass-store}"

# Resolve the session's working directory from the hook's stdin JSON; fall back to $PWD.
INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "${CWD:-}" ] && CWD="$PWD"

# Bail early if no bd available or no JSONL carrier in this repo.
if ! command -v bd >/dev/null 2>&1; then
  exit 0
fi
if [ ! -f "$CWD/.beads/issues.jsonl" ]; then
  exit 0
fi

# Bail early if no metadata.json (not a recognized beads project).
METADATA="$CWD/.beads/metadata.json"
if [ ! -f "$METADATA" ]; then
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# ORIGIN-CRASH RECOVERY: if a prior run crashed between
# `remote remove origin` and the restore, .beads/.origin-restore
# exists but origin is gone. Restore it now so the repo is healthy
# before doing anything else.
# ─────────────────────────────────────────────────────────────
ORIGIN_RESTORE_FILE="$CWD/.beads/.origin-restore"
if [ -f "$ORIGIN_RESTORE_FILE" ]; then
  # Only act if origin is actually missing (crash recovery).
  if ! git -C "$CWD" remote get-url origin >/dev/null 2>&1; then
    SAVED_URL=$(cat "$ORIGIN_RESTORE_FILE" 2>/dev/null || true)
    if [ -n "$SAVED_URL" ]; then
      if git -C "$CWD" remote add origin "$SAVED_URL" >/dev/null 2>&1; then
        rm -f "$ORIGIN_RESTORE_FILE" 2>/dev/null || true
        echo "[sync-memory-in] Restored git origin from crash-recovery sentinel in $CWD" >&2
      else
        echo "[sync-memory-in] WARNING: crash-recovery sentinel found but could not restore origin in $CWD — sentinel retained" >&2
      fi
    fi
  else
    # Origin exists; sentinel is stale (from a previously-completed run that
    # forgot to clean up, or a partial write). Remove it.
    rm -f "$ORIGIN_RESTORE_FILE" 2>/dev/null || true
  fi
fi

# Read dolt_mode from metadata.json (default: embedded).
DOLT_MODE=$(jq -r '.dolt_mode // "embedded"' "$METADATA" 2>/dev/null || echo "embedded")
DOLT_DB=$(jq -r '.dolt_database // ""' "$METADATA" 2>/dev/null || echo "")

# ─────────────────────────────────────────────────────────────
# SERVER MODE: just attempt import; server lifecycle not managed
# by this hook. Ignore import errors (server may be down, etc.)
# ─────────────────────────────────────────────────────────────
if [ "$DOLT_MODE" = "server" ]; then
  IMPORT_OUT=$(cd "$CWD" && bd import .beads/issues.jsonl 2>&1) || {
    # Log FK violations as warnings; silently ignore others (e.g. server down).
    if printf '%s' "$IMPORT_OUT" | grep -q 'fk_counter_parent\|foreign key violation'; then
      echo "[sync-memory-in] WARNING: bd import FK violation in $CWD (orphaned child in issues.jsonl) — session continues" >&2
    fi
    true
  }
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# EMBEDDED MODE: detect store health, self-heal if needed
# ─────────────────────────────────────────────────────────────

# Detect whether the local embedded store opens cleanly.
# Must cd into the repo — bd uses the process CWD for store location.
# bd ping: exit 0 = store opens fine; exit 1 = absent, empty, or migration crash.
# Run in a subshell so cd does not affect the outer shell's working directory.
if ( cd "$CWD" && bd ping >/dev/null 2>&1 ); then
  # ── HAPPY PATH: local store is working → idempotent import only ──────────
  IMPORT_OUT=$(cd "$CWD" && bd import .beads/issues.jsonl 2>&1) || {
    if printf '%s' "$IMPORT_OUT" | grep -q 'fk_counter_parent\|foreign key violation'; then
      echo "[sync-memory-in] WARNING: bd import FK violation in $CWD (orphaned child in issues.jsonl) — session continues" >&2
    fi
    # "nothing to commit" and other idempotent-import errors: silently ignored.
    true
  }
  exit 0
fi

# ── TRANSIENT RETRY: absorb lock contention before deciding to self-heal ────
# bd ping failed on the first attempt — wait 1s and retry once.
# Lock contention is transient; only treat as broken if the retry also fails.
sleep 1
if ( cd "$CWD" && bd ping >/dev/null 2>&1 ); then
  # Store opened on retry — transient issue. Run idempotent import and exit.
  IMPORT_OUT=$(cd "$CWD" && bd import .beads/issues.jsonl 2>&1) || {
    if printf '%s' "$IMPORT_OUT" | grep -q 'fk_counter_parent\|foreign key violation'; then
      echo "[sync-memory-in] WARNING: bd import FK violation in $CWD (orphaned child in issues.jsonl) — session continues" >&2
    fi
    true
  }
  exit 0
fi

# ── CONCURRENCY GUARD: mkdir-based atomic lock ──────────────────────────────
# macOS ships without flock(1); mkdir is POSIX-atomic on all local filesystems.
# If another SessionStart is already self-healing this repo, skip and exit 0.
# Stale locks (mtime > 120s ago) are auto-expired before attempting to acquire.
SELFHEAL_LOCK="$CWD/.beads/.selfheal.lock"
LOCK_TIMEOUT=120  # seconds — generous upper bound for the self-heal sequence

# Expire stale lock if present (mtime-based; 120s should be more than enough).
if [ -d "$SELFHEAL_LOCK" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -f '%m' "$SELFHEAL_LOCK" 2>/dev/null || echo 0) ))
  if [ "$LOCK_AGE" -gt "$LOCK_TIMEOUT" ]; then
    rmdir "$SELFHEAL_LOCK" 2>/dev/null || true
    echo "[sync-memory-in] Expired stale self-heal lock (${LOCK_AGE}s old) in $CWD" >&2
  fi
fi

# Try to acquire the lock (non-blocking).
if ! mkdir "$SELFHEAL_LOCK" 2>/dev/null; then
  # Another session is self-healing; skip silently.
  exit 0
fi

# Ensure the lock is released on exit (normal or unexpected).
_release_selfheal_lock() {
  rmdir "$SELFHEAL_LOCK" 2>/dev/null || true
}
trap _release_selfheal_lock EXIT

# ── SELF-HEAL PATH: build a clean local embedded store from issues.jsonl ───
# bd ping failed twice → store is absent, empty, or fails to open (stale migration).

# Derive the issue prefix from dolt_database name (they match in bd 1.0.5).
PREFIX="${DOLT_DB}"
if [ -z "$PREFIX" ]; then
  # Fallback: use the directory's basename (same heuristic bd init uses).
  PREFIX=$(basename "$CWD")
fi

echo "[sync-memory-in] No working local embedded store in $CWD — self-healing from issues.jsonl" >&2

# Step 1: Save the git origin URL to a crash-recovery sentinel file, then
#         temporarily remove origin to prevent bd from adopting stale remote
#         refs/dolt/data. If killed mid-operation, the next hook invocation
#         reads the sentinel and restores origin automatically (see startup
#         crash-recovery block above).
ORIGIN_URL=$(git -C "$CWD" remote get-url origin 2>/dev/null || true)
ORIGIN_REMOVED=0
if [ -n "$ORIGIN_URL" ]; then
  # Write sentinel BEFORE removing origin (crash-safe ordering).
  printf '%s\n' "$ORIGIN_URL" > "$ORIGIN_RESTORE_FILE" 2>/dev/null || true
  if git -C "$CWD" remote remove origin >/dev/null 2>&1; then
    ORIGIN_REMOVED=1
  else
    # Could not remove — skip sentinel (origin still present; not needed).
    rm -f "$ORIGIN_RESTORE_FILE" 2>/dev/null || true
  fi
fi

# Step 2: Handle the existing store directory.
#   - If it exists AND is non-empty: MOVE aside (recoverable).
#   - If absent or empty: just wipe (find -delete is safe on empty dirs).
STORE_DIR="$CWD/.beads/embeddeddolt"
if [ -d "$STORE_DIR" ]; then
  # Check if the store dir has any content (mindepth 1 to exclude the dir itself).
  STORE_CONTENTS=$(find "$STORE_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)
  if [ -n "$STORE_CONTENTS" ]; then
    # Non-empty: move aside to a timestamped backup directory (recoverable).
    BACKUP_DIR="$CWD/.beads/embeddeddolt.broken-$(date +%s)"
    if mv "$STORE_DIR" "$BACKUP_DIR" 2>/dev/null; then
      echo "[sync-memory-in] Moved non-empty broken store aside → $BACKUP_DIR" >&2
    else
      # mv failed (cross-device?); fall back to targeted delete with a warning.
      echo "[sync-memory-in] WARNING: could not move broken store aside in $CWD — removing contents" >&2
      find "$STORE_DIR" -mindepth 1 -delete 2>/dev/null || true
    fi
  else
    # Empty dir: safe to remove contents (idempotent; removes nothing in practice).
    find "$STORE_DIR" -mindepth 1 -delete 2>/dev/null || true
  fi
fi

# Step 3: Run bd init to create a clean local embedded store.
#         Must cd into the repo — bd init requires being in the project directory.
INIT_OUT=$(cd "$CWD" && bd init -p "$PREFIX" --non-interactive --skip-hooks --skip-agents 2>&1)
INIT_EXIT=$?

# Step 4: Restore the git origin before any further bd commands.
if [ "$ORIGIN_REMOVED" = "1" ]; then
  if git -C "$CWD" remote add origin "$ORIGIN_URL" >/dev/null 2>&1; then
    # Origin restored — delete the crash-recovery sentinel.
    rm -f "$ORIGIN_RESTORE_FILE" 2>/dev/null || true
  else
    echo "[sync-memory-in] WARNING: could not restore git origin in $CWD — sentinel retained for next-run recovery" >&2
  fi
fi

if [ "$INIT_EXIT" -ne 0 ]; then
  echo "[sync-memory-in] WARNING: bd init failed in $CWD: $INIT_OUT — session continues" >&2
  exit 0
fi

# Step 5: Import issues and memories from the JSONL carrier.
IMPORT_OUT=$(cd "$CWD" && bd import .beads/issues.jsonl 2>&1) || {
  if printf '%s' "$IMPORT_OUT" | grep -q 'fk_counter_parent\|foreign key violation'; then
    echo "[sync-memory-in] WARNING: bd import FK violation in $CWD (orphaned child in issues.jsonl) — session continues" >&2
  else
    echo "[sync-memory-in] WARNING: bd import failed in $CWD: $IMPORT_OUT — session continues" >&2
  fi
  true
}

# Step 6: Post-rebuild verification — confirm the rebuilt store actually opens.
#         A PREFIX/db-name mismatch causes a silent failure at import time; this
#         catches it before the session starts.
if ! ( cd "$CWD" && bd ping >/dev/null 2>&1 ); then
  echo "[sync-memory-in] WARNING: rebuilt store does not open in $CWD (possible PREFIX/db-name mismatch) — session continues" >&2
fi

# cm: no import — the playbook store is in-repo (memory-sync/cass-store/) and cm reads
# it live, so `git pull` alone makes new rules visible. (See sync-memory-out.sh.)

exit 0
