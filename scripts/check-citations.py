#!/usr/bin/env python3
"""
check-citations.py — corpus-level citation gate

Checks the published body corpus in the harness repo for residual bare
ADR-NNN citations and exits non-zero if any are found.

Published bodies must be ADR-citation-free: the publish flow applies
soften-citations.py to strip citations before copying files here.
This gate verifies the result — if ADR-[0-9] appears in a published body
it means either the publish softener was skipped or it missed a form.

Detection delegates to soften-citations.py's check_clean() function and
RESIDUAL_ADR_PATTERN — the corpus selection (which files to check) lives
here; the ADR-[0-9] detection logic lives in soften-citations.py (single
source of detection).

CORPUS (published bodies that must be ADR-citation-free):
  - agent/skills/**/SKILL.md         skill bodies
  - methodology/skills/**/SKILL.md   methodology skill bodies
  - agent/roles/*.md                 role prompts
  - methodology/hooks/*.sh           hook scripts
  - agent/skills/**/evals/evals.json eval fixtures
  - methodology/skills/**/evals/evals.json  eval fixtures

USAGE:
  # From the harness repo root:
  uv run scripts/check-citations.py

# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""

import importlib.util
import sys
from pathlib import Path

# Import detection logic from soften-citations.py (single source of truth).
# Both scripts live in the same scripts/ directory; the hyphen in the filename
# requires importlib.util rather than a plain `import` statement.
_soften_path = Path(__file__).parent / "soften-citations.py"
_spec = importlib.util.spec_from_file_location("soften_citations", _soften_path)
_soften_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_soften_mod)
check_clean = _soften_mod.check_clean
RESIDUAL_ADR_PATTERN = _soften_mod.RESIDUAL_ADR_PATTERN


def find_corpus(root: Path) -> list[Path]:
    """Return the list of published body files to check."""
    files: list[Path] = []

    # Skills SKILL.md — agent and methodology
    for skill_md in sorted(root.glob("agent/skills/**/SKILL.md")):
        files.append(skill_md)
    for skill_md in sorted(root.glob("methodology/skills/**/SKILL.md")):
        files.append(skill_md)

    # Roles
    for role_md in sorted((root / "agent/roles").glob("*.md")):
        files.append(role_md)

    # Hooks (shell scripts)
    hooks_dir = root / "methodology/hooks"
    if hooks_dir.is_dir():
        for hook in sorted(hooks_dir.glob("*.sh")):
            files.append(hook)

    # Evals JSON — agent and methodology
    for evals_json in sorted(root.glob("agent/skills/**/evals/evals.json")):
        files.append(evals_json)
    for evals_json in sorted(root.glob("methodology/skills/**/evals/evals.json")):
        files.append(evals_json)

    return files


def check_file(path: Path) -> list[tuple[int, str]]:
    """
    Return a list of (line_number, line_text) pairs where ADR-[0-9] is found.
    Empty list means the file is clean.

    Pass/fail detection uses check_clean() imported from soften-citations.py.
    Line-level hit reporting uses RESIDUAL_ADR_PATTERN from soften-citations.py.
    No duplicate ADR-detection regex is defined here.
    """
    text = path.read_text(encoding="utf-8")
    if check_clean(text):
        return []
    # File has residual citations — collect lines for reporting
    hits: list[tuple[int, str]] = []
    for i, line in enumerate(text.splitlines(), 1):
        if RESIDUAL_ADR_PATTERN.search(line):
            hits.append((i, line.rstrip()))
    return hits


def main() -> int:
    root = Path(__file__).parent.parent.resolve()

    corpus = find_corpus(root)
    if not corpus:
        print("WARNING: no corpus files found — check glob patterns", file=sys.stderr)
        return 2

    print(f"Checking {len(corpus)} published body files for residual ADR citations ...")

    failures: list[Path] = []
    for path in corpus:
        hits = check_file(path)
        if hits:
            failures.append(path)
            rel = path.relative_to(root)
            print(f"  FAIL: {rel}", file=sys.stderr)
            for lineno, line in hits:
                print(f"    line {lineno}: {line!r}", file=sys.stderr)

    if failures:
        print(
            f"\nCITATION CHECK FAILED: {len(failures)} file(s) contain residual ADR citations.",
            file=sys.stderr,
        )
        return 1

    print(f"All {len(corpus)} files passed — no residual ADR citations found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
