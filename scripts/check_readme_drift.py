#!/usr/bin/env python3
"""
check_readme_drift.py — README / install.sh drift checker

Asserts that every `./install.sh <verb>` command documented in README.md
fenced code blocks maps to a verb that install.sh's case dispatch actually
exposes. Implements the automatable subset assertion:

  README-command-set ⊆ install.sh-dispatch-surface

Algorithm:
  1. Extract every `./install.sh [ARG]` line from README.md fenced code blocks.
  2. Normalise each to the verb it maps to:
       - `./install.sh`          → "install"  (default, no arg)
       - `./install.sh install`  → "install"
       - `./install.sh doctor`   → "doctor"
       - `./install.sh --help`   → "--help"
       - `./install.sh -h`       → "-h"
       etc.
  3. Extract the dispatch verbs from install.sh's `case "$SUBCOMMAND" in` block.
     - Each `  VERB)` or `  VERB1|VERB2)` line contributes its alternatives.
     - The `*)` catch-all is excluded (it is not a named verb).
     - Empty-string alternative `""` is also excluded.
  4. Assert README-verb-set ⊆ dispatch-verb-set.
     Exit 0 if the subset holds; exit 1 and report unknown verbs otherwise.

Usage:
  uv run scripts/check_readme_drift.py                      # default paths
  uv run scripts/check_readme_drift.py --readme README.md --install install.sh

# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""

import argparse
import re
import sys
from pathlib import Path

HARNESS_ROOT = Path(__file__).parent.parent
DEFAULT_README = HARNESS_ROOT / "README.md"
DEFAULT_INSTALL = HARNESS_ROOT / "install.sh"


def extract_readme_verbs(readme_text: str) -> set[str]:
    """
    Extract the set of verbs from `./install.sh [ARG]` lines in fenced code blocks.

    Scans only content inside triple-backtick fenced blocks (with or without a
    language tag). Prose references outside fences are ignored.

    Each `./install.sh` line is normalised to its verb:
      - `./install.sh`         → "install"  (default, maps to the install|"" case)
      - `./install.sh install` → "install"
      - `./install.sh ARG`     → "ARG"

    Returns the set of unique verb strings found.
    """
    verbs: set[str] = set()

    # Match fenced blocks: ``` optionally followed by a language tag, then content, then ```
    fence_pattern = re.compile(r"```[^\n]*\n(.*?)```", re.DOTALL)
    for block_match in fence_pattern.finditer(readme_text):
        block_content = block_match.group(1)
        for line in block_content.splitlines():
            # Strip leading whitespace and prompt characters ($ or #)
            stripped = line.strip().lstrip("$ ")
            # Match ./install.sh with optional argument
            m = re.match(r"^\./install\.sh(?:\s+(.+))?$", stripped)
            if m:
                arg = m.group(1)
                if arg is None or arg.strip() == "":
                    # Bare `./install.sh` → default verb
                    verbs.add("install")
                else:
                    # Take only the first word (ignore flags like "# full install")
                    verb = arg.strip().split()[0]
                    verbs.add(verb)
    return verbs


def extract_dispatch_verbs(install_text: str) -> set[str]:
    """
    Extract the set of named dispatch verbs from install.sh's case statement.

    Looks for the `case "$SUBCOMMAND" in` block and parses each `VERB)` or
    `VERB1|VERB2)` arm. Excludes:
      - `*)` catch-all
      - empty-string `""` (the bare default arm)

    Returns the set of unique verb strings.
    """
    verbs: set[str] = set()

    # Find the case block
    in_case = False
    for line in install_text.splitlines():
        stripped = line.strip()
        # Detect case start
        if re.search(r'\bcase\b.*\bin\b', stripped):
            in_case = True
            continue
        if not in_case:
            continue
        # Detect case end
        if stripped == "esac":
            break
        # Match arm patterns like: provision) or install|"") or --help|-h)
        m = re.match(r'^([^)]+)\)$', stripped)
        if not m:
            continue
        arm = m.group(1).strip()
        # Split on | to get alternatives
        alternatives = [a.strip() for a in arm.split("|")]
        for alt in alternatives:
            # Strip surrounding quotes if present
            alt = alt.strip('"\'')
            # Skip catch-all and empty string
            if alt in ("*", ""):
                continue
            verbs.add(alt)
    return verbs


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Assert README-documented install.sh commands ⊆ install.sh dispatch verbs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exit codes:
  0  — all README-documented commands exist in install.sh dispatch (no drift)
  1  — one or more README-documented commands are NOT in install.sh dispatch (drift)
  2  — usage or I/O error
""",
    )
    parser.add_argument(
        "--readme",
        type=Path,
        default=DEFAULT_README,
        help=f"Path to README.md (default: {DEFAULT_README})",
    )
    parser.add_argument(
        "--install",
        type=Path,
        default=DEFAULT_INSTALL,
        help=f"Path to install.sh (default: {DEFAULT_INSTALL})",
    )
    args = parser.parse_args(argv)

    try:
        readme_text = args.readme.read_text(encoding="utf-8")
    except OSError as e:
        print(f"ERROR: cannot read README: {e}", file=sys.stderr)
        sys.exit(2)

    try:
        install_text = args.install.read_text(encoding="utf-8")
    except OSError as e:
        print(f"ERROR: cannot read install.sh: {e}", file=sys.stderr)
        sys.exit(2)

    readme_verbs = extract_readme_verbs(readme_text)
    dispatch_verbs = extract_dispatch_verbs(install_text)

    print("check_readme_drift.py — README / install.sh drift check")
    print(f"  README commands (verbs):   {sorted(readme_verbs)}")
    print(f"  install.sh dispatch verbs: {sorted(dispatch_verbs)}")

    unknown = readme_verbs - dispatch_verbs
    if unknown:
        print(f"\nDRIFT DETECTED — README documents verb(s) not in install.sh dispatch:")
        for v in sorted(unknown):
            print(f"  UNKNOWN: {v!r}")
        print("\nResult: RED (subset assertion failed)")
        sys.exit(1)
    else:
        print(f"\nResult: GREEN (all README-documented commands exist in install.sh dispatch)")
        sys.exit(0)


if __name__ == "__main__":
    main()
