# trivial-edit

## When this shape fits

The work is genuinely small and the orchestrator's context is already aligned: typo fix, single config line, mechanical rename, one-line copy edit. No load-bearing decisions. No ADRs in play.

Defaults around scout / adversarial review / dispatch are cost without benefit at this size.

## Composition sketch

1. Read the bead (or just the user's prompt if no bead exists yet).
2. Drive the change directly.
3. Run the harness (the harness signal, or just the test command the repo uses).
4. Commit + close bead (or just commit, if no bead).

## Watch-outs

- **The "trivial" trap.** If you find yourself touching more than the obvious surface, stop. The work isn't trivial anymore — re-frame against the diagnostic ladder and pick a heavier shape.
- **No bead, no acceptance contract.** For a no-bead trivial edit, the acceptance contract is implicit ("the typo is fixed"). Re-read the diff before claiming done; trivial edits silently regress when the fix is wrong in the same way the original was.
- **Don't skip the harness.** Even trivial edits can break builds. A 3-second `pytest` / `tsc` / `cargo check` is cheaper than the regression.

## Why this is in recipes

To make the small-shape legible. The orchestrator under-uses primitives when context is sparse, but it also over-uses them when context is heavy. This recipe is the explicit floor: sometimes the right composition is "edit, verify, done."
