# Global Pi Agent Instructions

This file is the global-pi instructions source. It is symlinked into `~/.pi/agent/AGENTS.md`
by `install.sh` and read by the pi harness as its project-level agent instructions.

## Mechanism layer

The `agent/` tree contains cross-harness substrate assets:

- `agent/roles/` — shared role-brief library (markdown), projected per-harness by `install.sh`
- `agent/skills/` — shared SKILL.md skill folders, symlinked into each harness's skill tree
- `agent/extensions/` — pi extensions and hook runner
- `agent/hooks-manifest.json` — shared hooks manifest, compiled to per-harness hook configs

Edit substrate files in the harness repo source. Never edit the symlink targets in `~/.pi/`
directly — those are read-only from the repo's perspective.

## Install

Run `install.sh` at the repo root to wire the substrate into a target home. See
`agent/skills/install-substrate/SKILL.md` for full documentation.
