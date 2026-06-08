---
name: decompose
description: Split a bead into children whose `--acceptance` conjunction satisfies the parent. Use when a bead's acceptance reads bigger-than-atomic — spans multiple test surfaces, multiple ADR scopes, or multiple file regions — and the countermand test ("would the user countermand me proceeding without decomposing?") reads plausible. Use BEFORE first execution dispatch on any non-atomic bead. **Do NOT use when input is already pre-decomposed** (tiered findings, P0/P1/P2 punch list, ordered bead-IDs handed in, "remaining issues" continuation) — that's `/scope-check` territory; re-decomposing pre-decomposed input is the canonical recipe leak. One-shot orchestrator draft + default-on whole-tree adversarial-review. Composes `/scope-check` (called before) and `/adversarial-review` (called on the proposed tree). Distinct from beadify-v2 (heavy 4-phase reference composition).
---

## Purpose

Take a bead whose contract is too large to execute in one shot and split it into a child-bead tree whose `--acceptance` conjunction satisfies the parent. The substrate-thick alternative to beadify-v2's Scout/Refiner/Critic/Materialize choreography — one-shot orchestrator draft, then default-on whole-tree adversarial review (the "Critic" equivalent), then materialize.

**Spec source:** the decompose-primitive design bead (full decision narrative — use `bd show` on that bead for full rationale).

## When to invoke

The orchestrator decides whether to invoke `/decompose` vs execute the bead directly via the **countermand test**:

> *"Would the user countermand me if I proceed to execute this bead in one shot without decomposing?"*

If the imagined countermand reads plausible, decompose. Anchor questions for self-prompting (not gates):

- *"This is one atomic action"* — if you can't honestly assert this, countermand is plausible.
- *"All end-states are tested together"* — if the parent's `--acceptance` predicates split across distinct test surfaces, countermand is plausible.
- *"One reviewer can see this whole change"* — if implementation spans too many surfaces for a single reviewer to audit, countermand is plausible.
- *"Decisions belong to one ADR scope"* — if multiple load-bearing ADRs own different parts, countermand is plausible.

Mechanical thresholds (bullet counts, action counts) are explicitly rejected. The countermand-test scales with orchestrator capability.

**Default-on for scope-check before this skill** — per the scope-check design bead D5: orchestrator runs `/scope-check <parent-id>` *before* `/decompose <parent-id>`. The checklist feeds the file-claim map, sibling-dep candidates, and per-child canonical_refs. Composition lives at orchestrator-recipe level, NOT as a sub-step inside this skill.

## Algorithm

```
/decompose <bead-id>
```

A single invocation runs:

1. **Read parent's state** — `bd show <bead-id> --json` to get `--design`, `--acceptance`, `--notes` (including any prior `## Scope-check record` block).

