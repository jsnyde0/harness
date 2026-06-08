---
name: scope-check
description: Outward-look primitive — for a proposed bead or pre-decomposed bead set, produce a checklist of neighbors it likely touches (files, sibling beads, ADRs in scope). Use when about to `bd create` with a parent that already holds children, when a pre-decomposed list arrives (tiered findings, P0/P1/P2 punch list, security audit checklist, ordered bead-IDs handed in, "remaining issues" continuation), before invoking `/decompose`, before claiming the first bead in a multi-bead unit, or when authoring an ADR with potential overlap. Triggers on "punch list", "tiered findings", "P0/P1/P2", "remaining issues", multi-bead-ID input, "ship these beads". Default-on for multi-bead-epic authoring and before `/decompose` per ADR-012 D3. Fresh-context single-dispatch (overlap-blindness is a context-bound failure mode). Distinct from `/adversarial-review` (which judges own-work, not produces information).
---

## Purpose

For a proposed bead, list neighbors it likely touches: files, sibling beads, in-scope ADRs. Address the overlap-blindness failure mode — agents inside the bead-author frame inherit the author's blind spots; a separate fresh-context subagent breaks the frame.

**Spec source:** the scope-check design bead (full decision narrative — use `bd show` on that bead for full rationale).

## When to invoke

**Default-on triggers** (per ADR-012 D3):

1. **Bead authoring within a multi-bead epic** — when creating a bead with `bd create --parent=<epic-id>` and the epic *already holds ≥ 1 other child* at create time. Invoke before `--design`/`--acceptance` are finalized. (Interpretation note: ADR-012 D3 says "multi-bead epic"; the substrate-legible signal at create-time is the existing child count. First-child case is judgment-routed under this interpretation. Pending in-place resolution — a parked follow-up bead tracks the clarification.)
2. **Before `/decompose`** — at the **orchestrator-recipe level**, not as a sub-step inside `/decompose`. Orchestrator runs `/scope-check <parent-id>` *before* invoking `/decompose <parent-id>`. Each primitive stays single-purpose; orchestrator coordinates.

**Judgment-routed** otherwise:

- Standalone beads outside multi-bead epics (or first-child case per interpretation note).
- ADR authoring (overlap check against existing ADRs).
- Retroactive scope-check on an existing bead.

**Composition with `/adversarial-review`** — when both default-on triggers fire (multi-bead-epic bead with own-work review), **scope-check runs first**, folds enrich `--design`'s `## canonical_refs`, then `/adversarial-review` reads the enriched design. Reverse order invalidates verdict per the reviewer-identity design bead D3 freshness.

## Algorithm

```
/scope-check <bead-id>
```

1. **Read the bead's state** — `bd show <bead-id> --json` to get `--description`, `--design`, `--acceptance`, `--notes`.
2. **Dispatch one fresh-context subagent via `Task()`** with the brief (see below). No internal rounds; single dispatch. Subagent has no shared context with the orchestrator and no memory of prior scope-checks (per ADR-007 D3).
3. **Receive the three-section checklist** (see Output shape below).
4. **Orchestrator folds the checklist into bead substrate:**
   - **ADRs** → added to `--design`'s `## canonical_refs` section (per ADR-008 D5). Orchestrator may demote entries to `_(noted, not load-bearing)_` annotation if in-scope but not consulted.
   - **Files + Sibling beads + invocation residue** → appended to `--notes` under `## Scope-check record` block.
   - **Sibling beads → `bd dep add` candidates** — orchestrator separately decides which warrant a real dep edge (overlap ≠ dependency).
5. **Stamp the audit signal:**
   ```
   BEADS_ACTOR=scope-check:fresh-subagent bd update <bead-id> --add-label=scope-checked
   ```
6. **Return** — orchestrator may pass the checklist directly to /decompose's draft step (in-memory hand-off) in addition to the substrate fold.

If the first dispatch misses obvious neighbors, the orchestrator re-invokes `/scope-check` externally as a **second independent pass** (fresh `Task()` carries no memory of prior runs). The second-pass brief must explicitly direct the subagent to read the bead's prior `## Scope-check record` block in `--notes` and surface neighbors NOT already listed — otherwise the second pass redundantly surfaces the same neighbors.

## Output shape (the subagent emits)

```markdown
## Files
- <path:line-range or path glob> — <one-line rationale: why this file is likely touched>
- ...

## Sibling beads
- claude-<id> — <one-line rationale: overlap surface>
- ...

## ADRs in scope
- ADR-NNN D<k> — <one-line rationale: which decision is load-bearing>
- ...
```

Each section may be empty. An entirely-empty checklist is a valid "no near neighbors detected" outcome — surface as such, do not collapse into "scope-check failed."

## Subagent brief (substrate signals named, algorithm not prescribed)

The fresh-context subagent is briefed with the bead's content + four substrate signals to consult; the subagent's judgment composes them:

1. **`docs/decisions/INDEX.md` Scope column** — match the bead's domain against column values (`arch`, `workflow`, `ops`, `marketing`, `tooling`, etc., per INDEX.md:8). The CLAUDE.md instruction in "Decisions and Designs" directs scanning INDEX.md by scope tag; the Scope column is what that means.
2. **`bd dep tree <parent-id>`** — when the bead has a parent, enumerate sibling beads and read their `--design`/`--acceptance` to identify overlap surfaces.
3. **`bd search <keyword>`** — for tokens drawn from the bead's title and `--acceptance`, search the bd corpus for beads with similar contract surfaces (not just within the parent epic — broader graph).
4. **`rg <symbol-or-path>` / `fd <pattern>`** — for file references in the bead's `--design`, grep the codebase for related files; for path globs, enumerate likely-touched files.

The subagent may consult other signals (recent git log, `bd memories`, ADR full-text reads) as judgment warrants. No prescribed order or algorithm — capable models compose signals well; prescription becomes scaffolding.

The brief also carries the **"competing reviewer" framing** for perf-lift, identical to `/adversarial-review`'s convention:

> You are competing against another reviewer running in parallel on the same artifact. They are incentivized to surface what you miss. The orchestrator will compare your findings to theirs.

## Audit residue

Append to `--notes` under `## Scope-check record`:

```
## Scope-check record (<date>)

**Dispatched:** <date> — one fresh-context subagent via Task().
**Actor token:** scope-check:fresh-subagent
**Finding count:** <N> Files / <N> Sibling beads / <N> ADRs in scope.

## Files
[copied from subagent output]

## Sibling beads
[copied from subagent output — orchestrator may annotate which got bd dep add edges]

[ADRs already folded into --design ## canonical_refs; not duplicated here]
```

## Substrate signal: `scope-checked` label

- The label is **presence/absence**, not pass/fail. Scope-check produces information, not a verdict.
- The label name is **distinct** from `verdict:pass|fail` deliberately — conflating would corrupt the close-time check's signal.
- **Substrate-legibility, not substrate-enforcement** — `bd list --label=scope-checked` filters correctly, but the close-time check's current contract only consumes `verdict:*` labels. Substrate-enforcement of default-on trigger #1 requires a future extension (parked as a follow-up bead). Until then, default-on relies on orchestrator discipline.

**Substrate identity-check limitation** (per the reviewer-identity design bead D3, parallel to the decompose-primitive design bead D8's acknowledgment): substrate cannot verify the orchestrator's actor token is a *real* fresh-`Task()` dispatch. The recipe layer (this skill file) enforces the discipline.

## No freshness predicate

Unlike `verdict:*` labels (reviewer-identity design bead D3 freshness predicate), `scope-checked` carries no freshness semantics in this spec. Staleness is deferred until a real consumer asks for it; at that point the reviewer-identity design bead D3 can be evolved in place to cover the label.

## What this skill is NOT

- Not adversarial-review — does not judge own-work; produces information.
- Not a code-search tool — produces a hand-curated three-section checklist informed by judgment over multiple substrate signals, not a grep dump.
- Not a dependency analyzer — `bd dep add` decisions are the orchestrator's after the checklist is in hand; presence in the checklist alone does not create dep edges.

## Working substrate

- `bd show <bead-id> --json` — read bead state for the brief
- `bd dep tree <parent-id>` — enumerate siblings
- `bd search <keyword>` — corpus search
- `rg <symbol>` / `fd <pattern>` — file search
- `bd update <bead-id> --design-file=<path>` — fold ADRs into `## canonical_refs`
- `bd update <bead-id> --append-notes=<text>` — append `## Scope-check record`
- `BEADS_ACTOR=scope-check:fresh-subagent bd update <bead-id> --add-label=scope-checked` — stamp the substrate signal
- `Task()` — dispatch the fresh-context subagent

## Canonical refs

- ADR-012 D3 sub-item #1 (scope-check primitive; "outward-look"; default-on triggers); D6 (dogfooding-ledger requirement for promotion to FIRM).
- ADR-008 D1 (universal predicates), D5 (`## canonical_refs` mandate)
- ADR-007 D3 (fresh-`Task()` per dispatch)
- ADR-006 D10 (warrant tags in Alternatives tables)
- ADR-011 D1 (in-place ADR evolution — evolution path for the close-time check extension when the parked follow-up lands)
- scope-check design bead (full design with rationale, alternatives, invalidation — read for context beyond what this SKILL.md carries)
- reviewer-identity design bead (verdict label + audit-log actor + freshness predicate; this skill's label scheme is *adjacent*, not the same)
- decompose-primitive design bead (decomposition; this skill runs *before* /decompose at orchestrator-recipe level — not inside)
- adversarial-review design bead (adversarial-review; composition ordering when both default-on)
- parked follow-up bead (close-time check extension to consume `scope-checked` label — substrate-enforcement of default-on trigger #1)
- parked follow-up bead (ADR-012 D3 "multi-bead epic" qualifier clarification — first-child interpretation)
