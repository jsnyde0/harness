---
name: recall
description: Inward-look prospective primitive — before sinking into a unit of work, tier-route a substrate query across L3 ADRs, L2A CASSMS, L2B bd memories, and skills. Use when picking up a new bead, after compaction when more substrate is needed beyond `bd prime`, when scope shifts mid-work, before /decompose, /adr-write, /implement, or /brainstorm on a unit you don't already hold context for, or when the user says "let's pick this up", "where were we", "what do we know about", "continue X", "start on Y". Triggers proactively on these phrases. Default-on at start of non-trivial work per CLAUDE.md "Substrate orientation". Brain-run discipline (brain needs substrate IN its context); delegates token-volume reads to file-scanner / content-extractor. Read counterpart to /compound's write.
---

## Purpose

Before sinking into a unit of work, orient against what's already known. Address the **silent-absorption failure mode**: the brain dives into the task, fills its context with unfocused reads, and discovers load-bearing FIRM ADRs or prior decisions only after committing to an approach.

`/recall` is **brain-run discipline**, not fresh-context dispatch. The brain needs the substrate IN its context to make downstream judgment (architecture calls, FIRM-conflict detection, scope decisions). A summarizing fresh subagent would lose the fidelity that load-bearing decisions need. Token-volume reads (INDEX-wide sweeps, multi-keyword searches, multi-file scans) delegate to `file-scanner` / `content-extractor`; **tier-routing judgment stays with the brain.**

**Symmetric to `/compound`:** `/compound` distills closed work *into* substrate (Record / Promote / Retire); `/recall` pulls relevant substrate *out* before new work. Same inward-look orientation, opposite direction.

## When to invoke

**Default-on triggers:**

1. **Picking up a new bead** — `bd show <id>` returns ≥ 1 of: non-trivial `--description`, `--design`, `--acceptance`, parent epic with siblings. Run `/recall <bead-id>` before `--claim`.
2. **After session compaction** when `bd prime` covers persistent memory but the task surface is broader (e.g., touches ADRs, cross-project conventions, L2A observations not in `bd prime`).
3. **Scope shift mid-work** — brainstorm decision set drifted from opening framing; implementation scope expanded across an ADR boundary. Pairs with the convergence re-scout in `/brainstorm`.
4. **Before `/decompose`, `/adr-write`, `/implement`, `/brainstorm`** on a unit you don't already hold context for at the orchestrator-recipe level.

**Judgment-routed:**

- Trivial / mechanical work (typo, single-config-line edit, mechanical rename) — skip `/recall`, just act.
- Continuation within the same session where the substrate is already in context — skip.
- Greenfield exploration with no plausible substrate overlap — skip with a one-sentence note.

**Phrase triggers** (proactive — invoke BEFORE the hand-rolled answer): "let's pick this up", "where were we", "what do we know about", "continue X", "start on Y", "ready to ship Z", "remind me what we decided about".

## Algorithm

```
/recall [<bead-id> | <free-text topic>]
```

The brain runs (no fresh-context primary dispatch):

