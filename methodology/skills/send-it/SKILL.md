---
name: send-it
description: Substrate-thick orchestrator that drives a unit of work toward its acceptance contract by composing primitives + subagents in judgment. Inputs: bead id, free-text prompt, or design ref. There is no fixed pipeline — the orchestrator's loop is "is acceptance met? if not, which substrate layer is wrong, and which primitive repairs it?" Raises (does not auto-resolve) FIRM ADR conflicts, ambiguous scope, and repeated failure without substrate change.
---

## Premise

The orchestrator-identity layer — "you are the brain of this loop / context is the scarce resource / default is dispatch / failure mode is silent absorption" — is **main-session default**, injected at session start as the "brain of loop" framing. Treat that framing as already-loaded; this skill assumes it.

What `/send-it` adds on top of the default posture: **a specific loop to drive a unit of work toward its `--acceptance` contract.** Primitives are **validators** (what does substrate not yet satisfy?) and **repair tools** (which substrate layer needs to change?). Loop until acceptance holds or you hit a raise condition.

The `absorbing-work` anti-pattern (below) applies during the loop too — if you're about to Edit/Write multi-line code or run a primitive's logic in your own head when a subagent equivalent exists, halt and dispatch.

This skill is intentionally short. The substrate (primitives, subagents, ADRs, bead) carries the load; orchestration is judgment, not recipe.

## Precondition — `/recall` before sinking in

Before composing primitives against this unit, ensure `/recall` has tier-routed across L3 ADRs / L2A CASSMS / L2B bd memories / skills for *this unit* in *this session window*. If it hasn't, run `/recall` first. `/scout-adrs` alone covers L3 only — three of four substrate layers stay dark, which is the silent-absorption failure mode at sink-in time. Self-judge from conversation state ("have I pulled `bd memories` / `cm context` against this unit yet?"); if yes, skip — don't re-run. No external mechanism enforces this; the gate is the orchestrator's.

## Inputs

One of:

- **`<bead-id>`** — work already framed; pick up the bead's `--design` / `--acceptance` / `--notes`.
- **`<free-text prompt>`** — no bead yet; frame the work first (probably `/scout-adrs` + `/scope-check` + `bd create`, or a heavier `/brainstorm` path if the shape is genuinely unclear), then ship.
- **`--design <path>`** — design narrative outside beads; create the bead from it, then ship.

## "Shipped" means

- Bead (or epic) `closed`, all children `closed`.
- **`--acceptance` contract met — two-part conjunction :**
 - (a) Prose acceptance bullets each observable-green — every stated condition verifiably satisfied.
 - (b) `## Harness target` Signal green per the bead's Expected-green criterion — OR a one-line named skip with rationale (trivial-work exemption : "trivial — no harness needed; \<rationale\>"). Non-trivial work without an explicit harness target or named skip fails part (b). No implicit-skip path for non-trivial work.
 - Both (a) AND (b) must hold. Prose-met + harness-absent on non-trivial work is not shipped.
- No FIRM ADR silently contradicted. Load-bearing decisions taken along the way have landed in the appropriate ADR via `/adr-write` ( in-place).

## The loop — composition, not pipeline

Each primitive answers a different question. The orchestrator's inner loop:

1. **What does substrate not yet satisfy?** Re-read the bead's `--acceptance` after each primitive completes. Acceptance is the **active arbiter**, not a final-check artifact.
2. **Which substrate layer is the gap in?** Bead `--design`? `--acceptance`? Tree decomposition? Harness? ADR? Leaf code? See *Diagnostic ladder* below.
3. **Which primitive moves substrate toward acceptance?** Compose the cheapest fit.
4. Repeat until acceptance holds.

**Tighten the bead, don't patch the trajectory.** When drift surfaces, the move is `/adr-write` or edit the bead — never inline workarounds.

## Two composition patterns cover almost everything

Compose by judgment; don't try to identify "which pattern this is" before starting.

**A. Validate → repair → re-validate.** The inner loop. Acceptance not met → diagnose which layer is wrong → repair via the matching primitive → re-check acceptance. Goal-pursuit shape.

Loop predicate (pseudo-code — the two conditions are HARD exits, not soft recommendations):

```
loop:
 prose_met = all --acceptance bullets observable-green
 harness_ok = (## Harness target Signal green per Expected-green)
 OR (one-line named skip with rationale present AND work is trivial)

 if prose_met AND harness_ok:
 exit loop ← acceptance met; proceed to close
 else:
 diagnose which layer is the gap (prose? harness? decomposition? ADR? leaf code?)
 repair via matching primitive
 re-validate (back to top of loop)
```

