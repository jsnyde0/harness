# Harness

Harness is a clone-and-adapt agentic-engineering substrate. It ships a curated set of workflow methodology skills, hook scripts, subagent roles, and ADRs that install cleanly into Claude Code, pi, and Codex via a single script. Clone it, run the installer, then adapt it to your own agent setup.

## What this is

Harness combines two layers:

- **Mechanism layer** (`agent/`) — subagent roles, hook scripts, extensions, and a Codex compile step. Wires into Claude Code, pi (`~/.pi`), and Codex (`~/.codex`) via relative symlinks.
- **Methodology layer** (`methodology/`) — workflow primitives (skills), ADRs 004–014, and global instructions. Installs per-skill and per-hook symlinks into the Claude Code home.

External dependencies (`bd` for task tracking, `cm` for CASS memory) are provisioned from pinned upstream releases with SHA256 verification. No binaries are vendored into this repo.

## Prerequisites

These tools must already be present on your machine before running the installer:

| Tool | Why needed |
|------|-----------|
| `python3` | Install script uses it for relative-symlink computation and Codex TOML generation |
| `git` | Required to clone this repo and for the pre-push hook |
| `curl` + `tar` | Used by the provisioning step to download and unpack `bd` and `cm` releases |
| `coreutils` (`realpath`, `sha256sum` / `shasum`) | Used in integrity checks during provisioning |
| `uv` | Required to run the Python helper scripts (`uv run scripts/...`) |

If you plan to use the harness with specific agent runtimes, you also need:

- **Claude Code** — for wiring methodology skills, hooks, and roles into the Claude Code home
- **pi** — for wiring roles, skills, extensions, and keybindings into `~/.pi`
- **Codex** — for wiring roles as TOML files and merging hook configuration into `~/.codex`

## What the installer provisions

The installer downloads and installs two external tools from their upstream GitHub releases into `~/.local/bin`. It verifies SHA256 checksums before installing. The pinned versions and checksums live in `manifest/deps.toml`.

| Tool | Binary | Source |
|------|--------|--------|
| beads | `bd` | [gastownhall/beads](https://github.com/gastownhall/beads) |
| CASSMS | `cm` | [Dicklesworthstone/cass_memory_system](https://github.com/Dicklesworthstone/cass_memory_system) |

No bundled binaries live in this repo.

## Quickstart

```sh
git clone https://github.com/jsnyde0/harness.git
cd harness
./install.sh
```

That runs the full install: provision deps (`bd`, `cm`) then wire all harness assets into your agent homes.

Check the health of an installed harness:

```sh
./install.sh doctor
```

Provision dependencies only (skip wiring):

```sh
./install.sh provision
```

Print usage:

```sh
./install.sh --help
```

## Adapt for yourself

Fork or clone the repo, then:

1. **Edit `agent/roles/`** — swap in your own subagent role briefs. Each `.md` file gets symlinked into the pi agent roles directory, the Claude Code agents directory, and compiled to the Codex agents directory as TOML.
2. **Edit `methodology/skills/`** — add, remove, or adapt workflow primitive skills. Each skill directory gets symlinked into the Claude Code skills home.
3. **Edit `methodology/hooks/`** — adjust hook scripts. Each hook file gets symlinked into the Claude Code hooks home.
4. **Edit `docs/decisions/`** — update ADRs to reflect your decisions. Each ADR file gets symlinked into the Claude Code decisions home.
5. **Edit `manifest/deps.toml`** — pin different dep versions or swap tools.
6. **Re-run `./install.sh`** after changes to re-wire everything.

The installer is idempotent: running it repeatedly is safe.

## One-way leak enforcement

The public core must never reference private markers (private repo paths, work-org tokens, hardcoded home paths, private bead IDs). This is enforced by a pre-push hook and a CI check.

Fresh clones do not inherit the hook configuration from the repo. After cloning, activate the pre-push hook once:

```sh
git config core.hooksPath .githooks
```

The hook runs two checks before every push:

```sh
uv run scripts/oneway-check.py          # scan tracked files for private markers
uv run scripts/test_oneway_check.py     # verify the check engine itself
```

Run either check manually at any time. See `CONTRIBUTING.md` for details.

## Contributing

See `CONTRIBUTING.md`.

## License

MIT. See `LICENSE`.
