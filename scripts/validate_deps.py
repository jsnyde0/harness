#!/usr/bin/env python3
"""
validate_deps.py — external-dependency manifest validator

Validates manifest/deps.toml against the deps manifest schema.
Each [[dep]] entry must carry:
  - name    (str, non-empty)
  - source  (str, URL template containing a {version} placeholder)
  - version (str, non-empty)
  - sha256  (str, exactly 64 lowercase hex characters)
  - arch    (str, non-empty)
  - install (str, non-empty — documented manual-equivalent recipe: user-local bin dir,
              pinned sha256 verification; honest mirror of provision-deps.sh, NOT consumed by it)
  - verify  (str, non-empty — command + expected output to confirm installation)

Exits 0 if all deps are valid; exits non-zero if any field is missing or malformed.
Mirrors the style of agent/roles/validate_roles.py.

Usage:
  uv run scripts/validate_deps.py [--manifest PATH]
"""

# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

import sys
import re
import argparse
import tomllib
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).parent
HARNESS_ROOT = SCRIPT_DIR.parent
DEFAULT_MANIFEST = HARNESS_ROOT / "manifest" / "deps.toml"

REQUIRED_FIELDS = ["name", "source", "version", "sha256", "arch", "install", "verify"]

# sha256 must be exactly 64 lowercase hex characters
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


# ---------------------------------------------------------------------------
# Core validation logic
# ---------------------------------------------------------------------------

def load_manifest(path: str) -> dict:
    """Load and parse a TOML manifest file. Returns the parsed dict."""
    with open(path, "rb") as f:
        return tomllib.load(f)


def validate_dep_entry(dep: dict, index: int) -> list[str]:
    """
    Validate a single [[dep]] entry.

    Returns a list of error strings (empty list = valid).
    """
    errors = []
    name = dep.get("name", f"<dep[{index}]>")

    # Check all required fields are present and non-empty
    for field in REQUIRED_FIELDS:
        if field not in dep:
            errors.append(f"  dep[{index}] ({name!r}): MISSING required field '{field}'")
        elif dep[field] is None or str(dep[field]).strip() == "":
            errors.append(f"  dep[{index}] ({name!r}): field '{field}' is null/empty")

    # Validate sha256 shape: must match ^[0-9a-f]{64}$
    if "sha256" in dep and dep["sha256"] is not None and str(dep["sha256"]).strip() != "":
        sha = str(dep["sha256"]).strip()
        if not SHA256_PATTERN.match(sha):
            errors.append(
                f"  dep[{index}] ({name!r}): sha256 '{sha}' does not match ^[0-9a-f]{{64}}$ "
                f"(must be exactly 64 lowercase hex characters)"
            )

    # Validate source contains a {version} placeholder
    if "source" in dep and dep["source"] is not None and str(dep["source"]).strip() != "":
        source = str(dep["source"]).strip()
        if "{version}" not in source:
            errors.append(
                f"  dep[{index}] ({name!r}): source URL '{source}' must contain a {{{{version}}}} placeholder"
            )

    return errors


def validate_manifest(path: str) -> tuple[bool, list[str]]:
    """
    Validate a deps.toml manifest file.

    Returns (passed: bool, errors: list[str]).
    passed=True and errors=[] means the manifest is valid.
    """
    all_errors = []

    try:
        manifest = load_manifest(path)
    except Exception as e:
        return False, [f"ERROR: Failed to parse TOML manifest at {path!r}: {e}"]

    deps = manifest.get("dep", [])

    if not deps:
        return False, [
            f"ERROR: manifest at {path!r} contains no [[dep]] entries — at least one dep is required"
        ]

    for i, dep in enumerate(deps):
        entry_errors = validate_dep_entry(dep, i)
        all_errors.extend(entry_errors)

    passed = len(all_errors) == 0
    return passed, all_errors


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="validate_deps.py — external-dependency manifest validator",
    )
    parser.add_argument(
        "--manifest",
        type=str,
        default=str(DEFAULT_MANIFEST),
        help=f"Path to deps.toml manifest (default: {DEFAULT_MANIFEST})",
    )
    args = parser.parse_args()

    manifest_path = args.manifest

    print("=" * 60)
    print("validate_deps.py — external-dependency manifest validator")
    print(f"Manifest: {manifest_path}")
    print("=" * 60)

    passed, errors = validate_manifest(manifest_path)

    if not passed:
        print(f"\nRESULT: VALIDATION FAILED — {len(errors)} error(s)")
        for err in errors:
            print(err)
        sys.exit(1)
    else:
        manifest = load_manifest(manifest_path)
        deps = manifest.get("dep", [])
        print(f"\nAll {len(deps)} dep(s) validated successfully:")
        for dep in deps:
            print(f"  PASS  {dep.get('name', '?')} @ {dep.get('version', '?')} [{dep.get('arch', '?')}]")
        print("\nRESULT: ALL DEPS VALID")
        sys.exit(0)


if __name__ == "__main__":
    main()
