---
name: beadify-bootstrap
description: Bootstrap decomposition workflow for Pi. Decomposes an epic bead into child beads using only the main/orchestrator session, creating runnable acceptance criteria and dependency edges with bd.
---

# Beadify Bootstrap

## Purpose

Decompose an approved epic bead into child beads without relying on any delegated worker workflow.

The orchestrator/main Pi agent owns the whole decomposition:

- read the epic design, acceptance, and ADR notes
- decide the child bead tree
- write each child target and acceptance criteria
- create child beads with `bd create --parent=<epic>`
- add dependency edges with `bd dep add`

This skill is a temporary bootstrap counterpart to future `beadify-v2`. It should be good enough to decompose the Pi subagent primitive work before subagent-powered workflow skills exist.

## Inputs

Invoke `/skill:beadify-bootstrap <epic-bead-id>`.

- `<epic-bead-id>` is required.
- Unknown arguments: stop and ask the user to clarify.

## Outputs

- Child beads created under the epic.
- Each child has:
  - verb-first title
  - concise description/design target
  - runnable or inspectable `--acceptance`
  - inherited relevant labels where appropriate
  - `## ADRs consulted` in notes when ADRs constrain the work
- Dependency edges for serial work.
- Optional integration/validation bead for multi-bead changes.
- Final line exactly:

```text
EPIC_ID: <bead-id> CHILDREN: <id1>,<id2>,...
```

On failure, final line exactly:

```text
BLOCKED: <reason>
```

No trailing text after the final contract line.

## Algorithm

### 0. Preflight

1. Run `bd show <epic-id>`.
2. If the bead is missing, stop with `BLOCKED: Bead <id> not found`.
3. If the bead is closed, stop with `BLOCKED: Bead <id> is already closed`.
4. If the bead lacks a populated `--design`, stop with `BLOCKED: Epic has no design field`.
5. Read:
   - epic title
   - epic design
   - epic acceptance
   - epic notes
   - existing children, if any
   - labels and priority
6. If children already exist, ask the user whether to augment, replace, or stop. Do not duplicate an existing decomposition silently.

### 1. Gather constraints

1. Read ADRs listed under `## ADRs consulted` in epic notes.
2. Inline-scan `docs/decisions/ADR-*.md` for any clearly relevant ADRs not listed. Keep the set small and explain why each is relevant.
3. Extract constraints that must shape child beads:
   - FIRM design decisions
   - explicit safety boundaries
   - acceptance criteria from the epic
   - excluded/non-goal scope
   - ordering constraints
   - likely integration point

### 2. Pre-decide the bead tree

Create a proposed tree in the main session before writing any beads.

For each proposed child, specify:

- title
- type (`task` unless another type is clearly warranted)
- purpose / target outcome
- scope boundaries
- acceptance criteria
- dependencies on sibling children
- expected validation command(s), if known
- rationale for why this is a separate bead

Discipline:

- **Organize + target, not prescribe.** Child descriptions say what observable outcome is required; they do not include step-by-step implementation instructions.
- Avoid file paths in child titles/descriptions unless the bead is specifically about a file-level artifact and the path is part of the observable target.
- Keep children independently implementable where possible.
- If two proposed children would modify the same file or same tightly coupled surface, either merge them or add an explicit serial dependency.

### 3. Check decomposition quality

Before creating beads, self-review the proposed tree:

- Does every epic acceptance criterion map to at least one child or integration bead?
- Is there any child with vague/non-runnable acceptance?
- Are there same-file/same-surface conflicts among parallel children?
- Is an integration/validation bead needed?
- Are there too many tiny beads or one giant bead?
- Are any child descriptions prescribing implementation rather than setting targets?
- Are dependency edges acyclic?

If quality is poor, revise the proposed tree before writing beads.

### 4. Create beads parent-first

The epic already exists, so create children under it.

Use `bd create` with:

- `--parent <epic-id>`
- `--type task` unless another type is clearly warranted
- `--title`
- `--description` or `--design` for the target narrative, depending on bd convention in this repo
- `--acceptance`
- `--notes` containing relevant ADRs and decomposition rationale
- labels copied/adjusted from epic when useful

Prefer temp files for long design/acceptance/notes fields to avoid shell quoting mistakes.

### 5. Add dependencies

For every serial relationship:

```bash
bd dep add <blocked-child> <blocking-child>
```

Meaning: `<blocked-child>` depends on `<blocking-child>`.

For integration/validation beads, add dependencies from the integration bead to each implementation sibling it validates.

### 6. Verify graph

Run:

```bash
bd dep tree <epic-id>
bd dep cycles
bd list
```

Confirm:

- created children appear under the epic
- dependencies are in the intended direction
- no cycles exist
- expected ready child beads are unblocked

### 7. Report contract

Report the created child IDs and the intended execution order. End with the exact final line:

```text
EPIC_ID: <epic-id> CHILDREN: <comma-separated-child-ids>
```

## Acceptance-writing rules

Each child acceptance should be runnable or directly inspectable. Good forms:

- `Given/When/Then` observable behavior.
- command-based check, e.g. `Given ..., when <command> runs, then ...`.
- file/content check for documentation or skill artifacts.
- manual verification only when automation is genuinely not available, and then with precise inspection criteria.

Acceptance must not be:

- "implementation exists"
- "code looks good"
- "update the file"
- a step-by-step implementation plan
- dependent on hidden conversation context

## Integration bead rule

For multi-bead changes, add an integration/validation bead unless the change is narrow and obviously self-contained.

The integration bead should validate the cross-bead outcome, not repeat each child’s local checks. It depends on all relevant sibling beads.

## Forbidden

- **Delegated decomposition.** Do not call another agent/model/process to write acceptance or decide the tree.
- **Children before parent.** The parent epic must exist first; create children with `--parent`.
- **Silent duplicate decomposition.** If children already exist, ask how to proceed.
- **Same-surface parallel children.** Merge or serialize children that would collide on the same file/surface.
- **Skipping integration validation for multi-bead work.** Include an integration bead unless the change is narrow.
- **Implementation plans as bead descriptions.** Beadify sets targets; implementation planning belongs later.
- **Fixing the epic design while decomposing.** If the epic design is wrong or too vague, stop or send it back through review/design rather than papering over it with child beads.

## Bootstrap note

This skill exists to break the bootstrapping cycle for building the Pi subagent primitive. Once `beadify-v2` exists, prefer it for normal decomposition. Keep this skill available for main-session-only fallback work.
