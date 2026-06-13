#!/usr/bin/env python3
"""
Harness validator for agent/roles/ files per C0 schema (ADR-002 D3).

Required frontmatter fields:
  - name (str)
  - description (str)
  - tools (str)
  - skills (str, MUST be non-empty — >= 1 real agent/skills/<folder> entry)
  - model (str, CC Anthropic keyword/ID/inherit)
  - pi-model (str, openrouter/<vendor>/<model> slug)
  - codex-model (str, provider/model slug, e.g. openai/gpt-5.5; non-openai provider WARNS)
  - output-contract (str, MUST be present — defines a concrete final-line contract)

Body: harness-neutral system prompt (non-empty)

Skill refs (each comma/newline separated token) must:
  - resolve to an existing agent/skills/<name>/ path (dangling refs FAIL)

CONJUNCTION REQUIREMENT (tightened conjunction requirement — skills+output-contract must be present and resolve):
  - skills: MUST be non-empty (empty string / "none" is a FAIL)
  - every skill entry MUST resolve to an existing agent/skills/ folder
  - output-contract: MUST be present

PER-ROLE-CLASS FIELD OPTIONALITY (ADR-002 D3):
  Role classes determine which fields are required vs. optional-with-rationale:

  - REFERENCE roles (no role-class, or role-class: reference):
      Keep the full CONJUNCTION REQUIREMENT above. skills + output-contract are both REQUIRED.

  - GENERAL-PURPOSE roles (role-class: general-purpose):
      skills and output-contract are optional, BUT only with an explicit in-frontmatter rationale:
        - skills may be omitted/empty IF 'skills-omit-rationale' is present (non-empty)
        - output-contract may be omitted IF 'output-contract-omit-rationale' is present (non-empty)
      Deliberate omission (rationale present) → PASS
      Accidental omission (no rationale field) → FAIL

  Syntax:
    role-class: general-purpose
    skills-omit-rationale: "<why these skills live outside agent/skills/>"
    output-contract-omit-rationale: "<why no fixed final-line contract applies>"
"""

import sys
import os
import re

# ── import yaml (pyyaml) ─────────────────────────────────────────────────────
try:
    import yaml
except ImportError:
    print(
        "ERROR: pyyaml is not available in this Python interpreter.\n"
        "Invoke this script via uv so that project dependencies are resolved:\n"
        "\n"
        "    uv run python agent/roles/validate_roles.py\n"
        "\n"
        "Or, to add it one-off:\n"
        "\n"
        "    uv run --with pyyaml python agent/roles/validate_roles.py",
        file=sys.stderr,
    )
    sys.exit(1)

# ── constants ─────────────────────────────────────────────────────────────────
ROLES_DIR = os.path.dirname(os.path.abspath(__file__))
SKILLS_DIR = os.path.join(os.path.dirname(ROLES_DIR), "skills")

REQUIRED_FIELDS = ["name", "description", "tools", "skills", "model", "pi-model", "codex-model", "output-contract"]

VALID_CC_MODEL_KEYWORDS = {
    "inherit",
    "haiku",
    "sonnet",
    "opus",
    "claude-haiku-4-5-20251001",
    "claude-sonnet-4-5",
    "claude-sonnet-4-5-20251001",
    "claude-opus-4",
    "claude-opus-4-5",
    "claude-3-5-haiku-20241022",
    "claude-3-5-sonnet-20241022",
    "claude-3-opus-20240229",
}

OPENROUTER_SLUG_PATTERN = re.compile(r"^openrouter/[a-zA-Z0-9_-]+/[a-zA-Z0-9_.\-:]+$")

# codex-model: provider/model-id form (lowercase-provider, slash, model-id)
# Distinct from OPENROUTER_SLUG_PATTERN — Codex is Responses-wire-only (not openrouter-routed)
CODEX_MODEL_SLUG_PATTERN = re.compile(r"^[a-z][a-z0-9-]*/[a-zA-Z0-9_.\-:]+$")


def parse_frontmatter(filepath):
    """Parse YAML frontmatter from a markdown file. Returns (meta_dict, body_str)."""
    with open(filepath, "r") as f:
        content = f.read()

    if not content.startswith("---"):
        return None, content

    # Split on the closing ---
    parts = content.split("---", 2)
    if len(parts) < 3:
        return None, content

    meta_raw = parts[1]
    body = parts[2].strip()
    meta = yaml.safe_load(meta_raw)
    return meta, body


def validate_cc_model(value):
    """Check that model: is a valid CC Anthropic keyword/ID/inherit."""
    v = str(value).strip()
    # Allow exact keywords
    if v in VALID_CC_MODEL_KEYWORDS:
        return True
    # Allow claude-* model IDs
    if re.match(r"^claude-[a-zA-Z0-9.\-]+$", v):
        return True
    return False


def validate_pi_model(value):
    """Check that pi-model: is a valid openrouter/<vendor>/<model> slug."""
    return bool(OPENROUTER_SLUG_PATTERN.match(str(value).strip()))


