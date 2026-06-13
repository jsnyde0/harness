#!/usr/bin/env python3
"""
test_oneway_check.py — self-test for oneway-check.py

DENY-PATH PROOF strategy (per project memory deny-path-hook-test-use-harmless-sentinel):
  Use harmless-but-discriminating sentinels — never real destructive/sensitive content.

Five runs total:
  C1-dirty: core file contains a private-path-token reference → engine must exit non-zero
  C2-dirty: core file contains a hardcoded ~/.claude path → engine must exit non-zero
  C3-dirty: core file contains a work-org token → engine must exit non-zero
  C4-dirty: core file contains a private bead-prefix ID cite → engine must exit non-zero
  clean:    no planted markers → engine must exit zero

All C3/C4/C5 dirty sentinels use SYNTHETIC tokens loaded from a test-only config
(no real private nouns appear in this file). The config-driven engine is expected to
fire on those synthetic tokens just as it fires on the real tokens in local config.

Per-class isolation: only one class's marker is present in each dirty run.
Fixture files are in a temp directory — the REAL core-manifest.toml is never touched.

# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""

import os
import sys
import tempfile
import tomllib
import subprocess
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
ENGINE_SCRIPT = SCRIPT_DIR / "oneway-check.py"

# ---------------------------------------------------------------------------
# Synthetic test config (NO real private nouns)
# ---------------------------------------------------------------------------
# These tokens are intentionally nonsensical so they cannot appear accidentally
# in any real file. The engine must fire on them when loaded from this config.

SYNTHETIC_MARKERS_TOML = """\
# Synthetic test-only markers — NOT real private nouns.
# Used by test_oneway_check.py to verify the config-driven engine fires
# on arbitrary tokens loaded from a markers config file.

# C1: private path token (the private overlay repo's path component)
private_path_token = "FAKEREPO-sentinel"

# C3: work-org tokens
work_org_tokens = ["FAKEORG-xyz", "fakeorg-sentinel"]

# C4: private bead-ID prefixes (regex shape: prefix-<base36>{2,5})
# "synthproj" is a third synthetic prefix used specifically for no-fire boundary tests
# so those tests exercise the regex against a REGISTERED prefix (not a tautological
# absent-prefix pass).
private_bead_prefixes = ["fakeproj", "synth", "synthproj"]

# C5: private project nouns and private source paths
private_project_nouns = ["fake-private-proj", "synth-private-app"]
private_source_paths = ["code/personal/fake-private-repo"]
"""


def make_synthetic_config(tmp_dir: Path) -> Path:
    """Write the synthetic markers TOML to a temp file and return its path."""
    config_path = tmp_dir / "synthetic-markers.toml"
    config_path.write_text(SYNTHETIC_MARKERS_TOML, encoding="utf-8")
    return config_path


def make_fixture_tree(tmp_dir: Path, core_content: str) -> Path:
    """
    Build a minimal throwaway fixture tree with a single core asset
    that contains the given content.
    Returns the path to the generated manifest TOML file.
    """
    # Create a fixture core file
    core_file = tmp_dir / "fixture-core-skill.md"
    core_file.write_text(core_content, encoding="utf-8")

    # Create a minimal TOML manifest with this one core asset
    manifest_path = tmp_dir / "fixture-manifest.toml"
    manifest_content = f"""# Fixture manifest for oneway-check self-test
[[assets]]
class = "skill"
home = "fixture"
path = "{core_file}"
disposition = "core"
rationale = "test fixture — synthetic core asset"
"""
    manifest_path.write_text(manifest_content, encoding="utf-8")
    return manifest_path


def run_engine(manifest_path: Path, markers_config: Path = None) -> tuple[int, str]:
    """
    Run oneway-check.py with a given manifest path and optional markers config.
    Returns (exit_code, combined_stdout_stderr).
    """
    cmd = ["uv", "run", str(ENGINE_SCRIPT), "--manifest", str(manifest_path)]
    if markers_config is not None:
        cmd += ["--markers-config", str(markers_config)]
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    return result.returncode, output


# ---------------------------------------------------------------------------
# Harmless-but-discriminating planted sentinels (per marker class)
# ---------------------------------------------------------------------------
# C1: synthetic private path token (not a real repo name)
C1_SENTINEL = "See also: ~/code/FAKEREPO-sentinel/README.md for context."

# C2: hardcoded ~/.claude path (the BAD form — literal home path)
# C2 is structural (not config-driven) — the real ~/.claude token is the marker
C2_SENTINEL = "Load skill from ~/.claude/skills/some-skill/SKILL.md directly."

# C3: synthetic work-org token from synthetic config
C3_SENTINEL = "Maintained by FAKEORG-xyz on the work side."

# C4: synthetic private bead-prefix ID from synthetic config
C4_SENTINEL = "This implements fakeproj-abc1 acceptance criteria."

# Innocuous clean content — no markers from any class
CLEAN_CONTENT = """
# Fixture Core Skill

