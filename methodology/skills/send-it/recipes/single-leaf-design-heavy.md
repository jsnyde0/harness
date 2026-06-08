# single-leaf-design-heavy

## When this shape fits

A single bead with critical architectural implications but small implementation. The risk surface is in the *decision*, not the code. Examples: changing how a module exposes its API; picking a storage shape; defining the contract between two subsystems for the first time.

## Composition sketch

1. **`/scout-adrs`** on the topic — find what already constrains this surface.
2. **Author the bead** with `--design` carrying decisions (FIRM/FLEXIBLE/EXPLORATORY + rationale + alternatives + "what would invalidate") and a `## canonical_refs` section. (ADR-008 D1, D5.)
3. **Dispatch `adversarial-reviewer`** on the design. Fresh-context judgment is highest-leverage here — the orchestrator is biased by having authored the decision.
4. Fold review findings into `--design`; re-dispatch only if REVISE/REJECT.
5. **Drive the implementation directly** (or dispatch `implementer` if non-trivial) — TDD discipline. The code is small; the decision is what mattered.
6. Run harness, commit, close.

## Watch-outs

- **Skipping design review because "the impl is small."** Frame-distance matters most when you authored the design moments ago. Default-on per ADR-012 D3.
- **Authoring an ADR inline.** If the decision is cross-cutting, route through `/adr-write`, not directly into `--design`. The bead carries the decision *in scope*; the ADR captures it *cross-cutting*.
- **Re-reviewing too early.** Fold all small/unambiguous findings first; re-dispatch only on substantive REVISE/REJECT. Anchored re-reviewers cost tokens for the same findings.

## Why this is in recipes

Calibrates the "small impl, big decision" shape against the orchestrator's reflex to "just write the code, it's small." The substrate-thick move is to invest where risk lives — in the decision.