def validate_codex_model(value):
    """
    Check that codex-model: is a valid provider/model-id slug (lowercase-provider slash model-id).

    Returns (valid: bool, warn_non_openai: bool).
    warn_non_openai is True when the slug is well-formed but the provider is not 'openai'
    — Codex is Responses-wire-only and non-OpenAI providers require a Responses-compatible
    endpoint the validator cannot confirm.
    """
    v = str(value).strip()
    if not CODEX_MODEL_SLUG_PATTERN.match(v):
        return False, False
    provider = v.split("/")[0]
    warn_non_openai = provider != "openai"
    return True, warn_non_openai


def resolve_skills(skills_value):
    """
    Parse skills field and check each against agent/skills/.
    Returns list of (skill_name, status) where status is 'ok' or 'dangling'.
    """
    if not skills_value or str(skills_value).strip().lower() in ("none", ""):
        return []

    # Skills may be a comma or newline separated list
    raw = str(skills_value)
    tokens = [t.strip() for t in re.split(r"[,\n]", raw) if t.strip()]

    results = []
    for skill in tokens:
        if os.path.isdir(os.path.join(SKILLS_DIR, skill)):
            results.append((skill, "ok"))
        else:
            results.append((skill, "dangling"))

    return results


def _is_general_purpose(meta):
    """Return True if this role's role-class is 'general-purpose'."""
    return str(meta.get("role-class", "reference")).strip().lower() == "general-purpose"