2. **One-shot orchestrator draft** — orchestrator drafts the child-bead tree in its own context (or `/tmp/decompose/<bead-id>.md` if narrative is long):
   - Per-child: title (verb-first imperative), `--acceptance` (falsifiable), `--design` (non-empty if child carries non-trivial decisions), inter-child `bd dep add` edges.
   - **Per-child `## Harness target` block — apply the `/harness compose` recipe (mode: `decompose-child`) for each child: consult harness/recipes/compose.md (methodology home) and author the four-predicate block against its output contract, then append it verbatim INTO that child's draft `--design` payload (the literal text destined for `bd create --design=...` at step 6).** `/harness compose` is a recipe you consult, not an executor that hands back finished block text — invoking the skill routes you to the recipe, and authoring the block *per that recipe* IS the compliant path. The failure mode being closed is drafting the block **from memory without consulting the recipe** (which forks harness thinking away from the canonical surface) — NOT authoring it per the recipe. `/harness compose` is the canonical surface per ADR-005 D7 (FLEXIBLE, revised 2026-05-22) precisely so improvements to harness thinking flow automatically to every authoring primitive.
   - **`## Harness conjunction-coverage probe` — after all children's harness target blocks are drafted, run an explicit coverage probe on the parent's harness target: *"What observable behavior could fire on the parent's harness target without firing on any child's harness target?"* Name each uncovered behavior explicitly. If none exist, state: "none — full conjunction coverage" PLUS enumerate the parent's signal dimensions and confirm each is addressed by at least one child's signal. A probe that produces only "none" without listing what was checked is not a real probe. Place the probe block in the orchestrator draft AND in the step-9 `--notes` payload (the literal text destined for `bd update --append-notes=...`).** Per ADR-005 D7's conjunction-coverage clause and ADR-012 D3 line 106-107.
   - A `## Coverage map` table: parent `--acceptance` bullet ↔ child slot ID(s) (per ADR-010 D9, FIRM carry-forward).
   - A `## File-claim map` table: child slot ID ↔ file globs (per the decompose-primitive design bead D4 #6, derived from scope-check's Files section if available).

3. **Leaf path check** — if the orchestrator judges no decomposition is warranted (the bead really IS one atomic action), return "no-split-needed" with a one-line rationale. Append a `## Decomposition record (leaf-path)` block to parent's `--notes` recording the invocation, rationale, and "no-split-needed" outcome. No children created. No verdict stamp. Exit.

4. **Call `/adversarial-review`** on the **whole proposed tree** — pass the brief:
   - Parent's `--design` + `--acceptance`
   - The proposed tree (every child's title / `--acceptance` / `--design` / dep edges)
   - The coverage map and file-claim map
   - **Decomposition-specific DoD** (caller's responsibility — the nine checks below)
   - Universal-rigor brief (carried by `/adversarial-review`)

5. **Fold findings** per the standard /adversarial-review loop. Apply fold-ins to the *draft* (not yet materialized).

6. **Materialize-after-review** — only after `/adversarial-review` returns convergence:
   - `bd create --type=<type> --title="<title>" --parent=<bead-id> --design="<design>" --acceptance="<acceptance>"` per child. **The child's `## Harness target` block (authored at step 2 via `/harness compose`, reviewed at step 4) MUST be included in the `--design` payload** — a child materialized without its harness target block in `--design` is a transcript-only-persistence failure (harness target drafted but never persisted to substrate). Reviewer's check #10 below grades against the materialized bead, not the draft.
   - `bd dep add <child-A> <child-B>` for every inter-child edge.
   - `bd dep add <integration-test-bead> <each-sibling>` for the integration-test bead (per ADR-005:10 carry-forward) if N ≥ 2 children whose work cross-references.
   - On each child, append a `## Origin` block in `--notes`: `## Origin: /decompose <parent-id> round <N>` + link-back to parent's `## Decomposition record`.

7. **Post-materialize graph verification** (per ADR-010 D11, FIRM carry-forward) — run these commands:
   - `bd dep tree <parent-id>` — verify expected child list.
   - `bd dep cycles` — verify no cycles introduced.
   - `bd list --parent=<parent-id>` — verify count matches draft.
   - If any verification fails, do NOT stamp `verdict:pass`; set `waiting:human` instead.

8. **Stamp the verdict on parent** (per the decompose-primitive design bead D8 — stamp-after-materialize for atomicity, not freshness). **Dual-write** (label + audit record, same `BEADS_ACTOR`) so the close-time check can read the actor and timestamp from `interactions.jsonl`:
   ```bash
   BEADS_ACTOR=reviewer:fresh-subagent bd update <bead-id> --add-label=verdict:pass
   echo '{"kind":"verdict","issue_id":"<bead-id>","extra":{"verdict":"pass"}}' \
     | BEADS_ACTOR=reviewer:fresh-subagent bd audit record --stdin
   ```
   See `/adversarial-review`'s "Verdict dual-write" section for the why — `bd label add` does not log `--actor`. For ceiling-hit (`verdict:fail`) or post-materialize verification failure (`waiting:human`), same pattern with the appropriate label; `waiting:human` does NOT need the audit-record dual-write (not a verdict).

9. **Append `## Decomposition record` + `## Harness conjunction-coverage probe` to parent's `--notes`** — same `bd update --append-notes=...` call writes both. The decomposition record carries: children created, coverage map, adversarial-review round count, exit reason. The conjunction-coverage probe carries: parent-signal dimensions enumerated, which child(ren) cover each, and any uncovered behavior (or "none — full conjunction coverage" with the enumerated dimensions as evidence). **Persisting the probe to `--notes` (not just orchestrator draft) is load-bearing per the failure-mode addressed by DoD check #10** — a working-context-only probe is the same transcript-only-persistence failure as transcript-only harness targets.

## Harness-target authoring — ADR-005 D7 surface

The authoring imperatives (invoke `/harness compose` per child; run + persist the conjunction-coverage probe) live in step 2 of the algorithm above. This section is conceptual context, not a competing instruction source.

**Why `/decompose` invokes `/harness compose` rather than inlining** — ADR-005 D7 (FLEXIBLE, revised 2026-05-22): "Inlining principles would duplicate logic and fork maintenance. Invoking the skill means harness improvements automatically reach all authoring primitives." `/harness compose` is the soldier-proofed canonical surface (2026-04-23). The same mandate applies to `/brainstorm` at convergence per ADR-005 D7; as of 2026-06-01 `/brainstorm/SKILL.md` still inlines the predicates — that parallel-gap fix is named in commit `d5c40ae`'s body as a separate substrate change, not addressed here.

**Why both the child harness target and the conjunction-coverage probe must reach substrate** — a 2026-05-26 failure-mode (harness targets drafted in transcript, never persisted): harness-target headings drafted ten times in transcript, persisted to zero of sixteen children. Working-context-only artifacts pass per-bead review, vanish at materialize, and surface only as ADR-violation drift at parent re-verify (see `parent-re-verify-catches-conjunction-drift` memory). The step-2 imperatives + DoD check #10 + step-6 `--design` requirement + step-9 `--notes` requirement together close the failure surface end-to-end.

**Canonical refs:** ADR-005 D7 (subcommand-invocation mandate + conjunction-coverage clause); ADR-012 D3 line 106-107 (children-jointly-cover-parent rule).

## Decomposition-specific DoD (passed to /adversarial-review as caller-brief data)

1. **Conjunction-completeness via the coverage map** — children's `--acceptance` predicates, conjoined, satisfy parent's `--acceptance`. Reviewer flags any parent bullet not covered or any redundant overlap, using the coverage map as evidence. (Checks #1 and #3 are the same check viewed from two angles — #1 is the rigor obligation, #3 is the auditable artifact.)
2. **No-overlap** — no two children claim the same end-state.
3. **Coverage map present, formatted, in-brief** (ADR-010 D9 carry-forward, FIRM).
4. **Parent-first hierarchy** — each child uses `bd create --parent=<parent-id>`; no orphan beads (ADR-005:10 carry-forward).
5. **Integration-test bead for multi-child trees** — if N ≥ 2 children cross-reference, a final child of `type=task` or `type=test` depending on all siblings carries the cross-component verification (ADR-005:10 carry-forward).
6. **File-conflict detection** — no two children claim ownership of the same file/region (ADR-005:10 carry-forward). Orchestrator's draft must include a `## File-claim map` section; reviewer flags any overlap.
7. **Leaf path first-class** (ADR-010 D12 carry-forward, FIRM) — "no-split-needed" is a valid outcome with its own audit residue.
8. **Per-child `--design` non-empty when child carries non-trivial decision** — trivial children may have empty `--design`; non-trivial must record ADR-008 D1 predicates.
9. **Inter-child `bd dep add` edges declared** — any ordering dependency between children is encoded in deps.
10. **Harness conjunction-coverage probe + per-child harness target present in their persistence payloads** — graded on the literal text destined for substrate, not on transcript narration. Required:
    - (a) Each child's draft `--design` payload (the literal text that will be passed to `bd create --design=...` at step 6) contains a `## Harness target` block with all four predicates populated (Signal / Expected green / Rationale / Invalidation per ADR-012 D3; named-skip-with-rationale satisfies presence for trivial children).
    - (b) The step-9 `--notes` payload (the literal text that will be passed to `bd update --append-notes=...` at step 9) contains a `## Harness conjunction-coverage probe` block.
    - (c) The probe block enumerates the parent's signal dimensions and names which child(ren) cover each (or names uncovered behavior). A bare "none" without dimension enumeration fails the check.
    - (d) Every parent signal dimension is covered by at least one child's `## Harness target` block.

    Reviewer flags if any of (a)–(d) fail. Transcript-only artifacts — blocks that appear in narration but not in the `--design` / `--notes` payload destined for `bd create` / `bd update` — are the transcript-only-persistence failure this check exists to close.

## Three-state exit (mirrors /adversarial-review's exit on the parent bead)

| Exit state | Skill action |
|---|---|
| **Convergence** | Materialize children → stamp `verdict:pass` on parent (after materialize) → return. |
| **Ceiling-hit** (3 review rounds without convergence) | `verdict:fail` on parent. No materialize. Orchestrator escalates. |
| **Raise** (FIRM-ADR contradiction in review) | `waiting:human` on parent. No verdict. No materialize. User input required. |
| **Leaf path** (no decomposition warranted) | `## Decomposition record (leaf-path)` block in parent's `--notes`. No children. No verdict stamp. |
| **Post-materialize verification fails** | `waiting:human` on parent. No `verdict:pass`. Orchestrator escalates. |

**Stamp-after-materialize is for atomicity** (per the decompose-primitive design bead D8, F1 fold-in): if materialize fails mid-way, the parent is not left with `verdict:pass` but no children. *Not* a freshness reason — `bd create --parent` does not mutate parent's `updated_at`. (Note: the close-time check uses bead `updated_at` as a conservative proxy for "the bead changed since verdict" — any post-verdict mutation, not just `--design`/`--acceptance`, marks the verdict stale. That's strictly broader than the reviewer-identity design bead D3's original wording but never under-strict.)

## Substrate identity-check limitation (acknowledged-not-fixed)

Per the decompose-primitive design bead D8: the close-time check compares verdict-add actor against the bead's *create-event actor*. For decomposition, the artifact being reviewed is the proposed tree drafted by the *current orchestrator*, but the verdict gets stamped on the *parent bead* whose create-event actor is typically unrelated (the user, or an earlier brainstorm session). So the substrate check passes trivially without actually verifying "reviewer ≠ decomposition-author." The recipe layer (this skill file) carries the discipline. A stronger substrate fix would require a first-class "decomposition draft" bead — out of scope; named as future-work.

## Audit residue

Append to parent's `--notes` under `## Decomposition record` (for convergence path) or `## Decomposition record (leaf-path)` (for leaf path):

```
## Decomposition record (<date>)

**Invoked:** <date>
**Children created:** <list of new bead IDs with titles>
**Coverage map:** [reproduced or linked to draft]
**Adversarial-review rounds:** <count>
**Exit reason:** [convergence | ceiling | raise | leaf-path | post-materialize-fail]
**Limitations acknowledged:** [substrate identity-check limitation per the decompose-primitive design bead D8 — recipe-layer discipline carries it]
```

## What this skill is NOT

- Not beadify-v2 — no Scout/Refiner/Critic/Materialize four-phase choreography. Beadify-v2 (beadify-v2/SKILL.md in the methodology home) remains as a heavy reference composition; this skill is the substrate-thick replacement.
- Not /scope-check — that runs *before* this skill at the orchestrator-recipe level, not inside it.
- Not /adversarial-review — that's the convergence sub-step; this skill *calls* it.
- **Not the end of the work.** After step 9 (`## Decomposition record` in parent notes + verdict stamp), control returns to the caller (typically `/send-it`). The next loop iteration walks the materialized children per Pattern B. Treating the `## Decomposition record` block as a stopping point — pausing for user confirmation before walking children — is the framing-layer absorption flagged in `/send-it`'s anti-patterns ("Pausing after fan-out for confirmation").

## Working substrate

- `bd show <bead-id> --json` — read parent state
- `bd create --type=<t> --title="<title>" --parent=<bead-id> --design="..." --acceptance="..."` — materialize children
- `bd dep add <child-A> <child-B>` — inter-child edges
- `bd dep tree <bead-id>` / `bd dep cycles` / `bd list --parent=<bead-id>` — post-materialize verification
- `bd update <bead-id> --append-notes=...` — audit residue
- `BEADS_ACTOR=reviewer:fresh-subagent bd update <bead-id> --add-label=verdict:pass` — verdict label (UX echo). **Pair with `bd audit record --stdin` per step 8 — load-bearing for the close-time check.**
- `echo '{"kind":"verdict","issue_id":"<id>","extra":{"verdict":"pass"}}' | BEADS_ACTOR=reviewer:fresh-subagent bd audit record --stdin` — audit-record half of the dual-write
- `/adversarial-review <bead-id>` — the embedded convergence sub-step
- `Task()` — fresh-context dispatch (handled by /adversarial-review internally)

## Canonical refs

- ADR-012 D3 (decomposition primitive; default-on tree review for own work); D6 (dogfooding-ledger)
- ADR-008 D1 (universal predicates), D5 (`## canonical_refs` mandate)
- ADR-007 D3 (fresh-`Task()` per round — inherited via /adversarial-review)
- ADR-009 D4 (depth cap=3 FLEXIBLE — ambient guidance for recursive decomposition)
- ADR-010 D9 (coverage map mandatory, FIRM carry-forward), D11 (post-materialize graph verification, FIRM carry-forward), D12 (leaf path first-class, FIRM carry-forward)
- ADR-005:10 (carry-forward enumeration from D9's supersession: parent-first hierarchy, integration-test rule, file-conflict detection)
- ADR-006 D10 (warrant tags in Alternatives tables)
- decompose-primitive design bead (full design with rationale, alternatives, invalidation predicates — read for context beyond what this SKILL.md carries)
- adversarial-review design bead (adversarial-review — this skill calls it; brief format and verdict-stamp scheme)
- scope-check design bead (scope-check — orchestrator runs it before this skill at recipe level)
- reviewer-identity design bead (verdict label + audit-log actor + freshness predicate)
- close-time verdict design bead (downstream close-time consumer of verdict labels)
