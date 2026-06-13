---
name: install-substrate
description: >
 Install the dotpi cross-harness substrate (roles, extensions, skills, hooks,
 AGENTS.md, keybindings) into a target home directory via relative symlinks.
 Produces a fully wired pi + Claude Code environment. Use when onboarding a new
 machine or re-running after repo changes. Triggers on "install dotpi",
 "re-install substrate", "link roles", "wire up ~/.pi", "set up pi environment".
---

# Install-Substrate Skill

Deterministic install script (`install.sh` at the dotpi repo root) that creates a
relative-symlink wiring from the dotpi source tree into the target home's `~/.pi`
and methodology-home directories. All wiring is managed as symlinks — never copied —
so edits in the dotpi repo are live immediately in every harness.

## Paths — set `$SKILL` first

```bash
export SKILL=$HOME/.claude/skills/install-substrate # Claude Code
export SKILL=$HOME/.pi/agent/skills/install-substrate # pi (via install.sh symlink)
```

All examples below use `$SKILL/` so the same text works in either harness.

## Running the install

```bash
bash $HOME/code/personal/harness/install.sh
```

Installs into the real `$HOME` (`~/.pi` and the methodology home). Idempotent: existing
symlinks are removed and re-created; existing real files are backed up with a
datestamp suffix before being replaced.

### Throwaway-target testing (safe, no host mutation)

```bash
mkdir -p "$HOME/tmp/install-target-test/{.pi/agent,.claude/agents}"
DOTPI_TEST_TARGET="$HOME/tmp/install-target-test" bash $HOME/code/personal/harness/install.sh
```

Set `DOTPI_TEST_TARGET` to any writable directory under `$HOME`. The script targets
that directory instead of `$HOME`. The relative symlinks resolve correctly because
the target and the dotpi source share the same home-directory path prefix.

Note: `/tmp` on macOS is a symlink to `/private/tmp`, which is not under `$HOME`.
Throwaway targets must live inside `$HOME` (e.g., `$HOME/tmp/`) for relative
symlinks to resolve.

To run the full automated verify:

```bash
bash $SKILL/test-install.sh
```

## What gets installed

| Link path in target | Source in dotpi | Notes |
|---|---|---|
| `~/.pi/agent/AGENTS.md` | `agent/AGENTS.md` | Source of truth — edit here, never in `~/.pi` |
| `~/.pi/agent/keybindings.json` | `agent/keybindings.json` | |
| `~/.pi/agent/extensions/` | `agent/extensions/` | Dir-link; hooks runner lives here |
| `~/.pi/agent/prompts/` | `agent/prompts/` | |
| `~/.pi/agent/skills/` | `agent/skills/` | Dir-link; includes this skill |
| `~/.pi/agent/roles/` | `agent/roles/` | Dir-link; all role files |
| `$HOME/.claude/agents/<name>.md` | `agent/roles/<name>.md` | Per-file; roles appear as CC sub-agents |
| `~/.codex/agents/<name>.toml` | `agent/roles/<name>.md` | **Generated** TOML (D6 compile-generation); not a symlink |
| `~/.codex/hooks.toml` | `agent/hooks-manifest.json` | **Generated** Codex hooks config (emit from manifest) |
| `~/.agents/skills` | `agent/skills/` | Dir-link; Codex skills discovery root |

Role files carry `model:` (Claude Code keyword), `pi-model:` (pi slug), and
`codex-model:` (Codex `provider/model` slug) in frontmatter. One shared source,
projected per-harness:

- **CC + pi** — symlink the shared markdown file. CC reads `model:` and ignores
 `pi-model:`/`codex-model:`; pi reads `pi-model:`. Byte-identity holds for the
 two markdown-format harnesses (C0-outcome-B).
