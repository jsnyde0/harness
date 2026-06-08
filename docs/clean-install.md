# clean-install local how-to

Run the full W4 integration proof locally using Docker before pushing.

## What it proves

`scripts/clean-install-test.sh` is the integration proof for the W4 Distribution epic. It verifies that, from a clean machine state (no beads/CASSMS preinstalled):

1. `install.sh` provisions beads and CASSMS via checksummed direct download (no bundled binaries)
2. `install.sh` completes W3 wiring (CC/pi/Codex symlinks)
3. `install.sh doctor` reports all-green with exit 0
4. Reference role `implementer` round-trips structurally:
   - CC symlink `~/.claude/agents/implementer.md` resolves into the harness tree
   - Codex TOML `~/.codex/agents/implementer.toml` exists and contains `"implementer"`
   - pi/roles symlink resolves into the harness tree and `implementer.md` exists there
5. Re-running `install.sh` is a provisioning no-op (binaries not re-fetched)

## Prerequisites (local)

- Docker Desktop or equivalent
- A checkout of this repo

## Run with Docker (ubuntu, matching CI)

```sh
# From the harness repo root:
docker run --rm \
  -v "$(pwd)":/harness \
  -w /harness \
  ubuntu:latest \
  bash -c "
    apt-get update -qq
    apt-get install -y -qq curl git python3 python3-pip tar coreutils ca-certificates
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    bash scripts/clean-install-test.sh
  "
```

This mirrors the CI runner (ubuntu-latest with uv pre-installed via `astral-sh/setup-uv`).

## Run directly on macOS (partial simulation)

You can run the script on macOS, but note:

- CASSMS (`cm`) has a `darwin-arm64` binary in the manifest — provisioning will succeed on Apple Silicon.
- The CI runner (linux-amd64) is the authoritative clean-machine proof. Local macOS runs exercise the same code paths but on a different platform.
- On darwin-arm64, the script uses the macOS binary variants automatically.

```sh
# From the harness repo root:
bash scripts/clean-install-test.sh
```

The script creates and cleans up a `mktemp -d` throwaway target — it never writes to real `$HOME`.

## CI signal

The authoritative signal is the `clean-install.yml` GitHub Actions workflow on `ubuntu-latest`. It runs on every push and pull request. A green run means the full conjunction holds on a truly clean machine:

- No preinstalled beads or CASSMS
- Provision via checksummed direct download
- Doctor all-green
- `implementer` structural round-trip
- Idempotent re-run

## Invalidation conditions

The signal is red (or invalid) if:

- The proof was tested only on an already-configured machine
- Deps were vendored as binaries into the repo
- The role round-trip was skipped
- The idempotent re-run was skipped
- Secrets were required to pass
