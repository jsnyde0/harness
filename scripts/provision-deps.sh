#!/usr/bin/env bash
# provision-deps.sh — provision external dependencies declared in manifest/deps.toml
#
# Reads manifest/deps.toml, selects the dep entry matching the current OS/arch,
# then for each dep:
#   1. Checks if already installed at the pinned version (idempotent skip if so)
#   2. Downloads the release artifact to a temp dir
#   3. Verifies SHA256 BEFORE installing (aborts non-zero on mismatch — never installs a bad artifact)
#   4. Installs the binary into $TARGET_HOME/.local/bin
#   5. Runs the manifest verify command to confirm the tool responds
#
# Environment:
#   TARGET_HOME           — installation root (default: $HOME)
#   DOTPI_DEPS_MANIFEST   — path to deps.toml (default: <harness-root>/manifest/deps.toml)
#
# Core config note: no per-tool config write is required beyond making the binaries
# available on PATH. beads and cm read their own per-workspace config at runtime.
# The manifest verify step (bd version / cm --version) IS the "config applied" check.
# Named config keys: none needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Target home (respects DOTPI_TEST_TARGET for throwaway-target testing)
TARGET_HOME="${DOTPI_TEST_TARGET:-$HOME}"

# Manifest path (overridable for testing with a corrupted manifest)
MANIFEST="${DOTPI_DEPS_MANIFEST:-$HARNESS_ROOT/manifest/deps.toml}"

# Binary installation directory — per-target, never system dirs, never requires sudo
BIN_DIR="$TARGET_HOME/.local/bin"

# ---------------------------------------------------------------------------
# Detect current OS/arch string matching manifest arch values
# ---------------------------------------------------------------------------
detect_arch() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  if [ "$os" = "Darwin" ]; then
    if [ "$arch" = "arm64" ]; then
      echo "darwin-arm64"
    else
      echo "darwin-amd64"
    fi
  elif [ "$os" = "Linux" ]; then
    if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
      echo "linux-arm64"
    else
      # CASSMS uses linux-x64 naming for linux amd64
      echo "linux-amd64"
    fi
  else
    echo "unknown-$(uname -m)"
  fi
}

# ---------------------------------------------------------------------------
# Use Python/tomllib (py3.11+) to parse deps.toml and emit shell-readable data.
# Invoked via `uv run python3` to ensure py3.11+ is available regardless of the
# system python version. tomllib is stdlib in py3.11+.
# Output: one line per dep entry matching the current arch, in the form:
#   NAME|BIN|VERSION|SHA256|SOURCE|VERIFY
# ---------------------------------------------------------------------------
parse_deps() {
  local arch="$1"
  uv run python3 - "$MANIFEST" "$arch" <<'PYEOF'
import sys
import tomllib

manifest_path = sys.argv[1]
target_arch = sys.argv[2]

with open(manifest_path, 'rb') as f:
    data = tomllib.load(f)

deps = data.get('dep', [])
seen_names = set()

for dep in deps:
    dep_arch = dep.get('arch', '')
    dep_name = dep.get('name', '')
    # Also match linux-amd64 against linux-x64 (CASSMS naming)
    arch_match = (dep_arch == target_arch)
    if not arch_match:
        # Normalise: linux-amd64 matches linux-x64
        norm_dep = dep_arch.replace('-x64', '-amd64')
        norm_target = target_arch.replace('-x64', '-amd64')
        arch_match = (norm_dep == norm_target)
    if not arch_match:
        continue
    # First match per name wins (handles duplicate linux-x64 / linux-amd64 aliases)
    if dep_name in seen_names:
        continue
    seen_names.add(dep_name)
    bin_name = dep.get('bin', dep_name)
    version = dep.get('version', '')
    sha256 = dep.get('sha256', '')
    source = dep.get('source', '').replace('{version}', version)
    verify = dep.get('verify', '')
    # Escape | in any field (unlikely but defensive)
    parts = [dep_name, bin_name, version, sha256, source, verify]
    print('|'.join(p.replace('|', '_') for p in parts))
PYEOF
}

# ---------------------------------------------------------------------------
# Verify a sha256 checksum. Works on both Linux (sha256sum) and macOS (shasum).
# Arguments: $1 = file path, $2 = expected hex sha256
# Exits non-zero if mismatch.
# ---------------------------------------------------------------------------
verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "[provision] ERROR: no sha256sum or shasum found — cannot verify checksum" >&2
    exit 1
  fi
  if [ "$actual" != "$expected" ]; then
    echo "[provision] ERROR: SHA256 checksum mismatch for $file" >&2
    echo "[provision]   expected: $expected" >&2
    echo "[provision]   actual:   $actual" >&2
    echo "[provision] Aborting — binary NOT installed." >&2
    exit 1
  fi
  echo "[provision] checksum verified: $file (sha256 ok)"
}

