# ADR-013: Memory Layer Architecture — Three Layers by Lifecycle, Bicameral L2

**Status:** Accepted (decisions are FIRM / FLEXIBLE / EXPLORATORY per-decision below; dogfooding bar in §Dogfooding bar)
**Date:** 2026-05-12 (revised 2026-05-13, 2026-05-18, 2026-05-19)
**Design:** [history/2026-05-12-memory-layer-design.md](../../history/2026-05-12-memory-layer-design.md)
**Related:**
- [ADR-012](ADR-012-substrate-thick-process-thin.md) D4 — bicameral compounding spine; this ADR sharpens and replaces the bicameral framing with a three-layer one.
- [ADR-008](ADR-008-adr-predicates-and-plan.md) D1 — firmness + alternatives + invalidation per decision (followed throughout).
- [ADR-011](ADR-011-adrs-reflect-target-architecture.md) D1 — in-place mutation rule (referenced by D3).
- [ADR-006](ADR-006-workflow-modernization.md) — broader workflow modernization arc.
- `bd remember` (beads CLI) — L2B substrate.
- `cm` (cass-memory-system) and `cass` (coding-agent-session-search) CLIs — L2A and L1 substrates.

## Context

ADR-012 D4 sketched a "bicameral compounding spine": ADRs hold decisions; a lighter memory layer holds observations + procedural learnings via `bd remember` with a `kind` enum. A brainstorm bead was scoped to spec that schema extension.

During brainstorming the scope expanded. A research pass (Karpathy LLM Wiki, Telos, CASS, CASSMS, Compound Engineering / Every, Cipher Day-30, Letta/MemPalace, Mem0, ACE, MemOS, OpenClaw, Hindsight, Vektor AUDN) showed every external memory system that scales beyond solo use converges on 3+ layers split by *lifecycle/derivation* (raw → mutable → canonical), not by content shape. A pressure-test against 12 real corpus entries in this repo surfaced two distinct mutation patterns in what the bicameral framing had collapsed into one bucket (fade-on-decay observations vs retrieve-on-demand parking-lot), and dissolved a "failed-attempts home" collision the original framing carried. A `/compound` smoke-test on this machine's existing data validated a judgment-driven retrospective shape over threshold-driven gates.

This ADR captures the resulting architecture as a cross-cutting Anchored Decision Record per ADR-012 D1: the decisions constrain bd usage, ADR practice, skill design, and SessionStart hook behavior across every domain. It supersedes ADR-012 D4's bicameral sketch (in-place edit to ADR-012 D4 references this ADR).

**Shape-refinement (in-place edit 2026-05-12 per ADR-011 D1).** A subsequent design pass aligned `/compound`'s shape to ADR-012 D3's primitive pattern, which had been implicit across scope-check / adversarial-review / decompose. The refinement surfaced that `/compound` is the inward-look counterpart to scope-check (same fresh-context dispatch, same orchestrator-folds, same substrate-residue shape — applied to memory substrate instead of code/bead neighbors). The implication: previous draft decisions D5/D6 that prescribed internal step protocols (5-step pattern, probe enum, weekly cache cadence) are process inside the primitive, not substrate. They are rewritten below to match the primitive pattern. ADR-012 D3 is in-place edited to make the primitive shape explicit and to register `/compound` as primitive #7.

## Decisions

---

### D1: Three-layer architecture, split by lifecycle/derivation

**Firmness: FIRM**

Memory is partitioned into three lifecycle layers:

```
L3 Canonical    ADRs · CLAUDE.md · skills        argument-or-noticing per firmness
       ▲
       │ /compound Promote section → /adr-write composition (D3 #6)
       │
   ┌───┴────────────────────┐  ┌────────────────────────┐
   │ L2A Observations       │  │ L2B Parking-lot        │
   │  CASSMS  (cm CLI)      │  │  bd remember           │
   │  fade-on-decay         │  │  no decay              │
   │  cross-project default │  │  per-project           │
   └────────────────────────┘  └────────────────────────┘
       ▲
       │ CASS provides evidence + recurrence signals
       │
L1 Raw          CASS index over session JSONL · bd audit · git · bead --notes
```

L1 is raw event substrate (immutable, indexed). L2 is mutable working belief (decays or is curated). L3 is canonical (argument-or-noticing per firmness). Decisions vs observations live *inside* layers (L3 vs L2A respectively); the top-level partition is lifecycle-based.

**Rationale:** External convergence — every memory system that scales beyond solo use lands on 3+ layers by lifecycle. Bicameral content-shape splits (ADR-012 D4 draft) produced two collisions surfaced in pressure-test: a failed-attempts home (collides with both anti-pattern observations and ADR Alternatives), and a parking-lot/observation conflation (current `bd memories` is parking-lot but was treated as observations).

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **3-layer by lifecycle (chosen)** | Matches external convergence; dissolves failed-attempts collision and parking-lot/observation conflation | One more layer to police vs bicameral |
| Bicameral by content-shape (ADR-012 D4 draft) | Fewer layers; existing tooling fits | Failed-attempts collision; parking-lot mistreated as observations. **direct:** pressure-test against 12 real corpus entries surfaced the failed-attempts collision and parking-lot/observation conflation that the bicameral framing produced |
| N-cameral by role (Telos-style 7 objects) | Each shape gets fitted tooling | Overbuilt for current scale. **external:** Telos-style 7-object memory system — comprehensive but adds governance and tooling overhead that isn't justified at solo scale |

**What would invalidate this:** dogfooding shows layer boundaries don't predict mutation rate — e.g. L2A entries routinely require argument to revise, or L3 entries routinely change on noticing without producing churn. Counter-signal: cross-layer migration is rare enough that the boundary is doing no work.

---

### D2: Two parallel L2 surfaces split by decay-behavior  *(rewritten 2026-05-18 in-place per ADR-011 D1 — previous version split by parking-lot vs observations; rewritten in a memory-write redesign epic after dogfood evidence showed the parking-lot framing was contradicted by L2B's de-facto session-start-loading and that 2/4 L2A kinds had wrong decay-shape. The originating epic's `--design` carries the full rationale and alternatives table; this section is the canonical summary.)*

**Firmness: FLEXIBLE**

L2 splits into two surfaces by mutation behavior — fading vs non-fading:

- **L2A — Decaying observations.** Substrate (Claude Code binding): cm playbook (CASSMS). Holds entries that should fade if unused. Kinds: `observation`, `calibration` (see D8). Per-entry decay via 90-day half-life; mark-on-use (`cm mark`) reinforces. Default scope: global; workspace overlay for project-specific entries (per D7).
- **L2B — Non-decaying agent-knowledge.** Substrate (Claude Code binding): bd memories with body-convention discipline (see the memory-write redesign epic's design D2 for the body convention spec; canonical reference: `bd-memories-write/SKILL.md` in the methodology home). Holds entries that must persist indefinitely. Kinds: `procedural-lesson`, `anti-pattern`, `user-pref`, `project-anchor`, `reference` (see D8). No decay; staleness signals surface age but don't drop entries. Per-project (bd-native scope).

**Substrate choice IS the decay decision.** "Should this fade?" → L2A. "Should this persist?" → L2B. The question is forced at write-time.

**Per-entry override is NOT in scope** for this decision. If dogfooding surfaces routine misclassifications (calibrations that need persistence; procedural-lessons that have gone stale), a per-entry `--pinned` flag on L2A or `--expires` convention on L2B would be warranted — but adding this surface now over-engineers ahead of evidence. Watch for it in /compound dogfood runs (5+ runs) before adding.

**Rationale:** The previous parking-lot framing conflated two orthogonal axes: content category and decay behavior. Dogfooding surfaced that decay-behavior is the load-bearing axis (observations CAN fade safely; procedural-lessons CANNOT — you don't "consult" an anti-pattern in a markable way; you stay clear of the trap, so mark-on-use can't reset decay for warning-kinds). Reframing by decay-behavior gives each substrate a clear job and forces the right question at write-time. Additionally: L2B's prior "retrieve-on-demand" framing contradicted its actual session-start-loaded use (via `bd prime` hook); the new framing matches observed behavior.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **L2A/L2B split by decay-behavior (chosen)** | Substrate-choice is decay-decision; each substrate plays to its strength; cross-agent portable; hedges bus-factor across two substrates | Two stores still; convention layer on bd is unenforced |
| Collapse L2 into single cm playbook with `--pinned` discipline | One substrate; architecturally cleanest | All-in on cm (single-author, weeks-old per D4 bus-factor risk); `--pinned` is an easy-to-forget flag default; less Pi/Codex-portable. **reasoned:** D4 already FLEXIBLE'd cm adoption specifically because of bus-factor; collapsing L2 onto cm doubles down on the same risk without earned evidence |
| Keep prior parking-lot vs observations split | No change | Contradicts observed use; doesn't fix decay-mismatch for procedural-lesson/anti-pattern; doesn't address auto-memory/bd-memories duplication. **direct:** the `bd prime` hook auto-injects L2B index at session start, proving L2B is session-start-loaded not retrieve-on-demand; the prior framing was contradicted by the substrate's own session-start behavior |
| Tri-substrate (L2A + L2B + auto-memory as distinct canonical layers) | Maximum expressiveness | Auto-memory is Claude-Code-internal — breaks cross-agent portability. **direct:** Pi-agent literally cannot use Claude Code's auto-memory system; treating it as a canonical layer encodes Claude lock-in into the architecture |

**What would invalidate this:** dogfooding shows procedural-lesson / anti-pattern entries DO benefit from a decay mechanism (e.g. stale lessons accumulate as junk and need explicit pruning); OR observation/calibration entries routinely need permanent retention; OR orchestrators are routinely reclassifying /compound Record entries between L2A and L2B during fold across 5+ runs (substrate-choice split would then be too coarse and per-entry override warranted).

---

### D3: Mutation rule follows firmness label, not layer

**Firmness: FIRM**

L3 entries are not uniformly argument-to-revise. The mutation rule follows the ADR's `Firmness:` label (per ADR-008 D1):

- **FIRM** L3 entries → argument required to revise.
- **EXPLORATORY** L3 entries → noticing sufficient (mutates like L2).
- **FLEXIBLE** L3 entries → middle ground (substantive observation or small set of cases; not full ADR debate).

This makes mutation rate orthogonal to layer placement. ADR-011 D1's in-place edit rule is the mechanism; this decision says firmness governs *whether* an in-place edit needs argument or noticing.

**Rationale:** Pressure-test example #12 — every decision in ADR-012 carries firmness EXPLORATORY pending dogfooding. A layer-governed "L3 requires argument" rule contradicts the explicit firmness label on those decisions. Firmness was already the substrate signal; making it the mutation governor prevents drift between firmness and edit-discipline.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **Firmness-governed mutation (chosen)** | Coherent with ADR-008 D1 + ADR-011 D1; predicts behavior of EXPLORATORY ADRs | Two-rule mental model (layer placement + firmness mutation) |
| Layer-governed mutation (L3 = argument-required uniformly) | Simple | Contradicts EXPLORATORY firmness semantics. **direct:** ADR-012's decisions D1–D5 explicitly carry EXPLORATORY firmness; a uniform "L3 = argument-required" rule would contradict the explicit firmness label on those decisions |
| Single mutation rule for all L3 | Simplest | Forces all decisions to be FIRM — eliminates EXPLORATORY as a useful label. **reasoned:** if the mutation rule is uniform regardless of firmness, the firmness label conveys no information about edit discipline; EXPLORATORY becomes a decoration rather than a governance signal |

**What would invalidate this:** firmness drift accumulates because EXPLORATORY-ADR edit-on-noticing creates churn faster than decisions firm up. Counter-signal: ADR-012's decisions stay EXPLORATORY for >6 months with no firmness progression, suggesting the label isn't moving anything along.

---

### D4: Adopt CASS + CASSMS as L1 / L2A substrate

**Firmness: FLEXIBLE**

- **CASS** (coding_agent_session_search, Rust CLI `cass`) is L1's indexer. Already installed; already used.
- **CASSMS** (cass_memory_system, TS/Bun CLI `cm`) is L2A's curator. Wraps CASS for evidence-gating. PlaybookBullet schema (id, content, category, scope, type, maturity, helpful/harmful counts, sourceAgents, sourceSessions, confidence with 90-day half-life) is L2A's storage.
- **Integration is CLI-only** — no MCP server (per user preference). CASSMS's HTTP MCP server (`cm serve`) is not used.
- **Build only:**
  1. `/compound` slash command (skill at `compound/` in the methodology home) — implements the primitive per [ADR-012 D3](ADR-012-substrate-thick-process-thin.md) primitive shape (narrow verb, fresh-context `Task()` dispatch, three-section Record/Promote/Retire output, orchestrator folds, substrate residue). Internal design at D5/D6 below. SKILL.md sized to match scope-check / adversarial-review / decompose (~150 lines), not a wrapped 5-step protocol.
  2. SessionStart hook merging `bd memories` + `cm context "$task" --json` into prime-time injection.
  3. Conventions for scope (`bullet.scope`) — global default, workspace overlay for project-specific observations.

**Risks named:**
- **Bus-factor.** CASS and CASSMS are by a single author; CASSMS was installed days ago. FIRM on a fresh single-author dependency is aggressive — hence FLEXIBLE.
- **Aspirational scale.** "Load-bearing at 10s→100s of agents" is a stated trajectory, not a measured signal. Substrate-thick principle (ADR-012 D1) cautions against building for aspirational scale; D4 is FLEXIBLE partly because of this.
- **Unverified SessionStart merge.** Current hook runs `bd prime` only; the `cm context --json` merge is not yet built. Build-phase item, not a brainstorm assumption.
- **CASSMS version pinning.** Schema may shift upstream. Build phase pins a version (smoke-test was on cm v0.2.9 / cass v0.4.2, 2026-05-12).

**Rationale:** CASS + CASSMS already implement most of what the spec asked for. Re-building incurs cost with no differentiation; adopt-and-wrap is the substrate-thick path. FLEXIBLE firmness reflects bus-factor and aspirational-scale risks — adoption is the right direction; the specific upstream choice should be revisable on signal.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **Adopt CASS + CASSMS (chosen)** | Working code exists; CLI-only; same author as CASS already in use | External dependency; bus-factor; CASSMS schema may shift |
| Build light custom L2A — extend `bd remember` with `--kind` enum + half-life timestamp + filter retriever; skip CASSMS's helpful/harmful counts and candidate→proven gates | No external dependency; matches existing bd workflow; ships in weeks | Lacks confidence decay, anti-pattern inversion, sourceAgents semantics for free; calendar time even if "light". **reasoned:** CASSMS already ships the features that would be the hardest to build (confidence decay, anti-pattern inversion, sourceAgents); replicating them takes calendar time that is better spent on `/compound` |
| Adopt meta_skill (`ms`) as L2A | Richer feedback loop; `prune proposals --emit-beads` is closer to /compound shape | Heavier; depends on `bv`; separate larger commitment. **reasoned:** meta_skill brings a dependency chain (`bv`, separate tooling) that is a larger adoption commitment than CASSMS; substrate-thick principle (ADR-012 D1) prefers working substrate over aspirational replacements |
| MCP integration (cm serve) | Easier protocol | User preference is CLI; protocol overhead unwarranted. **direct:** user preference is explicitly CLI-only; `cm serve` introduces a server process and protocol overhead that the CLI-only constraint rules out |

The "Build light" alternative is genuinely close. The deciding factor is that CASSMS already ships confidence decay, anti-pattern inversion, and sourceAgents — building those takes calendar time better spent on `/compound`. If CASSMS upstream destabilizes, the steelman is the fallback (fork or rebuild within the bd-remember substrate).

**What would invalidate this:** CASSMS's schema mismatches how observations actually accumulate (>20% of L2A writes need schema gymnastics after 30 days dogfooding); upstream becomes unstable or abandoned; the helpful/harmful machinery proves load-bearing earlier than expected and the 10-category hardcoded enum hits a limit.

---

### D5: `/compound` primitive shape — mirrors scope-check (ADR-012 D3)

**Firmness: FLEXIBLE**  *(rewritten 2026-05-12 in-place per ADR-011 D1 — previous version prescribed an internal 5-step protocol, which was process inside the primitive rather than substrate. The protocol is dissolved; the primitive shape is what's load-bearing.)*

`/compound` instantiates the ADR-012 D3 primitive pattern. Its load-bearing properties are the **shape**, not an internal step sequence:

- **Narrow verb, single purpose.** Distill compounding-worthy signal from a closed unit of work (bead / epic / window). Does not write canonical substrate itself.
- **Fresh-context `Task()` dispatch, single dispatch.** Originating session shares the work's blind spots; the fresh subagent reads CASS / `cm playbook` / `bd memories` / ADR INDEX / recent ADRs / recent closed beads / open-bead `--notes` from outside the frame. Subagent's brief lists these substrate signals; subagent composes them by judgment (no prescribed order, no enumerated probe types).
- **Three-section output artifact** *(this is the load-bearing shape)*:
  - **Record** — candidate L2A bullets (cm write) or L2B parking-lot entries (bd remember), each with one-line rationale. **Record deliberately covers both edit-existing and create-new** — the previous-draft distinction between `fold-in-place` (mutate existing L2A) and `propose-L2A` (create new) collapses here, mirroring ADR-011 D1's preference for in-place edit over chained versions. The orchestrator chooses mutate-vs-create at fold-time based on whether an existing bullet covers the candidate; the subagent's output flags this as `edit:<bullet-id>` or `new` per Record entry.
  - **Promote** — load-bearing L3 candidates, each with countermand reasoning *(the "why is this still right after challenge?" sketch)* and the proposed L3 target (ADR-NNN edit / CLAUDE.md section / skill edit).
  - **Retire** — fulfilled-pointer parking-lot keys and low-utility L2A bullets, each with the trigger that fulfilled or invalidated it.
- **The "watch-this-grow" pattern is handled by substrate, not by an extra section.** A candidate that's worth Recording now and may merit Promoting later does not need a special bucket — it lands in Record (L2A), and CASSMS `helpful_count` / cited-by signals are the substrate that surfaces it for Promote review at the next `/compound` run. No fourth section needed.
- **Orchestrator folds.** The subagent produces; the orchestrator decides per-entry:
  - Record entries → `cm playbook add` (L2A) or `bd remember --key ...` (L2B).
  - Promote entries → invoke `/adr-write` (ADR-012 D3 primitive #6) as a *separate composition step*. `/adr-write` will own the actual L3 authorship and the alignment-question discipline (per ADR-011 D1 in-place rules + ADR-013 D3 firmness-governed mutation). `/compound` does not author L3 itself.
    - **Interim discipline (until `/adr-write` exists)**: `/adr-write` is a named-but-unbuilt primitive per ADR-012 D3 #6. Until it lands, the orchestrator carries the L3 authorship discipline inline when acting on a Promote candidate: read the proposed target ADR/CLAUDE/skill; apply the firmness-governed mutation rule (D3); draft the edit; surface a one-sentence alignment question to the user before writing. This interim sits in the orchestrator's recipe-level, not in `/compound`'s primitive surface. The discipline is preserved across the gap — not floating.
  - Retire entries → `bd forget <key>` (L2B) or annotate `cm` bullet for accelerated decay (L2A).
- **Substrate residue.** See D6 below.

**Critical constraint preserved from earlier draft — judgment, not thresholds.** Counts and recurrence are inputs to subagent judgment, never gates. Critical-but-rare observations occur once; hardcoded count thresholds miss them. Smoke-test example #1 (missing dogfood ledger) was a structural absence no threshold-based query could surface.

**What disappears vs the previous draft:**
- 5-step pattern (read → probe → surface → classify → draft): subagent composes from substrate signals; step sequence is judgment.
- Verdict enum (fold / propose-L2A / RAISE / defer / retire): the three-section output is the verdict shape; "fold-in-place" lives in the orchestrator's act of choosing Record over Promote.
- Internal probe enum (presence / absence / recurrence / staleness) → moved to D6 as informational substrate-signal listing, not as a prescribed enumeration the subagent must execute.
- Agent drafts ADR inside `/compound` → drafting moves to `/adr-write` as a separate composition step.

**Rationale:** ADR-012 D3 primitive shape is now explicit; once it is, `/compound`'s previous internal scaffolding is recognizable as process the primitive shape already implies (fresh dispatch, specific output) or that belongs in a sibling primitive (`/adr-write` for L3 authorship). Internal protocols don't scale with model intelligence; the shape does.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **Primitive-shape per ADR-012 D3 (chosen)** | Matches sibling primitives; scales with model intelligence; composes via /adr-write for L3; output-shape is the constraint | Variance in subagent quality across runs (inherent to all fresh-dispatch primitives) |
| 5-step internal protocol (previous draft) | Prescribed; predictable | Process inside the primitive; bundles L3 authorship with L2 surfacing. **reasoned:** ADR-012 D3's primitive shape makes internal step sequences judgment, not prescribed; a 5-step protocol violates the shape by making the primitive process-thick rather than output-shape-constrained |
| No primitive, raw CLIs + CLAUDE.md guidance | Maximally thin | Forces orchestrator to assemble memory mechanics every invocation; not composable like sibling primitives. **reasoned:** scope-check, adversarial-review, and decompose are all primitives; making `/compound` a prose-guidance-only pattern creates an inconsistent surface where one category of work (memory) has no primitive while all others do |
| Bundle compound + adr-write into one primitive | Fewer hops | Violates "narrow verb, single purpose"; L3 authorship discipline (alignment question) is /adr-write's concern not /compound's. **direct:** ADR-012 D3's primitive shape principle: "narrow verb, single purpose" — `/compound` distills signal; `/adr-write` authors canonical artifacts; bundling conflates surfacing with authorship |

**What would invalidate this:**
- Subagent output across multiple dogfooding runs requires more orchestrator post-processing than the three-section shape promised (e.g. orchestrator routinely re-classifies the subagent's section assignments).
- The Promote / Record boundary keeps blurring in practice (e.g. >30% of fold-time orchestrator decisions are reclassifications between the two sections), suggesting the output shape needs revision.
- The Record-section edit-vs-new collapse fails (e.g. duplicate L2A bullets accumulate because the subagent can't reliably identify existing-bullet candidates), suggesting the previous-draft `fold-in-place` vs `propose-L2A` split was load-bearing after all.
- After `/adr-write` exists and `/compound` Promote has handed off ≥5 times, the orchestrator's interim alignment-question discipline shows it never actually fires (suggesting Promote → L3 authorship is a discipline that needs to live elsewhere, possibly back inside `/compound`).

**Dominant risk** (named explicitly per L5 fold-in below): `/adr-write` is a named-but-unbuilt primitive (ADR-012 D3 #6). Until it lands, `/compound` Promote depends on the orchestrator's interim discipline. If `/adr-write` is not built within the dogfooding window, the Promote handoff is recipe-level only — testing the primitive shape in isolation, not the composition.

---

### D6: `/compound` invocation, default-on trigger, and substrate residue

**Firmness: FLEXIBLE**  *(rewritten 2026-05-12 in-place per ADR-011 D1 — previous version prescribed internal probe enums and weekly cache cadence, which were process inside the primitive. Substrate hooks survive; internal mechanics dissolve. Harness-routing branch added 2026-05-22 in-place per ADR-011 D1 — the substrate-discipline epic.)*

- **Surface:** `/compound [--epic <id>] [--since <window>] [--bead <id>]`. One verb. Scope-bindable. Flags are subagent-brief inputs, not separate subcommands.
- **Default-on trigger** *(analog: scope-check's "multi-bead-epic bead authoring" default-on trigger, but legibility is weaker — see below)*: invocation is default-on at **epic close** — i.e. when `bd close` is invoked on a parent bead whose dep-tree contained ≥ 1 child closed since the parent was authored. Other invocations (mid-flight pattern-noticing, time-windowed sweeps) are judgment-routed.
- **Trigger legibility — sharpened 2026-05-13 in-place per ADR-011 D1.** The original draft proposed an `epic` label convention as the sharpening substrate; on inspection (2026-05-13), bd already carries a built-in `type=epic` field set at bead creation — the label would duplicate that signal. The corrected predicate: at close-time, evaluate the bead's `type` field (one-query check via `bd show <id> --json | jq -r '.[0].type == "epic"'`, or `bd list --type=epic` for batch queries). Combined with the parent-child closed-children check, this gives `/compound` a substrate-legible trigger without introducing a duplicate-signal label. The `epic` label convention is retired before adoption; back-labeling is unnecessary (existing epics already carry `type=epic`). Scope-check's create-time trigger remains the cleaner pattern; `/compound`'s trigger composes a type-check with a closed-children check, two queries to scope-check's one — acknowledged-but-acceptable looseness.
- **Substrate residue:**
  - `compounded` label on the bead/epic that was the subject of the run, stamped with `BEADS_ACTOR=compound:fresh-subagent`.
  - Audit-log entry recording: subject bead/epic ID, three-section finding counts (Record-N / Promote-N / Retire-N), and the substrate signals consulted (cass / cm / bd memories / ADR INDEX / recent closed beads).
  - Distinct label name from `verdict:*` and `scope-checked` — labels are presence/absence routing surfaces, not pass/fail. Future close-gate consumers can read `compounded` independently (analog: the verdict close-time check's `verdict:*` consumption, the parked scope-check's `scope-checked` consumption).
  - No freshness predicate in this spec; staleness deferred until a real consumer asks (matches scope-check's identical deferral).
- **Harness-shaped lesson routing (added 2026-05-22):** A distinct routing branch in `/compound`'s Record step for lessons that are *inventory-shaped* rather than *procedural-knowledge-shaped*. These route to a `.claude/harness.md` inventory-update proposal (file path + section + diff sketch), not to `bd remember`.

  **Recognition pattern — what makes a lesson harness-shaped:**

  A lesson is harness-shaped if it answers one of these structural questions about *what signals catch what class of bugs at what altitude*:
  1. **Fit-for-work pattern:** "For [X kind of work] in this repo, prefer [Y mechanism] because [Z — what it catches that alternatives miss]." The lesson is about *which signal to reach for*, not about *how to behave in a workflow*.
  2. **Coverage gap:** "Harness type [A] at altitude [B] caught / missed class [C] of defect." The lesson updates an entry's `Catches` or `Less useful when` field, or reveals a gap the current inventory doesn't name.
  3. **Fit swap:** "Verification mechanism [M] is poorly fit for surface [S]; better fit is [N]." The lesson replaces or adds a fit profile entry.

  The discriminating question is: **does the lesson populate a *per-mechanism-per-work-shape* cell in the harness inventory, or does it guide agent behavior?** Inventory-cell → `.claude/harness.md`. Agent-behavior guidance → `bd remember` (procedural-lesson / anti-pattern / etc. per D8).

  **Contrast with bd-remember shapes (ADR-013 D8):** Procedural lessons ("always run X before Y"), anti-patterns ("never do Z"), user-prefs, project-anchors, and references are NOT harness-shaped even if they mention a tool name. The test is: *would this lesson appear as a row/cell in a harness inventory?* If no, it's bd-shaped.

  **Ambiguous (L3) routing:** When a candidate lesson has both harness-shaped and bd-shaped characteristics (e.g., it mentions a harness type AND contains a procedural step), apply the **primary-signal test**: does the lesson's *primary content* characterize a signal-fit relationship (→ `.claude/harness.md`) or prescribe agent behavior (→ `bd remember`)? If neither dominates, surface both routes to the orchestrator — the two proposals are not mutually exclusive; a single lesson can warrant an inventory-update proposal AND a bd procedural-lesson entry when both fit genuinely and independently.
- **Substrate signals available to the fresh subagent's brief** *(listed, not prescribed as probes — the subagent composes them as judgment warrants)*:
  - `cass --since <window>` over recent session JSONL (L1 raw).
  - `cm playbook` and `cm context "<task>" --json` for L2A relevance and decay state.
  - `bd memories` for L2B parking-lot.
  - `docs/decisions/INDEX.md` + ADRs in scope for L3.
  - Recent closed beads (`bd list --status=closed --since=...`) and open bead `--notes` in the active epic.
  - Git log over the same window.
- **CASS substrate caveat** *(preserved from earlier draft)*: prefer 2-term lexical queries with `--explain` for auditability; never trust CASS hit counts alone; cross-check against ADRs / git / bd. CASS FTS is brittle on short tokens (sandboxed as L2A calibration entry on first `/compound` write).

**What disappears vs the previous draft:**
- Internal probe enum (presence / absence / recurrence / staleness): folded into the substrate-signals listing as inputs; subagent decides which probes to run.
- Pre-aggregated CASS health summary cached weekly: premature performance optimization; defer until the cost shows up in dogfooding.
- Alignment-question template requirement: moved to `/adr-write` per D5, where L3 authorship lives.

**Rationale:** Default-on at epic close gives `/compound` its scope-check-equivalent structural trigger (closing-gate event that's substrate-legible at the moment it fires). Substrate residue makes the run inspectable and composable by future close-gates without prescribing the internal mechanics. Substrate hooks survive; internal probe protocols don't.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **Default-on at epic close + judgment-routed otherwise (chosen)** | Structural trigger matches scope-check pattern; substrate-legible; doesn't fire on every bead | Some learning attaches to non-epic units of work (single beads, time windows) — captured by judgment-routed invocation |
| Default-on at every bead close | Always-on at finer grain | Too noisy; many bead-closes have nothing to compound. **reasoned:** single leaf beads often represent narrow implementation steps with no cross-cutting learning to surface; firing `/compound` on every close produces mostly-empty outputs that degrade the substrate signal |
| Explicit-only (previous draft) | Lowest invocation friction | Larson failure: retrospective forgotten on weeks where most learning accumulated. **external:** Larson solo-variant failure mode — explicit-only retrospectives are forgotten precisely during the weeks when the most learning accumulates; the trigger must be structural to be reliable |
| Cron-scheduled | Catches forgotten weeks | No scope-binding to active work; misses bead-shaped boundaries. **reasoned:** a cron-scheduled trigger has no natural scope boundary; it compiles over a time window that may span multiple epics, making it harder to focus the compound subagent on a coherent unit of work |

**What would invalidate this:** epic closes routinely fire `/compound` on near-empty units (false positives); or epics empirically aren't the right boundary (most learning crosses epics); or judgment-routed mid-flight invocation never happens, suggesting the trigger surface is too narrow.

---

### D7: Global vs local substrate placement

**Firmness: FLEXIBLE**

- **L2A (cm):** global default at `~/.local/share/cass-memory/playbook.yaml`; workspace overlay at `<workspace>/.cass/playbook.yaml`. Cross-cutting observations land global; project-specific observations use `bullet.scope: workspace` and write to overlay.
- **L2B (bd remember):** **per-project, scoped to `.beads/` of the active repo** *(reaffirmed 2026-05-18 in-place in the memory-write redesign epic — bd-memories per-project scope was previously implicit-via-bd-CLI; now stated explicitly so cross-environment implementations of L2B inherit a clear scope contract per D9)*. Existing convention unchanged.
- **L3 canonical:** dual-tier, existing convention.
  - Global ADRs / agent instructions / skills in the methodology home.
  - Per-project at `<repo>/docs/decisions/` and `<repo>/CLAUDE.md`.
- **Cross-agent (Claude / Codex / Pi):** CASSMS schema supports `sourceAgents[]` + privacy allowlist. **Schema-ready, not demonstrated.** No cross-agent operation has been verified at this writing — casr (cross_agent_session_resumer) is not installed; no Pi-Agent has written to the playbook; no contamination test has run. The design assumes the schema supports the use case; treat as conjecture until first cross-agent dogfooding entry lands.

**Scope-decision convention** (for `/compound` and human writers):
- Tied to this project's stack/repo → workspace overlay.
- Tied to the user's workflow regardless of project → global.
- When in doubt → global (defaults to broader applicability; can be scope-narrowed later).

**Rationale:** Cross-project learning is the main reason for adopting CASSMS over a per-project store; global default captures that. Workspace overlay is the escape hatch for genuinely project-specific entries. Cross-agent is a stated trajectory but not yet earned — labeled accordingly.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **Global default + workspace overlay (chosen)** | Cross-project learning; CASSMS native | Cross-project contamination risk |
| Per-project everything | Clean scoping | Loses cross-project learning at target scale. **reasoned:** cross-project learning is the main reason for adopting CASSMS over a per-project store; per-project scoping severs the cross-project signal that makes L2A valuable at scale |
| Global everything | Maximum cross-pollination | No project isolation. **reasoned:** some observations are genuinely project-specific (e.g. "this repo's test harness is slow on ARM"); polluting the global playbook with project-specific entries degrades cross-project retrieval quality |

**What would invalidate this:** cross-agent contamination becomes real (agent-A's environment-specific observation poisons agent-B's context); or no observations ever turn out to be cross-project, making the global default empty.

---

### D8: L2 `kind` enum — split across L2A and L2B by decay-behavior  *(extended 2026-05-18 in-place per ADR-011 D1 — previously L2A-only with 4 kinds and L2B free-text; rewritten in the memory-write redesign epic to align with D2's decay-behavior split. L2B is no longer free-text; it carries typed kinds via the body-convention discipline in bd-memories-write/SKILL.md (methodology home). Previous "L2B free-text by design" rationale is superseded — the convention IS the typing layer.)*

**Firmness: EXPLORATORY**

L2 entries carry a `kind` per their target substrate. The enum is split by decay-behavior (per D2):

**L2A kinds** (decaying, mapped to CASSMS's `type` field):
- `observation` — neutral finding (e.g. "test harness slow on ARM Macs").
- `calibration` — numeric/magnitude correction (e.g. "webhook bead scope ~2x", "scope-check fold yield averaged 4.2 over 12 runs").

**L2B kinds** (non-decaying, encoded in the body-convention frontmatter per `bd-memories-write/SKILL.md` in the methodology home):
- `procedural-lesson` — "do X next time / never do Y" (pure guidance the agent should follow).
- `anti-pattern` — inverted failure (e.g. "PITFALL: don't cache auth tokens without expiry validation"; the agent stays clear of the trap, no markable consult).
- `user-pref` — user-stated preference for how the agent should work (e.g. "always use uv for Python").
- `project-anchor` — current repo's state, conventions, build flags, migration status, parked-decision pointers.
- `reference` — pointer to external systems, repos, or docs (regardless of consultation frequency; origin-of-content is the discriminator).

**Why the L2A/L2B kind split is decay-behavior-driven:** observations and calibrations can legitimately fade if unused; procedural-lessons and anti-patterns are pure-warning patterns that should be permanently true. The previous L2A-only enum (which included procedural-lesson and anti-pattern) created a structural mismatch with CASSMS's 90-day half-life. Migrating warning-kinds to L2B (no decay) closes the mismatch.

**Dropped from ADR-012 D4's draft enum:**
- `failed-attempt` — collapses into either `anti-pattern` (L2B) or ADR `Alternatives` (L3 via `/compound antipatterns`). Single-home.
- `env-note` — subsumed into `observation`; "test harness slow on ARM" is just an observation. Smoke-test surfaced no entries needing a separate env-note kind.

**Side-effect on sibling bead 5f1.5.4** ("extend bd remember schema"): D8 implies 5f1.5.4 should close as obsolete (bd remember stays unkinded). Handled via dependency note on 5f1.5.4; not auto-closed from this ADR.

**L2B retirement path:** parking-lot entries do not decay automatically. When a pointer is fulfilled (e.g. an L2B entry referencing an ADR that now exists), explicit retirement via `bd forget <key>` is the path. `/compound`'s **Retire** output section (D5) surfaces fulfilled-pointer candidates; the orchestrator decides whether to call `bd forget`.

**CASSMS anti-pattern verification needed:** the design asserts `anti-pattern` is a CASSMS native inversion semantic. Smoke-test observed `type: workflow_rule` only. Build phase verifies whether `anti-pattern` is a valid `type` value, or maps to a CASSMS-supported type with a content prefix convention (e.g. `type: workflow_rule` with `content` prefixed `PITFALL:`).

**Rationale:** 4 kinds cover the smoke-test corpus and map cleanly to CASSMS native semantics. Adding `failed-attempt` re-introduces the collision D1 dissolved. Adding `env-note` is unsupported by real entries. EXPLORATORY firmness reflects that the enum is provisional until 30+ real entries accumulate.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **7 kinds split L2A (2) + L2B (5) by decay-behavior (chosen)** | Each kind matches its decay-shape; covers smoke-test corpus + memory-write redesign migration cases; L2B's typing (via body convention) closes the previous "L2B free-text doesn't benefit from filtering" gap by recognizing that bd memories' index needs kind tags for discovery | Two enums to think about; convention-encoded typing on L2B is unenforced by bd CLI |
| Previous L2A-only 4-kind enum | Single enum; CASSMS-native | Decay-mismatch for procedural-lesson/anti-pattern (90-day half-life on permanent-true patterns); leaves L2B untyped. **direct:** /compound dogfood (the memory-write redesign epic) showed `cm mark` discipline can't reset decay for anti-patterns (you stay clear of the trap, no markable consult) — the decay-mismatch is structural |
| ADR-012 D4 draft (4 kinds with `failed-attempt`, no `anti-pattern`) | Original framing | Failed-attempts collision unresolved. **direct:** D1 pressure-test surfaced the failed-attempts collision — `failed-attempt` entries collide with both `anti-pattern` (L2B) and ADR Alternatives (L3); the collision was the specific finding that drove the D1 rewrite |
| 2-track (CE-style: bug vs knowledge) | External precedent | Doesn't fit observation/calibration shape. **external:** compound-engineering-plugin (EveryInc) bug-vs-knowledge split — their taxonomy fits their pipeline architecture; it doesn't map cleanly to the kind structure that emerged from this repo's real entries |

**What would invalidate this:** real entries during dogfooding routinely don't fit any of the 7 kinds (≥2 raises during /compound Record fold-time → enum extension warranted per the memory-write redesign's D5 raise-recovery procedure); OR one of the 7 stays empty across 30+ entries (kind is unused; collapse it); OR L2A-kinds and L2B-kinds blur such that orchestrators routinely re-route at fold-time (substrate-choice split too coarse; per-entry override warranted per D2).

---

### D9: L2 architecture is impl-agnostic; tooling is per-environment  *(new 2026-05-18 in the memory-write redesign epic — formalizes cross-agent portability constraint surfaced during the same brainstorm that drove D2's rewrite)*

**Firmness: FLEXIBLE**

The L2 architecture (D1, D2, D7, D8) is described in environment-agnostic terms. Specific tool bindings are per-environment.

**Scope of FLEXIBLE.** FLEXIBLE governs the architectural spec — kind enum names, decay-behavior semantics, L2A/L2B abstraction surface, session-start-indexed contract. It does NOT govern the Claude Code recipe binding — embedding `cm playbook add` and `bd remember --key` CLI invocations directly inside /compound's SKILL.md is acceptable and is not a D9 violation. D9 governs how the architectural surface is *described and reasoned about*, not how the Claude Code recipe wires CLIs at fold-time.

**Canonical specification** (impl-agnostic):

- **L2A** = decaying observations + calibrations; relevance-scored retrieval; per-entry decay with reinforcement-on-use; default-global scope with per-project overlay; kind enum per D8 (observation, calibration).
- **L2B** = non-decaying procedural-knowledge + anchors + references; typed; **session-start-indexed** (see behavioral contract below); body retrieved on demand; per-project scope (project = environment-defined); kind enum per D8 (procedural-lesson, anti-pattern, user-pref, project-anchor, reference).

**Behavioral contract for "session-start-indexed"** (impl-agnostic):

> The L2B index (entry titles + one-line previews) MUST be present in the agent's working context at the start of each session — by whatever mechanism the environment provides (a session-start hook injection, a system-prompt block, a tool-call-on-first-message, etc.). The full body of any entry MUST be retrievable on demand via a stable key. No specific session-start mechanism is mandated.
>
> **Falsifiable compliance probe.** Compliant: at session T=0 (before the agent issues any tool call), the L2B index is accessible without an explicit retrieval step — visible in initial context, system-prompt, or equivalent. Non-compliant: the agent must explicitly call a tool at T=0 to retrieve the index — this is retrieve-on-demand, not session-start-indexed, and violates the contract.

**Scope of "project"** is environment-defined: in bd-using environments it maps to bd's per-project repo; for environments without project-scoping, "project" collapses to the agent's working-directory or session-namespace.

**Claude Code binding:** L2A = cm playbook (CASSMS); L2B = bd memories with body-convention discipline per `bd-memories-write/SKILL.md` in the methodology home.

**Other environments** (Pi-agent, Codex-agent, future agents): any backing store meeting the L2A and L2B specs above. Could be cm if cm matures cross-agent; could be bespoke.

**Cheap foresight for future tooling migration:**
- Body convention encoded in content, not CLI schema → bodies migrate intact across stores.
- Kind enum is impl-agnostic → names abstract; storage format per-store.
- Cross-refs use `[[key]]` notation → portable across stores.
- /compound's Record routing logic targets L2A/L2B abstractly; orchestrator's fold step is the only thing touching per-environment CLIs.

**Rationale:** Cross-agent portability was a hard constraint named at brainstorm time (the memory-write redesign epic's convergence). Without architectural-vs-tooling separation, this ADR would encode Claude-Code-specific choices that don't extend. FLEXIBLE (not FIRM) because the invalidation condition (no second environment implements) has no committed timeline — promotion to FIRM should follow earned-by-implementation evidence.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **Impl-agnostic architecture; per-environment tooling (chosen)** | Cross-agent extension is clean; tooling can evolve without redesign; preserves the option for a future Pi/Codex L2 implementation that doesn't fork the architecture | More abstract; readers must do tooling-binding mentally |
| Specify "use bd memories + cm playbook" as canonical L2 | Concrete; immediately actionable | Non-portable; Pi/Codex implementations would fork or diverge. **direct:** the cross-agent portability requirement (named at memory-write redesign epic brainstorm convergence) makes Claude-Code-internal tool choices inappropriate as canonical |
| No impl-agnostic layer; let each environment design its own L2 | Maximum per-environment fit | Architecture intent diverges across environments; no shared substrate for cross-agent learning. **reasoned:** the value of describing L2 architecturally is that observations made in one environment can in principle inform decisions in another (e.g. decay calibration); if every environment defines L2 fresh, that shared-substrate value is lost |

**What would invalidate this:** the spec proves too abstract to implement consistently across environments (each agent picks subtly different mechanics, breaking the architecture's intent); OR no second environment (Pi, Codex, or other) has begun implementing an L2 substrate within the Dogfooding bar window (5 /compound runs across 2 weeks per §Dogfooding bar) — at which point treat the abstraction as unearned and revisit whether the cross-agent framing is doing any work.

---

### D10: Default-on primitives stamp unconditional residue BEFORE interactive gates  *(new 2026-05-19 in the memory-write redesign epic — generalizes the audit-log placement fix from compound/SKILL.md in the methodology home)*

**Firmness: FLEXIBLE**

When a default-on primitive writes unconditional substrate residue (audit-log entry, presence label, file artifact) AND optionally prompts the user / orchestrator for fold actions, the unconditional residue MUST be stamped BEFORE any `AskUserQuestion` / fold-gate / interactive prompt.

**Scope.** Applies to default-on primitives that pair unconditional substrate residue with interactive fold gates: `/compound` (D6 audit-log + `compounded` label), `/adversarial-review` (if residue stamps are added), `/scope-check` (if residue stamps are added), `/scout-adrs` (if residue stamps are added), and future default-on primitives of the same shape. Does NOT apply to fold-conditional residue — e.g. `/compound`'s `compounded` label on bead/epic runs is correctly conditional on fold completion, while its audit-log entry is unconditional and must precede the fold gate.

**Rationale:** The value of unconditional residue is the presence-trail — knowing a run happened is the audit signal, independent of what the fold step chose to do. Placing the unconditional stamp inside a fold-gated execution path makes the stamp conditional in practice: under `--permission-mode bypassPermissions` or any other mode that denies interaction, the gate halts execution and the residue is silently skipped. Source incident: `compound/SKILL.md` initially placed audit-log emission inside the fold step; a dogfood replay run (bare `/compound` invocation, `bypassPermissions` mode) skipped the audit-log entirely. The fix moved the stamp before the `AskUserQuestion` fold-gate, and the retry run stamped `int-c8962308`. The principle generalizes — every default-on primitive's unconditional residue is liable to the same silent skip if ordered after an interactive gate.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **Residue-before-gate as cross-primitive rule (chosen)** | Each new default-on primitive inherits the discipline; no per-primitive reinvention; pairs with D6's audit-log unconditional language | Adds an ordering constraint on every default-on primitive's design |
| Per-primitive judgment (no cross-primitive rule) | Maximum design flexibility per primitive | Recreates the compound bug shape in every new primitive that pairs unconditional residue with an interactive gate. **direct:** the compound audit-log bug (`history/2026-05-19-compound-dogfood-replay/README.md` Criterion 2) was a runtime substrate-skip caused by per-primitive ordering judgment; codifying the rule shifts the default away from re-introducing it |
| Skill-local lesson only (no L3 binding) | Lightest; one L2A calibration already folded | L2A calibrations decay; future default-on primitive designs may be authored without the lesson in context. **reasoned:** the L2A entry exists as the lighter substrate path; D10's marginal value is L3-binding for primitive-authoring contexts where the calibration may have faded |

**What would invalidate this:** a default-on primitive design surfaces where unconditional residue genuinely cannot precede the interactive gate (e.g., the residue payload depends on the gate's outcome to be coherent); OR D10 is silently violated in 2+ subsequent default-on primitives without observable consequence (suggesting the rule isn't load-bearing in practice); OR the principle proves wrong-shaped at residue-bigger-than-audit-log scope (e.g. a primitive that writes substantial file artifacts can't reasonably stamp before user gating).

**See also:** [D11](#d11-juncture-awareness--re-survey-the-primitive-inventory-at-named-junctures) — the symmetric design pattern. D10 ensures the substrate residue *exists*; D11 ensures the residue (and its absence-signaling stderr warnings) is *recognized as a juncture cue* at the moment it matters. Sibling decisions, same family.

---

### D11: Juncture-awareness — re-survey the primitive inventory at named junctures  *(new 2026-05-19 — generalizes the silent-absorption pattern observed in a brainstorm session (the social-platform brainstorm); harness.md substrate tier added 2026-05-22 in-place per ADR-011 D1 — the substrate-discipline epic)*

**Firmness: FLEXIBLE**

At named junctures, the agent re-surveys the workflow-primitive inventory and substrate tiers. The contract is *consideration*, not *invocation* — each primitive's per-trigger default-on declarations (per ADR-012 D3) own actual invocation conditions; D11 ensures the inventory is available for consideration at moments where silent absorption is most likely.

**Named junctures:**
- Session entry.
- Post-compaction or self-checkpoint resumption.
- Scope shift mid-work.
- Before substrate write (`bd create`, ADR or skill edit).
- Before close-summary (about to write Landed / Next-steps prose).
- **Mid-task hand-back inside an active driving loop** *(added 2026-05-27 — dogfood evidence: a send-it session)* — about to pause and return control to the user before the task's acceptance is met, while a driving loop (`/send-it`, `/implement`, decompose-walk) is still mid-flight: a primitive just returned, or a coherent sub-unit just closed, and the next move is a status-report-and-await rather than the next loop step. Two considerations live at this juncture, both observed as silent-absorption misses: (a) **loop-continuation** — if the next step is fork-free (no design decision only the user can make), take it rather than asking; the "pause after fan-out for confirmation" anti-pattern (named in `/send-it` SKILL.md) is the recognition target. (b) **retrospective** — a sub-unit closing mid-epic is `/compound` territory even though the parent epic stays open (the epic-close default-on trigger per D6 has not yet fired); the hand-back summary's own shape (Landed / what-changed / next-steps) is the cue.

**Behavioral contract** (impl-agnostic, mirrors D9's "session-start-indexed" shape):

> The juncture-awareness reminder — primitive inventory + "consider what fits" framing — MUST be present in the agent's working context at the named junctures. The reminder lists primitives; it does not sequence them. Mechanism per environment.
>
> **Falsifiable compliance probe.** After a compaction or session-resume event, the juncture inventory + primitive list is accessible in working context without explicit retrieval. Non-compliant: the agent must call a tool at T=0 to recover the framing — that's retrieve-on-demand, not always-present.

**Claude Code binding:** two surfaces, scope-split by audience.

- **Cross-cutting content** (applies to subagents too): the global agent instructions file (CLAUDE.md in the methodology home) — `## Substrate orientation`, `## Python`, `## Bash`, `## Working directory`, `## Commits`, etc. It is injected into both the main agent's context AND every subagent's context via a `# claudeMd` system-reminder block (verified empirically 2026-05-20 — subagent quoted CLAUDE.md sections verbatim from its system prompt). Compaction-survival is structural via CLAUDE.md inclusion in the system prompt.
- **Main-agent-only content** (would misdirect subagents): the `brain-of-loop.sh` SessionStart hook in the methodology home — `## Brain of the loop` (orchestrator identity, dispatch-default framing) and `## Communicating with me` (user-facing comms preference). SessionStart fires only for the parent session — subagents dispatched via the Agent tool do NOT re-trigger SessionStart, keeping orchestrator-identity framing out of execute-only subagent contexts. SessionStart's `""` matcher catches startup / resume / compact / clear, so compaction-survival holds via re-fire on the post-compact event.

*(Binding rewritten 2026-05-20 in-place per ADR-011 D1 — prior version named CLAUDE.md as the sole always-loaded surface and called brain-of-loop.sh "redundant"; empirical verification showed CLAUDE.md leaks into subagent contexts, so identity-framing belongs in the hook layer where SessionStart's main-session-only scope provides audience isolation. The "always-loaded" property splits into two properties — cross-context (global agent instructions file) and main-session-only (SessionStart hook) — and D11's juncture-awareness contract requires both, with content routed by intended audience.)*

**`.claude/harness.md` as a substrate tier in the juncture re-survey** *(added 2026-05-22 in-place per ADR-011 D1 — the substrate-discipline epic; connects ADR-012 D3's `.claude/harness.md` inventory into the juncture-awareness tier-routing)*:

The juncture re-survey must include `.claude/harness.md` alongside ADRs / L2A cm / L2B bd memories / skills. `.claude/harness.md` is a **non-decaying, project-anchored, inventory-shaped** substrate tier — distinct from the other tiers as follows:

- **Adjacent to L2B, not equivalent.** Like L2B, it is per-repo and non-decaying. Unlike L2B (bd-keyed procedural knowledge), it is inventory-shaped: its entries characterize *which verification mechanisms fit which work surfaces* (fit profiles, per-category mechanism recommendations), not *how the agent should behave*. BD-keyed memories answer "what should I do?"; harness.md answers "what signal catches what class of defect for this work shape?"
- **Positioned between L2B and L3 in consultation order.** ADRs (L3) carry binding cross-cutting decisions; harness.md carries project-specific fit calibrations that inform harness composition without rising to ADR-level firmness. When a juncture re-survey surfaces both an ADR constraint and a harness.md fit profile for the same work surface, the ADR constraint governs; the fit profile informs implementation of the constraint.
- **When to consult `.claude/harness.md` during a juncture re-survey:**
  1. When work touches a **known work-surface category named in the inventory** — e.g. "Django view work", "prod-config-sensitive change", "cross-cutting harness composition" — consult to surface the fit profile for that category before composing a feedback loop.
  2. **Before authoring a `## Harness target`** in a bead design — consult to calibrate the target against existing inventory entries (which signal is fastest/most-faithful for this work shape?).
  3. **Before composing a feedback loop or proposing a verification strategy** — consult to avoid re-inventing a fit profile the inventory already names, or duplicating a mechanism already covered by the inventory.
- **What `.claude/harness.md` carries** (the guidance content that justifies consulting it):
  - Mechanism inventory: what verification tools exist in this repo, at what altitudes.
  - Fit profiles per work-surface category: "for X kind of work, prefer Y mechanism because Z — what Y catches that neighbors miss."
  - Coverage gaps and fit-swap findings: "mechanism A is poorly fit for surface B; better fit is C" — these are the entries `/compound`'s harness-shaped lesson routing (D6) produces.
- **How it composes with tier-routing in `/recall`:** the `/recall` skill tier-routes across L3 / L2B / L2A / skills; `.claude/harness.md` is an additional consult at the L2B tier-step, specifically when the work surface is code-shaped or harness-composing. Full consult-when guidance lives in `/recall` SKILL.md (tactical summary) and here (canonical). See `/recall` SKILL.md § Algorithm step 2 for the tier-routing location.

**Scope note.** `.claude/harness.md` does NOT replace ADRs as the binding canonical tier, nor does it replace bd memories as the procedural-knowledge tier. It carries *inventory-shaped calibrations* — the per-mechanism fit profiles that feed harness composition, not the agent-behavior prescriptions that feed task execution. A lesson that says "always run X before Y" is bd-shaped (procedural-lesson). A lesson that says "for Django view work, prefer integration tests at the view layer because they catch config-sensitivity that unit tests miss" is harness-shaped (fit profile). The discriminating question from D6's recognition pattern applies here: would this lesson appear as a row/cell in a harness inventory? If yes → `.claude/harness.md`. If no → `bd remember`.

**Write-direction symmetry — harness.md is populated by substrate-consulting writes, not blank-slate scans** *(added 2026-05-22 in-place per ADR-011 D1 — the scope-boundary design bead; pairs with the consultation-direction guidance above)*: the juncture re-survey reading harness.md (described above) has a paired write direction. `/harness audit` (per `recipes/audit.md` Step 1) re-surveys `bd memories` and the `docs/decisions/INDEX.md` ADR index before and during the filesystem scan, folding verification-relevant findings into the inventory's existing categories with inline `(source: bd memories key=... | ADR-NNN D<n>)` citations — memory is the *source*, not a new category (per `bd memories` key `categorization-by-what-not-by-source`). `/compound`'s harness-shape routing (D6) emits inventory-update proposals for harness-shaped lessons rather than `bd remember` entries, with the same citation discipline. Without this symmetry, harness.md grows from filesystem scan only, the memory ↔ inventory loop is one-way, and accumulated verification lessons in `bd memories` / ADRs never propagate into the inventory readers consult. The citation footnote convention is what makes the loop reproducible across re-audits and lets `/compound` retire stale calibrations by grepping inventory citations against current substrate.

**Rationale:** ADR-012 D3's `.claude/harness.md` is described as "substrate-thick discipline" that grows from inventory-only into inventory + project-specific fit profiles. Without naming harness.md as a tier in D11's juncture re-survey, the inventory is consulted only when a primitive explicitly triggers it (e.g. `adversarial-reviewer` checks it when reviewing harness targets); the juncture-awareness tier-routing silently skips it when no specific primitive has fired yet. The fold-in connects ADR-012 D3's inventory-building discipline into the juncture-awareness tier, so fit profiles surface at the moments (session entry, scope shift, before substrate write) where a missing calibration is most likely to produce a misfit harness target. The asymmetric three-artifact design (ADR-013 D11 carries full guidance; `/recall` SKILL.md carries the tactical consult-when entry; CLAUDE.md names the tier in one line) prevents drift by making D11 the single source of substance.

**In-band juncture cues alongside the always-loaded reminder** *(added 2026-05-19 in-place per ADR-011 D1 — dogfood evidence: a send-it session absorbed both `/adversarial-review` at pre-substrate-write and `/compound` at pre-close-summary; the close-time stderr warning fired in-band but read as "acknowledge and proceed" rather than as a juncture cue)*: substrate-level signals emitted at a juncture moment count as juncture reminders alongside the always-loaded text. Concretely in this binding: `bd close`'s `adversarial-review verdict gap` warning IS a pre-substrate-write juncture cue; a future `compounded` gap warning (if added) would be a pre-close-summary cue. The contract remains *consideration*, not *invocation* — the warning text widens recognition; the skip-decision may still be correct after consideration.

*Delivery is not the gap — recognition is (confirmed 2026-05-27, a send-it session).* That session paused twice at the "pause after fan-out for confirmation" anti-pattern, the second triggering an explicit user countermand ("didn't I ask you to /send-it? Why are you stopping?"). The natural hypothesis was a compaction-survival hole — the always-loaded reminder failing to re-inject after `/compact`. Empirically falsified: the session's `SessionStart:compact` hook fired (re-injecting `brain-of-loop.sh` content, including this juncture framing) and the agent still parked. So the always-loaded-after-compaction mechanism (the D9-shaped behavioral contract above) is sound; the failure is purely that the agent did not pattern-match its own mid-loop "want me to start building those, or review first?" hand-back against the in-context reminder. This is the same recognition-gap shape as the social-platform brainstorm finding below, now observed a second time at the mid-task-hand-back juncture — which is why that juncture was added to the Named-junctures list above rather than treated as a delivery fix.

**Other environments** (Pi-agent, Codex-agent, future agents): equivalent always-loaded substrate — system prompt block, persistent instruction file, or whatever the environment provides — carrying the juncture list + primitive inventory.

**Rationale:** Per-primitive triggers (ADR-012 D3) declare *when each primitive should fire*; D11 declares *when the agent should re-check the whole inventory*. The two compose: primitives still own invocation conditions; juncture-awareness ensures inventory recognition at transitions. Dogfood evidence (a social-platform brainstorm session, 2026-05-19) showed agents had relevant skill descriptions in context but skipped invocation when internal narration didn't pattern-match the trigger phrases verbatim — the hand-rolled `## Landed / ## ADR-routing candidates / ## Next-session targets` template at session-close was exactly `/compound`'s output shape, yet `/compound` was never invoked despite its SKILL.md naming "wrap-up", "ship it", "what did we learn" as triggers. A juncture reminder closes the recognition gap without replacing per-primitive triggers or adding sequencing rules.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| **Cross-primitive juncture-awareness contract (chosen)** | Composes with per-primitive triggers without replacing them; addresses dogfood-observed silent absorption directly; impl-agnostic via behavioral-contract shape; same family as D9 (session-start-indexed) and D10 (residue-before-gate) | Adds one more substrate convention to honor; depends on always-loaded context surviving across all junctures |
| Expand each primitive's per-trigger list to cover all junctures | Per-primitive locality | Combinatorial explosion; every new primitive must re-derive juncture coverage; trigger lists become unscannable. **reasoned:** ADR-012 D3 names per-primitive triggers as intentional design — *"Default-on vs judgment-routed named explicitly. No vague 'use when relevant'; each primitive states its default-on triggers."* Expanding each one to cover every juncture duplicates content and creates drift between primitive trigger lists. |
| Hook-only mechanism (post-compaction reinjection) | Concrete delivery | Hook events around compaction are partial and undocumented; no `PostCompact` event surfaced in docs; hook-output survival across compaction is not specified as a contract. **direct:** the compaction-survival mechanism for system-prompt content (CLAUDE.md) is documented and structural; hook timing is implementation-flexible delivery, not a substrate guarantee. |
| Skill-description trigger widening only (no juncture layer) | No new substrate convention | Doesn't address the dogfood pattern — the agent has descriptions in context but doesn't pattern-match its own narration against them at decision moments. **direct:** the social-platform brainstorm session showed `/compound` SKILL.md already names "wrap-up", "ship it", "what did we learn" as triggers; the agent wrote those exact patterns by hand and didn't invoke. Adding more trigger phrases doesn't fix the recognition gap. |

**Recipe-leak posture:** D11 names an enumerated juncture list, which is the shape that can ossify if the list grows or starts implying sequence ("at juncture X, do Y first"). FLEXIBLE firmness is the safety valve — the list shrinks or re-shapes on evidence. The contract phrasing is *consideration*, not *invocation*; sequencing is not specified. The recipe-leak guard (ADR-012 D3 primitive shape) applies: if D11 ever moves toward FIRM with a sequenced-juncture protocol, the move would need to rebut *"leave juncture-routing to orchestrator judgment governed by per-primitive triggers."*

**What would invalidate this:** dogfooding across 5+ sessions shows the juncture reminder either fires constantly and gets ignored (signal-degradation, same shape as D10's invalidation condition); OR no marginal-value over per-primitive triggers (agents pattern-match adequately without the cross-primitive layer, evidenced by post-compaction sessions invoking the right primitives at the right moments without recourse to the reminder); OR the juncture list itself proves wrong-shaped (named junctures don't predict silent absorption — most observed misses occur at moments not in the list, suggesting the list captures the wrong cuts).

---

## Cross-decision reconciliation

**D3 (firmness-governed mutation) ↔ D5 (`/compound` primitive shape) ↔ ADR-012 D3 #6 (`/adr-write` primitive):**

- **D3 governs mutating existing L3 entries.** EXPLORATORY ADRs mutate on noticing; FIRM ADRs require argument. Applies whether the noticer is human or agent.
- **D5 governs how candidates *surface* for L3 promotion.** `/compound`'s **Promote** section names load-bearing candidates with countermand reasoning + proposed target; the orchestrator decides which to act on.
- **ADR-012 D3 #6 (`/adr-write`) governs L3 *authorship*.** Drafting the actual ADR / CLAUDE.md / skill edit, running the alignment-question discipline, and applying ADR-011 D1 in-place rules all live inside `/adr-write`. `/compound` proposes; `/adr-write` authors.
- These compose without conflict: `/compound` Promote → orchestrator → `/adr-write` invocation → human alignment → in-place edit per D3 (firmness governs whether argument or noticing was sufficient).

**D11 (juncture-awareness) ↔ ADR-012 D3 (per-primitive trigger declarations):**

- **ADR-012 D3 governs when each primitive should fire.** Per-primitive default-on triggers (e.g. `/adversarial-review` on own-work contracts/plans/decomp trees; `/scope-check` on multi-bead-epic authoring; `/compound` on epic close via D6 of this ADR) are declared in each primitive's SKILL.md.
- **D11 governs when the agent should re-survey the whole inventory.** Recognition obligation at named junctures, independent of any specific primitive's trigger.
- These compose without conflict: D11 widens recognition; ADR-012 D3 governs invocation. A juncture re-survey can correctly result in no primitive being invoked (no trigger matches) — D11 is satisfied by *consideration*; ADR-012 D3 is satisfied by *correct invocation when triggers match*.

## Dogfooding bar (#1 checkpoint before any D1–D9 firmness promotion)

The architecture has a load-bearing dependency chain that currently sits empty:

- CASSMS playbook: 1 candidate bullet, score 0 (essentially empty).
- `docs/decisions/thesis-v2.1-dogfood-ledger.md` (required by ADR-012 D6 FIRM): does not exist.
- SessionStart `cm context --json` merge: not built.
- `/adr-write` primitive (ADR-012 D3 #6): named but unbuilt. Load-bearing for `/compound`'s Promote path (D5). Until built, Promote handoff is recipe-level inline orchestration only.

`/compound` is the load-bearing primitive AND the only meaningful writer into CASSMS at solo scale. If `/compound` doesn't run, CASSMS stays empty; if CASSMS stays empty, `/compound` has nothing to read. Recoverable only by deliberate dogfooding cadence.

**Bar:** ≥5 `/compound` runs across ≥2 weeks, each producing ≥1 surfaced candidate (any verdict), with the ADR-012 D6 dogfood ledger growing alongside. Until met, D1–D9 firmness labels stand as written; no promotion via this bar's evidence. D9's "no second environment implements" invalidation condition uses this same window.

## Foreseeable failure modes (named, not solved)

- **Cadence failure between epic closes (Larson, solo variant — updated 2026-05-12 after D6 rewrite).** Default-on at epic-close (D6) catches epic-shaped learning. Solo work that doesn't cluster into epics — single beads, time-windowed exploration, mid-flight pattern noticing — relies on judgment-routed invocation, which is the Larson failure shape. Likely failure: weeks of single-bead work accumulate learning that never compounds because no epic closes. Mitigation deferred — start with epic-close + judgment-routed; add scheduled/time-windowed trigger only if dogfooding shows judgment-routed invocation never fires.

  *Dogfood data point (2026-05-27, a send-it session):* judgment-routed `/compound` failed to fire across a substantial mid-epic unit (epic decomposed into 16+2 children, ADR-016 evolved twice, real lessons surfaced — `bd create --graph` drops design/acceptance fields, `--dry-run` persists) — three hand-rolled close-shaped summaries, `/compound` never considered, epic stayed open so the default-on trigger never fired. n=1 toward the "judgment-routed invocation never fires" condition. Recognition-side mitigation applied first: the D11 mid-task-hand-back juncture (added same date) now names sub-unit-close-mid-epic as `/compound` territory. If judgment-routed `/compound` still fails to fire at mid-epic hand-backs after the juncture fix, that recurrence is the signal to add a structural mid-epic/time-windowed trigger — weighed against this section's "fires on near-empty units" cost (D6 alternatives table).
- **Empty-substrate as "nothing to surface."** `/compound`'s prompt must probe for absences (smoke-test #1); a non-probing prompt will silently mistake empty-substrate for "system is healthy."
- **CASSMS upstream version drift.** No migration plan today; build phase pins a CASSMS version.

## canonical_refs

*(Added 2026-05-12 in-place per ADR-011 D1 to satisfy ADR-008 D5 mandate on design narratives. The previous `## Related` section is preserved below as supplementary context.)*

- [ADR-008](ADR-008-adr-predicates-and-plan.md) D1 — per-decision predicates (firmness + rationale + alternatives + invalidation). Applied throughout D1–D8.
- [ADR-008](ADR-008-adr-predicates-and-plan.md) D5 — `## canonical_refs` mandate (this section).
- [ADR-011](ADR-011-adrs-reflect-target-architecture.md) D1 — in-place mutation rule. Load-bearing for D3's firmness-governed mutation logic and for the 2026-05-12 shape-refinement that rewrote D5/D6.
- [ADR-012](ADR-012-substrate-thick-process-thin.md) D1 — cross-cutting ADR filter; D2 — scope tag conventions; D3 — six (now seven, with `/compound` added) workflow primitives + Primitive shape pattern (referenced by D4/D5/D6 of this ADR); D4 — original bicameral sketch sharpened by this ADR; D6 — dogfooding bar requirement (referenced by §Dogfooding bar).
- [ADR-006](ADR-006-workflow-modernization.md) D10 — warrant tag convention on Alternatives rejections. **Acknowledged gap:** this ADR's Alternatives tables (D1, D3, D4, D5, D6, D7) do not currently carry `direct:` / `external:` / `reasoned:` tags; ADR-012's tables share the same gap. Pre-existing systemic omission across both ADRs; not introduced by 2026-05-12 or 2026-05-18 edits. *(D2's new Alternatives table (the memory-write redesign epic, 2026-05-18) carries the tags; D8's updated table carries the tags; D9 carries the tags.)* Resolution of remaining gap deferred to a separate sweep.
- [ADR-007](ADR-007-primitive-loop.md) D3 — fresh-`Task()` per dispatch; referenced by D5's fresh-context dispatch requirement.
- [ADR-008](ADR-008-adr-predicates-and-plan.md) D8 — signal-shaped invalidation conditions (no bare numeric thresholds); applied throughout D2/D8/D9 invalidation rewrites in the memory-write redesign epic, 2026-05-18.
- The originating memory-write redesign epic — 2026-05-18 epic that rewrote D2, reaffirmed D7, extended D8, added D9. Carries the full design rationale and 2-round adversarial review record.
- A child verification task under the memory-write redesign epic — carries the dogfood-replay pass/fail criteria that verifies the D2/D8/D9 changes hold in practice.
- `bd-memories-write/SKILL.md` (in the methodology home) — agent-facing convention reference for L2B body discipline (per D2, D8). Authored as part of the memory-write redesign epic implementation.
- `history/2026-05-18-compound-dogfood-baseline/README.md` — baseline /compound dogfood evidence that drove the memory-write redesign epic refactor (L2A kind-metadata bug + audit-log inconsistency + L2A-only routing).
- The global agent instructions file (CLAUDE.md, `## Substrate orientation` and other cross-cutting sections) and the `brain-of-loop.sh` SessionStart hook (in the methodology home, `## Brain of the loop`, `## Communicating with me`) — Claude Code binding for D11's juncture-awareness behavioral contract, scope-split by audience per the binding section above.
- A social-platform brainstorm session (2026-05-19) — dogfood evidence that drove D11; the session hand-rolled `/compound`'s output shape at close without invoking `/compound`, surfacing the silent-absorption pattern D11 addresses.

## Related

- [history/2026-05-12-memory-layer-design.md](../../history/2026-05-12-memory-layer-design.md) — full design with research foundations and pressure-test details.
- `{scope-check,decompose,adversarial-review}/SKILL.md` in the methodology home — the three landed primitives ADR-012 D3's Primitive shape pattern abstracts from.
- The originating brainstorm bead (closed) — the brainstorm bead that produced this design.
- Follow-up beads (uncreated at time of writing): `/compound` skill build *(sized per ADR-012 D3 primitive shape, ~150 lines, scope-check analog)*, SessionStart hook merge, ADR-012 D6 in-place edit re: dogfood ledger ownership, `/adr-write` skill build *(ADR-012 D3 #6 primitive — currently a named gap; load-bearing for `/compound`'s Promote path; orchestrator carries interim discipline per D5)*, `epic` label convention follow-up *(sharpens D6 epic-close trigger legibility)*.
