#!/usr/bin/env python3
"""
Tests for validate_roles.py enforcement of the CONJUNCTION REQUIREMENT
(skills+output-contract must be present and resolve):
  - skills: MUST be non-empty (>= 1 entry)
  - every skill entry MUST resolve to an existing agent/skills/<folder>
  - output-contract: MUST be present
"""

import os
import sys
import tempfile
import unittest

# Ensure we can import validate_roles from this directory
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validate_roles


class TestValidatorEnforcement(unittest.TestCase):
    """Tests that the validator FAILS when new enforcement rules are violated."""

    def _make_role_file(self, content, tmp_dir=None):
        """Write a role file to a temp directory and return the path."""
        if tmp_dir is None:
            tmp_dir = tempfile.mkdtemp()
        path = os.path.join(tmp_dir, "test-role.md")
        with open(path, "w") as f:
            f.write(content)
        return path

    # ── RULE 1: skills must be non-empty ─────────────────────────────────────

    def test_empty_skills_fails(self):
        """A role with skills: '' must FAIL validation."""
        role_content = """\
---
name: test-role
description: A test role
tools: Read
skills: ""
model: haiku
pi-model: openrouter/google/gemini-flash-1.5
output-contract: Must end with DONE
---

Body content here that is long enough to pass the body check.
"""
        path = self._make_role_file(role_content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertFalse(passed, f"Expected FAIL for empty skills, but got PASS. Report:\n{report}")
        self.assertIn("skills", report.lower(),
                      "Error message should mention 'skills'")

    def test_skills_none_string_fails(self):
        """A role with skills: 'none' must FAIL validation."""
        role_content = """\
---
name: test-role
description: A test role
tools: Read
skills: none
model: haiku
pi-model: openrouter/google/gemini-flash-1.5
output-contract: Must end with DONE
---

Body content here that is long enough to pass the body check.
"""
        path = self._make_role_file(role_content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertFalse(passed, f"Expected FAIL for skills='none', but got PASS. Report:\n{report}")

    # ── RULE 2: every skill entry must resolve to an existing agent/skills/ path ──

    def test_dangling_skill_ref_fails(self):
        """A role with a non-existent skill path must FAIL validation."""
        role_content = """\
---
name: test-role
description: A test role
tools: Read
skills: nonexistent-skill-xyz
model: haiku
pi-model: openrouter/google/gemini-flash-1.5
output-contract: Must end with DONE
---

Body content here that is long enough to pass the body check.
"""
        path = self._make_role_file(role_content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertFalse(passed, f"Expected FAIL for dangling skill ref, but got PASS. Report:\n{report}")
        self.assertIn("dangling", report.lower(),
                      "Error message should mention 'dangling'")

    # ── RULE 3: output-contract must be present ───────────────────────────────

    def test_missing_output_contract_fails(self):
        """A role without output-contract: must FAIL validation."""
        role_content = """\
---
name: test-role
description: A test role
tools: Read
skills: browser-automation
model: haiku
pi-model: openrouter/google/gemini-flash-1.5
---

Body content here that is long enough to pass the body check.
"""
        path = self._make_role_file(role_content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertFalse(passed, f"Expected FAIL for missing output-contract, but got PASS. Report:\n{report}")
        self.assertIn("output-contract", report.lower(),
                      "Error message should mention 'output-contract'")

    # ── RULE 4: valid role with all three new requirements passes ─────────────

    def test_valid_role_with_real_skill_and_output_contract_passes(self):
        """A role with a real skill path and output-contract must PASS validation."""
        role_content = """\
---
name: test-role
description: A test role
tools: Read
skills: browser-automation
model: haiku
pi-model: openrouter/google/gemini-flash-1.5
codex-model: openai/gpt-5.5
output-contract: Must end with SCAN-COMPLETE
---

Body content here that is long enough to pass the body check.
"""
        path = self._make_role_file(role_content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertTrue(passed, f"Expected PASS for valid role, but got FAIL. Report:\n{report}")

    # ── RULE 5: both production role files must pass ──────────────────────────

    def test_file_scanner_role_passes(self):
        """The file-scanner.md production role must PASS the tightened rules."""
        roles_dir = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(roles_dir, "file-scanner.md")
        passed, report = validate_roles.validate_role_file(path)
        self.assertTrue(passed, f"file-scanner.md must PASS tightened rules. Report:\n{report}")

    def test_content_extractor_role_passes(self):
        """The content-extractor.md production role must PASS the tightened rules."""
        roles_dir = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(roles_dir, "content-extractor.md")
        passed, report = validate_roles.validate_role_file(path)
        self.assertTrue(passed, f"content-extractor.md must PASS tightened rules. Report:\n{report}")


class TestCodexModelField(unittest.TestCase):
    """Tests for codex-model: field enforcement."""

    def _make_role_file(self, content, tmp_dir=None):
        """Write a role file to a temp directory and return the path."""
        if tmp_dir is None:
            tmp_dir = tempfile.mkdtemp()
        path = os.path.join(tmp_dir, "test-role.md")
        with open(path, "w") as f:
            f.write(content)
        return path

    def _base_role_content(self, extra_frontmatter=""):
        """Return a valid base role content, optionally with extra frontmatter."""
        return f"""\
---
name: test-role
description: A test role
tools: Read
skills: browser-automation
model: haiku
pi-model: openrouter/openai/gpt-4.1-nano
output-contract: Must end with DONE
{extra_frontmatter}---

Body content here that is long enough to pass the body check.
"""

    def test_valid_codex_model_passes(self):
        """(a) A role with a valid codex-model openai/<model> slug must PASS validation."""
        content = self._base_role_content("codex-model: openai/gpt-5.5\n")
        path = self._make_role_file(content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertTrue(passed, f"Expected PASS for valid codex-model, but got FAIL. Report:\n{report}")

    def test_missing_codex_model_fails(self):
        """(b) A role WITHOUT codex-model: must FAIL — proves the field is required."""
        content = self._base_role_content()  # no codex-model field
        path = self._make_role_file(content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertFalse(passed, f"Expected FAIL for missing codex-model, but got PASS. Report:\n{report}")
        self.assertIn("codex-model", report,
                      "Error message should mention 'codex-model'")

    def test_malformed_codex_model_slug_fails(self):
        """(c) A malformed codex-model value (no slash, wrong shape) must FAIL."""
        content = self._base_role_content("codex-model: gpt-5.5\n")  # no provider/model form
        path = self._make_role_file(content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertFalse(passed, f"Expected FAIL for malformed codex-model slug, but got PASS. Report:\n{report}")
        self.assertIn("codex-model", report,
                      "Error message should mention 'codex-model'")

    def test_non_openai_provider_warns(self):
        """(d) A codex-model with non-openai provider segment must WARN (not fail)."""
        content = self._base_role_content("codex-model: azure/gpt-5.5\n")
        path = self._make_role_file(content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertTrue(passed, f"Expected PASS (with warning) for non-openai provider, but got FAIL. Report:\n{report}")
        self.assertIn("warn", report.lower(),
                      "Report should contain a WARNING for non-openai codex-model provider")


class TestRoleClassRelaxation(unittest.TestCase):
    """
    Tests for ADR-002 D3: per-role-class field optionality.

    Syntax: role-class: general-purpose
    When role-class is general-purpose:
      - skills may be omitted/empty IF skills-omit-rationale is present
      - output-contract may be omitted IF output-contract-omit-rationale is present
      - omission WITHOUT the corresponding rationale field → FAIL (accidental omission)
    REFERENCE roles (no role-class or role-class: reference) keep the full conjunction requirement.
    """

    def _make_role_file(self, content, tmp_dir=None):
        """Write a role file to a temp directory and return the path."""
        if tmp_dir is None:
            tmp_dir = tempfile.mkdtemp()
        path = os.path.join(tmp_dir, "test-role.md")
        with open(path, "w") as f:
            f.write(content)
        return path

    def test_general_purpose_omit_with_rationale_passes(self):
        """(a) A general-purpose role omitting skills+output-contract WITH rationale must PASS."""
        role_content = """\
---
name: orchestrator-role
description: A general-purpose orchestrator agent
tools: Read, Write
skills-omit-rationale: This role uses methodology-home skills which live outside agent/skills/
output-contract-omit-rationale: Orchestrators emit dynamic judgment, not a fixed final-line contract
role-class: general-purpose
model: haiku
pi-model: openrouter/google/gemini-flash-1.5
codex-model: openai/gpt-5.5
---

This is a general-purpose orchestrator agent that coordinates work across many sub-agents
and uses skills from the user's methodology home. It does not have a fixed
output-contract because its outputs vary by task context.
"""
        path = self._make_role_file(role_content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertTrue(
            passed,
            f"Expected PASS for general-purpose role with rationale, but got FAIL. Report:\n{report}"
        )

    def test_omit_without_rationale_fails(self):
        """(b) A role omitting skills+output-contract WITHOUT rationale must FAIL (accidental omission)."""
        role_content = """\
---
name: orchestrator-role
description: A general-purpose orchestrator agent
tools: Read, Write
role-class: general-purpose
model: haiku
pi-model: openrouter/google/gemini-flash-1.5
codex-model: openai/gpt-5.5
---

This is a general-purpose orchestrator agent that coordinates work across many sub-agents.
It accidentally omits skills and output-contract without explaining why.
"""
        path = self._make_role_file(role_content)
        passed, report = validate_roles.validate_role_file(path)
        self.assertFalse(
            passed,
            f"Expected FAIL for omission without rationale, but got PASS. Report:\n{report}"
        )

    def test_reference_role_file_scanner_still_passes(self):
        """(c) The file-scanner.md reference role must still PASS (no regression)."""
        roles_dir = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(roles_dir, "file-scanner.md")
        passed, report = validate_roles.validate_role_file(path)
        self.assertTrue(
            passed,
            f"file-scanner.md (reference role) must still PASS after relaxation. Report:\n{report}"
        )

    def test_reference_role_content_extractor_still_passes(self):
        """(c) The content-extractor.md reference role must still PASS (no regression)."""
        roles_dir = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(roles_dir, "content-extractor.md")
        passed, report = validate_roles.validate_role_file(path)
        self.assertTrue(
            passed,
            f"content-extractor.md (reference role) must still PASS after relaxation. Report:\n{report}"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
