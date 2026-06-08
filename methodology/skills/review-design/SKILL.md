---
name: review-design
description: Review and refine an existing design with fresh perspectives
---

Review an existing design document with subagent iterations.

**Goal:** Produce improved, coherent design docs (and ADRs). The review is a
means to that end — the deliverable is better documents, not a review report.

**Arguments:** `$ARGUMENTS` → `<design-name> [N]`
- design-name: required - matches `history/*-{design-name}-design.md`
- N: number of review passes (default 1)

## When to Use

Use this AFTER `/brainstorm` has created an initial design:
- Design exists but you want fresh eyes on it
- Need to challenge assumptions or find gaps
- Want to explore alternatives you might have missed

## Execution Pattern

You are the **manager**. Your job is to produce better documents. Subagents
help by identifying improvements — they append findings but never modify
existing content. You own the final integration.

### Manager orchestration:

```
1. Verify design exists: history/*-{design-name}-design.md
   - If not found → list available designs, ask user to pick
2. For pass = 1 to N:
   a. Spawn subagent with pass prompt (see below)
   b. Wait for completion
   c. If "BLOCKED" → stop early, report blocker to user
3. IMMEDIATELY after all passes complete — do NOT just dump raw
   findings. You triage, then align with the user BEFORE editing.

   a. Read through all appended findings. For each, form a judgment:
      fold it in, discard it, or flag it as needing discussion.

      **Default posture: present before editing.** Don't assume
      you know what the user considers a "clear win." Something
      that looks obviously good to you may conflict with context
      or intent you don't have. When in doubt, surface it.

      The only things you should silently discard are findings that
      are clearly wrong (factual errors, misreading the design) or
      trivially overengineered. Everything else goes to the user.

      Watch for findings that contradict an intentional design
      choice — even if technically valid, the question becomes
      "change the design or keep it and explain why." Always
      surface these.

   b. Present your triage to the user in a single structured summary:

      - **Recommend folding in**: findings you think improve the
        design. State why briefly. User confirms or pushes back.
      - **Recommend discarding**: findings you think are wrong or
        not worth it. State why briefly. User can override.
      - **Need discussion**: genuine tradeoffs, competing concerns,
        ADR conflicts, or anything where you're unsure. For heavy
        decisions, use /guide to walk through properly.

      Keep it scannable — the user should be able to quickly
      accept/reject each item without re-reading the whole design.

   c. Wait for the user's calls. Then apply: fold in accepted items
      by editing the relevant sections so the doc reads as if it
      always included them. Discard the rest.

   d. After all findings are processed:
      - Remove the appended findings section(s) entirely
      - The doc must read as a coherent whole — zero review artifacts
      - Update paired ADR if changes affect recorded decisions

4. Report to user: what was folded in, what was discarded, any
   remaining open questions.

5. After reporting, always end with this exact prompt to the user:
   'Design looks good — run /create-tickets to create Linear + Beads issues?'
```

### Subagent prompt template:

Dispatch with `subagent_type: "reviewer"` and `model: "opus"`.

```
Execute design review pass {pass}/{N} for '{design-name}'.

## Your role
You identify improvements to the design. You may APPEND a findings section
to the end of the design doc, but you MUST NOT modify any existing content.
The manager will rewrite the docs based on your input.

## Methodology
Verify every finding technically before reporting it (skill is pre-loaded).
Focus on challenging assumptions and finding gaps, not starting from scratch.

## Context to read
- Existing design: history/*-{design-name}-design.md
- Paired ADR (if exists): docs/decisions/ADR-*-{design-name}.md
- Relevant codebase files as needed

## MANDATORY: ADR check
Before reporting ANY findings, you MUST:
1. Scan `docs/decisions/ADR-*.md` for ALL decisions relevant to this design
   (not just the paired ADR — any ADR that touches the same domain).
   Tip: dispatch a Haiku subagent to find relevant ADRs and return their
   paths. This keeps 60+ ADRs out of your main context.
2. For each finding, note whether it conflicts with an existing ADR
3. If a finding conflicts with an ADR, flag it explicitly:
   "CONFLICTS WITH ADR-NNN: [what the ADR decided] vs [what I'm suggesting]"
4. An ADR conflict doesn't mean the finding is wrong — the ADR may need
   updating — but the conflict MUST be surfaced, never silently overridden

**Paired ADR specifically:**
- Respect FIRM decisions — they encode prior discussion and tradeoff analysis
- Review whether decisions still hold given new information
- Disagree? Flag the conflict — don't silently deviate

## Review focus
1. **Assumptions**: What assumptions does this design make? Are they valid?
2. **Gaps**: What's missing? Edge cases? Error handling?
3. **Alternatives**: Are there simpler approaches we missed?
4. **Dependencies**: What does this depend on? What depends on this?
5. **Risks**: What could go wrong? What's the fallback?

## Process
- Read the design thoroughly
- Complete the MANDATORY ADR check above
- For each section, ask: "Is this the simplest solution? What could go wrong?"
- For each improvement you identify, be specific: what's wrong and why.
- Flag findings that change the architecture (different system boundaries,
  changed data flow, fundamentally different approach, ADR conflicts).
  Most findings are implementation-level and don't need special flagging —
  use your judgment.

## Output
Append a `## Review Pass {pass} Findings` section to the END of the design
doc. Do NOT modify any existing content above.

Structure:
- **ADRs reviewed**: which ADR files you checked and their relevance
- **Findings**: list each with a specific suggestion for how the doc should
  change. Mark architectural changes with `[ARCH]` and include rationale.
  Flag ADR conflicts per the mandatory check above.
- **Verdict**: "SOLID" | "REFINED" | "BLOCKED: [issues]"

Also return the verdict as your message to the manager.
```