**`prose_met AND harness_ok` is the only exit predicate.** A loop iteration that exits with `prose_met=true` but `harness_ok=false` on non-trivial work is a loop bug — the harness check is not a post-loop advisory, it is an equal-weight exit condition. If the harness target is absent on non-trivial work, the repair move is: `/harness` compose the target, add it to the bead's `--design`, then re-validate. The trivial-work named-skip is the only legal path through part (b) without a green signal (, ).

**B. Frame → fan-out → re-verify-at-parent.** The epic shape. Scope → decompose → adversarial-review the tree → walk children (each runs pattern A) → parent dispatches `adversarial-reviewer` (fresh subagent) over the cumulative diff against the parent's `--design` + `--acceptance` + cited ADRs, for conjunction-drift detection . The fresh-context dispatch is load-bearing — orchestrator-internal re-check cannot see drift that only surfaces across the children's composition.

Concrete worked examples in `recipes/` — illustrations of how the patterns fit specific situations, not templates to match-and-execute. The substrate decides done-ness; recipes are inspiration.

## Primitives in the toolkit

Compose by judgment. None mandatory; none forbidden.

- **`/recall`** — inward-look prospective orientation. Tier-routes a substrate query across L3 ADRs / L2A CASSMS / L2B bd memories / skills before sinking into work. **Default-on at start of non-trivial work** per CLAUDE.md "Substrate orientation". Read counterpart to `/compound`; addresses the silent-absorption failure mode at sink-in time.
- **`/scout-adrs`** — cheap haiku read of `docs/decisions/INDEX.md` + canonical_refs. Almost always worth running when work touches design surface. Subsumed by `/recall` at start-of-work; invoke standalone for mid-loop ADR re-scout (e.g., after scope drift during `/brainstorm`).
- **`/scope-check`** — outward-look neighbor enumeration for a bead being authored. Default-on for multi-bead-epic authoring .
- **`/decompose`** — split a bead into children whose acceptance conjunction satisfies the parent. Output includes a `## File-claim map` that gates parallel fan-out.
- **`/adversarial-review`** — fresh-context review. Default-on for own work — dispatch `adversarial-reviewer` (subagent) on any design / decomposition / plan / impl you produce, or inherit and build on (an epic handed to `/send-it`, a `/brainstorm` bead you're about to decompose), before acting on it.
- **`/adr-write`** — author or evolve an ADR. Compose when a load-bearing decision surfaces that isn't yet canonical.
- **`/harness`** — design the feedback loop; consult before implementation if no obvious target exists.
- **`/compound`** — inward-look retrospective. **Default-on at epic close ** — fires BEFORE any hand-rolled closing summary, retrospective message, or "wrap-up." Triggers: last bead in a multi-bead unit closes; `bd close` on a parent with closed children of `type=epic`; you're about to write a unit-close message. The closing summary is downstream of `/compound`, not parallel to it.

Execution itself is a judgment call, not a primitive. Available moves:

- Dispatch `implementer` for fresh-context TDD on a non-trivial leaf bead. **Default for non-trivial execution.**
- Drive the change directly with TDD discipline when the work is trivial (typo, single config line, mechanical rename) and your context is already aligned.
- Dispatch a different specialist (see *Subagents* below).
- For a parent/epic: walk children per pattern B.

## Subagents in the toolkit

| Agent | Use when |
|---|---|
| `implementer` | TDD on a non-trivial leaf bead; the default execution shape |
| `reviewer` | Quality/correctness review on a diff |
| `code-reviewer` | Review with bundled close + commit |
| `debugger` | Stuck — need fresh-context root-cause; orchestrator folds the diagnosis |
| `adversarial-reviewer` | Fresh-context review of your own design / decomposition / plan / impl |
| `harness-designer` | Big tree (~10+ descendants) or churning leaf — fresh-context target design |

See subagents/SKILL.md (methodology home) for dispatch discipline (fresh-context preservation, execute-only contract, parallel-OK iff disjoint file-claims).

## Diagnostic ladder — when something fails, which substrate layer is wrong?

When a primitive returns failure (REVISE/REJECT, BLOCKED, test-flake, drift, repeated retry-without-progress), don't reach for the same primitive again. Diagnose the layer:

| Symptom | Layer wrong | Repair move |
|---|---|---|
| Tests pass but acceptance not met | Acceptance under-specified | Edit bead `--acceptance` |
| Implementation drifts outside scope | Scope wrong | Edit `--design`; re-scope; consider `/scope-check` |
| Implementation needs files outside its claim | Decomposition wrong | `/decompose` re-run on parent |
| Tests flake / pass-then-fail / can't reproduce | Harness wrong | `/harness` redesign; `harness-designer` if epic-level |
| Bead implements a decision that turned out wrong | ADR wrong | `/adr-write` evolve in place, then re-scope the leaf |
| Acceptance unclear; can't form binary done/not-done | Scope ambiguous | **Raise to user** |

For hard diagnoses, dispatch `debugger`; it reports root cause, orchestrator decides the repair layer.

**Retry-without-substrate-change is the anti-pattern.** The signal is "I am dispatching the same primitive without anything in the substrate having changed." Once is fine; twice is a smell; more is thrashing. Apply the diagnostic ladder before retrying; raise when no layer-change avenue is open. Substrate change between attempts is normal loop behavior, not thrashing.

## Walk-children — fan-out discipline

When walking an epic's children:

- **Scoping review BEFORE the first child dispatch.** Default-on for any multi-bead unit. **Trigger shapes** (these are the cue, not a bypass): input arrives as bead-IDs already authored ("ship these three beads: A, then B and C"); a tiered punch list / security findings / P0-P1-P2 checklist / "remaining issues" continuation hands you a pre-decomposed set; a parent bead's `--acceptance` / `--design` enumerates ≥3 items that each map to distinct work surfaces; you're about to claim the first bead in a multi-bead unit. Dispatch `adversarial-reviewer` on the bead set itself — boundaries, ordering, missing items, dependency edges — *not* on each item's content. This is a different beat from impl-review and runs at a different time; impl-review reviews the diff, scoping-review reviews the plan. Skipping it because each item is "small" is the failure mode: items can be small while the scoping is wrong.
- **Pre-decomposed input still needs child beads.** When `/decompose`'s algorithmic decomposition is correctly skipped via its pre-decomposed carve-out (acceptance items, punch list, bead-IDs handed in), the alternative is **author one child bead per pre-decomposed item** — not map "item N → one implementer dispatch" in your own head. Per-item child beads carry the parent re-verify substrate, the `adversarial-reviewer` scoping target, the audit residue, and the future-session resumability that a silent dispatch-loop discards. Skipping decomposition is not skipping child-bead authorship.
- **Serial** when children have dependencies on each other's outputs, OR when no `## File-claim map` exists, OR when claims overlap.
- **Parallel** when children are independent AND their `## File-claim map` slices are pairwise disjoint. Dispatch all in one message; collect; review each. Per .
- **Parent re-verify after all children close** — default-on for any epic with children. Dispatch `adversarial-reviewer` (fresh subagent) over (a) the cumulative diff in the close-window, (b) the parent's `--design` + `--acceptance` + cited ADRs, (c) closed children's `--design` decision-substrate. The job is **conjunction-drift detection**: ADR-contract violations, canonical-vocabulary divergence (enum-value drift, status-value drift), and silent gaps that only become visible when the children compose against the parent's substrate — *not* re-running per-child acceptance (already done at each child's close, and structurally blind to cross-child drift). Any FAIL → file a discovered-from child ; re-walk. Per . Skip only by naming the trivial-shape that makes it ok (trivial epic, single-child epic where the child IS the epic, mechanical-only diff with no ADR surface) — same discipline as the trivial-work exemption elsewhere in this skill; "feels small" doesn't count, and arbitrary count thresholds (≥3 children, etc.) are recipe leak. Canonical failure case where per-bead-green hid 4 substantive ADR-contract bugs across the conjunction: `bd memories parent-re-verify-catches-conjunction-drift`.

