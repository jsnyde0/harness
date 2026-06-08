---
name: beadify-v2
description: 'Heavy-recipe four-phase decomposition (scout, acceptance, critic, materialize). Reference composition for genuinely-large epic decomposition; superseded as default by thesis-v2 decomposition primitive (ADR-012).'
disable-model-invocation: true
---

## Purpose

Organize the unit-of-work shape of an epic bead. The output is one of two normal outcomes:

1. **Leaf-shaped epic** (first-class outcome, not BLOCKED): the bead represents a single unit of work that doesn't benefit from decomposition. Zero subagents dispatched. The epic stays a leaf and flows directly to `/implement-v2`.
2. **Decomposed epic**: the bead is broken into children with per-child `--acceptance` and dependencies. All decomposition work is held in orchestrator memory until the whole-tree critic returns PASS; then bead state is written in a single materialize phase.

"No decomposition needed" is a valid, expected answer — emit it via the leaf-shaped output contract, never via `BLOCKED:`.

The skill replaces the previous N-pass loop (ADR-005 D8/D9, superseded by ADR-010 D1/D2/D3) with a four-phase text-until-convergence pipeline:

- **Phase A — Explore** (in memory): pre-flight; leaf-or-decompose decision; Haiku ADR pre-filter; orchestrator-decided scout count; parallel scout dispatch; orchestrator synthesis into one canonical graph.
- **Phase B — Sharpen** (in memory, K=1..max(N,until-converged), cap=5): per-child parallel acceptance refiners; orchestrator structural sweep; convergence check; repeat or advance.
- **Phase C — Critique** (in memory, max 2 passes): whole-tree critic with TREE_VERDICT contract; PASS → materialize; FAIL → triage+revise+re-critique once; 2nd FAIL → BLOCKED.
- **Phase D — Materialize** (only after critic PASS): diff canonical graph against existing children; `bd create`/`bd update`/`bd close`; `bd dep add`; verification; audit notes; emit output contract.

**Key discipline:** organize + target, not prescribe. Neither the orchestrator nor any subagent puts file paths, code examples, or step-by-step instructions into bead descriptions.

## Inputs

- `$ARGUMENTS` (parsed positional-first, then flags): `<epic-bead-id> [--N=<n>] [--scouts=<n>]`
  - `<epic-bead-id>` (required, positional): the epic bead to decompose.
  - `--N=<n>` (optional; default 2): minimum sharpen iterations (floor, per ADR-010 D3). NOT a target. Convergence = sweep-clean AND K ≥ N. Hard cap = 5 iterations regardless of N. Default of 2 is empirically grounded — K=1 refiner output frequently contains HOW-prescription leakage that K=2 cleans up; pass `--N=1` only when speed matters more than acceptance precision.
  - `--scouts=<n>` (optional; 0/1/2/3): explicit override of the orchestrator's scout-count decision (per ADR-010 D4/D5). When omitted, orchestrator decides using reasoning signals. Cap at 3.
  - Parse order: positional argument first, then `--key=value` flags. **Unrecognized arguments → ask user to clarify; do NOT silently default.**

## Phase A — Explore (all in memory)

### Step 0 — Pre-flight check

Run `bd show <epic-id>`. Terminate early for any of these conditions:

- **Bead not found (404):** emit `BLOCKED: epic <id> not found` then exit.
- **Already closed:** emit `BLOCKED: epic <id> is already closed` then exit.
- **Missing `--design` field:** emit `BLOCKED: epic missing --design field — run /brainstorm-v2 or populate --design` then exit.

Load existing children via `bd list --parent=<epic-id>`. Classify each:

- `closed` children: ignore (do not block; do not carry into scouts).
- `open` (not started) children: load as candidate tree for scouts (see Step 0a/1).
- `in_progress` children: **frozen.** If canonical graph implies modifying or closing any in_progress child → emit `BLOCKED: in-progress child <id> (<title>) cannot be modified by re-decomposition` and exit (per ADR-010 D5).

### Step 0a — Leaf-or-decompose decision

