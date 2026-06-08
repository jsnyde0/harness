---
name: beadify
description: Crystallize discussion or plan into well-scoped beads
---

Convert design docs into trackable beads.

**Arguments:** `$ARGUMENTS` → `<change-name> [N] [with context: <additional-context>]`
- change-name: required (ask if missing)
- N: number of refinement passes (default 1)
- additional-context: optional constraints/guidance passed verbatim to subagents

## Bead Sizing

- Each bead = independently implementable and verifiable in a single focused session
- Don't use rigid formulas — judge by: "Can an agent complete this without context switching?"
- Each bead = one commit
- **File ownership:** Minimize file overlap between beads. If two beads modify the same file, consider merging them. Sequencing via `bd dep add` is the fallback when beads are genuinely independent (different risk profiles, different logical concerns).

**Default posture: fewer beads.** Each bead carries fixed overhead — agent startup, context loading, code review, and potential conflicts with parallel agents. A single bead that's slightly large is cheaper than two beads that each pay that overhead. When in doubt, merge.

**Split signals** — the bead is too large when:
- An agent would need to hold too many unrelated concerns in context at once
- "Done" can't be described in 2-3 crisp criteria
- Parts have meaningfully different risk profiles (safe refactor vs. behavioral change)

**Merge signals** — the beads are too small when:
- The next bead re-reads the same code to do its work
- You can't verify one without the other being done
- A bead can't justify a standalone commit message
- The overhead of a separate agent + review cycle exceeds the complexity saved by splitting

These are smells, not rules. When signals conflict, name the tradeoff and pick a side — but the tie-breaker favors merging.

## Integration Tests

**Always include integration tests** unless the change is narrow enough that unit-level verification fully covers it.

Skip integration tests only for changes like: single function signature cleanup, config tweak, typo fix, renaming — where there's nothing meaningful to test beyond what the implementation bead already verifies.

Include integration tests for anything that: modifies data flow between functions, changes behavior observed by other components, touches race conditions, spans multiple modules, or could break downstream consumers.

**Placement:**
- Single implementation bead → include integration tests as a verification step within it
- Multiple implementation beads → add a final integration test bead that depends on all siblings

## Execution Pattern

You are the **manager**. Spawn subagents via the Task tool — each pass gets a fresh subagent with the appropriate prompt below.

### Manager orchestration:

```
Before ANY pass:
  0a. Sketch the bead tree — YOU (the manager) read the design doc and produce
      an explicit bead tree BEFORE dispatching any subagent:
        - What beads exist (titles, purpose)
        - Parent/child structure
        - Which are sequential vs parallel (and why)
        - Rationale for any split or merge decisions
      Apply Bead Sizing (above) — start from the fewest beads that cover the
      change, then split only where split signals clearly outweigh overhead.
      This is a manager reasoning step, not a subagent dispatch. The plan-writer
      receives this pre-decided structure and is responsible only for writing
      bead content to spec — not for re-deciding the structure.

  0b. ADR pre-filter — dispatch a Haiku subagent to produce a filtered ADR list:
      (subagent_type: "general-purpose", model: "haiku")
      Prompt:
        Find the ADRs in docs/decisions/ that are relevant to: {change-name}.
        Return file paths only, no summaries.
      Wait for completion. Use the returned paths in all downstream subagent
      prompts instead of instructing them to scan all ADRs.
      Note: downstream subagents retain the instruction to flag any additional
      relevant ADRs they encounter that were not in the pre-filtered list.

For pass = 1 to N:
  a. Spawn subagent with prompt
  b. Wait for completion
  c. If subagent returned "BLOCKED: ..." → stop early, report blocker
  d. Otherwise → spawn the next pass. Do not evaluate whether another pass is "needed".
After ALL N passes complete: report completion with summary
```

