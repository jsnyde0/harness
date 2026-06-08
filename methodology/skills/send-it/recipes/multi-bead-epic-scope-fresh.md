# multi-bead-epic-scope-fresh

## When this shape fits

A genuinely new multi-step epic — not framed yet, no decomposition, no ADRs already in play. Examples: building a new subsystem from scratch; major refactor across modules; standing up a new integration.

This is composition pattern B (frame → fan-out → re-verify-at-parent) at its fullest.

## Composition sketch

1. **`/scout-adrs`** — find what constrains the surface. Almost always returns something even for "new" work.
2. **`/scope-check`** on the proposed epic — outward-look neighbor enumeration (files, sibling beads, ADRs). Default-on for multi-bead-epic authoring per ADR-012 D3.
3. **Author the epic bead** with `--design` carrying the framing decisions, `## canonical_refs` from scout, and `--acceptance` as the parent-level contract.
4. **`/decompose`** — produces children with their own `--acceptance` + a `## File-claim map`. Default-on whole-tree adversarial-review per the skill.
5. **Walk children:**
   - Read `## File-claim map`. Disjoint claims → parallel dispatch (single message, multiple `implementer` Task() calls). Overlapping or no map → serial.
   - Each child runs composition pattern A (validate → repair → re-validate) — that's its own per-leaf judgment call.
   - For non-trivial leaves: dispatch `implementer`. For design-heavy leaves: see `single-leaf-design-heavy.md`. For impl-heavy: see `single-leaf-impl-heavy.md`.
6. **Parent re-verify** when all children close: run the parent's `--acceptance` + ADR invalidation checks against the cumulative diff (ADR-009 D5). Any FAIL → file discovered-from child; re-walk.
7. **`/compound`** — default-on at epic close per ADR-013 D6. Produces Record / Promote / Retire candidates; orchestrator folds.

## Watch-outs

- **Skipping `/scope-check`.** Overlap-blindness is the #1 multi-bead failure mode (skeptic punch in ADR-012 context). Default-on for this shape.
- **Walking children without reading the file-claim map.** Parallel dispatch without disjointness verification is the race-condition failure mode ADR-009 D2 is designed to prevent.
- **Skipping parent re-verify.** Children all returning "done" doesn't mean the parent's acceptance holds — that's the infinite-handoff failure mode LangGraph documented (ADR-009 D5).
- **Skipping `/compound` because "I'm tired."** Default-on at epic close means the substrate captures learning; skipping it is how the memory layer stays empty.

## Why this is in recipes

The full pattern-B shape. Calibrates "this is the moment scope-check, decompose, parent-re-verify, and compound all matter — and the moment they're most tempting to skip."