This is a harmless fixture skill for testing purposes.
The author is jsnyde0 (personal account — fine).
Uses $SKILL/SKILL.md portable convention — fine.
References harness-abc.1 — fine (harness- namespace is the future core namespace).
"""


class TestOnewayCheckC1PrivatePath(unittest.TestCase):
    """C1: private-path-token references must fire."""

    def test_c1_dirty_fires(self):
        """Engine exits non-zero when a core file contains the configured private path token."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, C1_SENTINEL)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"C1 dirty run must exit non-zero (engine must fire on private path token).\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C1", output,
                          f"Output should mention C1 class.\nEngine output:\n{output}")


class TestOnewayCheckC2HardcodedPaths(unittest.TestCase):
    """C2: hardcoded ~/.claude paths must fire (NOT $SKILL portable convention)."""

    def test_c2_dirty_fires(self):
        """Engine exits non-zero when a core file contains a hardcoded ~/.claude path."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, C2_SENTINEL)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"C2 dirty run must exit non-zero (engine must fire on hardcoded ~/.claude path).\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C2", output,
                          f"Output should mention C2 class.\nEngine output:\n{output}")

    def test_c2_skill_portable_convention_clean(self):
        """Engine exits zero when content uses the $SKILL portable convention (NOT a leak)."""
        portable_content = "Load skill from $SKILL/SKILL.md — this is the correct form."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, portable_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"C2 $SKILL portable convention must NOT fire (it's the correct form).\n"
                f"Engine output:\n{output}"
            )


class TestOnewayCheckC3WorkAccount(unittest.TestCase):
    """C3: configured work-org token references must fire."""

    def test_c3_dirty_fires(self):
        """Engine exits non-zero when a core file references the configured work-org token."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, C3_SENTINEL)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"C3 dirty run must exit non-zero (engine must fire on work-org token).\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C3", output,
                          f"Output should mention C3 class.\nEngine output:\n{output}")

    def test_c3_personal_account_clean(self):
        """Engine exits zero when content references jsnyde0 (personal account — fine)."""
        personal_content = "Maintained by jsnyde0 on GitHub."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, personal_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"C3 personal account (jsnyde0) must NOT fire.\n"
                f"Engine output:\n{output}"
            )

    def test_c3_second_work_org_token_fires(self):
        """Engine fires on the second configured work-org token (fakeorg-sentinel)."""
        second_token_sentinel = "Integrated with the fakeorg-sentinel workspace tooling."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, second_token_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"C3 second work-org token dirty run must exit non-zero.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C3", output,
                          f"Output should mention C3 class.\nEngine output:\n{output}")

    def test_c3_personal_account_still_clean(self):
        """Engine still exits zero when content references jsnyde0 (personal account — fine)."""
        personal_content = "Maintained by jsnyde0 on GitHub at github.com/jsnyde0/harness."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, personal_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"C3 personal account (jsnyde0) must NOT fire.\n"
                f"Engine output:\n{output}"
            )


