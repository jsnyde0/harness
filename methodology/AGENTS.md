# Methodology — Agent Instructions

The `methodology/` directory contains the workflow skills, hook scripts, and ADRs (ADR-004 through ADR-014) that govern the agentic-engineering methodology. These assets are designed for installation into a Claude Code home via `install.sh`.

## What is here

- `methodology/skills/` — workflow primitive skills (`/recall`, `/decompose`, `/implement`, `/review`, `/compound`, etc.) and reference skills. Skills are loaded into Claude Code by `install.sh` as per-skill symlinks under the Claude Code skills directory.
- `methodology/hooks/` — Claude Code hook scripts (PreToolUse, PostToolUse, SessionStart, SessionEnd guards and priming hooks). Installed as per-file symlinks under the Claude Code hooks directory.
- `methodology/AGENTS.md` — this file; installed as the global Claude Code agent instructions file so it governs every session.

## How it is consumed

`install.sh` (at the repo root) symlinks every skill dir and every hook file into the target Claude Code home. The links are **relative**, so the substrate is portable across machines when the repo lives at the same path relative to `$HOME`.

## Task tracking

This repo uses **beads** (`bd`) for task tracking with the `harness-` prefix. Run `bd status` to see current work.
