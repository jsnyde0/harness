# bead-id-input-already-framed

## When this shape fits

The user hands you a bead-id. The bead was authored in a prior session (possibly by another agent, possibly by a human). `--design` / `--acceptance` / `--notes` already exist. Your job is to ship it.

The temptation is to either (a) treat the framing as authoritative and skip review, or (b) re-frame from scratch and ignore the existing work. Both are wrong. The right move is calibrated re-engagement.

## Composition sketch

1. **Read the bead fully** — `bd show <id>` for `--design`, `--acceptance`, `--notes`, parent chain, and any labels (`review:pending`, `verdict:*`, etc.).
2. **Check `## canonical_refs` freshness.** Are the cited ADRs still current? Have new ADRs landed since the bead was authored that would now apply? Run `/scout-adrs` only if `canonical_refs` is empty/stale or scope has shifted.
3. **Dispatch `adversarial-reviewer` on the existing `--design`** — default-on for own-work-equivalent (this bead is now *your* responsibility to ship, so it counts). Fresh-context review against current ADRs.
4. **Fold review findings** — REVISE → edit the bead; REJECT → raise to user (the framing is wrong, not just imperfect).
5. **Execute** based on the bead's shape — apply the relevant leaf recipe (`single-leaf-design-heavy.md`, `single-leaf-impl-heavy.md`, etc.) or pattern B if the bead has children.
6. **Dispatch `adversarial-reviewer` on the impl** before close — review against the (possibly updated) `--design`.
7. Close. **`/compound`** if the bead was load-bearing.

## Watch-outs

- **Trusting the framing because someone else wrote it.** Beads authored in prior sessions have the same self-anchoring problem as beads you just wrote — the author was biased by their context, you weren't there to check, and time has passed since. Adversarial review is *more* warranted, not less.
- **Re-framing from scratch.** The opposite failure: ignoring the existing `--design` and recreating it from your own framing. Wastes the prior work and loses any decisions the prior author captured. Read first, review second, edit only on substantive findings.
- **Skipping freshness check on `canonical_refs`.** ADRs evolve in place. A bead authored against ADR-X version N may now be operating against ADR-X version N+2 — the framing may quietly contradict current substrate.

## Why this is in recipes

Hand-off shape — the most common multi-session scenario. Calibrates "re-engage carefully, don't blind-trust, don't blind-restart."
