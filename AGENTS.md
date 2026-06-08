# Harness — Agent Instructions

**Harness** is the canonical home of the cross-harness agentic-engineering substrate. It combines workflow methodology (skills, hooks, ADRs 004–014) with the cross-harness mechanism (role-loader, hook-runner, compile/install skill, role library, ADRs 001–003). The substrate is designed to be installed into multiple agent runtimes — Claude Code, pi, and Codex — via `install.sh`.

## Layout

- `methodology/` — CC-home assets: workflow skills, hook scripts, methodology ADRs (004–014), global instructions
- `agent/` — mechanism assets: pi/Codex skills, roles, extensions (subagent, hooks, free-web-tools, dcg), keybindings
- `docs/decisions/` — merged ADR index: mechanism ADRs 001–003 + methodology ADRs 004–014
- `scripts/` — boundary-check scripts (walk-manifest.py, oneway-check.py, test_oneway_check.py)
- `manifest/core-manifest.toml` — machine-readable boundary: public-core vs private-overlay

## Install

Run `./install.sh` to wire the substrate into the current machine's agent runtimes.

## Task tracking

Task tracking uses beads with the `harness-` prefix. Run `bd status` to see current work.

## ADRs

Load-bearing decisions live in `docs/decisions/` — mechanism ADRs 001–003 (subagent primitive, cross-harness substrate, orchestration model) and methodology ADRs 004–014. Consult the INDEX.md before design or contract work.
