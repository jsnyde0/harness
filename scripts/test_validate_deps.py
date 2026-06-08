#!/usr/bin/env python3
"""
Tests for validate_deps.py enforcement of the deps.toml schema.

Required fields for each [[dep]] entry:
  - name       (str, non-empty)
  - source     (str, URL template with {version} placeholder)
  - version    (str, non-empty)
  - sha256     (str, must match ^[0-9a-f]{64}$)
  - arch       (str, non-empty)
  - install    (str, non-empty)
  - verify     (str, non-empty)

Tests:
  - Valid manifest with all required fields passes
  - Missing any required field fails with a clear message
  - Malformed sha256 (not 64 hex chars) fails
  - sha256 with uppercase hex fails (must be lowercase)
  - sha256 with wrong length fails
  - Empty name fails
  - Missing {version} placeholder in source fails
  - Production manifest/deps.toml passes validation
"""

import os
import sys
import tempfile
import unittest

# Ensure we can import validate_deps from the scripts/ directory
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validate_deps

# A known-good 64-char hex sha256 for testing
GOOD_SHA256 = "643e602e27f666c8726abff0f22001e2b5883988fa960204bde20a3129d448a5"


def _write_toml(content: str) -> str:
    """Write TOML content to a temp file and return the path."""
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".toml", delete=False
    )
    tmp.write(content)
    tmp.close()
    return tmp.name


def _valid_manifest_content() -> str:
    """Return a valid minimal deps.toml content for a single dep."""
    return f"""
[[dep]]
name = "testdep"
source = "https://example.com/releases/download/v{{version}}/testdep_{{version}}_linux_amd64.tar.gz"
version = "1.0.0"
sha256 = "{GOOD_SHA256}"
arch = "linux-amd64"
install = "curl -L ... && sha256sum -c && tar xz"
verify = "testdep --version"
"""


class TestValidDepEntry(unittest.TestCase):
    """Tests that a valid dep entry passes validation."""

    def test_valid_manifest_passes(self):
        """A complete, well-formed manifest must PASS validation."""
        path = _write_toml(_valid_manifest_content())
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertTrue(
                passed,
                f"Expected PASS for valid manifest, got FAIL. Errors:\n{errors}"
            )
        finally:
            os.unlink(path)

    def test_valid_manifest_has_no_errors(self):
        """A complete manifest must return an empty error list."""
        path = _write_toml(_valid_manifest_content())
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertEqual(errors, [], f"Expected no errors, got: {errors}")
        finally:
            os.unlink(path)


class TestMissingRequiredFields(unittest.TestCase):
    """Tests that missing required fields cause validation to fail."""

    def _manifest_without_field(self, field: str) -> str:
        """Return a valid manifest with one field removed."""
        lines = _valid_manifest_content().strip().splitlines()
        filtered = [l for l in lines if not l.startswith(f"{field} =")]
        return "\n".join(filtered) + "\n"

    def test_missing_name_fails(self):
        path = _write_toml(self._manifest_without_field("name"))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for missing 'name'")
            self.assertTrue(
                any("name" in e.lower() for e in errors),
                f"Error should mention 'name'. Errors: {errors}"
            )
        finally:
            os.unlink(path)

    def test_missing_source_fails(self):
        path = _write_toml(self._manifest_without_field("source"))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for missing 'source'")
            self.assertTrue(
                any("source" in e.lower() for e in errors),
                f"Error should mention 'source'. Errors: {errors}"
            )
        finally:
            os.unlink(path)

    def test_missing_version_fails(self):
        path = _write_toml(self._manifest_without_field("version"))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for missing 'version'")
            self.assertTrue(
                any("version" in e.lower() for e in errors),
                f"Error should mention 'version'. Errors: {errors}"
            )
        finally:
            os.unlink(path)

    def test_missing_sha256_fails(self):
        path = _write_toml(self._manifest_without_field("sha256"))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for missing 'sha256'")
            self.assertTrue(
                any("sha256" in e.lower() for e in errors),
                f"Error should mention 'sha256'. Errors: {errors}"
            )
        finally:
            os.unlink(path)

    def test_missing_arch_fails(self):
        path = _write_toml(self._manifest_without_field("arch"))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for missing 'arch'")
            self.assertTrue(
                any("arch" in e.lower() for e in errors),
                f"Error should mention 'arch'. Errors: {errors}"
            )
        finally:
            os.unlink(path)

    def test_missing_install_fails(self):
        path = _write_toml(self._manifest_without_field("install"))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for missing 'install'")
            self.assertTrue(
                any("install" in e.lower() for e in errors),
                f"Error should mention 'install'. Errors: {errors}"
            )
        finally:
            os.unlink(path)

    def test_missing_verify_fails(self):
        path = _write_toml(self._manifest_without_field("verify"))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for missing 'verify'")
            self.assertTrue(
                any("verify" in e.lower() for e in errors),
                f"Error should mention 'verify'. Errors: {errors}"
            )
        finally:
            os.unlink(path)