## Raise conditions (do not auto-resolve)

Halt and surface when:

1. **FIRM ADR conflict** — a decision required to proceed contradicts a FIRM entry. Surface which ADR / which decision / what conflicts. Do not silently override.
2. **Ambiguous scope** — the input doesn't decompose into a unit small enough for a binary done/not-done call. Surface for narrowing.
3. **Repeated failure without substrate change** — same primitive returns failure against unchanged substrate, and the diagnostic ladder offers no layer-change avenue. The orchestrator judges thrashing by the substrate-unchanged signal, not by counting.

These are the only built-in halts. Everything else is judgment.

## Anti-patterns

**Shared name for what this section guards against: "recipe leak."** Judgment that should be the orchestrator's (or a model's) ossified into a deterministic rule, fixed step ordering, keyword match on agent output, numeric threshold gate, or framework heuristic. Substrate-thick / process-thin fails the moment process re-thickens — recipe leak is what that re-thickening looks like in practice. Each bullet below is one shape it takes; "recipe leak" is the call-out to use in skill review, ADR drafting, and orchestration audits.

- **Treating this as a pipeline runner.** No fixed step order, no pass-count digits, no profile presets. The right composition for "fix typo in README" is "edit, run harness, close." For "ship an ADR-paired feature with three child beads" it is much more. Judge. (Canonical recipe leak.)
- **Absorbing work that should be dispatched.** The orchestrator's identity slip — silently downshifting from "compose + dispatch" to "edit + run" because doing-it-yourself feels faster than writing a subagent prompt. The cue: you're about to Edit/Write multi-line code, or run a primitive's logic in your own context, without first naming the trivial-shape that makes it ok. **Common escape hatch — "I can't expose the secret to a subagent."** That carve-out applies *only to the token-touching turns themselves*. Diagnosis, recovery, root-cause work, harness design, post-rotation verification — all still dispatchable; rotating one token doesn't make the surrounding 250 turns yours. Halt; dispatch the matching subagent (`implementer`, `adversarial-reviewer`, `debugger`, `harness-designer`); use the `secrets-via-stdin` skill for the token-touching steps in isolation. This is the failure mode that turns a 5-bead epic into 5 solo edits and one diff-review at the end.
- **Higher-order absorption — absorbing framing primitives while dispatching execution primitives.** The harder-to-catch shape: implementers fire cleanly via fresh-context dispatch, but `/decompose`, `/scope-check`, child-bead authorship, and parent re-verify get absorbed into the orchestrator's head as "I'll just map acceptance items to implementer prompts." Dispatch hygiene at the execution layer masks framing-layer absorption. The cue isn't just "you're about to Edit/Write" — it's also **"you're about to dispatch implementers off a list that you treated as decomposition without writing it to substrate."** If the parent's `--acceptance` is what your dispatch loop is iterating over, the framing primitives are getting absorbed; halt and author the child beads (or run `/scope-check` + create the bead set) before the first execution dispatch.
- **Pausing after fan-out for confirmation — the inverse absorption.** After `/decompose` materializes children, the next loop iteration walks them per Pattern B (Walk-children) — not "report status, await user confirmation." The slip is treating `/decompose`'s `## Decomposition record` output as a stopping point ("framing primitives done — hand back to user") instead of a mid-loop substrate change that *enables* the next iteration. Recognition cue: you're about to write "Ready to either pick up X / Y / Z, or break here for review" or any equivalent opt-in language after a primitive completes cleanly. That phrasing IS the failure mode — the orchestrator's loop only exits on `--acceptance` met or a raise condition (FIRM ADR conflict, ambiguous scope, repeated failure without substrate change). "Natural break point after primitive completion" is not a raise condition; it's the loop running normally. Halt the opt-in question; the next move is walk-children. Special case: if the parent's `--acceptance` is *brainstorm-shaped* (reads true post-decompose because the contract was "decompose-ready," not "system-state shipped"), that's the bridge-bead footgun — see bd memories key `brainstorm-bead-bridge-footgun` and route to `/adr-write` or bead-acceptance edit, not to silent exit.
- **Reaching for `/implement` reflexively.** The v1 `/implement` skill bundles its own multi-subagent recipe (impl → review → commit → fix → retry) and overlaps with this orchestrator's job. Don't compose it from here — pick the lightest execution shape directly.
- **Letting an execute-only subagent compose primitives.** When `implementer` (or any execute-only specialist) is dispatched, its job is to satisfy `--acceptance` against the codebase — not to `/decompose`, `/scope-check`, or rewrite scope. If it finds the scope wrong, it raises to you. See `agents/implementer.md` and `skills/subagents/SKILL.md`.
- **Suppressing `/adversarial-review`.** Default-on for own work . Dispatch `adversarial-reviewer` (subagent) for proper frame-distance, or run the skill yourself only when frame-distance is low-stakes (trivial work where the orchestrator's context isn't biased). **Literal recognition cue: `bd close`'s `adversarial-review verdict gap` stderr warning.** If that warning fires at close, the primitive got absorbed — acknowledging-and-proceeding past the warning IS the failure mode it was added to surface ( in-band juncture cues). Stamp `verdict:pass` via a fresh-context review or, if the review was genuinely empty (trivial mechanical edit, harness green), record the noticing in the close-commit and move on — but the noticing must happen.
- **Authoring ADRs inline without `/adr-write`.** Load-bearing decisions route through `/adr-write` (alignment-question discipline + overlap detection). Do not silently edit `docs/decisions/`.
- **Retrying the same primitive against unchanged substrate.** The thrashing failure mode. Apply the diagnostic ladder; change a layer between attempts.
- **Following `superpowers:subagent-driven-development` blanket prohibition on parallel implementers.** We override : parallel is OK iff file-claims are disjoint. Same skill mandates TodoWrite — we use `bd` per CLAUDE.md.

## Recipes

send-it/recipes/ (methodology home) holds worked examples for common shapes. These are illustrations — read one or two to calibrate the composition vocabulary, don't treat them as templates to match-and-execute.

## Canonical refs

- subagents/SKILL.md (methodology home) — subagent dispatch discipline.
- agents/ directory (methodology home) — execute-only subagent definitions.
- send-it/recipes/ (methodology home) — worked composition examples.