1. **Frame the query** — one-line task description + scope (single bead / epic / topic / file). Surface explicitly so downstream readers know what was recalled against.
2. **Tier-route by gravitas** (per CLAUDE.md "Substrate orientation"; per ADR-013 D1 three-layer architecture):
   - **L3 canonical (always-on for non-trivial)** — invoke `/scout-adrs` (preferred) or delegate to `file-scanner` over `docs/decisions/INDEX.md` if `/scout-adrs` unavailable in the current context (e.g., dispatched-subagent context).
   - **L2B parking-lot** — for any task touching a known epic / work-stream / project pointer. **Default: index-helper.** Dispatch one general-purpose subagent with this brief: *"Run `bd memories --json` and `cm playbook list`. Read the full inventory. Against task framing `<task>`, return ONLY the keys/IDs of plausibly-relevant entries with a one-line gloss each. Do NOT summarize bodies — brain pulls bodies post-filter."* Helper returns filtered keys; brain reads full bodies via `bd memories <key> --json | jq -r '.<key>'` (bare `bd memories <key>` returns ~80-char previews only) and `cm playbook get <id>`. Full-inventory scan catches adjacencies that keyword-derived sweep misses; helper context stays ephemeral, only filtered keys land in brain.
     - **Fallback: direct batched sweep (only when dispatch is unavailable — judgment-bearing subagent re-orienting on a thin brief).** Derive 3-5 keywords from bead title + acceptance; run all `bd memories <kw>` calls plus the L2A `cm context` call in a single parallel message. Pull full bodies via `--json | jq` on the hits worth deep-reading. Inferior to the index helper on adjacency-catch, but works without dispatch capability.
     - Sequential L2 sweep (one `bd memories <kw>` per message) was the dominant call-count cost in /recall stress-tests — avoid either way.
   - **`.claude/harness.md` fit profiles** — consult when work touches a known work-surface category named in the inventory, when about to author a `## Harness target`, or when composing a feedback loop and fit calibration is absent from context. Read the relevant section of `.claude/harness.md` directly. Per-repo and inventory-shaped (distinct from bd-keyed L2B); carries fit profiles ("for X work, prefer Y mechanism because Z") and coverage gaps. Full guidance: [ADR-013 D11](../../docs/decisions/ADR-013-memory-layer-architecture.md#d11). Skip if no `.claude/harness.md` exists in the project.
   - **L2A observations** — `cm context "<task>"` for procedural / workflow / repeated-pattern work. Cross-project default per ADR-013 D7.
   - **Skills** — descriptions always-loaded; note which skills match the task surface for downstream composition.
   - **L1 CASS** — distinct from L2A (L2A is `cm` namespace; L1 is `cass` namespace, per ADR-013 D1). **Skip by default** — expensive, rarely load-bearing. **Invoke when** the user's prompt contains an explicit retro / audit phrase trigger ("remind me what we decided about", "what did we discuss last time", "audit our reasoning", "trail of past reasoning"). On these triggers, the reasoning trail across prior sessions IS the artifact under examination — `cm`-namespace L2A summaries are not a substitute. Working commands: `cass search "<topic keywords>"` to find sessions, then `cass view <session-id>` on the load-bearing hit.
3. **Delegate volume, keep judgment** — token-heavy reads dispatch to subagents per the agent definitions. Triggers: >3 ADRs to read in full, INDEX-wide scans, multi-keyword cross-search, `bd show <id>` outputs that overflow to a persisted-output file (large `--design` / `--acceptance` / sibling-tree), **and busy L2 inventory (see L2B step 2 — dispatch the index helper).** For persisted-output beads: dispatch `content-extractor` with a schema (status, title, --design summary, --acceptance, canonical_refs, child/parent links) — do NOT `Read` the persisted file directly into the orchestrator window. For single-file deep-slicing where structured extraction isn't needed, `Read` with `offset` / `limit` is the cheaper move. Tier-routing decisions and FIRM-conflict detection stay with the brain.
4. **Surface a compact orientation block** (see Output shape below).
5. **Verify currency before acting** — for any memory naming a specific file / function / flag, confirm it still exists (grep, file read). For any ADR-NNN Dk you cite with a firmness label, **read the ADR's decision section to confirm the label** — do not reason firmness from prior context. Memory captures a moment in time. A FIRM ADR claim is binding only when verified; a stale memory pointer is not.

## Output shape (brain emits)

```markdown
## Orientation: <one-line task framing>

### FIRM constraints (do not silently contradict)
- ADR-NNN D<k> [FIRM] — <what it decided, why it's load-bearing for this task>
- ...

### Relevant prior context
- L3 FLEXIBLE / EXPLORATORY: ADR-NNN D<k> — <one-line>
- L2B (bd remember `<key>`) — <one-line>
- L2A (cm playbook bullet `<id>`) — <one-line>
- ...

### Skills in scope
- `/<skill>` — <why relevant to this task>
- ...

### Verification needed before acting
- <claim from memory naming file/function/flag> → check <path or symbol> still exists
- ...

### Empty signals (probed but absent)
- <expected-but-missing>: <what would have appeared if substrate held it>
- ...

### Relevant file paths (optional)
- <absolute path> — <one-line load-bearing role>
- ...
```

Each section may be empty. Empty `FIRM constraints` is valid ("no in-scope ADRs"); entirely-empty output is valid ("greenfield; no prior substrate touching this task").

**Optional prelude — load-bearing surprise.** When the recall surfaces a state-mismatch with the user's framing (closed bead, missing file, deleted ADR, scope drift, FIRM-ADR conflict with implied direction), prepend a `## Load-bearing surprise` block before the canonical sections. Keep it ≤5 lines: what's surprising, why it matters, what disambiguation the user should resolve before proceeding.

**Probe for absences, not just presences** (per ADR-013 §Foreseeable failure modes; same discipline as `/compound`). A non-probing recall mistakes empty-substrate for "system healthy." The brain must explicitly ask: *What is expected but missing? What pattern would I expect to see recorded that isn't?*

## Composition

- **With `/scout-adrs`** — `/recall` composes `/scout-adrs` as its L3 sub-tool. `/scout-adrs` covers L3 only; `/recall` covers L1–L3 + skills.
- **With `/brainstorm`** — `/brainstorm` already runs `/scout-adrs` at cold-start and convergence. `/recall` is invoked at the orchestrator-recipe level *before* `/brainstorm` when the topic touches existing substrate beyond ADRs (L2 pointers, skill scope).
- **With `/scope-check`** — both run before commit. `/recall` is inward (what existing substrate constrains this work); `/scope-check` is outward (what neighbors does this work touch). They compose: `/recall` first to orient, then `/scope-check` to enumerate neighbors with the orientation block in hand.
- **With `/compound`** — read↔write pair. `/recall` reads what `/compound` writes. The orientation block surfaces L2A bullets and L2B entries that `/compound` previously distilled.

## Brain-run vs fresh-context dispatch

`/compound`, `/scope-check`, and `/adversarial-review` use fresh-context `Task()` dispatch because the originating session shares the work's blind spots — a fresh frame is load-bearing.

`/recall` is different: the brain needs the substrate **in its own context** to make downstream judgment (FIRM-conflict detection, architecture decisions, scope calls). A subagent summarizing the substrate would lose fidelity exactly where it matters most. So:

- **Brain runs the tier-routing decision and reads the substrate into its context.**
- **Subagent dispatches are for volume reduction, not frame-breaking.** `file-scanner` enumerates many files; `content-extractor` deep-reads 1–5 files against a schema; brain holds the results.

This is the same pattern as the SessionStart "brain of loop" framing: brain holds judgment; subagents hold token volume.

## What this skill is NOT

- **Not `/compound`** — `/compound` writes substrate after closed work (Record / Promote / Retire); `/recall` reads substrate before new work. Same inward direction; opposite verb.
- **Not `/scout-adrs`** — `/scout-adrs` is L3-only and is a sub-tool `/recall` composes. `/recall` covers L1–L3 + skills.
- **Not fresh-context dispatch** — the brain needs substrate IN context for downstream judgment. `file-scanner` / `content-extractor` delegations are volume reduction, not frame-breaking.
- **Not an answer-producer** — produces a routing/orientation block, not the answer to the underlying task. Subsequent skills (`/decompose`, `/implement`, `/brainstorm`, `/adr-write`) consume the orientation.
- **Not a CASS searcher by default** — L1 is expensive and rarely load-bearing per CLAUDE.md "Substrate orientation"; invoke only on explicit retro / audit asks.
- **Not a blanket loader** — tier-routed, not "read everything to be safe." Trivial tasks skip `/recall` entirely.

## Anti-patterns

- **Loading everything "to be safe."** Recall is tier-routed; trivial work should skip recall, not run with empty output.
- **Treating recalled facts as current.** Verify before recommending. A memory naming a file is a claim from when it was written; grep before acting.
- **Recall-then-summarize loop.** Recall produces one orientation block; the brain holds it. Re-running `/recall` mid-task indicates scope-shift, not normal flow.
- **Skipping the absences probe.** Empty substrate can mean "system healthy" OR "system never written to" — distinguish per ADR-013 §Foreseeable failure modes.
- **Substituting `/recall` for `/scout-adrs` at the orchestrator level.** When the task is L3-only (canonical decisions, no L2 pointers expected), `/scout-adrs` is the cheaper primitive. `/recall` is the multi-tier compose.
- **Treating bead-loaded substrate as recall-equivalent.** A bead's `--design` + `## canonical_refs` + prior `/adversarial-review` history is *one layer's worth of frozen orientation* — L3 entries the prior author already cited, plus L2A/L2B never probed for *this* task. The bead's tier-routing captures the prior author's call, not yours; the gravitas tiers above and around the bead need a fresh `/recall` probe at pickup. Skipping because "the bead has a design and reviewed canonical_refs" is the canonical mis-skip — it confuses substrate-already-loaded-in-bead with substrate-already-loaded-in-context.
- **Running `/recall` inside a dispatched subagent — *default*.** The brain is the consumer of orientation; running it inside a haiku / execute-only subagent (`file-scanner`, `content-extractor`, `feature-scout`, single-pass reviewers) leaves the brain without the substrate it needed, and the subagent's context discards on return. The dispatch brief should pre-carry relevant substrate. **Narrow exception:** judgment-bearing subagents (`implementer`, `debugger`, `harness-designer`) operating on a thin brief and hitting a load-bearing decision point may re-orient via `/recall` — better than silently violating a FIRM ADR. Two mechanical prerequisites for that exception: (a) the agent's tool allowlist includes `Skill`, and (b) the dispatch brief names `/recall` so the agent knows to invoke it (SessionStart hooks don't fire for subagents, so skill descriptions aren't auto-loaded).

## Working substrate

- `bd show <id> --json` — bead state for framing
- `bd memories <keyword>` — L2B parking-lot query (preview only, ~80 chars per entry)
- `bd memories <key> --json | jq -r '.<key>'` — full body of one entry (canonical post-filter retrieval)
- `bd memories --json` — full inventory dump (use for index-helper sweep)
- `cm context "<task>" --json` — L2A observations query (cross-project default)
- `cm playbook list` — L2A enumerate / relevance debug (bare `cm playbook` returns help text)
- `/scout-adrs` — L3 query primitive (composed)
- `docs/decisions/INDEX.md` — L3 fallback when `/scout-adrs` unavailable; scope-tag column for routing
- `file-scanner` agent — volume scans (INDEX.md, skill descriptions, multi-ADR enum)
- `content-extractor` agent — deep-read 1-5 ADR / memory files against orientation schema
- `rg` / `fd` / `Grep` — verify currency of claims naming files / functions / flags
- `git log` / `git show` — verify currency of memory claims naming commits or recent authoring dates
- `cass search "<topic>"` / `cass view <session-id>` — L1 query (only on explicit retro / audit triggers)

## Canonical refs

- CLAUDE.md §"Substrate orientation" — tier-by-gravitas discipline this skill codifies; ADRs always-on, bd/cm situational, CASS rare.
- [ADR-013](../../docs/decisions/ADR-013-memory-layer-architecture.md) D1 — three-layer architecture by lifecycle; defines L1/L2A/L2B/L3 tiers this skill routes across.
- [ADR-013](../../docs/decisions/ADR-013-memory-layer-architecture.md) D2 — L2A vs L2B mutation patterns (fade-on-decay vs retrieve-on-demand); informs tier-routing decisions.
- [ADR-013](../../docs/decisions/ADR-013-memory-layer-architecture.md) D3 — firmness-governed mutation; informs FIRM-constraint flagging in output.
- [ADR-013](../../docs/decisions/ADR-013-memory-layer-architecture.md) D7 — global vs workspace scope conventions; informs which L2A / L2B substrate to query when project-scoped.
- [ADR-012](../../docs/decisions/ADR-012-substrate-thick-process-thin.md) D1, D3 — substrate-thick / process-thin; primitive shape pattern (note: `/recall` is brain-run, a deliberate departure from the fresh-dispatch primitives — see "Brain-run vs fresh-context dispatch").
- compound/SKILL.md (methodology home) — write-counterpart; symmetric inward-look design (this skill is its read mirror).
- scout-adrs/SKILL.md (methodology home) — composed sub-tool for L3 queries.
- file-scanner agent (methodology home) — haiku-tier inventory agent for volume scans.
- content-extractor agent (methodology home) — haiku-tier deep-read agent for schema-pinned extraction.