class TestOnewayCheckC4BeadIds(unittest.TestCase):
    """C4: configured private bead-prefix IDs must fire; harness-* must NOT fire."""

    def test_c4_dirty_fires(self):
        """Engine exits non-zero when a core file cites a configured private bead-prefix ID."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, C4_SENTINEL)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"C4 dirty run must exit non-zero (engine must fire on private bead-prefix ID).\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C4", output,
                          f"Output should mention C4 class.\nEngine output:\n{output}")

    def test_c4_second_prefix_fires(self):
        """Engine fires on the second configured bead prefix (synth-)."""
        second_prefix_sentinel = "Implements synth-x3z acceptance criteria."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, second_prefix_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"C4 second prefix dirty run must exit non-zero.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C4", output,
                          f"Output should mention C4 class.\nEngine output:\n{output}")

    def test_c4_harness_namespace_clean(self):
        """Engine exits zero when content references harness-* bead IDs (fine — core namespace)."""
        harness_content = "Implements harness-abc.1 and harness-xyz.2 acceptance."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, harness_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"C4 harness-* namespace must NOT fire.\n"
                f"Engine output:\n{output}"
            )

    def test_c4_bead_prefix_bare_form_fires(self):
        """Engine fires on a bare bead ID (no .N suffix) for configured prefix."""
        bare_sentinel = "See fakeproj-zzz for the original design decision."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, bare_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"Bare fakeproj-zzz (no .N suffix) must fire C4.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C4", output,
                          f"Output should mention C4 class.\nEngine output:\n{output}")

    def test_c4_bead_prefix_with_subid_fires(self):
        """Engine fires on bead ID with .N sub-ID suffix."""
        sub_id_sentinel = "Decision landed by fakeproj-abc1.4.2 (the decomposition-primitive design bead)."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, sub_id_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"fakeproj-<hash>.<N> sub-bead ID must fire.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C4", output,
                          f"Output should mention C4 class.\nEngine output:\n{output}")

    def test_c4_bare_registered_prefix_alone_clean(self):
        """The bare registered prefix word (no bead token) must NOT fire.

        Uses 'synthproj' — a prefix that IS registered in the test config.
        This is non-tautological: the engine has a C4 pattern for 'synthproj',
        but the bare word (not followed by '-<base36id>') must not match it.
        Paired assertion: 'synthproj-abc1' (same registered prefix) MUST fire.
        """
        bare_word = (
            "The synthproj substrate is a cross-harness tool. "
            "Install synthproj to get started."
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            # --- no-fire: bare registered prefix ---
            manifest = make_fixture_tree(tmp_path, bare_word)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"Bare registered prefix 'synthproj' (no bead token) must NOT fire C4.\n"
                f"Engine output:\n{output}"
            )
            # --- fire: same prefix with a bead-ID token ---
            bead_id_form = "The synthproj-abc1 bead tracks this work."
            manifest2 = make_fixture_tree(tmp_path, bead_id_form)
            code2, output2 = run_engine(manifest2, config)
            self.assertNotEqual(
                code2, 0,
                f"Bead-ID form 'synthproj-abc1' for registered prefix MUST fire C4.\n"
                f"Engine output:\n{output2}"
            )
            self.assertIn("C4", output2,
                          f"Output should mention C4 class.\nEngine output:\n{output2}")

    def test_c4_english_compound_registered_prefix_clean(self):
        """English compound words built on a REGISTERED prefix must NOT fire.

        Uses 'synthproj' — a prefix that IS registered in the test config.
        The regex requires the slug after '-' to be 2-5 base36 chars; English
        words like 'managed' (7 chars) and 'driven' (6 chars) exceed that bound.
        Paired assertion: a real bead-ID shape on the same prefix MUST fire.
        """
        compound_content = (
            "This is a synthproj-managed configuration. "
            "The synthproj-driven workflow is preferred."
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            # --- no-fire: English compound words ---
            manifest = make_fixture_tree(tmp_path, compound_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"English compounds 'synthproj-managed' / 'synthproj-driven' must NOT fire.\n"
                f"Engine output:\n{output}"
            )
            # --- fire: same registered prefix with a bead-ID token ---
            bead_id_form = "Implements synthproj-f8l acceptance criteria."
            manifest2 = make_fixture_tree(tmp_path, bead_id_form)
            code2, output2 = run_engine(manifest2, config)
            self.assertNotEqual(
                code2, 0,
                f"Bead-ID form 'synthproj-f8l' for registered prefix MUST fire C4.\n"
                f"Engine output:\n{output2}"
            )
            self.assertIn("C4", output2,
                          f"Output should mention C4 class.\nEngine output:\n{output2}")

    def test_c4_temp_dir_prefix_registered_clean(self):
        """Temp-dir prefix strings built on a REGISTERED prefix must NOT fire.

        Uses 'synthproj' — a prefix that IS registered in the test config.
        The trailing '-' after the slug is excluded by the negative lookahead
        (?![a-z0-9-]) in the regex, so 'synthproj-probe-' does not match.
        Paired assertion: a real bead-ID shape on the same prefix MUST fire.
        """
        tmpdir_content = (
            'const probeHome = path.join(os.tmpdir(), "synthproj-probe-" + Date.now()); '
            'const sentinelReason = "synthproj-sentinel-test: blocked by dcg policy"; '
            'const negDir = await mkdtemp(path.join(os.tmpdir(), "synthproj-neg-")); '
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            # --- no-fire: temp-dir prefix strings (trailing '-' guards them) ---
            manifest = make_fixture_tree(tmp_path, tmpdir_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"Temp-dir prefix strings (synthproj-probe-, synthproj-neg-, etc.) "
                f"must NOT fire C4.\n"
                f"Engine output:\n{output}"
            )
            # --- fire: same registered prefix with a bead-ID token ---
            bead_id_form = "Decision landed by synthproj-3bi (the decomp bead)."
            manifest2 = make_fixture_tree(tmp_path, bead_id_form)
            code2, output2 = run_engine(manifest2, config)
            self.assertNotEqual(
                code2, 0,
                f"Bead-ID form 'synthproj-3bi' for registered prefix MUST fire C4.\n"
                f"Engine output:\n{output2}"
            )
            self.assertIn("C4", output2,
                          f"Output should mention C4 class.\nEngine output:\n{output2}")

    def test_c4_claude_model_names_clean(self):
        """Model names like claude-opus-4-8, claude-sonnet-4-6 must NOT fire."""
        model_content = (
            "The model claude-opus-4-8 is used for heavy work. "
            "claude-sonnet-4-6 for everyday tasks. "
            "claude-haiku-4-5 for fast/cheap. "
            "claude-opus, claude-sonnet, claude-haiku are also valid aliases."
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, model_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"Model names (claude-opus-4-8 etc.) must NOT fire as C4.\n"
                f"Engine output:\n{output}"
            )

    def test_c4_claude_word_slugs_clean(self):
        """Product/word slugs like claude-code, claude-switch, claude-session, etc. must NOT fire."""
        slug_content = (
            "Use claude-code for implementation. "
            "See claude.ai for the web UI. "
            "claude-switch changes accounts. "
            "claude-session tracks history. "
            "claude-account manages credentials. "
            "claude-extension adds functionality. "
            "claude-caliper measures output."
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, slug_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"Word slugs (claude-code, claude-switch, etc.) must NOT fire as C4.\n"
                f"Engine output:\n{output}"
            )


class TestOnewayCheckCleanRun(unittest.TestCase):
    """Clean run: no planted markers → engine must exit zero."""

    def test_clean_exits_zero(self):
        """Engine exits zero when no private markers are present."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, CLEAN_CONTENT)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"Clean run must exit zero.\n"
                f"Engine output:\n{output}"
            )


