#!/usr/bin/env python3
"""
walk-manifest.py — harness core-manifest coverage walk-script

Walks the harness repo tree (single home) and cross-references every substrate
asset path against manifest/core-manifest.toml.

Reports:
  - classified assets (core counts by class)
  - unclassified assets (the TDD assertion: must be 0 for green)

Usage:
  uv run scripts/walk-manifest.py [--harness-root PATH]

Exit 0  — unclassified count = 0 (green)
Exit 1  — unclassified assets found (red)
"""

# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

import sys
import argparse
import tomllib
from pathlib import Path
from collections import defaultdict

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).parent
HARNESS_ROOT = SCRIPT_DIR.parent  # scripts/ is one level under repo root
MANIFEST_PATH = HARNESS_ROOT / "manifest" / "core-manifest.toml"


def resolve_path(path_str: str, home_key: str, harness_root: Path) -> Path:
    """
    Resolve a manifest path to an absolute Path.

    For the harness manifest all paths are harness-relative (home="harness").
    home_key is ignored (always "harness"); path_str is relative to harness_root.
    """
    if Path(path_str).is_absolute():
        return Path(path_str)
    # All paths in the harness manifest are relative to harness_root
    return harness_root / path_str


def load_manifest(manifest_path: Path) -> dict:
    """Load and parse the TOML manifest."""
    with open(manifest_path, "rb") as f:
        return tomllib.load(f)


def get_manifest_path_strings(manifest: dict, harness_root: Path) -> dict[str, dict]:
    """Return a dict keyed by resolved-path → asset entry."""
    result = {}
    for asset in manifest.get("assets", []):
        p = resolve_path(asset["path"], asset.get("home", "harness"), harness_root)
        key = str(p.resolve()) if p.exists() else str(p)
        result[key] = asset
    return result


# ---------------------------------------------------------------------------
# Walk logic: substrate topology in harness
# ---------------------------------------------------------------------------

def walk_harness_substrate(harness_root: Path) -> list[Path]:
    """
    Walk the harness repo and collect substrate asset paths.

    Substrate layout:
      methodology/skills/<name>/       — each top-level dir is a skill
      methodology/hooks/<file>         — each file is a hook
      methodology/AGENTS.md            — instruction
      agent/skills/<name>/             — each top-level dir is a skill
      agent/roles/<file.md|.py>        — each file is a role
      agent/extensions/**              — collected per-file
      agent/hooks-manifest.json        — hook
      agent/hooks-manifest.schema.json — hook
      agent/AGENTS.md                  — instruction
      agent/keybindings.json           — config
      docs/decisions/<file>            — adr
    """
    assets = []

    # methodology/skills/: each top-level dir is a skill
    meth_skills_dir = harness_root / "methodology" / "skills"
    if meth_skills_dir.is_dir():
        for item in sorted(meth_skills_dir.iterdir()):
            if item.is_dir() and not item.name.startswith("."):
                if item.name not in {"__pycache__", "node_modules"}:
                    assets.append(item.resolve())

    # methodology/hooks/: each file is a hook
    meth_hooks_dir = harness_root / "methodology" / "hooks"
    if meth_hooks_dir.is_dir():
        for item in sorted(meth_hooks_dir.iterdir()):
            if item.is_file() and not item.name.startswith("."):
                assets.append(item.resolve())

    # methodology/AGENTS.md: instruction
    meth_agents = harness_root / "methodology" / "AGENTS.md"
    if meth_agents.exists():
        assets.append(meth_agents.resolve())

    # agent/skills/: each top-level dir is a skill
    agent_skills_dir = harness_root / "agent" / "skills"
    if agent_skills_dir.is_dir():
        for item in sorted(agent_skills_dir.iterdir()):
            if item.is_dir() and not item.name.startswith("."):
                if item.name not in {"__pycache__", "node_modules"}:
                    assets.append(item.resolve())

    # agent/roles/: each .md and .py file (not __pycache__)
    agent_roles_dir = harness_root / "agent" / "roles"
    if agent_roles_dir.is_dir():
        for item in sorted(agent_roles_dir.iterdir()):
            if item.is_file() and not item.name.startswith("."):
                if "__pycache__" not in str(item):
                    assets.append(item.resolve())

    # agent/extensions/**: per-file (skip node_modules, __pycache__, .venv, .git)
    extensions_dir = harness_root / "agent" / "extensions"
    if extensions_dir.is_dir():
        for item in sorted(extensions_dir.rglob("*")):
            if item.is_file():
                parts = item.parts
                if any(p in ("node_modules", "__pycache__", ".venv", ".git") for p in parts):
                    continue
                if item.name.startswith("."):
                    continue
                assets.append(item.resolve())

    # agent/hooks-manifest.json + schema
    for fname in ("hooks-manifest.json", "hooks-manifest.schema.json"):
        p = harness_root / "agent" / fname
        if p.exists():
            assets.append(p.resolve())

    # agent/AGENTS.md: instruction
    agent_agents = harness_root / "agent" / "AGENTS.md"
    if agent_agents.exists():
        assets.append(agent_agents.resolve())

    # agent/keybindings.json: config
    agent_keybindings = harness_root / "agent" / "keybindings.json"
    if agent_keybindings.exists():
        assets.append(agent_keybindings.resolve())

    # docs/decisions/: each file is an adr
    adrs_dir = harness_root / "docs" / "decisions"
    if adrs_dir.is_dir():
        for item in sorted(adrs_dir.iterdir()):
            if item.is_file() and not item.name.startswith("."):
                assets.append(item.resolve())

    return assets


