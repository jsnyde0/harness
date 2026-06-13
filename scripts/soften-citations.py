#!/usr/bin/env python3
"""
soften-citations.py — deterministic ADR-citation softener

Prepares a skill body or non-skill published file for public publication by removing
methodology-ADR pointers while preserving firmness meaning, per ADR-002 D7.7(c).

WHAT IT DOES (deterministic, no LLM):
  1. Drops every bare ADR-NNN pointer in all citation forms it recognises:
       - Inline prose: "per ADR-006 D4", "ADR-012 D3", "(per ADR-008 D5 FIRM)"
       - Per-prefix (case-insensitive): "Per ADR-013 D4 build item:" (shell comment form)
       - Slash-delimited: "/ ADR-012 D3 /" (hook comment form)
       - Markdown links: "[ADR-012](../../docs/decisions/ADR-012-...md) D1/D2"
       - canonical_refs block bullet lines: "- ADR-NNN Dk (FIRM) — ..."
  2. Where a citation carries an explicit firmness token (FIRM|FLEXIBLE|EXPLORATORY),
     replaces it with a fixed firmness phrase:
       FIRM        → "this is a hard rule"
       FLEXIBLE    → "this is the default — deviate only with reason"
       EXPLORATORY → "exploratory — may change"

CORPUS COVERAGE (extension):
  The softener handles all published non-skill content types:
  - Markdown (.md): roles/*.md, SKILL bodies, AGENTS.md, CONTRIBUTING.md
  - Shell (.sh): hooks/*.sh, install.sh — ADR refs in comments and string values
  - JSON (.json): evals.json — ADR refs in prompt/rationale/assertion string values
  JSON validity is preserved: transforms operate on string content without touching
  JSON structural characters (quotes, braces, colons, brackets).

SCOPE BOUNDARY:
  Citations that carry NO explicit (FIRM|FLEXIBLE|EXPLORATORY) token — e.g. a bare
  "per ADR-008 D5" with no inline firmness annotation — are DROPPED without a
  firmness phrase. They require semantic ADR-firmness lookup (the ADR must be read
  to know its firmness), which is handled by a downstream agent step.
  This script's job is: drop the pointer; if an explicit token was present, preserve
  its meaning as a phrase. It does NOT invent firmness for bare citations.

--check MODE:
  Pass --check to exit non-zero if ANY ADR-[0-9] pattern remains in the output.
  This is the fail-closed gate used by the publish flow (C3/C4 wiring).

USAGE:
  # Soften a skill body (stdout):
  uv run python scripts/soften-citations.py path/to/SKILL.md

  # Fail-closed gate: exit non-zero if any ADR-[0-9] remains:
  uv run python scripts/soften-citations.py --check path/to/SKILL.md

  # Produce the after fixture (run this when before.md changes):
  uv run python scripts/soften-citations.py scripts/fixtures/adr-citation/before.md \
    > scripts/fixtures/adr-citation/after.md

# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""

import re
import sys
import argparse
from pathlib import Path


# ---------------------------------------------------------------------------
# Firmness phrase mapping (exact strings — tests are stable against these)
# ---------------------------------------------------------------------------

FIRMNESS_PHRASES: dict[str, str] = {
    "FIRM":        "this is a hard rule",
    "FLEXIBLE":    "this is the default — deviate only with reason",
    "EXPLORATORY": "exploratory — may change",
}


# ---------------------------------------------------------------------------
# Regex patterns
# ---------------------------------------------------------------------------

# ---- Pattern 1: canonical_refs block bullet lines ---------------------------
# Matches a whole line (to be removed entirely) of the form:
#   - ADR-NNN Dk (FIRM, ...) — description
#   - ADR-NNN Dk — description
#   - **ADR-NNN Dk** — description   (bold-wrapped form used in many real skills)
# These appear in ## canonical_refs / ## Canonical refs sections.
# We also match the full markdown-link form in refs:
#   - [ADR-NNN](path) Dk (FIRM) — description
#
# IMPORTANT: the bold-wrapped form must be matched here (whole-line removal),
# not left to fall through to Pattern 4 (bare inline) which would strip only
# the ADR substring and leave orphaned '- **** — ...' artifacts.
# (L2B lesson: deterministic-text-transform-must-own-the-whole-line-per-corpus-variant)
CANONICAL_REF_LINE_PATTERN = re.compile(
    r"^[ \t]*-[ \t]+"              # bullet
    r"(?:"
        r"\[ADR-[0-9]+\]\([^)]*\)" # [ADR-NNN](path) markdown link form
        r"|"
        r"\*\*ADR-[0-9]+"          # **ADR-NNN bold-wrapped form
        r"|"
        r"ADR-[0-9]+"              # bare ADR-NNN
    r")"
    r"[^\n]*$",                    # rest of line
    re.MULTILINE,
)

# ---- Pattern 1.5: slash-delimited citations in shell comments ----------------
# Matches the entire "/ ADR-NNN Dk /" construct (the slash-delimited form common
# in shell comment lines like: "# Substrate landing / ADR-012 D3 / description").
# WHOLE-UNIT removal: both slashes are consumed to prevent orphaned "/ /" artifacts.
# This pattern is applied BEFORE inline patterns to claim the full delimited unit.
#
# Examples:
#   / ADR-012 D3 /            → "" (both slashes removed)
#   / ADR-013 D4 build item / → "" (full unit with trailing text stops at /)
SLASH_DELIMITED_PATTERN = re.compile(
    r"/\s*ADR-[0-9]+(?:\s+D[0-9]+(?:/D[0-9]+)*)?\s*/"
)

# ---- Pattern 1.7: parenthesised comma-firmness citations -------------------
# Matches the whole parenthetical unit when the firmness token follows the ADR
# ref by a comma rather than whitespace:
#   (ADR-005 D1, FIRM)    — comma-firmness form
#   (ADR-005 D6, FLEXIBLE) — comma-firmness form
# These appear in role and skill body inline prose (not in canonical_refs bullets).
# The WHOLE parenthetical (both parens) is consumed to prevent orphaned '(, FIRM)'
# artifacts that would remain if only the ADR-NNN Dk part were stripped.
# Must run BEFORE Pattern 3 (INLINE_WITH_FIRMNESS) which doesn't handle comma form.
PAREN_COMMA_FIRMNESS_PATTERN = re.compile(
    r"\(\s*"                                            # opening paren + optional space
    r"ADR-[0-9]+(?:\s+D[0-9]+(?:/D[0-9]+)*)?"          # ADR-NNN + optional Dk
    r"\s*,\s*(FIRM|FLEXIBLE|EXPLORATORY)[^)]*"          # , FIRM or , FLEXIBLE etc.
    r"\)"                                               # closing paren
)

# ---- Pattern 2: markdown-link citations in prose ----------------------------
# Matches: [ADR-NNN](path) optionally followed by Dk/Dm/Dn
# e.g.: [ADR-012](../../docs/decisions/ADR-012-substrate-thick-process-thin.md) D1/D2/D3
MARKDOWN_LINK_PATTERN = re.compile(
    r"\[ADR-[0-9]+\]\([^)]*\)"    # [ADR-NNN](path)
    r"(?:\s+D[0-9]+(?:/D[0-9]+)*)?",  # optional Dk/Dm/Dn
)

# ---- Pattern 3: inline citations with explicit firmness tokens ---------------
# Matches the whole citation phrase (to replace with firmness phrase):
#   (per ADR-NNN Dk (FIRM)) or (per ADR-NNN Dk FIRM) etc.
#   per ADR-NNN Dk (FIRM, ...)
#   Per ADR-NNN Dk (FIRM, ...)   — capital-Per form (shell comment prefix)
#   ADR-NNN Dk (FIRM)
# Strategy: detect the ADR pointer + explicit firmness token; capture token.
#
# Forms handled:
#   a) "per ADR-NNN Dk (FIRM ...)" — "per " prefix (case-insensitive), token in parens
#   b) "per ADR-NNN Dk FIRM"       — "per " prefix (case-insensitive), token bare after ref
#   c) "ADR-NNN Dk (FIRM ...)"     — no prefix, token in parens
#   d) "ADR-NNN Dk FIRM"           — no prefix, token bare after ref
#
# We use a single pattern that captures the firmness token and matches the
# surrounding citation structure. Per-prefix is case-insensitive to cover shell
# comment usage ("Per ADR-NNN Dk" at start of comment lines).

INLINE_WITH_FIRMNESS_PATTERN = re.compile(
    r"(?:[Pp]er\s+)?"                                # optional "per/Per " prefix (case-insensitive)
    r"ADR-[0-9]+(?:\s+D[0-9]+(?:/D[0-9]+)*)?"        # ADR-NNN + optional Dk
    r"(?:\s+lines\s+[0-9]+(?:-[0-9]+)?)?"            # optional " lines N-N" location suffix
    r"(?:"
    r"\s*\(\s*(FIRM|FLEXIBLE|EXPLORATORY)[^)]*\)"     # (FIRM ...) or (FLEXIBLE ...) in parens
    r"|"
    r"\s+(FIRM|FLEXIBLE|EXPLORATORY)\b"               # bare FIRM/FLEXIBLE/EXPLORATORY after ref
    r")",
)

# ---- Pattern 4: bare inline citations (no firmness token) -------------------
# Matches: "per ADR-NNN Dk" or "ADR-NNN Dk" or "Per ADR-NNN Dk" (capital-Per shell form)
# without a following firmness token.
# Used as a final cleanup pass after the above patterns have already handled
# all firmness-carrying citations.
# Per-prefix is case-insensitive to cover "Per ADR-NNN" in shell comment lines.
# Also consumes an optional trailing " lines N-N" location suffix: a line-range
# locator (e.g. "lines 121-127") is only meaningful in context of its ADR ref —
# when the ADR ref is dropped, the locator becomes an orphan and must also go.
BARE_INLINE_PATTERN = re.compile(
    r"(?:[Pp]er\s+)?"                             # optional "per/Per " prefix (case-insensitive)
    r"ADR-[0-9]+(?:\s+D[0-9]+(?:/D[0-9]+)*)?"     # ADR-NNN + optional Dk
    r"(?:\s+lines\s+[0-9]+(?:-[0-9]+)?)?",         # optional " lines N-N" location suffix
)

# ---- Pattern 5: residual ADR-[0-9] guard ------------------------------------
# Used only in --check mode to verify nothing slipped through.
RESIDUAL_ADR_PATTERN = re.compile(r"ADR-[0-9]")


# ---------------------------------------------------------------------------
# Softener transform
# ---------------------------------------------------------------------------

def _canonical_ref_line_replacement(match: re.Match) -> str:
    """
    Replace a canonical_refs bullet line.

    The whole line is removed. We return an empty string; the caller
    also strips the resulting blank line from the output.
    """
    return ""


def _slash_delimited_replacement(match: re.Match) -> str:
    """
    Replace a slash-delimited citation with nothing.
    The whole unit (both slashes + ADR ref) is consumed to prevent '/ /' orphans.
    """
    return ""


def _paren_comma_firmness_replacement(match: re.Match) -> str:
    """
    Replace a parenthesised comma-firmness citation with the firmness phrase.
    The whole '(ADR-NNN Dk, FIRM)' unit is consumed (both parens) to prevent
    orphaned '(, FIRM)' artifacts.
    """
    token = match.group(1)
    if token in FIRMNESS_PHRASES:
        return FIRMNESS_PHRASES[token]
    return ""


def _markdown_link_replacement(match: re.Match) -> str:
    """Replace a markdown-link citation with nothing (pointer dropped)."""
    return ""


def _inline_with_firmness_replacement(match: re.Match) -> str:
    """
    Replace an inline citation that carries a firmness token with the
    corresponding firmness phrase.
    """
    # The firmness token is in group 1 (first alternation) or group 2 (second)
    token = match.group(1) or match.group(2)
    if token in FIRMNESS_PHRASES:
        return FIRMNESS_PHRASES[token]
    # Unknown token — drop the pointer, leave no phrase
    return ""


def _bare_inline_replacement(match: re.Match) -> str:
    """Replace a bare inline citation (no firmness token) with nothing."""
    return ""


def soften(text: str) -> str:
    """
    Apply all citation-softening transforms to the given text.

    Works across corpus types: Markdown (.md), Shell (.sh), JSON (.json).
    JSON structural integrity is preserved — transforms operate on string content
    only, not JSON syntax characters.

    Returns the softened text.

    Transform order (matters — process firmness-carrying and whole-unit forms before
    bare inline forms, to prevent orphaned scaffolding):
      1.   Remove canonical_refs bullet lines (whole-line removal, Markdown)
      1.5. Remove slash-delimited citations / ADR-NNN Dk / (shell comment form)
      2.   Remove markdown-link citations in prose
      3.   Replace inline citations with explicit firmness tokens → firmness phrase
      4.   Remove remaining bare inline citations (case-insensitive per-prefix)
      5.   Clean up orphaned "per" prefixes and whitespace artifacts
    """
    # Step 1: Remove canonical_refs bullet lines entirely.
    # We substitute with "" then clean up the resulting blank lines below.
    text = CANONICAL_REF_LINE_PATTERN.sub(_canonical_ref_line_replacement, text)

    # Step 1.5: Remove slash-delimited citations (/ ADR-NNN Dk / form).
    # Must run BEFORE inline patterns to consume both slashes as a unit, preventing
    # orphaned '/ /' artifacts if only the inner ADR-NNN were stripped.
    text = SLASH_DELIMITED_PATTERN.sub(_slash_delimited_replacement, text)

    # Step 1.7: Replace parenthesised comma-firmness citations with firmness phrases.
    # Handles '(ADR-NNN Dk, FIRM)' form — the whole parenthetical is consumed to
    # prevent orphaned '(, FIRM)' artifacts. Must run BEFORE Pattern 3 (inline with
    # firmness) which doesn't handle the comma-firmness variant.
    text = PAREN_COMMA_FIRMNESS_PATTERN.sub(_paren_comma_firmness_replacement, text)

    # Step 2: Remove markdown-link citations in prose.
    text = MARKDOWN_LINK_PATTERN.sub(_markdown_link_replacement, text)

    # Step 3: Replace inline citations that carry firmness tokens with phrases.
    text = INLINE_WITH_FIRMNESS_PATTERN.sub(_inline_with_firmness_replacement, text)

    # Step 4: Remove remaining bare inline citations (no firmness token).
    # Handles both lowercase "per ADR-NNN" (prose) and uppercase "Per ADR-NNN"
    # (shell comment prefix form) via case-insensitive per-prefix in the pattern.
    text = BARE_INLINE_PATTERN.sub(_bare_inline_replacement, text)

    # Step 5: Clean up whitespace artifacts from substitutions.
    #   a) Collapse multiple consecutive blank lines into one blank line
    text = re.sub(r"\n{3,}", "\n\n", text)
    #   b) Clean up "per " that had its citation dropped, leaving trailing "per "
    #      e.g. "(per )" or "per )." → tidy up (case-insensitive)
    text = re.sub(r"\b[Pp]er\s+([).,;:\]])", r"\1", text)
    #   c) Fix "()" or "( )" left after removing content inside parens
    text = re.sub(r"\(\s*\)", "", text)
    #   c2) Fix orphaned space-before-sentence-punctuation left after parenthetical removal.
    #       e.g. "word (ADR-NNN Dk). Next" → "word (). Next" → "word. Next" → "word. Next"
    #       Collapses one or more spaces immediately before sentence-ending punctuation
    #       (., ; ,) when preceded by a non-whitespace character — the space was the
    #       one before the opening paren of a now-removed parenthetical.
    #       Applied AFTER "()" removal so the empty-paren artifact is already gone.
    text = re.sub(r"(?<=[^\s\n]) +([.,;])", r"\1", text)
    #   d) Fix "(per )" or "(Per )" patterns
    text = re.sub(r"\(\s*[Pp]er\s*\)", "", text)
    #   d2) Fix "content, )" — trailing comma before closing paren left after ADR removal
    #       e.g. "(done = harness green AND acceptance met, ADR-006 D4)" →
    #            "(done = harness green AND acceptance met, )" →
    #            "(done = harness green AND acceptance met)"
    text = re.sub(r",\s*\)", ")", text)
    #   e) Fix "(: content" orphaned paren+colon left after removing "ADR-NNN Dk: content"
    #      e.g. "(ADR-002 D2: description)" → "(: description)" → "(description)"
    #      Removes "(:" and any trailing space, keeping the paren open for the content.
    text = re.sub(r"\(\s*:\s+", "(", text)
    #   e2) Fix "# :\s+ content" orphaned comment-hash+colon at line start
    #       e.g. "# Per ADR-012 D3: description" → (after removal) "# : description" → "# description"
    #       Applies only to comment-like contexts (# or // prefix) to avoid over-removal.
    text = re.sub(r"^([ \t]*#+[ \t]*):\s+", r"\1", text, flags=re.MULTILINE)
    #   f) Collapse multiple inline spaces into one (preserves leading indentation).
    #      Only applies to spaces preceded by a non-whitespace character, so
    #      JSON/YAML indentation and code-block leading spaces are preserved.
    text = re.sub(r"(?<=[^ \t\n])  +", " ", text)
    #   g) Trim trailing whitespace on each line
    lines = text.splitlines()
    lines = [line.rstrip() for line in lines]
    text = "\n".join(lines)
    #   h) Remove orphaned canonical_refs section headers.
    #      After bullet removal, a ## [Cc]anonical refs (optionally with parenthetical
    #      suffix) header that is now followed by ONLY blank lines until the next
    #      header or EOF is an empty-section artifact — remove it entirely.
    #      CRITICAL: only remove when the section has ZERO surviving bullets.
    #      A section with any surviving non-ADR bullet MUST keep its header.
    text = _remove_empty_canonical_refs_headers(text)
    # Ensure file ends with a single newline
    text = text.rstrip("\n") + "\n"

    return text


# ---- Pattern: canonical_refs section header (both casing variants + optional suffix) ----
# Matches: ## canonical_refs  or  ## Canonical refs  or  ## Canonical refs (any suffix)
_CANONICAL_REFS_HEADER_PATTERN = re.compile(
    r"^## [Cc]anonical[_ ]refs\b[^\n]*$",
    re.MULTILINE,
)


def _remove_empty_canonical_refs_headers(text: str) -> str:
    """
    Remove ## canonical_refs / ## Canonical refs section headers that have no
    surviving bullet content — i.e. headers followed only by blank lines until
    the next Markdown header (##/###/etc.) or EOF.

    A section with any surviving non-ADR bullet KEEPS its header (no over-removal).
    """
    lines = text.splitlines()
    result: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # Check if this line is a canonical_refs section header
        if _CANONICAL_REFS_HEADER_PATTERN.match(line):
            # Look ahead: scan past blank lines to determine if any bullets follow
            # before the next ## header or EOF
            j = i + 1
            has_content = False
            while j < len(lines):
                peek = lines[j].rstrip()
                if not peek:
                    # Blank line — keep scanning
                    j += 1
                    continue
                if peek.startswith("#"):
                    # Next markdown header reached — no bullets found
                    break
                # Non-blank, non-header content (e.g. a surviving bullet) found
                has_content = True
                break
            if has_content:
                # Section has surviving content — keep the header
                result.append(line)
            # else: section is empty — drop the header (don't append)
        else:
            result.append(line)
        i += 1
    return "\n".join(result)


# ---------------------------------------------------------------------------
# --check mode
# ---------------------------------------------------------------------------

def check_clean(text: str) -> bool:
    """Return True if no ADR-[0-9] pattern remains; False if any found."""
    return RESIDUAL_ADR_PATTERN.search(text) is None


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Soften ADR citations in a skill body for public publication.\n"
            "Drops ADR pointers; preserves firmness meaning where an explicit\n"
            "firmness token (FIRM|FLEXIBLE|EXPLORATORY) was present."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  uv run python scripts/soften-citations.py path/to/SKILL.md
  uv run python scripts/soften-citations.py --check path/to/SKILL.md

Firmness phrases produced:
  FIRM        → "this is a hard rule"
  FLEXIBLE    → "this is the default — deviate only with reason"
  EXPLORATORY → "exploratory — may change"

Scope boundary:
  Bare citations without an explicit firmness token are dropped without
  a replacement phrase. Firmness lookup for those requires semantic
  ADR reading (handled downstream by).
""",
    )
    parser.add_argument(
        "input_file",
        type=Path,
        help="Path to the skill body file to soften.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        default=False,
        help=(
            "After softening, exit non-zero if any ADR-[0-9] pattern remains. "
            "Fail-closed gate for the publish flow."
        ),
    )
    args = parser.parse_args()

    if not args.input_file.exists():
        print(f"ERROR: input file not found: {args.input_file}", file=sys.stderr)
        return 2

    original = args.input_file.read_text(encoding="utf-8")
    softened = soften(original)

    if args.check:
        if not check_clean(softened):
            # Print findings to stderr
            for i, line in enumerate(softened.splitlines(), 1):
                if RESIDUAL_ADR_PATTERN.search(line):
                    print(f"  RESIDUAL ADR: line {i}: {line.strip()!r}", file=sys.stderr)
            print(
                "ERROR: ADR-[0-9] references remain after softening. "
                "Softener did not fully clean the input.",
                file=sys.stderr,
            )
            return 1
        print(softened, end="")
        return 0

    print(softened, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
