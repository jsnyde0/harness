# Sharpen convergence — worked examples

Per-slot frozen-vs-dispatched calibration for Phase B Step 6 convergence.

## Example A — savings appear when sweep keeps finding issues past the floor (3 slots, N=2)

- Pass 1: dispatch P1, P2, P3 (all K_slot 0→1). Sweep flags P2 only.
- Pass 2: P1 K_slot=1 below floor → dispatch. P2 below floor AND flagged → dispatch. P3 below floor → dispatch. (At-floor pass costs nothing extra.) After: all K_slot=2. Sweep flags P2 again.
- Pass 3: P1 K_slot=2 ≥ N AND sweep-clean → **frozen, no dispatch**. P2 ≥ N but flagged → dispatch. P3 K_slot=2 ≥ N AND sweep-clean → **frozen, no dispatch**. Only P2 runs.
- Continue until P2 sweep-clean, then converge.

## Example B — savings appear immediately when `--N=1` (3 slots)

- Pass 1: dispatch P1, P2, P3. Sweep flags P2 only.
- Pass 2: P1 K_slot=1 ≥ N AND sweep-clean → **frozen**. P2 ≥ N but flagged → dispatch. P3 K_slot=1 ≥ N AND sweep-clean → **frozen**. Only P2 runs.
- Continue.

## When the savings compound

The N=2 default still pays a one-pass floor tax on clean slots; the savings compound only when sweep keeps finding issues past the floor or when the caller passes `--N=1`. Both cases are common in practice on epics with one dominant problem slot.