- **Codex** — compile-generate a TOML role file from the shared brief at install
 time. The `codex-model:` slug (e.g. `openai/gpt-5.5`) is split
 into Codex TOML `model` (bare id: `gpt-5.5`) and `model_provider` (table key:
 `openai`). The body becomes `developer_instructions`. No byte-identity across
 the markdown→TOML boundary — generation is the mechanism, not symlink.

**Hooks divergence note:** The shared `cc-hook` adapter covers
Codex without a new protocol enum or runner branch. However, Codex supports only
a *subset* of the `cc-hook` decision surface: `deny`+reason, `allow`+updatedInput,
and exit-2+stderr. **An `ask`-emitting hook is silently ignored by Codex and the
tool PROCEEDS (fail-open)** — the run is marked Failed but the tool is not
blocked. Pure deny-or-pass guard hooks (e.g. `block-compound-commands.sh`,
`restrict-sensitive-paths.sh`) are unaffected. Only hooks that emit
`permissionDecision:"ask"` diverge in behavior on Codex. This is documented in
the generated `~/.codex/hooks.toml` header and recorded here for cross-harness
auditability. This is the C0-outcome-B resolution.

## Relative-symlink convention (`$SKILL` cross-machine portability)

All symlinks are **relative**, not absolute. Example: from
`~/.pi/agent/skills`, the link to the harness source is `../../../../code/personal/harness/agent/skills`
rather than `$HOME/code/personal/harness/agent/skills` (with a hardcoded username).

This matches the `$SKILL` doc-path convention used in browser-automation (the
canonical precedent, commit e7807b9): SKILL.md exports `SKILL=<its own dir>`
once per session; examples read `node $SKILL/x.js`, so one shared SKILL.md
resolves in any harness with no hardcoded methodology-home path. Relative symlinks
are the storage-layer equivalent: the path computation is relative to the link's
own location, so the same wiring works under a different username on laptop vs
mini as long as the repo lives at the same relative path from `$HOME`
(e.g., `~/code/personal/harness`).

**Warning:** cloning dotpi to a different location (or a different relative path from `$HOME`)
produces silently dangling links on other machines — the install script does not validate
that symlinks resolve after creation.

## Host vs. container distinction

**Host install** (this script) is dotpi's normal operation. It manages symlinks
into the developer's `~/.pi` and the methodology home. This is NOT container
initialisation and does not affect the container's init sequence — those are
governed separately, container-side, and dotpi's host-side wiring step is outside
that scope.

**Container-hosted pi** gets the substrate MOUNTED read-only into the container.
Container config is container-local; the container does not run `install.sh` against
a host home directory. The substrate arrives via container mount. Host-side symlink
management is irrelevant inside the container.

The two contexts are entirely separate: host-install writes symlinks into the
developer's home; container-mount writes nothing to the host.

## Sandbox requirement (relies-on, does not re-implement)

The install-AGENT (when a pi agent runs this skill to install substrate) must run
under a sandboxed execution environment:

- **Idempotency** — install scripts must be safe to re-run; existing symlinks are
  replaced, not accumulated. The script must not fail or corrupt state on repeated
  execution.
- **Prompt-injection surface** — install scripts are a named hostile-input vector.
  Agent-run install code must execute in a sandboxed environment where arbitrary
  shell execution cannot escape into the host without explicit permission grants.
- **Permission model** — agents running install scripts operate under
  `bypassPermissions` inside containers; the container is the safety boundary, with
  hooks serving as in-container guardrails.

Sandbox enforcement is the responsibility of whatever container or DCG runtime
wraps the agent execution — this skill **relies on that enforcement and documents
it**. It does NOT re-test or re-implement the sandbox boundary. Do not add sandbox
logic here — that would duplicate the enforcement layer and create a maintenance
hazard.

## Source-of-truth rule

Edit substrate files in the dotpi repo (under `agent/`). Never edit the symlink
targets in `~/.pi/` or the methodology home directly — those are read-only from
the repo's perspective. See `agent/AGENTS.md` for the canonical source-of-truth
statement.
