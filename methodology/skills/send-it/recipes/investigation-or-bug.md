# investigation-or-bug

## When this shape fits

The work is to **find out what's wrong** before fixing anything. Examples: a bug whose root cause isn't obvious; an investigation into "why is X slow"; a "does feature Y work the way we think it does?" question.

The mistake here is jumping to fix-shape work before the problem is understood. Investigation has its own loop, distinct from feature work.

## Composition sketch

1. **`/scout-adrs`** — what already documents this surface? An ADR's "what would invalidate" may already name the failure mode.
2. **`/harness` (reproduce)** — design the reproduction signal first. The most important harness output here is "the bug currently fires." Without a reproduction, "fixed" is unverifiable.
3. **Author a bead** carrying the investigation as the unit of work. `--acceptance` is "root cause identified, named in `--notes`, and the bug is either fixed or filed as follow-up."
4. **Dispatch `debugger`** if the orchestrator is stuck or the problem space is unfamiliar. Fresh-context root-cause analysis. `debugger` reports diagnosis; orchestrator decides the repair path.
5. **Repair**:
   - Trivial fix → drive directly with TDD discipline (write the test against the reproduction, then fix).
   - Non-trivial → dispatch `implementer` on the fix bead.
   - Discovered scope mismatch → repair via the diagnostic ladder (`/decompose`, `/adr-write`, etc.).
6. **Dispatch `adversarial-reviewer`** on the impl diff — for bugs especially, regression risk is high; review focuses on "did the fix introduce a different bug?"
7. Close. **`/compound`** if the bug was load-bearing or surfaced a learnings-worthy pattern.

## Watch-outs

- **Fixing before reproducing.** The most common failure mode. "Fix" without a reproduction loop is a guess that ships untested. The harness step exists precisely for this.
- **Treating `debugger` output as fix instructions.** `debugger` is execute-only and reports diagnosis. The orchestrator decides which substrate layer to repair — sometimes the right fix is editing the bead `--acceptance` (the bug was a misunderstood requirement), not patching code.
- **Skipping ADR-write when the bug surfaces a load-bearing decision.** If the bug means "our assumption about X was wrong," that assumption probably lives in (or should live in) an ADR. `/adr-write` evolves it in place.

## Why this is in recipes

Investigation/bug shape differs from feature shape primarily in *where verification lives* — reproduction first, fix second. Calibrates that ordering against the orchestrator's reflex to fix-then-verify.