# ---------------------------------------------------------------------------
# Main report
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="walk-manifest.py — harness substrate coverage check",
    )
    parser.add_argument(
        "--harness-root",
        type=Path,
        default=HARNESS_ROOT,
        help=f"Path to the harness repo root (default: {HARNESS_ROOT})",
    )
    args = parser.parse_args()

    harness_root = args.harness_root.resolve()
    manifest_path = harness_root / "manifest" / "core-manifest.toml"

    print("=" * 70)
    print("walk-manifest.py — harness substrate coverage check")
    print(f"Manifest: {manifest_path}")
    print(f"Harness root: {harness_root}")
    print("=" * 70)

    # Load manifest
    manifest = load_manifest(manifest_path)
    manifest_assets = manifest.get("assets", [])
    manifest_lookup = get_manifest_path_strings(manifest, harness_root)

    print(f"\nManifest entries: {len(manifest_assets)}")

    # Walk harness
    walked = walk_harness_substrate(harness_root)
    print(f"Walked assets (harness tree): {len(walked)}")

    # Cross-reference: find unclassified
    unclassified = []
    for asset_path in walked:
        key = str(asset_path)
        if key not in manifest_lookup:
            unclassified.append(asset_path)

    # Per-class breakdown
    counts_core = defaultdict(int)
    for entry in manifest_assets:
        cls = entry.get("class", "unknown")
        disp = entry.get("disposition", "unknown")
        if disp == "core":
            counts_core[cls] += 1

    print("\n--- Classification breakdown (from manifest) ---")
    total_core = 0
    for cls in sorted(counts_core.keys()):
        c = counts_core[cls]
        total_core += c
        print(f"  {cls:15s}  core={c:3d}")
    print(f"  {'TOTAL':15s}  core={total_core:3d}")
    print(f"  {'(manifest total)':15s}  {len(manifest_assets):3d}")

    print("\n--- Walked assets not in manifest (unclassified) ---")
    if unclassified:
        for p in sorted(unclassified):
            print(f"  UNCLASSIFIED: {p}")
    else:
        print("  (none — full coverage)")

    print(f"\n=== RESULT: unclassified-asset count = {len(unclassified)} ===")

    if len(unclassified) == 0:
        print("GREEN: all substrate assets are classified.")
        sys.exit(0)
    else:
        print("RED: unclassified assets found — update manifest/core-manifest.toml.")
        sys.exit(1)


if __name__ == "__main__":
    main()
