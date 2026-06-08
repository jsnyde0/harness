# ADR-011: ADRs Reflect Target Architecture — In-Place Updates for Decision Evolution

**Status:** Accepted (revised 2026-05-13)
**Date:** 2026-04-28

**Related:**
- [ADR-008](ADR-008-adr-predicates-and-plan.md) D1 — ADR predicates required on every decision; this ADR governs how those predicates evolve over time.

## Context

When a brainstorm changes the meaning, framing, or firmness of a decision in an existing ADR, two paths are possible:

1. **In-place update** — rewrite the decision in the existing ADR; the file reflects the current target.
2. **Supersession** — keep the predecessor's body intact, flip its firmness to `SUPERSEDED`, create a new ADR for the evolved decision and link the two.

ADRs are read as current-state target architecture. Supersession chains turn the corpus into historical layers — readers must follow pointers across files to reconstruct what is currently load-bearing. Git already preserves the WHY-trail with better tooling than inline markdown markers (blame, log, diff). In-place updates with git as the history surface keep ADRs as a flat current-state read.

The existing `/design-v2` skill (Algorithm step 5, ADR overlap detection) handles **duplicate avoidance** but not **decision evolution**. A concrete failure mode (2026-04-28): for the `/beadify-v2` redesign, the orchestrator routed to "create ADR-010 with supersession of ADR-005 D8/D9" despite the overlap detector returning a 4/5 (high-overlap) score that should have triggered in-place. The orchestrator rationalized 4/5 → "moderate" by reframing supersession as "successor, not duplicate." The skill provided a soft nudge, not a hard rule.

This ADR records the rule that closes that seam.

## Decisions

### D1: Decision evolution requires in-place update of the existing ADR

**Firmness: FIRM**

When a brainstorm's decisions evolve, replace, or restrict the firmness of any decision in an existing ADR, those changes are applied as in-place edits to that ADR. The decision text, alternatives table, rationale, and "What would invalidate this" field are rewritten to reflect the new target. A one-line `**Date:** <orig> (revised <new-date>)` annotation in the ADR header flags the revision; git history (`log` / `blame` / `diff`) carries the predecessor wording.

`SUPERSEDED` firmness markers, `## Revisions` blocks pointing to successor ADRs, and new-ADR-with-cross-reference-to-old patterns are not used as substitutes for in-place editing.

This rule is binding for the `/design-v2` skill and any agent producing or editing ADRs.

**Rationale:** ADRs answer "what is the current target?" Readers should not navigate supersession chains to reconstruct that. Soft routing nudges (overlap-detection scores) are insufficient — agents rationalize past them. A hard rule with a clear trigger (decision evolution) closes the seam.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| In-place update mandatory (chosen) | ADRs reflect current target; no supersession chains; git carries WHY-trail with better tooling than markdown | Loses inline "before/after" view in the file — mitigated: `git diff` |
| Supersession-via-new-ADR with markers | Preserves predecessor wording inline in the file | ADRs become historical layers; cross-reference chains grow with each evolution; readers chase pointers across files. **reasoned:** supersession chains turn the ADR corpus into archaeology; each evolved decision requires reconstructing state across multiple files |
| Hybrid (in-place for high overlap, supersession for moderate) | Reuses existing routing | Soft nudge; agents rationalize past it; inconsistent ADR shapes across the corpus. **direct:** `/design-v2` skill Algorithm step 5 overlap detector — a concrete failure mode on 2026-04-28 showed the orchestrator rationalized 4/5 overlap score as "moderate" and created a new ADR instead of in-place updating; soft nudges fail |

**What would invalidate this:** If `git log` / `git blame` / `git diff` routinely fail to convey what changed and why (vague commit messages, history truncated by squash merges, readers without git context), the rule loses its mitigation. Counter-signal: if multiple readers report needing an inline "before/after" to follow decision evolution, revisit — possibly with a structured `## Revision history` section that captures revision *metadata* (date, brief reason) but not predecessor decision text.

### D2: New ADRs are for genuinely-new decision space, not supersession

**Firmness: FIRM**

A new ADR is created only when the brainstorm's decisions open decision space the existing ADR corpus does not cover. New ADRs are not created to give a successor home to evolved decisions.

When a brainstorm contains both evolution AND new decision space (the common case), apply both rules in parallel: in-place update the existing ADR for the evolution; create a new ADR for the new content. Cross-references between the two are minimal — typically one line in each `Related` section.

**Rationale:** Conflating "decision evolved" with "new ADR needed" produces ADR-count growth without decision-space growth. Each new ADR should answer a question the existing corpus doesn't already answer.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| New ADRs for new decision space only (chosen) | ADR count grows with covered space, not revision count; clear test for whether a new ADR is warranted | Mixed brainstorms (evolution + new) require applying both rules at once — care needed |
| Allow new ADRs for supersession | Preserves predecessor wording in a separate file | Double-counts the same decision in two places; supersession chains grow indefinitely. **reasoned:** each evolved decision would spawn a new ADR; the corpus count grows with revision frequency, not decision coverage — a metric that doesn't reflect actual scope |
| Always one ADR per major change (regardless of evolution vs new) | Predictable | Same as supersession — each change spawns an ADR; corpus inflates without new coverage. **reasoned:** "one ADR per change" produces the same corpus inflation as supersession; the corpus then requires a dedup pass to distinguish genuine new coverage from revision history |

**What would invalidate this:** If applying both rules in parallel routinely fragments ADRs into small one-decision new-ADRs that depend heavily on cross-references to a sibling, the test for "new decision space" is too lax — tighten authoring guidance.

## Related

- [ADR-008](ADR-008-adr-predicates-and-plan.md) D1 — ADR predicates per decision; this ADR governs predicate evolution.
- `/design-v2` skill (Algorithm step 5) — implements D1's binding rule.
