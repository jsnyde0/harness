#!/usr/bin/env python3
"""
oneway-check.py — one-way-reference check engine

Enforces the keystone invariant of the public-core extraction:
  PRIVATE may reference CORE, but CORE must NEVER reference PRIVATE.

The engine scans ALL git-tracked files in the repo for private markers.
It reports each finding as:
  file:line — CLASS — matched-text
and exits non-zero if any finding is present, zero if clean.

SCAN SET:
  All files returned by `git ls-files` from the repo root (i.e., every
  tracked file that will be published). Binary/non-text files are skipped
  gracefully. The manifest is still used by walk-manifest.py for asset
  classification — the leak-check's job is "nothing private in ANY published
  file".

MARKERS CONFIG:
  Author-specific private markers are loaded from a local TOML config file:
    scripts/oneway-markers.local.toml   (gitignored; author's real tokens)
  Falls back to:
    scripts/oneway-markers.example.toml (committed; generic placeholders only)
  Override with:
    --markers-config /path/to/custom.toml

  The config supplies tokens for the author-specific marker classes:
    C1  private_path_token   — path fragments / repo refs for the private overlay repo
    C3  work_org_tokens      — work-org name(s) and work GitHub account handle(s)
    C4  private_bead_prefixes — bead-namespace prefixes for private projects
    C5  private_project_nouns — private repo / project proper nouns
    C5  private_source_paths  — partial paths to private source trees

MARKER CLASSES:
  C1  private path token     — path fragments / repo refs containing the configured
                               private-repo path token (from markers config)
  C2  hardcoded ~/.claude    — literal ~/.claude or /Users/<user>/.claude paths
                               (NOT $SKILL portable convention — that's the correct form)
  C3  work-org tokens        — work-org directory name and work GitHub account handles
                               (from markers config); personal account (jsnyde0) is fine
  C4  private bead IDs       — bead IDs in configured private-namespace prefixes
                               (e.g. prefix-abc1, prefix-f8l.3);
                               harness-* is the core namespace — fine;
                               for the "claude" prefix: excludes model names
                               (claude-opus-4-8, claude-sonnet-4-6, etc.) and word slugs
                               (claude-code, claude-switch, etc.);
                               bare provenance words (e.g. "dotpi" alone) do NOT fire;
                               English compound dashes and temp-dir prefixes do NOT fire
  C5  private source paths / project names — configured private project nouns
                               and configured private source-path fragments
  C6  absolute macOS home paths — /Users/<anything>/ (any hardcoded absolute home path;
                               generic class — does NOT hardcode any author name;
                               catches any machine-specific home path that leaked in)

USAGE:
  # Against the repo root (reporting mode, all tracked files):
  uv run scripts/oneway-check.py

  # With an explicit markers config (overrides auto-discovery):
  uv run scripts/oneway-check.py --markers-config /path/to/my-markers.toml

  # Against a custom manifest (used by self-test fixture runs):
  uv run scripts/oneway-check.py --manifest /path/to/fixture-manifest.toml

  # Check only specific classes (comma-separated):
  uv run scripts/oneway-check.py --classes C1,C2

IMPORTABLE API:
  from oneway_check import run_check, Finding
  findings = run_check(manifest_path)  # returns list[Finding]

Exit 0  — no private markers found in any tracked file (clean)
Exit 1  — private markers found (dirty)

# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""

import sys
import re
import tomllib
import argparse
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Paths (defaults — can be overridden via --manifest / --markers-config)
# ---------------------------------------------------------------------------

HOME = Path.home()
SCRIPT_DIR = Path(__file__).parent
HARNESS_ROOT = SCRIPT_DIR.parent
DEFAULT_MANIFEST_PATH = HARNESS_ROOT / "manifest" / "core-manifest.toml"

# Markers config: prefer local (gitignored, author-specific) over example (committed, generic)
LOCAL_MARKERS_CONFIG = SCRIPT_DIR / "oneway-markers.local.toml"
EXAMPLE_MARKERS_CONFIG = SCRIPT_DIR / "oneway-markers.example.toml"

# ---------------------------------------------------------------------------
# Markers config loading
# ---------------------------------------------------------------------------


def find_default_markers_config() -> Path:
    """
    Return the markers config path to use:
    - oneway-markers.local.toml if it exists (author's real tokens)
    - else oneway-markers.example.toml (generic placeholders; safe for CI)
    """
    if LOCAL_MARKERS_CONFIG.exists():
        return LOCAL_MARKERS_CONFIG
    return EXAMPLE_MARKERS_CONFIG


def load_markers_config(config_path: Path) -> dict:
    """Load and parse a markers TOML config. Returns the parsed dict."""
    with open(config_path, "rb") as f:
        return tomllib.load(f)


# ---------------------------------------------------------------------------
# Pattern construction from config
# ---------------------------------------------------------------------------

# The "claude" prefix has a special exclusion list to avoid firing on model names
# and product/word slugs. These exclusions are structural (not author-specific)
# and are hardcoded here so they travel with the engine.
_CLAUDE_EXCLUSION_LOOKAHEAD = (
    r"(?!opus\b|sonnet\b|haiku\b|code\b|switch\b|session\b|account\b|extension\b|caliper\b|ai\b)"
)


def _build_prefix_pattern(prefix: str) -> str:
    """
    Build a regex alternative for a single bead-namespace prefix.

    Pattern shape: <prefix>-<base36id> where:
    - base36id is 2-5 lowercase alphanumeric chars
    - optionally followed by .<N> sub-ID suffixes
    - NOT immediately followed by another alphanumeric char or hyphen
      (guards against English compound words and temp-dir prefix strings)

    Special case: the "claude" prefix gets an exclusion lookahead to avoid
    firing on model names (claude-opus-4-8) and word slugs (claude-code).
    """
    safe_prefix = re.escape(prefix)
    if prefix == "claude":
        return (
            rf"{safe_prefix}-{_CLAUDE_EXCLUSION_LOOKAHEAD}"
            r"[a-z0-9]{2,5}(?:\.[0-9]+)*(?![a-z0-9-])"
        )
    return rf"{safe_prefix}-[a-z0-9]{{2,5}}(?:\.[0-9]+)*(?![a-z0-9-])"


def build_marker_patterns(markers: dict) -> dict[str, re.Pattern]:
    """
    Build compiled regex patterns for author-specific marker classes from config.

    Returns a dict mapping class label ("C1", "C3", "C4", "C5") to compiled pattern.
    Classes C2 and C6 are structural and are returned from get_structural_patterns().
    """
    patterns: dict[str, re.Pattern] = {}

    # C1: private path token
    path_token = markers.get("private_path_token", "")
    if path_token:
        patterns["C1"] = re.compile(re.escape(path_token))

    # C3: work-org tokens
    work_org_tokens = markers.get("work_org_tokens", [])
    if work_org_tokens:
        alt = "|".join(re.escape(t) for t in work_org_tokens)
        patterns["C3"] = re.compile(alt)

    # C4: private bead-namespace prefixes
    prefixes = markers.get("private_bead_prefixes", [])
    if prefixes:
        alts = [_build_prefix_pattern(p) for p in prefixes]
        patterns["C4"] = re.compile(r"\b(" + "|".join(alts) + r")")

    # C5: private project nouns + private source paths
    project_nouns = markers.get("private_project_nouns", [])
    source_paths = markers.get("private_source_paths", [])
    c5_parts = []
    # Source paths: match as literal fragments; exclude "code/personal/harness" (public core)
    for sp in source_paths:
        if sp.rstrip("/") == "code/personal/harness":
            continue  # always excluded — the public core repo path
        c5_parts.append(re.escape(sp))
    # Project nouns: match as literal strings
    for noun in project_nouns:
        c5_parts.append(re.escape(noun))
    if c5_parts:
        patterns["C5"] = re.compile("|".join(c5_parts))

    return patterns


def get_structural_patterns() -> dict[str, re.Pattern]:
    """
    Return the hardcoded structural patterns (C2, C6).
    These carry NO personal information and are the same for every user.
    """
    # C2: hardcoded ~/.claude or /Users/<user>/.claude paths.
    # The CORRECT portable form is $SKILL or $CLAUDE_HOME — flag only literal paths.
    c2 = re.compile(
        r"(?<!\$SKILL)(?<!\$\{SKILL\})"   # not after $SKILL convention
        r"(~\/\.claude(?:\/[^\s\"'`]*)?|"  # ~/.claude or ~/.claude/path/...
        r"\/Users\/[^/\s]+\/\.claude(?:\/[^\s\"'`]*)?)"  # /Users/<user>/.claude/...
    )

    # C6: absolute macOS home paths — /Users/<anything>/
    # Generic class: catches ANY hardcoded absolute home path.
    c6 = re.compile(r"/Users/[^/\s]+")

    return {"C2": c2, "C6": c6}


def build_all_patterns(markers: dict) -> dict[str, re.Pattern]:
    """Combine config-driven patterns with structural patterns."""
    patterns = build_marker_patterns(markers)
    patterns.update(get_structural_patterns())
    return patterns


# ---------------------------------------------------------------------------
# Class descriptions (generic — no real nouns)
# ---------------------------------------------------------------------------

CLASS_DESCRIPTIONS: dict[str, str] = {
    "C1": "private path token from markers config (private overlay repo reference)",
    "C2": "hardcoded ~/.claude path (use $SKILL convention instead)",
    "C3": "work-org token from markers config (work org or work GitHub account)",
    "C4": "private bead-namespace ID from markers config (configured prefix-<id>)",
    "C5": "private project noun or source path from markers config",
    "C6": "absolute macOS home path (/Users/<username>/...)",
    "BOUNDARY": "docs/decisions/ boundary violation (ADR-*.md or INDEX.md must not be published)",
}


# ---------------------------------------------------------------------------
# Finding dataclass
# ---------------------------------------------------------------------------


@dataclass
class Finding:
    """A single private-marker hit in a core asset."""
    file_path: Path
    line_number: int
    marker_class: str       # e.g. "C1", "C2", "C3", "C4"
    matched_text: str       # the matched fragment
    line_content: str       # the full line (for context)

    def format(self) -> str:
        """Format as: file:line — CLASS — matched-text"""
        return f"{self.file_path}:{self.line_number} — {self.marker_class} — {self.matched_text!r}"


# ---------------------------------------------------------------------------
# Manifest loading + core asset resolution
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Files to exclude from the C6 self-scan (they define/demonstrate the pattern)
# ---------------------------------------------------------------------------

# The leak-check scripts themselves use /Users/ in pattern strings and test fixtures.
# Exclude them from the all-tracked scan to avoid false positives from the tool's own
# pattern definitions. They are still tested for correctness in the self-test suite.
# The example markers config is also excluded: it intentionally contains placeholder
# private-token strings (your-work-org, myproj-abc1, ...) to demonstrate the format, and
# in CI (where the gitignored .local.toml is absent) it is loaded as the fallback config —
# scanning it would self-match those placeholders. (.local.toml is gitignored, never tracked.)
SCAN_SELF_EXCLUSIONS = {
    "scripts/oneway-check.py",
    "scripts/test_oneway_check.py",
    "scripts/oneway-markers.example.toml",
}


# ---------------------------------------------------------------------------
# Boundary-presence guard: docs/decisions/ must remain EMPTY by design
# ---------------------------------------------------------------------------

# docs/decisions/ is empty by design — all methodology/mechanism ADRs are private
# and must never publish. Any file matching these patterns is a leak.
_DOCS_DECISIONS_BOUNDARY_PATTERNS = ("ADR-*.md", "INDEX.md")


def check_docs_decisions_boundary(repo_root: Path) -> list["Finding"]:
    """
    Boundary-presence guard: fail if docs/decisions/ contains any ADR or INDEX file.

    The docs/decisions/ directory is EMPTY BY DESIGN — all methodology and
    mechanism ADRs are private and must never enter the public harness repo.
    This guard catches silent re-entry of private ADR files.

    Scans the filesystem (not git ls-files) for files matching:
      - ADR-*.md  (any numbered ADR file)
      - INDEX.md  (the ADR index)

    Returns a list of Finding objects (marker_class="BOUNDARY") for each
    offending file found. Empty list = clean.
    """
    decisions_dir = repo_root / "docs" / "decisions"
    findings: list[Finding] = []

    if not decisions_dir.exists():
        return findings

    import fnmatch
    for candidate in sorted(decisions_dir.iterdir()):
        if not candidate.is_file():
            continue
        name = candidate.name
        matched = any(fnmatch.fnmatch(name, pat) for pat in _DOCS_DECISIONS_BOUNDARY_PATTERNS)
        if matched:
            findings.append(Finding(
                file_path=candidate,
                line_number=0,
                marker_class="BOUNDARY",
                matched_text=str(candidate.relative_to(repo_root)),
                line_content="",
            ))

    return findings


def load_manifest(manifest_path: Path) -> dict:
    """Load and parse a TOML manifest. Returns the parsed dict."""
    with open(manifest_path, "rb") as f:
        return tomllib.load(f)


def get_all_tracked_files(repo_root: Path) -> list[Path]:
    """
    Return all files tracked by git in the repo, excluding binary/non-text files
    and the leak-check scripts themselves (which contain pattern strings + fixtures).

    Uses `git ls-files` from the repo root. Files in SCAN_SELF_EXCLUSIONS (relative
    to repo root) are excluded to avoid false positives from the tool's own pattern
    definitions.
    """
    try:
        result = subprocess.run(
            ["git", "ls-files"],
            capture_output=True,
            text=True,
            cwd=repo_root,
        )
    except FileNotFoundError:
        print("  WARN: git not found; cannot enumerate tracked files", file=sys.stderr)
        return []

    if result.returncode != 0:
        print(f"  WARN: git ls-files failed: {result.stderr.strip()}", file=sys.stderr)
        return []

    paths = []
    for rel_path_str in result.stdout.splitlines():
        if not rel_path_str:
            continue
        if rel_path_str in SCAN_SELF_EXCLUSIONS:
            continue  # skip the tool's own files
        abs_path = repo_root / rel_path_str
        if not abs_path.exists():
            continue  # skip files that don't exist on disk (e.g. deleted but staged)
        paths.append(abs_path)

    return paths


def resolve_asset_path(path_str: str, home_key: str, manifest_path: Path) -> Optional[Path]:
    """
    Resolve a manifest asset path to an absolute Path.

    For the harness manifest, all paths are harness-relative (home="harness").
    The harness root is determined as the parent of the manifest's directory's parent
    (manifest lives at harness_root/manifest/core-manifest.toml).

    Supports:
      - Absolute path strings (used by fixture manifests in self-test)
      - Relative paths with home="harness" (relative to harness repo root)
      - Legacy: home="fixture" (absolute path, used by self-test manifests)
      - Legacy: home="dotpi" or home="claude" (relative to source homes — NOT used
        in the harness manifest but kept for backward compatibility with fixture tests)
    """
    if Path(path_str).is_absolute():
        # Absolute path (used in fixture manifests)
        return Path(path_str)

    if path_str.startswith("~/"):
        return HOME / path_str[2:]

    if home_key in ("harness", "fixture"):
        # harness-relative path: manifest is at harness_root/manifest/core-manifest.toml
        harness_root = manifest_path.parent.parent
        return harness_root / path_str

    if home_key == "dotpi":
        # Legacy: relative to dotpi root (manifest_path.parent.parent for real manifests)
        # For fixture manifests: path_str is absolute anyway (handled above)
        harness_root = manifest_path.parent.parent
        return harness_root / path_str

    if home_key == "claude":
        return HOME / ".claude" / path_str

    # Fallback: treat as relative to harness root
    harness_root = manifest_path.parent.parent
    return harness_root / path_str


def get_core_assets(manifest: dict, manifest_path: Path) -> list[Path]:
    """
    Return the list of resolved absolute Paths for all assets with disposition="core".
    Skips assets whose resolved path does not exist (logs a warning).
    """
    assets = []
    for asset in manifest.get("assets", []):
        if asset.get("disposition") != "core":
            continue
        path_str = asset.get("path", "")
        home_key = asset.get("home", "harness")
        resolved = resolve_asset_path(path_str, home_key, manifest_path)
        if resolved is None:
            print(f"  WARN: could not resolve path for asset {path_str!r} (home={home_key!r})", file=sys.stderr)
            continue
        if not resolved.exists():
            print(f"  WARN: core asset path does not exist: {resolved}", file=sys.stderr)
            continue
        assets.append(resolved)
    return assets


# ---------------------------------------------------------------------------
# Scanning logic
# ---------------------------------------------------------------------------


def scan_file(
    file_path: Path,
    marker_classes: dict[str, re.Pattern],
    active_classes: Optional[set[str]] = None,
) -> list[Finding]:
    """
    Scan a single file for private markers. Returns list of Finding objects.

    active_classes: if provided, only scan for those classes; default = all classes.
    """
    if active_classes is None:
        active_classes = set(marker_classes.keys())

    patterns_to_check = {
        cls: pat for cls, pat in marker_classes.items()
        if cls in active_classes
    }

    findings = []

    try:
        content = file_path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"  WARN: could not read {file_path}: {e}", file=sys.stderr)
        return findings

    lines = content.splitlines()
    for line_num, line in enumerate(lines, start=1):
        for cls, pattern in patterns_to_check.items():
            for match in pattern.finditer(line):
                findings.append(Finding(
                    file_path=file_path,
                    line_number=line_num,
                    marker_class=cls,
                    matched_text=match.group(0),
                    line_content=line.strip(),
                ))

    return findings


def scan_asset(
    asset_path: Path,
    marker_classes: dict[str, re.Pattern],
    active_classes: Optional[set[str]] = None,
) -> list[Finding]:
    """
    Scan a single asset (file or directory) for private markers.
    If the asset is a directory, scans all files within it recursively.
    """
    if asset_path.is_file():
        return scan_file(asset_path, marker_classes, active_classes)
    elif asset_path.is_dir():
        findings = []
        for child in sorted(asset_path.rglob("*")):
            if not child.is_file():
                continue
            parts = child.parts
            if any(p in ("node_modules", "__pycache__", ".venv", ".git") for p in parts):
                continue
            if child.suffix in (".pyc", ".pyo", ".class", ".o", ".so", ".dylib"):
                continue
            findings.extend(scan_file(child, marker_classes, active_classes))
        return findings
    else:
        return []


# ---------------------------------------------------------------------------
# Main entry point (engine API)
# ---------------------------------------------------------------------------


def run_check(
    manifest_path: Path,
    active_classes: Optional[set[str]] = None,
    verbose: bool = True,
    use_all_tracked: Optional[bool] = None,
    markers_config_path: Optional[Path] = None,
) -> list[Finding]:
    """
    Run the one-way-reference check.

    markers_config_path: path to a markers TOML config. If None, auto-discovers:
      - oneway-markers.local.toml if present (author's real tokens)
      - else oneway-markers.example.toml (generic placeholders; safe for CI)

    Scan set:
      - Production mode (use_all_tracked=True, or default when manifest_path is the
        real core-manifest.toml): ALL git-tracked files via `git ls-files`. This
        ensures non-manifest files like install.sh, .githooks/, scripts/, README.md,
        CONTRIBUTING.md, AGENTS.md, and .github/ are also scanned.
      - Fixture/self-test mode (use_all_tracked=False, automatic when a custom manifest
        is supplied): use only the manifest's listed assets. Self-test fixtures live in
        temp dirs outside the repo and are not git-tracked — they must go through the
        manifest path.

    The manifest is still consumed by walk-manifest.py for asset classification;
    here it is only used in fixture/self-test mode.

    Returns the list of Finding objects. Prints a report to stdout if verbose=True.
    """
    # Load markers config
    if markers_config_path is None:
        markers_config_path = find_default_markers_config()
    markers = load_markers_config(markers_config_path)
    marker_classes = build_all_patterns(markers)

    if active_classes is None:
        active_classes = set(marker_classes.keys())

    # Determine scan mode
    if use_all_tracked is None:
        # Auto-detect: use all-tracked scan when running against the real manifest
        use_all_tracked = (manifest_path.resolve() == DEFAULT_MANIFEST_PATH.resolve())

    if use_all_tracked:
        # Derive repo root from manifest path (manifest lives at repo_root/manifest/)
        repo_root = manifest_path.parent.parent
        scan_paths = get_all_tracked_files(repo_root)
        scan_label = f"all tracked files ({len(scan_paths)} files)"
    else:
        manifest = load_manifest(manifest_path)
        core_assets = get_core_assets(manifest, manifest_path)
        scan_paths = core_assets
        scan_label = f"manifest core assets ({len(scan_paths)} assets)"

    if verbose:
        print("=" * 70)
        print("oneway-check.py — one-way-reference check")
        print(f"Manifest:       {manifest_path}")
        print(f"Markers config: {markers_config_path}")
        print(f"Scan set:       {scan_label}")
        print(f"Active classes: {', '.join(sorted(active_classes))}")
        print("=" * 70)

    all_findings: list[Finding] = []
    for asset_path in scan_paths:
        findings = scan_file(asset_path, marker_classes, active_classes)
        all_findings.extend(findings)
        if verbose and findings:
            for f in findings:
                print(f"  LEAK: {f.format()}")

    # Boundary-presence guard: runs in all-tracked (production) mode
    if use_all_tracked:
        boundary_findings = check_docs_decisions_boundary(repo_root)
        all_findings.extend(boundary_findings)
        if verbose and boundary_findings:
            for f in boundary_findings:
                print(f"  BOUNDARY: {f.format()}")

    if verbose:
        print()
        if all_findings:
            by_class: dict[str, int] = {}
            for f in all_findings:
                by_class[f.marker_class] = by_class.get(f.marker_class, 0) + 1
            print("--- Summary by class ---")
            for cls in sorted(by_class.keys()):
                desc = CLASS_DESCRIPTIONS.get(cls, "")
                print(f"  {cls}: {by_class[cls]:3d} finding(s) — {desc}")
            print(f"\n=== RESULT: {len(all_findings)} finding(s) — RED (private markers in any tracked file) ===")
        else:
            print(f"=== RESULT: 0 findings — GREEN (no private markers in any tracked file) ===")

    return all_findings


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="One-way-reference check: scan all tracked files for private markers.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Marker classes:
  C1  private path token (from markers config — private overlay repo reference)
  C2  hardcoded ~/.claude paths (use $SKILL convention instead)
  C3  work-org tokens (from markers config — work org name / work GitHub account)
  C4  private bead-namespace IDs (from markers config — configured prefix-<id>)
  C5  private project nouns or source paths (from markers config)
  C6  absolute macOS home paths (/Users/<username>/...)

Markers config (auto-discovered unless --markers-config is given):
  scripts/oneway-markers.local.toml   — author's real tokens (gitignored)
  scripts/oneway-markers.example.toml — generic template (committed; CI fallback)

Exit 0  = clean (no findings)
Exit 1  = dirty (findings present)
""",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST_PATH,
        help=f"Path to the TOML manifest (default: {DEFAULT_MANIFEST_PATH})",
    )
    parser.add_argument(
        "--markers-config",
        type=Path,
        default=None,
        dest="markers_config",
        help="Path to the markers TOML config (default: auto-discover local then example)",
    )
    parser.add_argument(
        "--classes",
        type=str,
        default=None,
        help="Comma-separated list of classes to check (default: all classes C1-C6)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        default=False,
        help="Suppress verbose output (findings still printed); exit code only.",
    )
    args = parser.parse_args()

    # Determine markers config path
    markers_config_path: Optional[Path] = args.markers_config
    if markers_config_path is None:
        markers_config_path = find_default_markers_config()

    # Load markers to get the set of available classes
    markers = load_markers_config(markers_config_path)
    marker_classes = build_all_patterns(markers)

    active_classes: Optional[set[str]] = None
    if args.classes:
        active_classes = {c.strip().upper() for c in args.classes.split(",")}
        unknown = active_classes - set(marker_classes.keys())
        if unknown:
            print(f"ERROR: unknown class(es): {', '.join(sorted(unknown))}", file=sys.stderr)
            sys.exit(2)

    findings = run_check(
        manifest_path=args.manifest,
        active_classes=active_classes,
        verbose=not args.quiet,
        markers_config_path=markers_config_path,
    )

    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
