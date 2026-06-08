# send-it recipes

Worked examples of how composition patterns A (validate → repair → re-validate) and B (frame → fan-out → re-verify-at-parent) fit specific situations.

**These are illustrations, not templates.** Read one or two to calibrate the composition vocabulary; do not match-and-execute. The substrate (bead `--acceptance` + harness signal) decides done-ness; recipes are inspiration for the moves available.

## Index

- [`trivial-edit.md`](trivial-edit.md) — typo / one-line / mechanical change. The floor of how thin orchestration can be.
- [`single-leaf-design-heavy.md`](single-leaf-design-heavy.md) — small impl, critical architectural decision. Risk lives in the decision.
- [`single-leaf-impl-heavy.md`](single-leaf-impl-heavy.md) — simple architecture, challenging implementation. Risk lives in the code.
- [`adr-paired-feature.md`](adr-paired-feature.md) — new feature surfacing a load-bearing cross-cutting decision. Heavyweight shape.
- [`pre-decomposed-input.md`](pre-decomposed-input.md) — audit findings / punch list / pre-tiered input. Recognize the upstream did the decompose work.
- [`multi-bead-epic-scope-fresh.md`](multi-bead-epic-scope-fresh.md) — genuinely new multi-step epic. Pattern B at its fullest.
- [`investigation-or-bug.md`](investigation-or-bug.md) — find out what's wrong first; reproduction before fix.
- [`bead-id-input-already-framed.md`](bead-id-input-already-framed.md) — multi-session hand-off; re-engage carefully.

## How to read these

Each recipe carries three sections:

- **When this shape fits** — the cue that says "this might be relevant."
- **Composition sketch** — the moves, in a typical order. Order is illustrative, not mandatory.
- **Watch-outs** — common failure modes specific to this shape.

If none of the recipes obviously fits, you're probably between two of them — compose by judgment from the primitives + subagents in send-it/SKILL.md (methodology home). The recipes don't enumerate the work-space; they calibrate vocabulary.