class TestSha256Validation(unittest.TestCase):
    """Tests that sha256 must be exactly 64 lowercase hex characters."""

    def _manifest_with_sha256(self, sha: str) -> str:
        """Return a manifest with the given sha256 value."""
        return f"""
[[dep]]
name = "testdep"
source = "https://example.com/releases/download/v{{version}}/testdep_{{version}}_linux_amd64.tar.gz"
version = "1.0.0"
sha256 = "{sha}"
arch = "linux-amd64"
install = "curl -L ..."
verify = "testdep --version"
"""

    def test_valid_sha256_passes(self):
        """A valid 64-char lowercase hex sha256 must PASS."""
        path = _write_toml(self._manifest_with_sha256(GOOD_SHA256))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertTrue(passed, f"Expected PASS for valid sha256. Errors: {errors}")
        finally:
            os.unlink(path)

    def test_malformed_sha256_too_short_fails(self):
        """A sha256 shorter than 64 chars must FAIL."""
        short_sha = "abc123def456"  # only 12 chars
        path = _write_toml(self._manifest_with_sha256(short_sha))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for too-short sha256")
            self.assertTrue(
                any("sha256" in e.lower() for e in errors),
                f"Error should mention 'sha256'. Errors: {errors}"
            )
        finally:
            os.unlink(path)

    def test_malformed_sha256_too_long_fails(self):
        """A sha256 longer than 64 chars must FAIL."""
        long_sha = GOOD_SHA256 + "ab"  # 66 chars
        path = _write_toml(self._manifest_with_sha256(long_sha))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for too-long sha256")
        finally:
            os.unlink(path)

    def test_malformed_sha256_uppercase_fails(self):
        """A sha256 with uppercase hex chars must FAIL (must be lowercase)."""
        upper_sha = GOOD_SHA256.upper()  # 64 chars but uppercase
        path = _write_toml(self._manifest_with_sha256(upper_sha))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for uppercase sha256")
            self.assertTrue(
                any("sha256" in e.lower() for e in errors),
                f"Error should mention 'sha256'. Errors: {errors}"
            )
        finally:
            os.unlink(path)

    def test_malformed_sha256_with_non_hex_fails(self):
        """A sha256 with non-hex characters must FAIL."""
        bad_sha = "zzzz" + GOOD_SHA256[4:]  # 64 chars with invalid prefix
        path = _write_toml(self._manifest_with_sha256(bad_sha))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for non-hex sha256")
        finally:
            os.unlink(path)

    def test_placeholder_sha256_fails(self):
        """A placeholder like 'PLACEHOLDER' must FAIL (not 64 hex chars)."""
        path = _write_toml(self._manifest_with_sha256("PLACEHOLDER"))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for placeholder sha256")
        finally:
            os.unlink(path)


class TestSourceUrlTemplate(unittest.TestCase):
    """Tests that source URL must contain a {version} placeholder."""

    def _manifest_with_source(self, source: str) -> str:
        return f"""
[[dep]]
name = "testdep"
source = "{source}"
version = "1.0.0"
sha256 = "{GOOD_SHA256}"
arch = "linux-amd64"
install = "curl -L ..."
verify = "testdep --version"
"""

    def test_source_with_version_placeholder_passes(self):
        """A source URL with {{version}} placeholder must PASS."""
        source = "https://example.com/releases/v{version}/testdep_{version}.tar.gz"
        path = _write_toml(self._manifest_with_source(source))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertTrue(passed, f"Expected PASS for source with {{version}}. Errors: {errors}")
        finally:
            os.unlink(path)

    def test_source_without_version_placeholder_fails(self):
        """A source URL without {{version}} placeholder must FAIL."""
        source = "https://example.com/releases/v1.0.0/testdep_1.0.0.tar.gz"
        path = _write_toml(self._manifest_with_source(source))
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for source without {version} placeholder")
            self.assertTrue(
                any("source" in e.lower() or "version" in e.lower() for e in errors),
                f"Error should mention 'source' or 'version'. Errors: {errors}"
            )
        finally:
            os.unlink(path)


class TestEmptyManifest(unittest.TestCase):
    """Tests for edge cases like empty manifests."""

    def test_empty_manifest_fails(self):
        """An empty manifest (no [[dep]] entries) must FAIL."""
        path = _write_toml("# empty manifest\n")
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for empty manifest with no [[dep]] entries")
        finally:
            os.unlink(path)

    def test_manifest_with_no_deps_fails(self):
        """A manifest with a [meta] section but no [[dep]] must FAIL."""
        path = _write_toml('[meta]\ntitle = "test"\n')
        try:
            passed, errors = validate_deps.validate_manifest(path)
            self.assertFalse(passed, "Expected FAIL for manifest with no [[dep]] entries")
        finally:
            os.unlink(path)


class TestProductionManifest(unittest.TestCase):
    """Tests that the production manifest/deps.toml passes validation."""

    def test_production_deps_toml_passes(self):
        """The production manifest/deps.toml must PASS validation."""
        harness_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        deps_toml = os.path.join(harness_root, "manifest", "deps.toml")
        self.assertTrue(
            os.path.exists(deps_toml),
            f"manifest/deps.toml must exist at {deps_toml}"
        )
        passed, errors = validate_deps.validate_manifest(deps_toml)
        self.assertTrue(
            passed,
            f"manifest/deps.toml must PASS validation. Errors:\n{errors}"
        )

    def test_production_manifest_has_beads(self):
        """The production manifest must declare 'beads' (bd) as a dep."""
        harness_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        deps_toml = os.path.join(harness_root, "manifest", "deps.toml")
        if not os.path.exists(deps_toml):
            self.skipTest("manifest/deps.toml does not exist yet")
        deps = validate_deps.load_manifest(deps_toml)
        names = [d["name"] for d in deps.get("dep", [])]
        self.assertIn(
            "beads",
            names,
            f"manifest must include a 'beads' dep. Found names: {names}"
        )

    def test_production_manifest_has_cassms(self):
        """The production manifest must declare 'cassms' (cm) as a dep."""
        harness_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        deps_toml = os.path.join(harness_root, "manifest", "deps.toml")
        if not os.path.exists(deps_toml):
            self.skipTest("manifest/deps.toml does not exist yet")
        deps = validate_deps.load_manifest(deps_toml)
        names = [d["name"] for d in deps.get("dep", [])]
        self.assertIn(
            "cassms",
            names,
            f"manifest must include a 'cassms' dep. Found names: {names}"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
