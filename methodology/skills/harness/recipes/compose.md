# /harness compose — Author a Harness Target Block for a Bead Scope

## What this recipe is

`/harness compose` is the canonical surface that bead-authoring primitives (`/brainstorm` at convergence, `/decompose` at child authoring) invoke to produce a `## Harness target` section for a specific bead scope. **Single source of truth** — harness principles, fast/slow hierarchies, and the build/connect/configure/reduce taxonomy live here, never inlined into the caller.

The output is a four-predicate block (Signal / Expected green / Rationale / Invalidation) the **caller** then persists to the bead's `--design`. `/harness compose` returns the block; it does not write to bead substrate.

**Provenance note (2026-06-01).** The bead-authoring subcommand mandate's Rationale references a soldier-proof pass on `/harness compose` from 2026-04-23 covering all HOW modes and both inventory branches. That coverage applies to the *principles* encoded across harness/SKILL.md (methodology home) and `recipes/quick.md` (the parent skill's review criteria, fast/slow hierarchy, and inventory-first discipline). The **four-predicate output contract** (Signal / Expected green / Rationale / Invalidation) is a binding structural predicate — it was binding before this file existed, but its packaging as a callable-subcommand output contract is new in this 2026-06-01 re-exposure and was NOT within the 2026-04-23 soldier-proof scope. A soldier-proof pass on this specific recipe shape (subcommand-contract framing + the inputs/return-value shape + caller-persists discipline) is named as future work. Until then: the four-predicate structure is binding, the HOW-mode and inventory principles are binding via SKILL.md/quick.md, but the subcommand-call ergonomics are untested under pressure — surface friction back as drift signals.

## Inputs the caller passes

- **Bead scope** — title + `--design` excerpt + `--acceptance` for the bead the block is being authored for. For a `/decompose` child: also the parent's `--design` + `## Harness target` so conjunction-coverage can be reasoned about.
- **Authoring mode** — `brainstorm-convergence` (single-bead) or `decompose-child` (one of N children).
- **Inventory context** — `.claude/harness.md` if present in the project; the caller already consulted it for the unit-level harness, so cite the same entries here when they apply.

## What to do

### Step 1: Re-orient against substrate

Same inventory-first discipline as `/harness`: read `.claude/harness.md` if present, plus any `bd memories` already loaded by the caller's prior `/recall`. The caller is responsible for substrate orientation at the unit level; this recipe's job is to keep the block aligned with what was already surveyed, not to re-survey from scratch.

### Step 2: Identify the goal-faithful signal

What observable would fail if this bead's intended outcome is NOT met, and pass when it is? Alignment is load-bearing per the harness review criteria — a test suite that passes even when the integration is wired wrong is misaligned; a linter check on a bead whose intent is behavioral change is misaligned.

**The Signal is a partial proxy, not proof.** It's the *hillclimbing gradient* an implementer iterates against — the fast, executable stand-in for the bead's intent. It is necessary, not sufficient: the bead's acceptance usually carries prose ("the error is actually helpful," "the abstraction doesn't leak") that no Signal can capture. That prose remainder doesn't disappear because it's unautomatable — done is `harness green AND acceptance met`, a conjunction. Author the Signal as the best available proxy, and name what it leaves uncovered (in the Rationale) so the reviewer knows what to judge by hand. Do not frame the Signal as if green meant done.

For `decompose-child` mode: the child's signal must address at least one dimension of the parent's signal. Note which parent-signal dimension this child covers — the caller's conjunction-coverage probe (in `/decompose`) compares the union of children's signals to the parent's signal, and that probe relies on each child's signal being scoped concretely enough to compare.

### Step 3: Pick the altitude

Fastest-deterministic signal that captures the bead's intent. The hierarchy from the parent skill applies:

```
FAST / DETERMINISTIC SLOW / SEMANTIC
───────────────────────────────────────────────────────────────────→
compile → typecheck → lint → unit test → integration → E2E → LLM judge → human
```

For `decompose-child`: a child whose signal sits at a coarser altitude than the parent's (parent: integration; child: unit on the same module) is fine — children compose. A child whose signal is at the **same** altitude as the parent (parent: integration test X; child: same integration test X) is a smell — that's not decomposition coverage, it's duplication.

### Step 4: Write the four-predicate block

Return exactly this shape (markdown), populated:

```
## Harness target

**Signal:** <concrete observable — name the command, file, region, or runtime check>
**Expected green:** <what the signal looks like when this bead is done — binary, observable>
**Rationale:** <why this altitude best captures the design intent; cite `.claude/harness.md` entry if used; for decompose-child, name which parent-signal dimension this covers; **name what this Signal does NOT cover** — the prose acceptance it can't reach — so the reviewer knows what to verify by hand (per harness-designer's "what this harness will NOT catch")>
**Invalidation:** <qualitative cue an agent or human applies in the moment — "watch for X surfacing in practice; if it does, tighten Y" shape. Signal-shaped invalidation is the hard rule: no numeric thresholds unless paired with named active instrumentation (a scheduled job, hook, `bd` query, or harness check) that actually collects the data AND an agent or human routinely reads the collected data — unbacked numeric thresholds are falsifiability theater.>
```

Trivial work may use a named-skip-with-rationale that still occupies all four fields (e.g. Signal: `none — mechanical rename`, Rationale: `the diff IS the verification`). Named skip ≠ empty field.

### Step 5: Return — do not write

Hand the block back to the caller (`/brainstorm` or `/decompose`). The caller persists:

- `/brainstorm` at convergence — appends the block to the bead's `--design` in the `bd create --design=...` call.
- `/decompose` at child authoring — appends the block to each child's `--design` in the child's `bd create --design=...` call (step 6 of the decompose algorithm).

**Persistence is load-bearing.** A `## Harness target` block that lives only in the orchestrator's working context is the canonical failure mode (2026-05-26 send-it session: harness-target headings drafted ten times in transcript, persisted to zero of sixteen children). The caller's responsibility is to ensure the block reaches the bead's `--design`; `/harness compose` cannot enforce that from inside the recipe.

## Review criteria reminder

The block this recipe returns is graded by the harness review criteria in the parent SKILL.md when `/adversarial-review` runs on the tree (or single bead). Apply them in order while drafting:

1. **Alignment** — Signal is goal-faithful.
2. **Presence** — all four fields populated (named-skip OK for trivial).
3. **Falsifiability** — Signal + Expected green form a binary observable.
4. **Fit vs inventory** — if `.claude/harness.md` names a faster goal-faithful signal at the same altitude, use it and cite.
5. **Rationale + Invalidation populated** — not templated.
6. **Conjunction coverage** (decompose-child mode) — Rationale names the parent-signal dimension this covers; the caller's conjunction probe checks union completeness.

## What this recipe is NOT

- Not `/harness` — that composes a *task-level* harness (2-5 mechanisms for an iteration loop). This authors a single `## Harness target` block at *bead scope* for the bead-authoring primitive's contract.
- Not `/harness audit` — that builds the project inventory; this consumes it.
- Not the persistence step — the caller persists to `--design`.

## Canonical refs

- Parent SKILL.md "Harness target review criteria" — the six-point grading the returned block will face.
