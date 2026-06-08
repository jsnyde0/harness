---
name: worktree
description: Create isolated git worktree for parallel development
---

Create an isolated workspace for a feature/change using git worktrees.

**Arguments:** `$ARGUMENTS` → `[branch-name]`
- branch-name: optional - defaults to current change context or asks

## When to Use

- Before `/brainstorm` - isolate exploratory work
- Before `/implement` - isolate feature development
- Anytime you want parallel development without branch switching

## Methodology

Use Skill(superpowers:using-git-worktrees) for the setup process.

This skill handles:
- Directory selection (.worktrees/ or global location)
- .gitignore verification (prevents accidental commits)
- Project setup (yarn install, etc.)
- Environment file copying (.env.development, .env.production, etc.)
- Test baseline verification

## Branch Naming

**Priority order** (if no branch-name provided):
1. Bead exists → `feat/<bead-id>-<short-desc>` (e.g., `feat/mp-5ef-app-header`)
2. Exploratory → `explore/<desc>` (e.g., `explore/caching-strategy`)
3. Bug fix → `fix/<desc>` (e.g., `fix/login-redirect`)

**Conventions:**
- `feat/<bead-id>-<desc>` - planned feature work (preferred, links to bead tracking)
- `fix/<desc>` - bug fixes
- `explore/<desc>` - exploratory/brainstorming

**Recommended workflow:** `/beadify` → `/worktree` ensures plans land on dev first (visible to team) and branch includes bead ID for traceability.

## Process

1. **Invoke skill**
   Skill(superpowers:using-git-worktrees) handles:
   - Directory selection (existing > CLAUDE.md > ask)
   - .gitignore verification
   - Worktree creation
   - Dependency installation
   - Test verification

   **IMPORTANT:** Override the worktree creation step — use `bd worktree create` instead of `git worktree add`:
   ```bash
   bd worktree create .worktrees/<name> --branch <branch-name>
   ```
   This ensures `.beads/redirect` is set up so the worktree shares the main beads database. Without it, `bd` commands will fail in the worktree.

2. **Copy environment files**
   After worktree creation, copy environment files that are gitignored (won't transfer automatically).

   Detect and copy from main worktree:
   ```bash
   # Root .env (MCP server secrets, dotenv-cli)
   [ -f ".env" ] && cp ".env" "<worktree>/"

   # Frontend .env files
   for f in .env .env.local .env.development .env.production; do
     [ -f "app/frontend/$f" ] && cp "app/frontend/$f" "<worktree>/app/frontend/"
   done

   # Backend API local settings (Azure Functions)
   [ -f "app/backend/functions/api/local.settings.json" ] && \
     cp "app/backend/functions/api/local.settings.json" "<worktree>/app/backend/functions/api/"
   ```

   Report what was copied (or "No environment files to copy" if none found).

3. **Materialize Git LFS files**
   New worktrees inherit LFS config but may have pointer stubs instead of real files until `git lfs pull` runs. Tests that rely on binary fixtures (parquet, images) will fail with `footer != PAR1` or similar errors if this step is skipped.

   ```bash
   git -C <worktree> lfs pull
   ```

   Fast no-op when files are already cached. Do this before running the test baseline.

4. **Validate Beads worktree wiring**
   Keep Beads setup aligned with 0.52+:
   - Do not copy or symlink Beads data files between worktrees.
   - Worktrees should generally use shared `.beads` state unless intentionally configured local.

   Run from inside the new worktree:
   ```bash
   bd worktree list
   bd where
   bd info --json
   ```

   If these checks fail or look inconsistent, follow `.beads/AGENTS.md` troubleshooting steps.

5. **Set up backend Python environment**
   The superpowers skill only handles root-level Python setup. Azure Functions apps need their own venv.

   ```bash
   cd <worktree>/app/backend/functions/api
   uv venv
   uv pip install -r requirements-dev.txt
   ```

   **Why this matters:** Without this step, `func start` will crash with `ModuleNotFoundError` (e.g., missing `jose`, `azure-functions`, etc.). The venv is gitignored and doesn't transfer with the worktree. Use `requirements-dev.txt` (not `requirements.txt`) to include dev-only dependencies like `python-dotenv` for local `.env` loading.

6. **Report ready**
   - Worktree path
   - Environment files copied
   - Beads status check result
   - Backend venv status
   - Test status
   - Next steps suggestion

## Output

- Isolated worktree created and ready
- Environment files copied from main worktree
- Tests passing (or failures reported)
- Working directory changed to worktree

## Pairing

After work is complete, `/ship` will offer branch finishing options:
- Merge locally
- Create PR
- Keep as-is
- Discard