class TestOnewayCheckPerClassIsolation(unittest.TestCase):
    """
    Per-class isolation: verify each class fires independently.
    This closes the hole where a lumped fixture passes even if the
    check is blind to some classes.
    """

    def _run_isolated(self, sentinel: str, expected_class_label: str, config: Path):
        """Helper: run with only the given sentinel, assert non-zero + class in output."""
        with tempfile.TemporaryDirectory() as tmp:
            manifest = make_fixture_tree(Path(tmp), sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"Isolated {expected_class_label} dirty run must exit non-zero.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn(expected_class_label, output,
                          f"Output should mention {expected_class_label}.\nEngine output:\n{output}")

    def test_isolation_c1_only(self):
        """Only C1 marker present → engine fires on C1."""
        with tempfile.TemporaryDirectory() as tmp:
            config = make_synthetic_config(Path(tmp))
            self._run_isolated(C1_SENTINEL, "C1", config)

    def test_isolation_c2_only(self):
        """Only C2 marker present → engine fires on C2."""
        with tempfile.TemporaryDirectory() as tmp:
            config = make_synthetic_config(Path(tmp))
            self._run_isolated(C2_SENTINEL, "C2", config)

    def test_isolation_c3_only(self):
        """Only C3 marker present → engine fires on C3."""
        with tempfile.TemporaryDirectory() as tmp:
            config = make_synthetic_config(Path(tmp))
            self._run_isolated(C3_SENTINEL, "C3", config)

    def test_isolation_c4_only(self):
        """Only C4 marker present → engine fires on C4."""
        with tempfile.TemporaryDirectory() as tmp:
            config = make_synthetic_config(Path(tmp))
            self._run_isolated(C4_SENTINEL, "C4", config)


