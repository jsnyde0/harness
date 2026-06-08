---
name: review
description: Review all work for a change
---

Review implementation work for a change using competing reviewers.

**Goal:** Produce an actionable fix list and update ADRs where decisions need
revising. The review process is a means to that end — the deliverable is a
focused document of what to fix and how, not a raw findings dump.

**Arguments:** `$ARGUMENTS` → `<change-name> [N]`
- change-name: required (ask if missing)
- N: number of review passes (default 1)

## Execution Pattern

You are the **manager**. Each pass spawns TWO competing subagents in parallel.
You own the triage — subagents report findings, you decide what matters.

### Manager orchestration:

```
For pass = 1 to N:
  1. Spawn BOTH reviewers IN PARALLEL (architecture + implementation)
  2. Wait for BOTH to complete
  3. If either is "BLOCKED" → stop early, report blocker
After all passes:
  4. IMMEDIATELY triage — do NOT ask the user what to do, do NOT
     present raw findings and wait. You process and act:

     a. Read through all findings from both reviewers. Use your
        judgment for each: include in fix list (real issue worth
        fixing), discard (wrong, overengineered, not worth it, noise),
        or surface for alignment.

        Watch for findings that contradict an intentional design
        choice — even if technically valid, the question becomes
        "fix the code or update the design doc," and only the
        human can answer that. Surface these for alignment.

        Surfacing has two modes depending on the weight of the call:
        - **Borderline calls**: you lean one way but want confirmation.
          Bundle these together with your suggestion for each — the
          user can accept, reject, or dig deeper on any item.
        - **Hard decisions**: genuine tradeoffs, competing concerns,
          or ADR conflicts where it's not clear what's right. Use
          /guide to walk through these properly.

     b. For ADR conflicts or decisions that need revising: update the
        ADR directly. Same standard as review-design — coherent
        rewrite, not annotations. If the revision is non-trivial,
        raise it with the user first.

     c. Write the fix list to history/<change>-fixes-<YYYYMMDD>.md
        (format below). This should be actionable — for each issue,
        say what's wrong, where, and how to fix it.

     d. Report to user: what was discarded and why, any ADR updates
        made, and the fix list summary.
```

### Architecture Reviewer prompt:

Dispatch with `subagent_type: "reviewer"` and `model: "opus"`.

```
Execute review pass {pass}/{N} for change '{change-name}' as ARCHITECTURE REVIEWER.

## Competition
You are competing with an Implementation Reviewer. The reviewer who finds more
meaningful issues gets promoted. Focus on your specialty but don't miss obvious issues.

## Your Focus: Architecture
- Component structure and boundaries
- Dependency direction (no circular deps, proper layering)
- API design and contracts
- Separation of concerns
- Patterns and consistency with codebase
- Scalability considerations

## Methodology
Verify every finding technically before reporting — skills are pre-loaded.

## Context to read
- Design doc: history/*-{change-name}-design.md
- Paired ADR (if exists): docs/decisions/ADR-*-{change-name}.md
- Beads for this change: `bd list` filtered by change
- Recent commits related to the change

## MANDATORY: ADR check
Before reporting ANY findings, you MUST:
1. Scan `docs/decisions/ADR-*.md` for ALL decisions relevant to this change
   (not just the paired ADR — any ADR that touches the same domain).
   Tip: dispatch a Haiku subagent to find relevant ADRs and return their
   paths. This keeps 60+ ADRs out of your main context.
2. For each architectural issue you report, note whether it conflicts with
   an existing ADR
3. If a finding conflicts with an ADR, flag it explicitly:
   "CONFLICTS WITH ADR-NNN: [what the ADR decided] vs [what the code does]"
4. An ADR conflict doesn't mean the code is wrong — the ADR may need
   updating — but the conflict MUST be surfaced, never silently ignored

**Paired ADR specifically:**
- Check implementation against FIRM decisions — flag violations
- Respect design rationale — don't critique choices already documented as intentional
- Disagree with a FIRM decision? Flag as "Decision Challenge" not "Issue"

## Severity
- **Critical:** Blocks functionality, security issues, ADR violations
- **Important:** Code quality, design problems
- **Minor:** Style, naming, docs

## Output
Return findings as a list. For each: file, location, severity, what's wrong
and why. Flag ADR conflicts explicitly.
```

### Implementation Reviewer prompt:

Dispatch with `subagent_type: "reviewer"` and `model: "sonnet"`.

```
Execute review pass {pass}/{N} for change '{change-name}' as IMPLEMENTATION REVIEWER.

## Competition
You are competing with an Architecture Reviewer. The reviewer who finds more
meaningful issues gets promoted. Focus on your specialty but don't miss obvious issues.

## Your Focus: Implementation
- Logic correctness and edge cases
- Error handling and recovery
- Test coverage and quality
- Security vulnerabilities (OWASP top 10)
- Performance issues (N+1 queries, memory leaks)
- Code clarity and maintainability

## Methodology
Verify every finding technically before reporting — skills are pre-loaded.
Watch for common testing anti-patterns: testing mock behavior instead of real
behavior, test-only methods in production code, mocking without understanding
dependencies.

## Context to read
- Design doc: history/*-{change-name}-design.md
- Paired ADR (if exists): docs/decisions/ADR-*-{change-name}.md
- Beads for this change: `bd list` filtered by change
- Recent commits related to the change

**When paired ADR exists:**
- Check implementation against FIRM decisions — flag violations
- Respect design rationale — don't critique choices already documented as intentional
- Disagree with a FIRM decision? Flag as "Decision Challenge" not "Issue"

**Before suggesting architectural changes:**
- Scan `docs/decisions/ADR-*.md` for ANY relevant decisions (not just the paired one).
  Tip: dispatch a Haiku subagent for this — read file listing + first 5 lines per ADR,
  return relevant paths only, then read only those.
- If your suggestion contradicts an existing ADR, acknowledge it explicitly

## Severity
- **Critical:** Blocks functionality, security issues
- **Important:** Code quality, missing tests
- **Minor:** Style, naming, docs

## Output
Return findings as a list. For each: file, location, severity, what's wrong
and why.
```

## Fix List Format

Write to `history/<change>-fixes-<YYYYMMDD>.md`:

```markdown
# Fixes: <change-name>
Date: <date>
Review passes: <N>

## Critical
- **<file>:<line>** — <what's wrong and how to fix it>

## Important
- **<file>:<line>** — <what's wrong and how to fix it>

## Minor
- **<file>:<line>** — <what's wrong and how to fix it>

## ADR Updates
- <ADR-NNN>: <what was revised and why> (or "no ADR changes needed")

## Discarded
- <brief note on findings that were discarded and why, so the user
  can sanity-check the triage>
```