# ---------------------------------------------------------------------------
# Check if a dep is already installed at the pinned version.
# Arguments: $1 = bin name, $2 = verify command, $3 = pinned version
# Returns 0 if already correct, 1 if needs install.
# ---------------------------------------------------------------------------
already_installed() {
  local bin_name="$1"
  local verify_cmd="$2"
  local pinned_version="$3"

  # Check if binary exists in target bin dir
  if [ ! -f "$BIN_DIR/$bin_name" ]; then
    return 1
  fi

  # Run verify command with target bin dir prepended to PATH
  local verify_output
  if ! verify_output="$(PATH="$BIN_DIR:$PATH" $verify_cmd 2>/dev/null)"; then
    return 1
  fi

  # Check if pinned version appears in the output
  if echo "$verify_output" | grep -qF "$pinned_version"; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Provision a single dependency
# ---------------------------------------------------------------------------
provision_one() {
  local name="$1"
  local bin_name="$2"
  local version="$3"
  local sha256="$4"
  local source_url="$5"
  local verify_cmd="$6"

  echo "[provision] dep: $name ($bin_name) @ $version"

  # Idempotency: skip if already installed at pinned version
  if already_installed "$bin_name" "$verify_cmd" "$version"; then
    echo "[provision] already installed at pinned version — skip"
    return 0
  fi

  echo "[provision] fetching: $source_url"

  # Download to a temp file
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local artifact_file
  artifact_file="$tmp_dir/$(basename "$source_url")"

  if ! curl -fsSL "$source_url" -o "$artifact_file"; then
    echo "[provision] ERROR: download failed for $source_url" >&2
    rm -rf "$tmp_dir"
    exit 1
  fi
  echo "[provision] download complete: $artifact_file"

  # Verify SHA256 BEFORE installing — abort on mismatch
  verify_sha256 "$artifact_file" "$sha256"

  # Ensure bin dir exists
  mkdir -p "$BIN_DIR"

  # Install: extract .tar.gz or install direct binary
  if [[ "$artifact_file" == *.tar.gz ]]; then
    echo "[provision] extracting archive..."
    # Extract the specific binary (bin_name) from the archive
    tar -xzf "$artifact_file" -C "$tmp_dir" "$bin_name" 2>/dev/null \
      || tar -xzf "$artifact_file" -C "$tmp_dir" 2>/dev/null
    local extracted="$tmp_dir/$bin_name"
    if [ ! -f "$extracted" ]; then
      echo "[provision] ERROR: binary $bin_name not found in archive after extraction" >&2
      echo "[provision] Archive contents:" >&2
      tar -tzf "$artifact_file" >&2
      rm -rf "$tmp_dir"
      exit 1
    fi
    cp "$extracted" "$BIN_DIR/$bin_name"
  else
    # Direct binary (e.g. cass-memory-macos-arm64)
    cp "$artifact_file" "$BIN_DIR/$bin_name"
  fi

  chmod +x "$BIN_DIR/$bin_name"
  echo "[provision] installed: $BIN_DIR/$bin_name"

  # Run verify
  echo "[provision] running verify: $verify_cmd"
  if ! PATH="$BIN_DIR:$PATH" $verify_cmd; then
    echo "[provision] ERROR: verify command failed after install: $verify_cmd" >&2
    rm -rf "$tmp_dir"
    exit 1
  fi
  echo "[provision] verify passed: $name"

  rm -rf "$tmp_dir"
}

# ---------------------------------------------------------------------------
# Main provisioning loop
# ---------------------------------------------------------------------------
main() {
  local arch
  arch="$(detect_arch)"
  echo "[provision] platform arch: $arch"
  echo "[provision] manifest: $MANIFEST"
  echo "[provision] bin dir: $BIN_DIR"

  local deps_data
  deps_data="$(parse_deps "$arch")"

  if [ -z "$deps_data" ]; then
    echo "[provision] WARNING: no deps found for arch '$arch' in $MANIFEST"
    return 0
  fi

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    IFS='|' read -r dep_name bin_name version sha256 source_url verify_cmd <<< "$line"
    provision_one "$dep_name" "$bin_name" "$version" "$sha256" "$source_url" "$verify_cmd"
  done <<< "$deps_data"

  echo "[provision] all deps provisioned"
}

main "$@"