class TestOnewayCheckC5PrivatePaths(unittest.TestCase):
    """C5: configured private source paths and private project nouns must fire."""

    def test_c5_code_personal_private_path_fires(self):
        """Engine fires on a configured private 'code/personal/<repo>' path fragment."""
        private_path_sentinel = "See ~/code/personal/fake-private-repo/agent/skills/ for the skill source."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, private_path_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"Configured private path must fire C5.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C5", output,
                          f"Output should mention C5 class.\nEngine output:\n{output}")

    def test_c5_private_project_noun_fires(self):
        """Engine fires on a configured private project noun."""
        noun_sentinel = "Confirmed on fake-private-proj and another private repo."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, noun_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"Configured private project noun must fire C5.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C5", output,
                          f"Output should mention C5 class.\nEngine output:\n{output}")

    def test_c5_second_private_noun_fires(self):
        """Engine fires on the second configured private project noun."""
        second_noun_sentinel = "Proven across the methodology home and synth-private-app repos."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, second_noun_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"Second configured private project noun must fire C5.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C5", output,
                          f"Output should mention C5 class.\nEngine output:\n{output}")

    def test_c5_code_personal_harness_clean(self):
        """Engine does NOT fire on 'code/personal/harness' — that IS the public core."""
        harness_path_content = (
            "Install from ~/code/personal/harness/install.sh — this is the public repo. "
            "bash $HOME/code/personal/harness/install.sh runs the install."
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, harness_path_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"'code/personal/harness' (the public core repo path) must NOT fire C5.\n"
                f"Engine output:\n{output}"
            )

    def test_c5_resume_verb_clean(self):
        """The English verb 'resume' must NOT fire (too ambiguous; only repo-name use is a leak)."""
        verb_content = (
            "When re-pulled, the orchestrator resumes its persisted session. "
            "Resume the session with `pi --session <id>`. "
            "Session-resume is cheaper than cold respawn. "
            "After compaction or session-resume, context is restored."
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, verb_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"English verb 'resume' / 'resumes' must NOT fire C5.\n"
                f"Engine output:\n{output}"
            )


class TestOnewayCheckC5Isolation(unittest.TestCase):
    """C5 isolation: verify C5 fires independently (only C5 marker present)."""

    def _run_isolated(self, sentinel: str, expected_class_label: str, config: Path):
        """Helper: run with only the given sentinel, assert non-zero + class in output."""
        with tempfile.TemporaryDirectory() as tmp:
            manifest = make_fixture_tree(Path(tmp), sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"Isolated {expected_class_label} dirty run must exit non-zero.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn(expected_class_label, output,
                          f"Output should mention {expected_class_label}.\nEngine output:\n{output}")

    def test_c5_private_path_isolated(self):
        """Only C5 marker (configured private path) present → engine fires on C5."""
        with tempfile.TemporaryDirectory() as tmp:
            config = make_synthetic_config(Path(tmp))
            self._run_isolated(
                "See ~/code/personal/fake-private-repo/agent/skills/ for context.",
                "C5",
                config,
            )

    def test_c5_private_noun_isolated(self):
        """Only C5 marker (configured private project noun) present → engine fires on C5."""
        with tempfile.TemporaryDirectory() as tmp:
            config = make_synthetic_config(Path(tmp))
            self._run_isolated(
                "Confirmed on fake-private-proj and a private project.",
                "C5",
                config,
            )

    def test_c5_second_noun_isolated(self):
        """Only C5 marker (second configured private noun) present → engine fires on C5."""
        with tempfile.TemporaryDirectory() as tmp:
            config = make_synthetic_config(Path(tmp))
            self._run_isolated(
                "Proven across the methodology home and synth-private-app repos.",
                "C5",
                config,
            )


class TestOnewayCheckC6HomePaths(unittest.TestCase):
    """C6: absolute macOS home paths (/Users/<username>/) must fire; generic paths clean."""

    def test_c6_absolute_home_path_fires(self):
        """Engine exits non-zero when a core file contains an absolute /Users/ home path."""
        c6_sentinel = "See /Users/someone/secret/config.yaml for details."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, c6_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"C6 dirty run must exit non-zero (engine must fire on /Users/ home path).\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C6", output,
                          f"Output should mention C6 class.\nEngine output:\n{output}")

    def test_c6_any_username_fires(self):
        """Engine fires on /Users/ paths regardless of the specific username."""
        different_user_sentinel = "Configured at /Users/anotheruser/dotfiles/config.toml."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, different_user_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"C6 must fire on any /Users/<username> path.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C6", output,
                          f"Output should mention C6 class.\nEngine output:\n{output}")

    def test_c6_home_variable_clean(self):
        """Content using $HOME or ~ (portable forms) must NOT fire C6."""
        portable_content = (
            "Install to $HOME/code/personal/harness/. "
            "Run ~/bin/setup.sh to configure."
        )
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, portable_content)
            code, output = run_engine(manifest, config)
            self.assertEqual(
                code, 0,
                f"Portable $HOME and ~ paths must NOT fire C6.\n"
                f"Engine output:\n{output}"
            )

    def test_c6_isolation_fires_independently(self):
        """Only C6 marker present → engine fires on C6 (isolation test)."""
        c6_only_sentinel = "Path is /Users/testuser/workspace/project."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, c6_only_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(
                code, 0,
                f"Isolated C6 dirty run must exit non-zero.\n"
                f"Engine output:\n{output}"
            )
            self.assertIn("C6", output,
                          f"Output should mention C6 class.\nEngine output:\n{output}")


