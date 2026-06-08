# Why design-v2 chains back to review-v2 on contradiction

The chain-back path (algorithm step 6) exists because review-v2's internal Haiku pre-filter caps at ≤3 ADRs. A FIRM ADR that contradicts a decision in the bead's `--design` may legitimately have been outside the filtered set review-v2 saw. Design-v2's whole-corpus scan catches the gap and routes the contradiction back to review-v2 with that ADR force-injected, rather than letting design-v2 adjudicate a contradiction (which is review-v2's job per ADR-007 D7).

This case is rare in practice — most contradictions surface during review-v2's own loop. The chain-back exists as the safety net for the small set of ADRs the Haiku filter excluded.