**N passes is a hard requirement, not a target.**
- Do NOT interpret subagent output to decide whether to continue.
- Do NOT skip passes because beads "look good", "are solid", or "need no changes".
- Do NOT rationalize early termination ("no further refinement needed", "already complete", etc.).
- The ONLY exit before pass N is an explicit `BLOCKED` signal.
- If you are about to skip a pass, you are violating this instruction. Run the pass.

### Subagent prompt:

**Manager responsibility:** Construct the prompt below, substituting `{variables}` and selecting the appropriate section based on context. If `additional-context` was provided, include it in the prompt.

Dispatch with `subagent_type: "plan-writer"` and `model: "sonnet"`.

```
Execute beadify pass {pass}/{N} for change '{change-name}'.
You MUST complete this pass fully — the manager will handle whether more passes follow.

## Your task
Create or refine beads so an agent can execute without ambiguity.
The bead tree structure has already been decided by the manager (see Pre-decided Structure
below). Your job is to write bead content to spec — not to re-decide the structure.
You MAY flag structural concerns back to the manager (e.g. "these two beads share the
same file and should be merged"), but the initial structure decision is not yours to make.

## Methodology
Follow the writing-plans skill (pre-loaded) when creating beads from design docs.
This ensures tasks are detailed enough for engineers with zero codebase context,
with exact file paths, complete code examples, and verification steps.

## Pre-decided Structure
{bead-tree-sketch from manager step 0a}

## Context to read
- Design doc: history/*-{change-name}-design.md
- Relevant ADRs (pre-filtered): {adr-paths from Haiku pre-filter step 0b}
- Existing beads: `bd list` filtered by change

**When ADR exists:**
- Respect FIRM decisions — they encode prior discussion and tradeoff analysis
- Ensure beads don't violate FIRM decisions
- Disagree? Raise it — don't silently deviate, state the conflict and wait for alignment
- If you encounter additional relevant ADRs not in the pre-filtered list, flag them.

{if additional-context provided}
## Additional Context
{additional-context}
{endif}

## Pass-specific instructions
```

**Manager selects ONE of these sections based on context:**

**If no beads exist yet:**
```
- The manager's pre-decided structure is your starting point. Do NOT add beads beyond it
  unless you find a clear split signal the manager missed — and flag it, don't silently add.
- **Hierarchy rule**: If creating >1 bead, create a parent bead first
- Create parent: `bd create --type=epic --title="..."`
- Create one child bead per bead: `bd create --parent=<parent-id> --title="..."`
  - **CRITICAL**: Without `--parent`, children aren't tracked by parent
- Set blocking dependencies between siblings: `bd dep add <task> <depends-on>`
- **File-conflict check**: If any file appears in multiple beads, first consider whether those beads should be merged. If they remain separate, add `bd dep add` to sequence them — beads sharing files cannot run in parallel.
- **Integration tests**: Always include unless the change is narrow enough that unit-level verification fully covers it (e.g., single function cleanup, config tweak). For single-bead changes, include integration tests as a verification step within the bead. For multi-bead changes, create a final child bead for integration tests that depends on ALL siblings.
```

**Otherwise (refinement pass):**
```
- Review beads against merge signals first (can any be combined?), then split signals — name the reasoning for each decision
- Check: Can an agent execute each bead without ambiguity?
- Refine descriptions, update dependencies if structure changed
```

## Bead pattern (succinct with references)
```
Title: [Component] Short description
Priority: P2
Type: task

Design: history/YYYY-MM-DD-{change-name}-design.md#section

Done when:
- [1-2 line acceptance criteria]
- Verification passes
```

## Output
- Create/update beads via `bd create`/`bd update`
- Set dependencies via `bd dep add`
- Return one of:
  - "PASS {pass}/{N} COMPLETE: [summary of what was created/changed/verified]"
  - "BLOCKED: [issues]" — design gaps prevent beadification (triggers early termination)
```

## Manager Output
- Epic + child beads created/refined
- Dependencies set
- Report: passes completed, beads created/modified, early termination reason (if any)