class TestOnewayCheckAllTrackedScan(unittest.TestCase):
    """
    Verify that the all-tracked-files scan covers non-manifest files.

    The all-tracked scan runs when the real core-manifest.toml is used.
    Fixture-manifest runs still use the manifest-asset scan (backward compat for self-test).

    These tests verify the scan-mode selection logic using the importable API.
    """

    def test_fixture_manifest_uses_asset_scan(self):
        """Fixture manifest runs use manifest-asset scan (use_all_tracked=False)."""
        # The fixture manifest sentinel must fire even in asset-scan mode
        # Use synthetic C4 sentinel with the synthetic config
        c4_sentinel = "This implements fakeproj-abc1 acceptance criteria."
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config = make_synthetic_config(tmp_path)
            manifest = make_fixture_tree(tmp_path, c4_sentinel)
            code, output = run_engine(manifest, config)
            self.assertNotEqual(code, 0,
                                 f"Fixture manifest run with C4 sentinel must fire.\n{output}")
            self.assertIn("C4", output)

    def test_all_tracked_scan_label_in_production_run(self):
        """
        Production run (real manifest) reports 'all tracked files' in the scan label.

        This verifies the scan-mode auto-detection: when running against the real
        core-manifest.toml, the engine reports scanning all tracked files (not just
        manifest assets).
        """
        result = subprocess.run(
            ["uv", "run", str(ENGINE_SCRIPT)],
            capture_output=True,
            text=True,
            cwd=str(SCRIPT_DIR.parent),  # run from repo root
        )
        output = result.stdout + result.stderr
        self.assertIn(
            "all tracked files",
            output,
            f"Production run should report 'all tracked files' in scan label.\n{output}"
        )

    def test_all_tracked_scan_covers_non_manifest_files(self):
        """
        Verifies the all-tracked scan reaches non-manifest files by planting a
        synthetic C4 marker in a NON-manifest tracked file inside a throwaway git
        repo and asserting the engine fires on it.

        Strategy:
          1. Build a minimal throwaway git repo in a temp dir.
          2. Create a manifest/ subdir with a clean core-manifest.toml (no markers).
          3. Create a non-manifest tracked file (install.sh) containing a C4 sentinel.
          4. git-init, git-add, git-commit so ls-files returns both files.
          5. Run the engine against the synthetic manifest with use_all_tracked=True
             (via --manifest pointing at our synthetic manifest, using the subprocess
             interface with the engine's auto-detection logic).
          6. Assert exit non-zero and C4 in output — proving the scan reached the
             non-manifest install.sh.

        The temp dir is fully discarded after the test — no real tracked files touched.
        """
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)

            # Set up a minimal manifest/ subdir — engine expects manifest at
            # repo_root/manifest/*.toml so it can derive repo_root = manifest.parent.parent
            manifest_dir = tmp_path / "manifest"
            manifest_dir.mkdir()
            manifest_path = manifest_dir / "core-manifest.toml"
            # The manifest lists NO assets — the test relies on all-tracked mode
            manifest_path.write_text(
                "# Throwaway synthetic manifest for all-tracked scan test\n",
                encoding="utf-8",
            )

            # Create a non-manifest tracked file with a C4 synthetic marker
            # (synthproj is registered in the synthetic config)
            non_manifest_file = tmp_path / "install.sh"
            non_manifest_file.write_text(
                "#!/bin/sh\n"
                "# Throwaway install script\n"
                "# synthproj-abc1 was the bead that landed this design.\n",
                encoding="utf-8",
            )

            # Also create the scripts/ dir so git-init finds it; markers config goes there
            scripts_dir = tmp_path / "scripts"
            scripts_dir.mkdir()
            markers_config = scripts_dir / "synthetic-markers.toml"
            markers_config.write_text(
                SYNTHETIC_MARKERS_TOML,
                encoding="utf-8",
            )

            # Initialise a throwaway git repo and commit both files so git ls-files
            # returns them. We use a throwaway git identity to avoid touching real config.
            subprocess.run(
                ["git", "init", str(tmp_path)],
                capture_output=True,
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "config", "user.email", "test@example.com"],
                capture_output=True,
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "config", "user.name", "Test"],
                capture_output=True,
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "add", "."],
                capture_output=True,
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "commit", "-m", "throwaway"],
                capture_output=True,
                check=True,
            )

            # Run the engine: use_all_tracked is auto-detected as False here because
            # manifest_path != DEFAULT_MANIFEST_PATH. We need to force True.
            # We do this via subprocess with an explicit --manifest pointing at our
            # synthetic manifest, but wrap it with a helper flag approach:
            # The cleanest way is to call run_check via importable API.
            sys.path.insert(0, str(SCRIPT_DIR))
            try:
                import importlib.util
                spec = importlib.util.spec_from_file_location(
                    "oneway_check_mod", str(ENGINE_SCRIPT)
                )
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                # run_check with use_all_tracked=True to force all-tracked mode
                import io
                from contextlib import redirect_stdout, redirect_stderr
                buf = io.StringIO()
                with redirect_stdout(buf):
                    with redirect_stderr(buf):
                        findings = mod.run_check(
                            manifest_path=manifest_path,
                            use_all_tracked=True,
                            markers_config_path=markers_config,
                        )
                output = buf.getvalue()
            finally:
                sys.path.pop(0)

            # The engine must have found the C4 marker in install.sh (non-manifest file)
            self.assertTrue(
                len(findings) > 0,
                f"All-tracked scan must find the C4 marker planted in non-manifest "
                f"install.sh.\nEngine output:\n{output}"
            )
            c4_findings = [f for f in findings if f.marker_class == "C4"]
            self.assertTrue(
                len(c4_findings) > 0,
                f"At least one finding must be class C4.\nFindings: {findings}\n"
                f"Engine output:\n{output}"
            )
            # Confirm the finding came from the non-manifest file (install.sh)
            hit_paths = [str(f.file_path) for f in c4_findings]
            self.assertTrue(
                any("install.sh" in p for p in hit_paths),
                f"C4 finding must originate from non-manifest install.sh.\n"
                f"Finding paths: {hit_paths}\n"
                f"Engine output:\n{output}"
            )


