# pre-decomposed-input

## When this shape fits

Someone (or some prior process) already did the decomposition. Examples: a security audit's tiered findings list; a checklist from a code-review pass; a manual punch list with explicit P0/P1/P2 tiers.

The risk is **re-decomposing the already-decomposed input** — burning tokens reproducing analysis that was already done. The probe ledger showed this is a real failure mode: orchestrator authors 20 beads when the input already named 20 items.

## Composition sketch

1. **Recognize the pre-decomp.** Cue: input is a tiered list, ordered list, or numbered findings — the upstream did the scope/decompose work.
2. **`/scout-adrs`** once on the topic to surface in-scope ADRs that constrain the items. Cheap; useful.
3. **Beadify per item directly** — `bd create` for each finding/task. `--design` cites the source review + the specific finding. `## canonical_refs` from step 2. **Skip `/decompose`** — there's nothing to split that wasn't already split.
4. **Dispatch `adversarial-reviewer` on the scoping** — single fresh-context pass checking the bead boundaries make sense and nothing was missed at the *scoping* level. This is the lightweight design-review for this shape.
5. **Walk items** — dispatch `implementer` per non-trivial bead; drive directly for trivial ones. File-claim disjoint → parallel dispatch is fine.
6. **`/compound`** at the end if the items belong to a coherent unit (e.g., the punch list is one epic). Otherwise skip.

## Watch-outs

- **Re-decomposing.** The probe showed this: orchestrator runs `/decompose` on each item out of habit. Don't — `/decompose` is for items that *need splitting*; pre-decomposed items are already at leaf-shape.
- **Skipping scoping review because each item is "small."** The risk in pre-decomposed input isn't that any single item is wrong — it's that the upstream tiering / ordering missed dependencies. Review the *scoping*, not each item.
- **Driving every item directly because they're "small."** Some pre-decomposed items are small; some are deceptively non-trivial. Default to dispatching `implementer` unless the item is genuinely trivial (typo, one-line change). Probe 1's failure mode was orchestrator solo-working all 20 items.

## Why this is in recipes

This shape was the primary substrate-thick gap surfaced by a security-audit punch list. Calibrates "recognize the upstream did the work; don't redo it; review the scoping."
