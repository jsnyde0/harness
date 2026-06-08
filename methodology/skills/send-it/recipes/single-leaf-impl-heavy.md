# single-leaf-impl-heavy

## When this shape fits

A single bead with simple architecture but challenging implementation. The decision shape is obvious; the code is where the risk lives. Examples: a tricky data transformation against an existing schema; a performance-sensitive inner loop; integrating with a flaky external API.

## Composition sketch

1. **`/scout-adrs`** (light pass) — usually returns "no in-scope ADRs" or one obvious one. Cheap; do it anyway.
2. **Author the bead** — `--design` is short. `--acceptance` carries the heavy lifting: observable, falsifiable, runnable.
3. **`/harness`** — design the feedback loop deliberately. For impl-heavy work, fast→slow signal tiers matter more than the design narrative.
4. **Dispatch `implementer`** — fresh-context TDD. The orchestrator's framing context is low-value here; what matters is rigor against the harness.
5. **Dispatch `adversarial-reviewer`** on the implementation diff after `implementer` returns. ADR-alignment check + acceptance coverage. Skip only if frame-distance is genuinely low-stakes (e.g., you also wrote the harness and the failure mode space is fully named in `--acceptance`).
6. Fold; re-dispatch `implementer` on substantive findings. Apply the diagnostic ladder if the failures repeat (likely harness wrong → `/harness` redesign).
7. Commit, close.

## Watch-outs

- **Letting the implementer raise scope.** `implementer` is execute-only. If it surfaces "the bead is mis-scoped," that's a substrate problem, not an implementer problem — receive the raise, repair the bead, re-dispatch.
- **Skipping impl-stage review because design-stage review passed.** Different reviewers catch different things. Design review is "is the plan sound?"; impl review is "did the code do what the plan said, and does it still respect ADRs?"
- **Retrying `implementer` without changing substrate.** If two cycles fail with similar failures, the harness or the acceptance contract is wrong — apply the diagnostic ladder.

## Why this is in recipes

Mirror-image of single-leaf-design-heavy. Same primitive set, different center of gravity. Calibrates "review the impl, not just the design."
