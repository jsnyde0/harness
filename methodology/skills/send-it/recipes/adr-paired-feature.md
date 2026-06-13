# adr-paired-feature

## When this shape fits

A new feature surfaces a load-bearing decision not yet captured anywhere canonical. The decision constrains future work even after this bead closes. Examples: introducing a new persistence layer; picking a cross-service auth model; deciding the failure-handling contract for a new subsystem.

## Composition sketch

1. **`/brainstorm`** if the topic is genuinely unclear — Socratic exploration lands the rough shape into a `--design` narrative. Wait for explicit user convergence.
2. **`/adr-write`** — author or evolve the ADR canonicalizing the load-bearing decision. Alignment-question discipline + 5-dim overlap detection.
3. **`/scout-adrs`** post-write — sanity-check what else this newly-canonical decision composes with.
4. **Author the bead** carrying the implementation, with `## canonical_refs` pointing at the new ADR.
5. **`/decompose`** if the bead is multi-step — produces children with `## File-claim map`.
6. **Dispatch `adversarial-reviewer`** on the decomposition tree (default-on).
7. **Walk children** — see `walk-children` notes inline in `/send-it` (serial unless claims disjoint).
8. **Parent re-verify** — re-run the parent's `--acceptance` + ADR invalidation checks.
9. **`/compound`** at epic close (default-on) — surfaces Record / Promote / Retire candidates.

## Watch-outs

- **Authoring the ADR after implementation.** The whole point of the ADR-paired shape is that the decision constrains the impl, not vice versa. If you implement first, the impl's framing biases the ADR.
- **Skipping the brainstorm convergence gate.** Brainstorm produces substrate; the bead-id is the durable handoff. Without explicit user convergence the framing is still mutable, and any downstream review burns tokens on a moving target.
- **Conflating `/adr-write` and inline `--design` edits.** Bead `--design` captures decisions *in scope* (this bead); ADR captures them *cross-cutting* (everything that will touch this surface). Both exist; neither substitutes.

## Why this is in recipes

The full heavyweight shape. Most ADR-worthy work doesn't follow this entire chain — but when the decision is genuinely cross-cutting and load-bearing, skipping steps is how learnings get lost.
