#!/usr/bin/env python3
"""
test_readme_drift.py — self-test for check_readme_drift.py

Verifies that the drift checker correctly:
  - extracts ./install.sh ... commands from README fenced code blocks
  - extracts dispatch verbs from install.sh case statement
  - asserts README-command-set is a subset of install.sh dispatch surface
  - exits 0 when all README commands map to real verbs
  - exits 1 when a README command references a non-existent verb

# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
CHECKER_SCRIPT = SCRIPT_DIR / "check_readme_drift.py"


def run_checker(readme_content: str, install_content: str) -> tuple[int, str]:
    """
    Run check_readme_drift.py with synthetic README and install.sh content.
    Returns (exit_code, combined_stdout_stderr).
    """
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        readme_path = tmp_path / "README.md"
        install_path = tmp_path / "install.sh"
        readme_path.write_text(readme_content, encoding="utf-8")
        install_path.write_text(install_content, encoding="utf-8")

        result = subprocess.run(
            [
                "uv", "run", str(CHECKER_SCRIPT),
                "--readme", str(readme_path),
                "--install", str(install_path),
            ],
            capture_output=True,
            text=True,
        )
        output = result.stdout + result.stderr
        return result.returncode, output


# Minimal synthetic install.sh case block for tests
INSTALL_SH_REAL = """\
#!/usr/bin/env bash
SUBCOMMAND="${1:-install}"
case "$SUBCOMMAND" in
  provision)
    run_provision
    ;;
  doctor)
    run_doctor
    ;;
  --help|-h)
    print_help
    ;;
  install|"")
    run_provision
    ;;
  *)
    echo "unknown"
    exit 1
    ;;
esac
"""

INSTALL_SH_MINIMAL = """\
#!/usr/bin/env bash
SUBCOMMAND="${1:-install}"
case "$SUBCOMMAND" in
  provision)
    ;;
  doctor)
    ;;
  install|"")
    ;;
  *)
    exit 1
    ;;
esac
"""


class TestExtractReadmeCommands(unittest.TestCase):
    """Verify README command extraction from fenced code blocks."""

    def test_no_install_commands(self):
        """README with no ./install.sh lines → empty set, exit 0."""
        readme = "# README\n\nNo commands here.\n"
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 0, f"Expected exit 0, got {code}. Output: {out}")

    def test_basic_install_default(self):
        """./install.sh with no argument maps to 'install' (default verb)."""
        readme = "```sh\n./install.sh\n```\n"
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 0, f"Expected exit 0. Output: {out}")

    def test_known_verb_doctor(self):
        """./install.sh doctor is a real verb → exit 0."""
        readme = "```sh\n./install.sh doctor\n```\n"
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 0, f"Expected exit 0. Output: {out}")

    def test_known_verb_provision(self):
        """./install.sh provision is a real verb → exit 0."""
        readme = "```sh\n./install.sh provision\n```\n"
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 0, f"Expected exit 0. Output: {out}")

    def test_help_flag(self):
        """./install.sh --help is a real verb → exit 0."""
        readme = "```sh\n./install.sh --help\n```\n"
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 0, f"Expected exit 0. Output: {out}")


class TestDriftDetection(unittest.TestCase):
    """Verify drift checker fires on unknown verbs."""

    def test_unknown_verb_fires(self):
        """./install.sh nonexistent is not in dispatch → exit 1 (drift detected)."""
        readme = "```sh\n./install.sh nonexistent\n```\n"
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 1, f"Expected exit 1 (drift), got {code}. Output: {out}")
        self.assertIn("nonexistent", out)

    def test_mixed_known_and_unknown_fires(self):
        """One known verb + one unknown → still exits 1."""
        readme = "```sh\n./install.sh doctor\n./install.sh ghost-verb\n```\n"
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 1, f"Expected exit 1 (drift). Output: {out}")
        self.assertIn("ghost-verb", out)

    def test_all_known_verbs_passes(self):
        """README with all real verbs → exit 0."""
        readme = (
            "```sh\n"
            "./install.sh\n"
            "./install.sh provision\n"
            "./install.sh doctor\n"
            "./install.sh --help\n"
            "```\n"
        )
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 0, f"Expected exit 0. Output: {out}")


class TestSubsetAssertion(unittest.TestCase):
    """Verify subset assertion logic."""

    def test_only_fenced_blocks_scanned(self):
        """Bare text (not in fenced blocks) is not extracted."""
        # This ./install.sh reference is in prose, not a code block
        readme = "Run ./install.sh ghost-verb to do things.\n"
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 0, f"Expected exit 0 (prose ignored). Output: {out}")

    def test_multiple_fence_styles(self):
        """Both ```sh and ``` (no lang) blocks are scanned."""
        readme = (
            "```sh\n./install.sh doctor\n```\n"
            "\n"
            "```\n./install.sh provision\n```\n"
        )
        code, out = run_checker(readme, INSTALL_SH_REAL)
        self.assertEqual(code, 0, f"Expected exit 0. Output: {out}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