class TestDocsDecisionsBoundary(unittest.TestCase):
    """
    Boundary-presence guard: docs/decisions/ must remain EMPTY by design.

    All methodology/mechanism ADRs are private and must never publish.
    Any file matching ADR-*.md or INDEX.md under docs/decisions/ is a leak.
    """

    def _run_boundary_check(self, repo_root: Path) -> tuple[list, str]:
        """
        Run check_docs_decisions_boundary() via the importable API.
        Returns (findings_list, output_string).
        """
        import importlib.util
        import io
        from contextlib import redirect_stdout, redirect_stderr

        spec = importlib.util.spec_from_file_location(
            "oneway_check_boundary", str(ENGINE_SCRIPT)
        )
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        buf = io.StringIO()
        with redirect_stdout(buf):
            with redirect_stderr(buf):
                findings = mod.check_docs_decisions_boundary(repo_root)
        output = buf.getvalue()
        return findings, output

    def test_boundary_fires_on_adr_file(self):
        """check_docs_decisions_boundary() returns a finding when ADR-*.md exists."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            decisions_dir = tmp_path / "docs" / "decisions"
            decisions_dir.mkdir(parents=True)
            fake_adr = decisions_dir / "ADR-999-fake.md"
            fake_adr.write_text("fake test ADR body", encoding="utf-8")

            findings, output = self._run_boundary_check(tmp_path)
            self.assertTrue(
                len(findings) > 0,
                f"Boundary check must return a finding for ADR-999-fake.md.\n"
                f"Output:\n{output}"
            )
            # Finding text must mention the offending file
            finding_strs = [str(f) for f in findings]
            self.assertTrue(
                any("ADR-999-fake.md" in s for s in finding_strs),
                f"Finding must mention ADR-999-fake.md.\nFindings: {finding_strs}"
            )

    def test_boundary_fires_on_index_file(self):
        """check_docs_decisions_boundary() returns a finding when INDEX.md exists."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            decisions_dir = tmp_path / "docs" / "decisions"
            decisions_dir.mkdir(parents=True)
            index_file = decisions_dir / "INDEX.md"
            index_file.write_text("fake test INDEX body", encoding="utf-8")

            findings, output = self._run_boundary_check(tmp_path)
            self.assertTrue(
                len(findings) > 0,
                f"Boundary check must return a finding for INDEX.md.\n"
                f"Output:\n{output}"
            )
            finding_strs = [str(f) for f in findings]
            self.assertTrue(
                any("INDEX.md" in s for s in finding_strs),
                f"Finding must mention INDEX.md.\nFindings: {finding_strs}"
            )

    def test_boundary_passes_when_decisions_absent(self):
        """check_docs_decisions_boundary() returns no findings when docs/decisions/ is absent."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            # No docs/decisions/ dir created at all
            findings, output = self._run_boundary_check(tmp_path)
            self.assertEqual(
                len(findings), 0,
                f"Boundary check must return no findings when docs/decisions/ is absent.\n"
                f"Output:\n{output}"
            )

    def test_boundary_passes_when_decisions_empty(self):
        """check_docs_decisions_boundary() returns no findings when docs/decisions/ is empty."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            decisions_dir = tmp_path / "docs" / "decisions"
            decisions_dir.mkdir(parents=True)
            # No files created inside

            findings, output = self._run_boundary_check(tmp_path)
            self.assertEqual(
                len(findings), 0,
                f"Boundary check must return no findings when docs/decisions/ is empty.\n"
                f"Output:\n{output}"
            )

    def test_boundary_non_adr_files_clean(self):
        """check_docs_decisions_boundary() ignores non-ADR files (e.g. .gitkeep, README)."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            decisions_dir = tmp_path / "docs" / "decisions"
            decisions_dir.mkdir(parents=True)
            (decisions_dir / ".gitkeep").write_text("", encoding="utf-8")
            # A hypothetical non-ADR harness-specific file that might be added later
            (decisions_dir / "HARNESS-NOTE.md").write_text(
                "This dir is intentionally empty.", encoding="utf-8"
            )

            findings, output = self._run_boundary_check(tmp_path)
            self.assertEqual(
                len(findings), 0,
                f"Boundary check must not fire on non-ADR files (.gitkeep, HARNESS-NOTE.md).\n"
                f"Output:\n{output}"
            )

    def test_boundary_integrated_in_run_check_via_git_repo(self):
        """
        End-to-end: run_check() with a throwaway git repo returns a finding when
        docs/decisions/ADR-999-fake.md is tracked.

        This verifies the boundary guard is wired into the main run_check() flow
        (not just callable as a standalone function).
        """
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)

            # Set up minimal manifest structure
            manifest_dir = tmp_path / "manifest"
            manifest_dir.mkdir()
            manifest_path = manifest_dir / "core-manifest.toml"
            manifest_path.write_text(
                "# Throwaway synthetic manifest for boundary integration test\n",
                encoding="utf-8",
            )

            # Plant an ADR file in docs/decisions/
            decisions_dir = tmp_path / "docs" / "decisions"
            decisions_dir.mkdir(parents=True)
            (decisions_dir / "ADR-999-fake.md").write_text(
                "fake test ADR body", encoding="utf-8"
            )

            # Markers config (no real tokens needed for the boundary check)
            scripts_dir = tmp_path / "scripts"
            scripts_dir.mkdir()
            markers_config = scripts_dir / "synthetic-markers.toml"
            markers_config.write_text(SYNTHETIC_MARKERS_TOML, encoding="utf-8")

            # Init throwaway git repo and commit everything
            subprocess.run(["git", "init", str(tmp_path)], capture_output=True, check=True)
            subprocess.run(
                ["git", "-C", str(tmp_path), "config", "user.email", "test@example.com"],
                capture_output=True, check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "config", "user.name", "Test"],
                capture_output=True, check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "add", "."],
                capture_output=True, check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "commit", "-m", "throwaway"],
                capture_output=True, check=True,
            )

            import importlib.util
            import io
            from contextlib import redirect_stdout, redirect_stderr

            spec = importlib.util.spec_from_file_location(
                "oneway_check_integ", str(ENGINE_SCRIPT)
            )
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)

            buf = io.StringIO()
            with redirect_stdout(buf):
                with redirect_stderr(buf):
                    findings = mod.run_check(
                        manifest_path=manifest_path,
                        use_all_tracked=True,
                        markers_config_path=markers_config,
                    )
            output = buf.getvalue()

            boundary_findings = [f for f in findings if "BOUNDARY" in str(f)]
            self.assertTrue(
                len(boundary_findings) > 0 or any("ADR-999-fake.md" in str(f) for f in findings),
                f"run_check() must report a finding for docs/decisions/ADR-999-fake.md.\n"
                f"All findings: {findings}\n"
                f"Output:\n{output}"
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