def validate_role_file(filepath):
    """Validate a single role file. Returns (passed: bool, report: str)."""
    errors = []
    warnings = []

    meta, body = parse_frontmatter(filepath)

    if meta is None:
        return False, f"ERROR: No YAML frontmatter found in {filepath}"

    # Determine role class — drives which fields are required vs. optional-with-rationale
    # REFERENCE (default): skills + output-contract are both required (CONJUNCTION REQUIREMENT)
    # GENERAL-PURPOSE: skills and output-contract are optional IF the corresponding
    #   *-omit-rationale field is present and non-empty; accidental omission (no rationale) → FAIL
    general_purpose = _is_general_purpose(meta)

    # Fields whose requirements depend on role-class:
    #   skills — required for reference; optional-with-rationale for general-purpose
    #   output-contract — required for reference; optional-with-rationale for general-purpose
    # All other REQUIRED_FIELDS are unconditionally required.
    UNCONDITIONAL_REQUIRED = [f for f in REQUIRED_FIELDS if f not in ("skills", "output-contract")]

    # Check unconditionally required fields
    for field in UNCONDITIONAL_REQUIRED:
        if field not in meta:
            errors.append(f"  MISSING required field: '{field}'")
        elif meta[field] is None:
            errors.append(f"  FIELD '{field}' is null/empty")

    # Check model:
    if "model" in meta and meta["model"] is not None:
        if not validate_cc_model(meta["model"]):
            errors.append(
                f"  INVALID model: '{meta['model']}' — must be a CC Anthropic keyword/ID/inherit"
            )

    # Check pi-model:
    if "pi-model" in meta and meta["pi-model"] is not None:
        if not validate_pi_model(meta["pi-model"]):
            errors.append(
                f"  INVALID pi-model: '{meta['pi-model']}' — must match openrouter/<vendor>/<model>"
            )

    # Check codex-model:
    if "codex-model" in meta and meta["codex-model"] is not None:
        valid, warn_non_openai = validate_codex_model(meta["codex-model"])
        if not valid:
            errors.append(
                f"  INVALID codex-model: '{meta['codex-model']}' — must match <provider>/<model-id> (lowercase provider)"
            )
        elif warn_non_openai:
            provider = str(meta["codex-model"]).strip().split("/")[0]
            warnings.append(
                f"codex-model provider is '{provider}', not 'openai' — Codex is Responses-wire-only; "
                f"non-OpenAI providers require a Responses-compatible endpoint the validator cannot confirm"
            )

    # Check body
    if not body or len(body.strip()) < 10:
        errors.append("  EMPTY or minimal body — must have a harness-neutral system prompt")

    # ── skills check ─────────────────────────────────────────────────────────
    # For general-purpose roles: field may be absent/empty IF skills-omit-rationale is present.
    # For reference roles: field MUST be non-empty and all entries must resolve.
    skills_in_meta = "skills" in meta
    skills_raw = meta.get("skills")
    skills_is_empty = not skills_raw or str(skills_raw).strip().lower() in ("none", "")

    if general_purpose and not skills_in_meta:
        # Missing skills field — check for rationale
        rationale = meta.get("skills-omit-rationale")
        if not rationale or not str(rationale).strip():
            errors.append(
                "  MISSING skills: field — for role-class: general-purpose, provide either "
                "a skills list or a non-empty 'skills-omit-rationale' field (deliberate omission requires rationale)"
            )
        else:
            warnings.append(
                f"  skills: field omitted with rationale (general-purpose role): {rationale}"
            )
    elif general_purpose and skills_is_empty:
        # Present but empty — same rationale check
        rationale = meta.get("skills-omit-rationale")
        if not rationale or not str(rationale).strip():
            errors.append(
                "  EMPTY skills: field — for role-class: general-purpose, provide either "
                "a non-empty skills list or a 'skills-omit-rationale' field (deliberate omission requires rationale)"
            )
        else:
            warnings.append(
                f"  skills: field empty with rationale (general-purpose role): {rationale}"
            )
    elif not general_purpose:
        # Reference role: full CONJUNCTION REQUIREMENT
        if not skills_in_meta:
            errors.append(f"  MISSING required field: 'skills'")
        elif skills_is_empty:
            errors.append(
                "  EMPTY skills: field — CONJUNCTION REQUIREMENT requires >= 1 entry resolving to an existing agent/skills/ path"
            )
        else:
            skill_results = resolve_skills(skills_raw)
            if not skill_results:
                errors.append(
                    "  EMPTY skills: field — CONJUNCTION REQUIREMENT requires >= 1 entry resolving to an existing agent/skills/ path"
                )
            for skill, status in skill_results:
                if status == "dangling":
                    errors.append(
                        f"  DANGLING skill ref: '{skill}' — not found in agent/skills/"
                    )
    else:
        # general_purpose AND skills_in_meta AND not empty — validate normally
        skill_results = resolve_skills(skills_raw)
        for skill, status in skill_results:
            if status == "dangling":
                errors.append(
                    f"  DANGLING skill ref: '{skill}' — not found in agent/skills/"
                )

    # ── output-contract check ─────────────────────────────────────────────────
    # For general-purpose roles: field may be absent IF output-contract-omit-rationale is present.
    # For reference roles: field MUST be present (handled by REQUIRED_FIELDS loop above for
    # non-general-purpose; for general-purpose we do the explicit check below).
    oc_in_meta = "output-contract" in meta

    if not general_purpose and not oc_in_meta:
        # Reference role: required (already caught by the UNCONDITIONAL_REQUIRED loop? No —
        # output-contract was removed from UNCONDITIONAL_REQUIRED above. Add error here.)
        errors.append(f"  MISSING required field: 'output-contract'")
    elif not general_purpose and oc_in_meta and meta["output-contract"] is None:
        errors.append(f"  FIELD 'output-contract' is null/empty")
    elif general_purpose and not oc_in_meta:
        # Missing output-contract — check for rationale
        rationale = meta.get("output-contract-omit-rationale")
        if not rationale or not str(rationale).strip():
            errors.append(
                "  MISSING output-contract: field — for role-class: general-purpose, provide either "
                "an output-contract or a non-empty 'output-contract-omit-rationale' field (deliberate omission requires rationale)"
            )
        else:
            warnings.append(
                f"  output-contract: field omitted with rationale (general-purpose role): {rationale}"
            )

    name = os.path.basename(filepath)
    lines = []
    lines.append(f"\n{'='*60}")
    lines.append(f"File: {name}")
    lines.append(f"  name:         {meta.get('name', '(missing)')}")
    lines.append(f"  description:  {meta.get('description', '(missing)')}")
    lines.append(f"  model:        {meta.get('model', '(missing)')}")
    lines.append(f"  pi-model:     {meta.get('pi-model', '(missing)')}")
    lines.append(f"  codex-model:  {meta.get('codex-model', '(missing)')}")
    lines.append(f"  tools:        {meta.get('tools', '(missing)')}")
    lines.append(f"  skills:       {meta.get('skills', '(missing)')}")
    if "output-contract" in meta:
        lines.append(f"  output-contract: {meta.get('output-contract')}")
    lines.append(f"  body_chars:  {len(body)}")

    if warnings:
        for w in warnings:
            lines.append(f"  WARN: {w}")

    if errors:
        lines.append(f"  STATUS: FAIL ({len(errors)} error(s))")
        for e in errors:
            lines.append(e)
        return False, "\n".join(lines)
    else:
        lines.append("  STATUS: PASS")
        return True, "\n".join(lines)


def main():
    """Main validator: find all .md files in agent/roles/, skip validate_roles.py itself."""
    role_files = [
        os.path.join(ROLES_DIR, f)
        for f in sorted(os.listdir(ROLES_DIR))
        if f.endswith(".md")
    ]

    if not role_files:
        print("ERROR: No .md role files found in agent/roles/")
        sys.exit(1)

    all_passed = True
    for filepath in role_files:
        passed, report = validate_role_file(filepath)
        print(report)
        if not passed:
            all_passed = False

    print("\n" + "="*60)
    if all_passed:
        print(f"RESULT: ALL {len(role_files)} ROLE(S) PASS")
        sys.exit(0)
    else:
        print(f"RESULT: VALIDATION FAILED — fix errors above")
        sys.exit(1)


if __name__ == "__main__":
    main()