Read the epic `--design`, `--acceptance`, and `--notes` (check `## ADRs consulted` section — seed the Haiku ADR pre-filter in Step 0b with the paired ADR(s) listed there, preserving the link from epic to originating ADR into subagent briefs).

Make one decision: **decompose or leaf?**

**Primary test:** *"If I handed this to one implementer subagent right now, would it come back asking 'which part first?' or 'are these one commit or two?'"* If yes → decompose (the unit of work isn't atomic). If they'd just start typing → leaf. The test is external and predictive — it kills the introspective "let me think about whether this is decomposable" hedge.

**Corroborating signals — decompose** when any of the following hold:
- The `--acceptance` contract has 2+ independent observable clauses targeting different files, modules, or concerns.
- The work spans risk profiles that should commit separately (e.g. one safe refactor + one behavioral change).
- A single implementer would need to hold meaningfully unrelated concerns in context simultaneously.

**Corroborating signals — leaf** when all of the following hold:
- The `--acceptance` contract is one atomic check, or a tight cluster of checks against the same file/module.
- The change can be described in 2–3 crisp criteria.
- A single implementer can complete it without context-switching.

**If leaf:** record the decision on the epic's `--notes` (append; never destructively overwrite):

```
## Decomposition (beadify-v2 iteration <run-number>)

decision: leaf
rationale: <one line>
scout-count: 0
```

**Always append a fresh decision for this run, even if a prior `## Decomposition (...)` section already exists** — silently skipping the append because a prior section is present is a contract violation. Re-runs must leave a per-run rationale trail.

Then skip Phases A(remainder)/B/C/D entirely and emit the leaf-shaped output contract. The leaf path is a first-class outcome.

**If decompose:** proceed to Step 0b. Decision audit is appended once via Step 13's audit block; do not append a separate `## Decomposition` block at this step.

### Step 0b — Haiku ADR pre-filter

Dispatch a Haiku subagent to scan `docs/decisions/ADR-*.md` and return at most 5 in-scope ADR paths for this epic (cap is 5 for `/beadify-v2` operating on a whole epic; per-bead skills cap at 3 per ADR-008 D3). Seed with the paired ADR(s) from `## ADRs consulted` in the epic's `--notes`.

The 3-tier dispatch fallback (Tier 1: named subagent at assigned model — Haiku for ADR pre-filter, Sonnet for scouts/refiners, Opus for critic; Tier 2: session-model fallback when override unavailable; Tier 3: orchestrator-inline ONLY after deferred-tool discovery fails) applies to every subagent role in this skill — see the **Subagent dispatch shape summary** section below for the canonical text.

Subsequent subagents (or orchestrator fallback) receive only this filtered ADR set.

### Step 1 — Orchestrator decides scout count

When `--scouts=<n>` is passed, use that value directly (cap at 3). Otherwise, the orchestrator reads the epic's `--design`, `--acceptance`, and in-scope ADRs, then decides 0/1/2/3 using these reasoning signals (not hard rules — weigh them):

- **Independence and breadth of `--acceptance` clauses** — tight cluster → fewer scouts; sprawling multi-module → more scouts.
- **Sprawl of `--design`** — single concern → 1 scout; multiple distinct concerns → 2–3 scouts.
- **Number and centrality of in-scope ADRs** — many overlapping ADRs → benefit from independent proposals.
- **Variance in risk profiles** — safe refactor + behavioral change → more exploration.
- **Familiarity of change type** — novel architectural moves benefit more from multi-scout than well-trodden patterns.
- **Operator-supplied context in `--notes`** — any `## Probe context`, `## Decomposition guidance`, or similar operator hint section may inform reasoning; weigh as one signal among others, not as a hard override.

On the leaf path, scout count is 0 (short-circuited in Step 0a).

### Step 2 — Parallel scout dispatch

Dispatch scouts in parallel via `subagent_type: "design-scout"` (model: sonnet, defined in the design-scout agent in the methodology home). Each scout's prompt receives:
- The epic `--design`, `--acceptance`, and `--notes`.
- The filtered ADR set.
- Existing open children (if any), as `existing-id=<id> title=<title> acceptance=<text>`. Scouts may keep, modify, replace, or drop them in their proposals.

Role brief, hard constraints (no HOW-prescription, no acceptance text, no `superpowers:writing-plans`), and the `TREE_PROPOSAL: ready|blocked` final-line contract are encoded in the agent definition — do not duplicate them inline.

A `TREE_PROPOSAL: blocked` from any scout causes the orchestrator to inspect the scout's output, decide whether to triage (absorb the concern, adjust the brief, retry) or escalate. If escalation is needed: emit `BLOCKED: <scout-blocking-reason>` and exit.

### Step 3 — Orchestrator synthesis

The orchestrator reads all scout proposals and produces one **canonical graph** in memory (text). The canonical graph is the single source of truth from this point through Phase C. It must include:

- One slot per child bead: `slot-id` (temporary label), `title`, `scope-summary`, `kept-from-existing: <id>|new` (to enable diff-and-apply materialize per ADR-010 D7).
- Dependency edges between slots.
- `## Coverage map`: maps each epic acceptance clause to the slot(s) covering it. Uncovered clauses must be assigned a slot before Phase C — uncovered = critic auto-FAIL.
- Synthesis notes: major disagreements across scouts + orchestrator resolution rationale.

If only 1 scout was dispatched, the canonical graph is the scout's proposal with any orchestrator adjustments; synthesis notes are minimal.

## Phase B — Sharpen (all in memory)

Sharpen runs **per-slot**, not tree-wide. Each slot has its own iteration counter `K_slot`. Convergence is reached when every slot independently satisfies `K_slot ≥ N AND has been sweep-clean since its last refiner pass`. Hard cap = 5 per slot.

### Step 4 — Per-child parallel acceptance refiners (only flagged slots after K=1)

**On the first sharpen pass (every slot's K_slot = 0 → 1):** dispatch one refiner per canonical slot, in parallel, via `subagent_type: "design-refiner"` (model: sonnet, defined in the design-refiner agent in the methodology home).

**On subsequent passes:** dispatch refiners ONLY for slots that meet either condition:
- `K_slot < N` (slot has not yet hit the floor), OR
- the most recent sweep (Step 5) flagged a finding against this slot since its last refiner pass.

Slots whose `K_slot ≥ N` AND were sweep-clean in the most recent sweep stay frozen — their acceptance text is final, no re-dispatch.

This avoids re-running clean refiners just to satisfy a tree-wide minimum.

Each dispatched refiner's prompt receives:
- Its slot (title, scope-summary, coverage-map entry, `kept-from-existing` field).
- The filtered ADR set.
- The epic `--design` and `--acceptance`.
- Any sweep findings from the prior pass that reference this slot (verbatim).

Role brief, hard constraints (no HOW-prescription, no restructuring, no `superpowers:writing-plans`), and the `ACCEPTANCE_REFINED: yes|no` final-line contract are encoded in the agent definition.

**Fallback when subagent dispatch is unavailable:** orchestrator writes `--acceptance` inline. MUST consult the project's harness inventory (typically `.claude/harness.md`) before composing. Record `acceptance-author: orchestrator-inline (no dispatch tool); harness-inventory-consulted: <path or "none-found">` in audit notes.

Orchestrator collects all refined acceptance texts and updates the in-memory canonical graph with them. Increment `K_slot` for each slot that was dispatched on this pass; clean-frozen slots' counters do not change.

### Step 5 — Orchestrator structural sweep

The orchestrator proactively re-evaluates the canonical graph. This is an orchestrator responsibility — not a subagent dispatch. Checks:

- **Re-apply leaf criteria to each slot:** still atomic? still 2–3 crisp criteria? If a slot grew during refinement (acceptance now spans 2+ unrelated concerns), split it. If two slots shrank and now look like one concern, merge them.
- **Same-file ownership across parallel slots** (no dep edge between them): same-file parallel siblings is a structural bug → merge or serialize via dep edge.
- **Cross-bead reference without dep edge:** slot A's acceptance references behavior produced by slot B but no dep edge exists → add the dep, or rethink the boundary.
- **Acceptance overlap:** two sibling slots' acceptance text overlaps substantially (verifying near-identical observables) → candidate merge. **Integration-bead vs sibling overlap:** if an integration slot's acceptance clause restates an observable already covered by a sibling's acceptance → strip that clause from the integration slot.
- **Missing integration slot:** 2+ slots touch related surface area but no integration test slot exists, and the epic's `--acceptance` doesn't already cover the cross-child observable behavior → add one (or record a one-line justification for skipping).
- **Coverage gaps:** check the `## Coverage map`; any epic acceptance clause with no covering slot must be assigned one.
- **Subagent-flagged structural concerns:** resolve any flags returned by scouts or refiners.

Apply revisions to the canonical graph in memory. Do NOT write any `bd` commands yet.

### Step 6 — Convergence check (per-slot)

**Convergence = for every slot: `K_slot ≥ N` AND most-recent sweep raised no finding against that slot.**

Equivalently: the tree converges when no slot in the canonical graph still qualifies for re-dispatch under Step 4.

- If converged → advance to Phase C.
- If any slot still qualifies for dispatch (its `K_slot < N` OR sweep flagged it) → run another iteration on those slots only. Other slots stay frozen with their existing acceptance text.
- Hit `K_slot = 5` with sweep still flagging → advance to Phase C; record `sharpen-cap-reached: <slot-id>` + one-line finding in audit notes.

Worked examples (frozen vs dispatched, N=1 vs N=2): see `references/sharpen-convergence-examples.md`.

## Phase C — Critique (all in memory, max 2 passes)

### Step 7 — Whole-tree critic dispatch

Dispatch one whole-tree critic via `subagent_type: "design-critic"` (model: opus, defined in the design-critic agent in the methodology home). The critic's prompt receives:
- The full canonical graph (all slots, all acceptance texts, all dep edges, coverage map).
- The epic `--design`, `--acceptance`, and `--notes`.
- The filtered ADR set.

Role brief, audit dimensions (coverage, structure, HOW-leakage, ADR alignment), report-don't-restructure constraint, and the `TREE_VERDICT: PASS|FAIL` final-line contract are encoded in the agent definition. On FAIL, a structured findings block precedes the verdict line.

### Step 8 — Critic verdict triage

**PASS (1st or 2nd pass):** advance to Phase D.

**FAIL (1st pass):** orchestrator triages the critic's findings using the **countermand test** — *"Would the user countermand this if I acted without asking?"* For each finding:
- **Fold-in** — *No, this is the obvious move.* Apply the revision to the canonical graph in memory. Adjust coverage map. Size is not the test: a multi-slot rewrite that executes the obvious next step is Fold-in; a one-line tweak that touches an intentional structural choice is Decision-challenge or Surface.
- **Discard** — *No, this isn't worth doing.* Wrong, redundant, or contradicts a finding the critic already covered. Record one-line rationale.
- **Decision-challenge** — *No — a FIRM ADR already says otherwise.* Record why an in-scope ADR choice was correct despite the finding. The orchestrator may not reclassify a FIRM-ADR-justified choice as Fold-in.
- **Surface** — *Yes — there's a real choice here.* Flag for human review without BLOCKING. The orchestrator cannot resolve unilaterally; surface to operator and continue with whatever resolution the operator gives.

After triage, apply all Fold-in revisions to the canonical graph, then re-dispatch the critic (second pass).

**FAIL (2nd pass):** emit `BLOCKED: critic 2nd-pass FAIL — <critic-findings-summary>` and exit. No partial `bd` state is created (text-until-convergence guarantee, ADR-010 D1).

## Phase D — Materialize (only after critic PASS)

Phase D is the only phase that writes to `bd`. No `bd create`, `bd update`, `bd close`, or `bd dep add` commands are issued in Phases A, B, or C.

### Step 9 — Diff canonical graph against existing children

For each slot in the canonical graph, the `kept-from-existing` field (set during Phase A synthesis) determines the materialize operation:

- `kept-from-existing: <id>` (existing open child to keep): `bd update <id>` for any title/design/acceptance changes.
- `kept-from-existing: new`: `bd create --parent=<epic-id>` with full content.

For each existing open child whose ID does NOT appear in any slot's `kept-from-existing` field: close it with `bd close <id> --reason="superseded by /beadify-v2 re-decomposition"`. (Only `open` children — `in_progress` children would have caused BLOCKED in Step 0.)

### Step 10 — Create/update/close beads

**Parent-first hierarchy:** the epic exists prior to `/beadify-v2` invocation (most commonly created by `/brainstorm-v2` at convergence per ADR-006 D5 revised 2026-04-30, but may also originate from agent-filed bug beads during implementation, or from manual creation). Create children with `--parent=<epic-id>`. Children must never be created before the parent exists.

For each slot in canonical order:

```bash
# New slot:
bd create --parent=<epic-id> \
  --title="<slot-title>" \
  --design="<scope-summary>" \
  --acceptance="<refined-acceptance>" \
  --notes="..."

# Kept-modified slot:
bd update <existing-id> \
  --title="<slot-title>" \
  --design="<scope-summary>" \
  --acceptance="<refined-acceptance>"

# Superseded slot:
bd close <existing-id> --reason="superseded by /beadify-v2 re-decomposition"
```

Each child bead's `--acceptance` is the refined acceptance text from Phase B. The `--design` field holds the slot's scope-summary (architectural intent, not implementation prescription). The `--notes` field carries the in-scope ADR paths under `## ADRs consulted`, plus a one-line `## Slot` reference (e.g. `slot-X from /beadify-v2 canonical graph for epic <id>, iteration <K>, critic PASS first-pass`) for traceability back to the run that created it.

### Step 11 — Add dependency edges

```bash
bd dep add <child-id> <dep-id>
```

For each dep edge in the canonical graph. Also diff existing dep edges (from `bd dep tree <epic-id>`) against canonical edges and add any missing edges. If `bd dep remove` is unavailable, document stale edges in audit notes.

**Integration test bead:** when 2+ children are created/updated and touch related surface area, the canonical graph must include an integration test slot. Create it as a child bead. Add `bd dep add <integration-id> <sibling-id>` for each implementation sibling. Skip only when children are narrow and independent (different files, unrelated concerns), or when the epic's `--acceptance` already covers the cross-child observable behavior. Record the skip justification in audit notes.

**File-conflict check:** if two child beads would modify the same file and no dep edge serializes them, that is a structural bug. Resolve by merging those beads (rerun from Phase A) or serializing via `bd dep add`. Do not finalize with same-file parallel children.

### Step 12 — Post-materialize verification

Run verification commands and confirm results before emitting the contract line (per ADR-010 D11):

```bash
bd dep tree <epic-id>
bd dep cycles
bd list --parent=<epic-id>
```

Expected: created children appear under the epic; dep edges are in the intended direction; no cycles; ready children are unblocked; integration bead (if any) is blocked by the implementation children it validates.

If verification reveals problems (cycles, missing children, wrong dep direction): correct via `bd dep add` / `bd update` before emitting the contract.

### Step 13 — Append audit notes to epic

Append the following structured audit block to the epic's `--notes` (never destructively overwrite existing content). **Always append even if a prior audit block exists** — each run appends its own block.

```markdown
## Decomposition (beadify-v2 iteration <run-number>)

decision: <leaf|decompose>
rationale: <one line>
scout-count: <0|1|2|3> — <orchestrator reasoning OR "user override --scouts=N">
sharpen-iterations: <slot-id>=<K_slot>, ... (min=<N>, cap=5 per slot)
sharpen-cap-reached: <comma-separated slot-ids that hit K=5 with sweep findings still open, or "false">

Scout dispatches:
- scout-1: TREE_PROPOSAL: <ready|blocked> [<one-line summary>]
- scout-2: ...

Synthesis notes (when scouts ≥ 2):
- <major disagreements + orchestrator resolution>

Refiner dispatches:
- refiner-<slot>: ACCEPTANCE_REFINED: <yes|no>

Critic dispatches:
- critic-1: TREE_VERDICT: <PASS|FAIL> [<findings if FAIL>]
- critic-2: TREE_VERDICT: PASS  (if first FAIL'd and re-critiqued)

Created/updated/closed:
| Op     | Bead ID | Title | Why |
|--------|---------|-------|-----|

ADRs consulted: <comma-separated paths>
```

### Step 14 — Emit output contract

Emit the final output contract line:

```
EPIC_ID: <epic-id> CHILDREN: <id1>,<id2>,...
```

Comma-separated child IDs, no spaces around commas, at least one child on the decompose path.

## Output contract

The final line of skill output is one of:

```
EPIC_ID: <bead-id> CHILDREN: <id1>,<id2>,...
EPIC_ID: <bead-id> CHILDREN:
BLOCKED: <reason>
```

- **Decompose path:** `EPIC_ID: <id> CHILDREN: <id1>,<id2>,...` — at least one child; comma-separated, no spaces around commas.
- **Leaf path (first-class outcome):** `EPIC_ID: <id> CHILDREN:` — empty list (no IDs after the colon, no trailing comma). The bead is the unit of work; downstream `/implement-v2` operates on the epic directly. This is a normal, expected outcome — not a failure.
- **Failure:** `BLOCKED: <reason>` — emitted only for actual failures (epic not found; epic closed; missing `--design`; in_progress child conflict; critic 2nd-pass FAIL). "No decomposition needed" is NOT a failure; use the leaf path.

No trailing whitespace. No additional text on the final line. Downstream callers grep for `EPIC_ID:` and parse the children list (possibly empty).

## Checkpoint output format

When emitting a moment that needs the user's input or signals end-of-phase (e.g. BLOCKED escalation, decomposition summary, critic 2nd-pass FAIL surface, "Surface" triage items), structure the human-facing message as:

- **Anchor** what work this is and what just happened (1 line).
- `---`
- Mechanical detail, citations, finding-by-finding breakdown — drill-up content.
- `---`
- **The ask** in plain language, framed by what the system would do differently — not by mechanism.
- **Options** (≤3, one phrase each, in observable-behavior terms).
- **One-line recommendation.**

**Why this shape:** the user reads chat tail-first — the most recent visible line is what they act on, not the top. Anchor at the top orients on first-read; the ask at the tail is what their attention lands on when switching between parallel agents. Mechanical detail in the middle is drill-up if needed.

**Anti-pattern:** the wall-of-X summary — captured state enumerated through the body, the actual ask diluted into a closing question that gets drowned by everything above it. Signal density at the tail is what makes a checkpoint actionable.

Reference IDs — bead IDs, ADR/decision codes, slot IDs, file:line refs — are breadcrumbs for the drill-up section, never the ask at the tail. Collapse correlated decisions to the root choice; don't make the user re-derive interdependencies. Findings that don't need user input (Fold-ins, Discards, Decision-challenges resolved via FIRM ADR) get one summary line, not an enumeration.

This shapes the human-facing message only; the `EPIC_ID: ...` / `BLOCKED: ...` contract line per **Output contract** above is unchanged.

## Subagent dispatch shape summary

| Phase | Role | Count | Agent / Model | Contract line |
|-------|------|-------|---------------|---------------|
| A (Step 0b) | ADR pre-filter | 1 | inline dispatch, `model: claude-haiku-4-5` | (none — returns filtered list) |
| A (Step 2) | Decomposition scouts | 0–3 (orchestrator-decided) | `subagent_type: "design-scout"` (sonnet) | `TREE_PROPOSAL: ready\|blocked` |
| B (Step 4) | Acceptance refiners | 1 per slot, parallel | `subagent_type: "design-refiner"` (sonnet) | `ACCEPTANCE_REFINED: yes\|no` |
| C (Step 7) | Whole-tree critic | 1 (up to 2 passes) | `subagent_type: "design-critic"` (opus) | `TREE_VERDICT: PASS\|FAIL` |

**Leaf path:** zero subagents dispatched (Phases A/B/C short-circuit at Step 0a).

**3-tier dispatch fallback applies to every role:**
1. **Tier 1 (preferred):** dispatch the named subagent at its assigned model — Haiku for ADR pre-filter, Sonnet for scouts (`design-scout`) and refiners (`design-refiner`), Opus for critic (`design-critic`). The agent definition pins the model; the orchestrator does not override.
2. **Tier 2:** if model override is unavailable in the runtime, the dispatch falls back to the session model. Adversarial separation is preserved; only the cost profile changes.
3. **Tier 3 (inline)** is reachable ONLY after attempting deferred-tool discovery (e.g. `ToolSearch select:Agent,Task,TaskCreate` or the harness equivalent). Only if no dispatch tool can be activated does tier-3 apply. Record `dispatch-discovery: <tools-found-but-unusable|none-found>` and the role-inline annotation (`adr-pre-filter: inline (...)` / `role: inline (...)`) in audit notes. For inline ADR pre-filter: `ls docs/decisions/ADR-*.md` then Read each candidate's first ~30 lines — fabricated paths are a contract violation (reinforces ADR-008 D5 `canonical_refs`).

## Forbidden

- **HOW-prescription in bead descriptions and acceptance text.** Bead content states what must be observable, not how to achieve it. Three categories — scouts, refiners, and the orchestrator must classify each candidate phrase before keeping it:

  **(1) FORBIDDEN — strip on sight.** These are pure HOW and have no place in scope-summary or acceptance.
  - ❌ Line numbers anywhere: `"remove the duplicate write at classify_pages.py:274"`. Line numbers drift; mechanism, not contract.
  - ❌ Prescriptive verbs naming an internal mechanism: `"the writer calls a rotate() helper before each append"`, `"manager records the event in `_history.append(evt)`"`.
  - ❌ Step orderings: `"first disable triggers, then migrate, then re-enable"`. Sequencing is HOW.
  - ❌ Code excerpts or function bodies, even one-liners: `"helper returns `instructor.from_provider(...)`"`.
  - ❌ Implementation libraries cited as instruction: `"use httpx instead of requests"`.

  **(2) ALLOWED as observable contract.** The deliverable's *public surface* — what an outside observer can verify by reading or running the result. These belong in acceptance text and scope-summary.
  - ✅ Public symbol or module names that ARE the contract: `"module gtm_lib/llm.py exports resolve_instructor_client"`, `"PageClassification has a @field_validator on investment_level"`.
  - ✅ Symbol names of code that must be deleted (observable absence): `"classify_inventory is absent from classify_pages.py"`.
  - ✅ Substring assertions on errors or output: `"the validation error string contains the substring 'flagship is forbidden at seed time'"`.
  - ✅ File paths as the deliverable target — naming WHERE something must exist, not how to put it there: `"a docstring exists at the top of gtm_lib/llm.py describing public symbols"`.
  - ✅ Quantified observables: `"classify_pages.py is under 630 lines"`, `"the --dry-run exit code is 0"`.

  **(3) BORDERLINE — default to FORBID.** When in doubt, strip. The critic will FAIL the tree if HOW leaks; rather take a tighter acceptance now.
  - ⚠️ File paths inside a multi-step recipe → strip (recipe is the leak; path follows).
  - ⚠️ Function signatures with parameter defaults → keep ONLY the part the caller depends on. `"exports resolve_instructor_client(base_url=None) -> instructor.Instructor"` is acceptable as a public-surface contract; `"resolve_instructor_client uses an env-var priority chain LLM_API_KEY > REQUESTY_API_KEY"` is HOW — strip the priority chain.
  - ⚠️ "Existing tests pass" alone is fine; "all tests in foo/tests/test_X.py pass" is borderline (file path serves as scope anchor, acceptable). "All tests pass after the import path is changed from X to Y" is HOW — strip.

  Quick test for any candidate phrase: *can an implementer satisfy the bead by a different mechanism than the one the phrase implies?* If yes → keep (it's observable contract). If no → strip (it's HOW).
- **`superpowers:writing-plans` dependency.** Do not invoke `superpowers:writing-plans` (or any writing-plans skill). Acceptance criteria are written via `/harness compose` (ADR-005 D1, FIRM).
- **Subagents redeciding structure.** Scouts propose structure; refiners write acceptance; critic audits. None act on structural changes — they flag concerns back to the orchestrator. The orchestrator owns the canonical graph.
- **Same-file parallel children.** If two child beads both write the same file with no dep edge between them, the tree is structurally broken. Merge or serialize before materializing.
- **Skipping the integration test bead on multi-bead changes when children touch related surface area.** When 2+ children share related concerns or could regress each other, an integration test slot is required in the canonical graph. Skip only when children are narrow and independent (different files, unrelated concerns) or when the epic's `--acceptance` already covers the cross-child observable behavior. Record the skip justification.
- **Treating "no decomposition needed" as a failure or BLOCKED.** The leaf path is a normal outcome — emit `EPIC_ID: <id> CHILDREN:` (empty), never `BLOCKED:`.
- **Children created before parent exists.** Always create the parent bead first, then create children with `--parent`.
- **Writing partial `bd` state before critic PASS.** No `bd create`, `bd update`, `bd close`, or `bd dep add` commands are issued in Phases A, B, or C. The text-until-convergence guarantee means a BLOCKED in Phase C leaves no orphaned bead state.
- **Scouts, refiners, or critic restructuring beyond their assigned scope.** Each role has one cognitive job. A scout that writes acceptance text, a refiner that drops slots, or a critic that creates beads has violated role separation. These actions are forbidden and orchestrator should reject them.
- **Skipping `bd dep cycles` verification.** Running `bd dep cycles` after materialize is mandatory (ADR-010 D11). A BLOCKED from a cycle discovered post-create is worse than catching it via verification.

## ADRs consulted

- **ADR-010 D1** — text-until-convergence: canonical graph in memory until critic-PASS, then single materialize (Phases A–C in memory; Phase D writes once).
- **ADR-010 D2** — three-role dispatch: scouts (TREE_PROPOSAL), refiners (ACCEPTANCE_REFINED), critic (TREE_VERDICT); each has a parseable final-line contract.
- **ADR-010 D3** — `--N` as minimum-iterations floor (not target); convergence = sweep-clean AND K ≥ N; hard cap = 5.
- **ADR-010 D4** — orchestrator-decided scout count (0/1/2/3) using reasoning signals; `--scouts` flag overrides.
- **ADR-010 D5** — existing open children loaded as first proposal (not BLOCKED); in_progress children frozen (BLOCKED if canonical implies modification).
- **ADR-010 D6** — per-child parallel refiners, blind to siblings; sweep + critic handle cross-bead concerns.
- **ADR-010 D7** — diff-and-apply materialize: `kept-from-existing` field drives `bd update` vs `bd create`; superseded open children closed.
- **ADR-010 D8** — critic 2-pass cap: PASS → materialize; 1st FAIL → triage+revise+re-critique; 2nd FAIL → BLOCKED.
- **ADR-010 D9** — coverage map mandatory in scout output; critic validates; uncovered epic acceptance clause = auto-FAIL.
- **ADR-010 D10** — richer audit notes template appended to epic `--notes` after materialize.
- **ADR-010 D11** — post-materialize verification: `bd dep tree`, `bd dep cycles`, `bd list` before emitting contract.
- **ADR-010 D12** — leaf path stays first-class: short-circuits at Step 0a; zero subagents; `EPIC_ID: <id> CHILDREN:` contract.
- **ADR-005 D1** — drop `superpowers:writing-plans` dependency entirely (FIRM).
- **ADR-005 D2** — bead pattern uses `bd` native quality gates (`--design`, `--acceptance`).
- **ADR-005 D3** — whole-change acceptance contracts live on the epic's `--acceptance` field; per-bead acceptance derived from it.
- **ADR-005 D6** — beadify methodology is organize + target, not prescribe; no file paths, code examples, step-by-step instructions (FIRM).
- **ADR-005 D7** — harness-target authoring discipline (D7 generalized 2026-05-22 to all bead-authoring primitives; the canonical discipline now lives at `/brainstorm` at convergence and `/decompose` at child authoring; beadify-v2 inherits it as a v2 reference composition).
- **ADR-006 D1** — design narrative lives on the epic's `--design` field; `bd show` is the single context lookup.
- **ADR-006 D3** — bead → ADR is the primary link; each bead's `--notes` `## ADRs consulted` section carries in-scope ADRs.
- **ADR-008 D3** — Haiku scope cap: ≤3 ADRs for per-bead skills, ≤5 for `/beadify-v2` operating on a whole epic.
