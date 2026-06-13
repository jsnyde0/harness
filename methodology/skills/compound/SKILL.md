---
name: compound
description: Inward-look retrospective primitive — over a closed or about-to-close unit of work (bead / epic / window / substantial-artifact-just-shipped), surface a three-section Record / Promote / Retire proposal list across memory substrate (L2A cm / L2B bd remember / L3 ADRs via /adr-write). Use when the last bead in a multi-bead unit closes, when `bd close` runs on a parent whose `type=epic` has closed children, when you just authored a substantial ADR / cross-cutting commit / CLAUDE.md change, when about to write a closing summary / retrospective / "wrap-up" message, or when the user says "we're done", "that's it", "ship it", "wrap up", "what did we learn", "looking back". Triggers on these phrases proactively — `/compound` runs BEFORE the hand-rolled summary, not after; catching yourself about to write a Status/Next-steps bullet list IS the cue. **Self-referential skip-rationalization is also a trigger** — "skipping compound because…", "no compound needed since…", "/compound already ran on the parent so…": by the time you're authoring the skip-reason you've crossed the consideration bar; fire the primitive, and the skip may still be correct after fresh-context probing. Default-on at epic close ; judgment-routed for everything else (co-equal mode, not exception). Common mis-skips: gating on bd-epic shape when single-artifact units qualify; skipping because you already have one bd remember queued (the value is the fresh-context probe across all four layers, not authoring the pre-known entry); reading empty CASSMS as "nothing to compound" (first-run substrate is expected to be empty §Dogfooding bar); rationalizing the skip in the closing summary itself (the rationalization is the cue, not a valid skip signal). Fresh-context single-dispatch. Composes with /adr-write on Promote handoff. Scope-check's inward counterpart.
---

## Purpose

After a unit of work closes, distill compounding-worthy signal from the substrate into a three-section proposal list — Record (L2A/L2B candidates), Promote (load-bearing L3 candidates), Retire (fulfilled or low-utility entries). The fresh-context dispatch is load-bearing: the originating session shares the work's blind spots; a fresh context reads the substrate from outside the frame.

**Spec source:** the compound-primitive build bead + **** (where the primitive shape design lives; the build contract links both).

## When to invoke

Two **co-equal** invocation modes. Judgment-routed is not "exception to the default" — it's the wider surface where most non-epic units land.

### Default-on — epic close

`bd close` on a parent bead where **both** hold:
- (a) `bd show <id> --json | jq -r '.[0].type == "epic"'` returns `true` *(substrate-legible sharpening, 2026-05-13; the earlier-drafted `epic` label convention was retired before adoption — `type=epic` is set at bead creation, no duplicate signal)*.
- (b) At least one `parent-child` dependent (filter `bd dep tree`; ignore `blocks` / `blocked-by` / `discovered-from` edges) is in `closed` state with `closed_at > parent.created_at`.

Two-query check — looser than scope-check's one-query predicate, but mechanically computable.

### Judgment-routed — everything else

Each of the following is a **first-class invocation shape**. If any holds and `/compound` has not yet fired for the unit, fire it **before** the wrap-up summary or handoff message:

- **Substantial-artifact unit shipped.** Authored an ADR (especially cross-cutting or FIRM), made a CLAUDE.md change with cross-domain implications, committed a refactor that crosses module boundaries, or landed a design that touches multiple skills/primitives. **No bd-epic required** — the unit is the artifact, not its bd shape.
- **Wrap-up imminent.** About to write a Status / Next-steps / "done here" bullet list, a post-commit summary, a "we shipped X" handoff message, or any retrospective-flavored close. `/compound` runs BEFORE the summary, not after — once you've written the summary, the fresh-dispatch value is gone (you've absorbed the synthesis into your own context). **This includes memory-writes that close a unit** — a queued `bd remember` or `cm playbook add` IS the closing gesture, not a precursor to one.
- **User trigger phrase.** "we're done", "that's it", "ship it", "wrap up", "what did we learn", "looking back", "retrospective on this", "did we miss anything from memory's perspective", "anything we should remember from this".
- **Mid-flight pattern-noticing.** Recognized a recurring failure, calibration, or procedural lesson during work — surface it without waiting for unit close.
- **Time-windowed sweep** (`--since <window>`). Compounding across a period when no single bead/epic frames the work. Window-scoped runs leave audit-log residue only (no `compounded` label).
- **Single-bead retrospective** (`--bead <id>`). A non-epic bead meaningful enough on its own — substantial design bead, contentious decision bead, bead whose closing surfaces cross-cutting learning.

## Common mis-skips

If your reasoning matches any pattern below, fire `/compound` anyway — **the reasoning itself is the failure mode, not a valid skip signal.** All four came up in real sessions; each one feels locally rational and is wrong.

1. **"This isn't a bd epic with closed children, so the default-on trigger doesn't fire."** Correct that the trigger doesn't fire; wrong that this means `/compound` shouldn't run. Judgment-routed mode (above) is co-equal. The unit shape that matters is *meaningful-cross-cutting-work-just-closed*, not *bd-epic*.

2. **"I already know the one bd remember I'd write — running `/compound` for one entry is overkill."** The pre-known entry is the *Record→L2B* path only. The value of `/compound` is the **fresh-context probe across all four substrate layers** (L1 CASS reads / L2A cm / L2B bd / L3 ADRs) — surfacing Record/Promote/Retire candidates the originating session is blind to. Your queued entry is a tiny slice of the surface; the rest is what the fresh subagent finds. Cost is one fresh-context dispatch.

3. **"CASSMS is essentially empty / nothing has accumulated to compound against."** First-run substrate IS empty by design ( §Dogfooding bar). `/compound` is the primary writer into CASSMS at solo scale; skipping because CASSMS is empty locks the empty-substrate trap closed. The fresh subagent's brief explicitly probes for **absences, not just presences** — empty-substrate is exactly the substrate `/compound` exists to populate.

4. **"I'll fold this into the end-of-turn summary."** `/compound` runs BEFORE the hand-rolled summary, not after. Writing the summary first absorbs the synthesis work into the originating session's already-fatigued context — defeating the fresh-dispatch design. The summary IS the trigger; once written, the moment has passed.

## Invocation surface

```
/compound [--epic <id>] [--since <window>] [--bead <id>]
```

One verb. Scope-bindable. Flags are subagent-brief inputs, not separate subcommands.

## Algorithm

Single invocation runs:

1. **Dispatch one fresh-context subagent** with the brief (see below). **No internal rounds; single dispatch.** The originating session carries the work's blind spots — one fresh pass, one output. Per and bucket (a).

 <!-- HARNESS-DISPATCH: role=general-purpose tier=medium -->

 On **Claude Code**: use `Task(subagent_type="general-purpose", model="sonnet")` — spawns a fresh subagent with no inherited context.
 On **pi**: use the `subagent` tool with `role="general-purpose"` and `modelTier="medium"` — spawns a fresh pi subprocess with no inherited context.

2. **Receive the three-section output artifact** (see Output shape below).
3. **Orchestrator immediately stamps the audit-log** via `bd audit record --stdin` (see Substrate residue below). This step is **unconditional** — it fires for EVERY /compound run, including bare/no-action runs, BEFORE any fold decisions or AskUserQuestion prompts. The audit-log records that the run happened; it is independent of whether any proposals are acted on.
4. **Orchestrator folds per-entry** (only after audit-log stamp):
 - **Record → L2A** → `cm playbook add --category=<observation|calibration> "<content>"` (see CASSMS mapping note below)
 - **Record → L2B** → `bd remember --key=<key>` with frontmatter+structured-body per bd-memories-write/SKILL.md (methodology home)
 - **Record → harness.md** → propose inventory update: file path + section + diff sketch ( harness-routing branch); orchestrator applies via `Edit` on `.claude/harness.md` after review
 - **Promote** → invoke `/adr-write` as a separate composition step ( cross-decision reconciliation)
 - **Retire** → `bd forget <key>` (L2B) or `cm playbook remove <id>` / annotate for accelerated decay (L2A)
5. **Stamp `compounded` label** on bead/epic-scoped runs only (see Substrate residue below). This is conditional — skipped for window-scoped (`--since`) runs.

**Note on the prior interim discipline.** named an interim where the orchestrator carried L3 authorship inline (read target / apply firmness rule / surface alignment question) because `/adr-write` was unbuilt. `/adr-write` now exists (closed 2026-05-13); the interim is retired. Promote entries hand off via the chain in the "Composition with `/adr-write`" section below — no recipe-level fallback applies on new handoffs.

## Output shape (subagent emits)

```markdown
## Record

- [edit:<bullet-id> | new] <one-line summary> — <rationale: why this warrants L2A, L2B, or harness.md>
 target: L2A (cm) | L2B (bd remember --key=<key>) | harness.md (<section> diff-sketch)
 kind: observation | calibration | procedural-lesson | anti-pattern | user-pref | project-anchor | reference # omit for harness.md targets
 harness-route: <file-path> §<section> — <one-line diff sketch> # harness.md targets only
 scope: global | workspace # L2A only — ; default global, workspace when project-specific
 body: | # L2B only — full frontmatter+structured-body per bd-memories-write/SKILL.md
 ---
 kind: <kind>
 scope: global | workspace
 created: YYYY-MM-DD
 ---

 One-line summary.

 **Why:** Reason this matters.
 **How to apply:** When/where this guidance kicks in.
- ...

## Promote

- [ADR-NNN edit | new ADR | CLAUDE.md §<section> | skill <name> edit] — <countermand reasoning: why this holds after challenge>
 target: <proposed L3 target with specific location>
- ...

## Retire

- <key-or-bullet-id> — <trigger that fulfilled or invalidated it>
 target: bd forget | cm decay
- ...
```

**Record covers both edit-existing and create-new** — the subagent flags `edit:<bullet-id>` or `new` per entry ( collapse of fold-in-place vs propose-L2A). Orchestrator chooses mutate-vs-create at fold-time based on whether an existing bullet already covers the candidate. This mirrors 's in-place-first preference at the L2A layer.

**Record routing decision tree — three-way fork ( harness-routing branch, added 2026-05-22):**

Before assigning a `target:` to any Record entry, the subagent applies this decision tree in order:

**Step 1 — Harness-shape test:** Does the lesson answer one of these questions about *what signals catch what class of bugs at what altitude*?
- "For [X kind of work], prefer [Y mechanism] because [Z — what it catches that alternatives miss]" (fit-for-work pattern)
- "Harness type [A] at altitude [B] caught / missed class [C] of defect" (coverage gap / fit update)
- "Verification mechanism [M] is poorly fit for surface [S]; better fit is [N]" (fit swap)

If **yes** (primary content is about signal-fit relationships, inventory-cell shaped) → **target: `.claude/harness.md`** inventory-update proposal (file path + section + diff sketch). This is the harness-shaped route recognition pattern.

If **no** (primary content guides agent behavior, not signal-fit) → proceed to Step 2.

**Step 2 — Decay-behavior test ( / D8):** Should this fade if unused?
- `observation` or `calibration` → **target: L2A** (cm playbook). Decay applies; mark-on-use reinforces.
- `procedural-lesson`, `anti-pattern`, `user-pref`, `project-anchor`, or `reference` → **target: L2B** (bd remember). No decay; entries persist indefinitely.

**Step 3 — Ambiguous (both harness-shaped AND bd-shaped):** When a lesson's primary content characterizes a signal-fit relationship AND independently prescribes agent behavior (both fit genuinely and without stretch), surface BOTH routes to the orchestrator — a `.claude/harness.md` inventory-update proposal AND a `bd remember` entry. Label each proposal with its routing rationale. The orchestrator decides whether to act on one or both.

**Discriminating question (Steps 1 vs 2/3):** *Would this lesson appear as a row or cell in a harness inventory's fit profiles section?* If yes → harness-shaped (Step 1). If no → bd-shaped (Step 2). If yes-to-both-independently → ambiguous (Step 3).

**The subagent's per-entry `target:` line MUST carry the explicit kind.** Orchestrator reads `target:` to determine the fold path; misrouting wastes the decay/persistence design.

**L2A/L2B routing by kind ( — applies inside Step 2 above):**

- Kinds `observation` or `calibration` → **target: L2A** (cm playbook). Decay applies; mark-on-use reinforces.
- Kinds `procedural-lesson`, `anti-pattern`, `user-pref`, `project-anchor`, or `reference` → **target: L2B** (bd remember). No decay; entries persist indefinitely.

**L2B body requirement:** L2B entries MUST include a `body:` block with the frontmatter+structured-body convention from bd-memories-write/SKILL.md (methodology home). The subagent pre-populates this in the output artifact so the orchestrator can fold without a separate lookup. Content requirement: `kind`, `scope`, `created` frontmatter fields + `**Why:**` + `**How to apply:**` body fields — all required. Choice of markdown block style is implementation-detail; the SKILL.md template above is illustrative.

Scope : global by default; workspace when the entry is tied to this project's stack/repo; in-doubt → global (broadens later by scope-narrowing, not re-write).

**Promote handoff caveat.** Targets of kind `[CLAUDE.md ...]` or `[skill ... edit]` are *suggestion-only* downstream (instruction files are human-scope); `/adr-write` will surface them as one-liners, not apply autonomously. Only `[ADR-NNN edit]` and `[new ADR]` targets land non-interactively after the alignment question. `[new ADR]` targets additionally trigger 's 5-dim overlap detection inside `/adr-write` before authoring.

**Promote carries countermand reasoning** — the "why is this still right after challenge?" sketch . Load-bearing candidates only; recurrence and count are inputs to judgment, not gates.

Each section may be empty; an empty section is valid output — surface as "nothing surfaced for this section," do not collapse.

## Subagent brief (substrate signals — listed, not prescribed)

The fresh-context subagent is briefed with the epic/bead scope + substrate signals to consult by judgment. **No prescribed order; no enumerated probe types.** The subagent composes them:

- **L1 raw recurrence signals** over recent session JSONL — on **Claude Code**: `cass --since <window>` (prefer 2-term lexical queries with `--explain`; CASS FTS brittle on short tokens, a known calibration entry); on **pi**: an equivalent L1 search over the pi session logs. Never trust hit counts alone; cross-check against ADRs / git / bd.
- **`cm playbook` + `cm context "<task>" --json`** — L2A relevance, decay state, existing bullets (for edit-vs-new judgment).
- **`bd memories`** — L2B parking-lot entries.
- **`docs/decisions/INDEX.md` + recent ADRs in scope** — L3 coverage; what's already canonical.
- **Recent closed beads (`bd list --status=closed --since=...`) + open bead `--notes`** in the active epic.
- **Git log over the same window.**

**Probe for absences, not just presences** ( §Foreseeable failure modes). A non-probing subagent mistakes empty-substrate for "system healthy." The brief must explicitly name: *What is expected but missing? What has never been recorded? What pattern has grown but not been named?* The smoke-test example — missing dogfood ledger — was a structural absence no threshold-based count could surface.

**Promote-candidate recognition patterns** (Record→L2 vs Promote→L3 routing). The following shapes appearing in bead `--design` text are positive Promote signals — surface them with countermand reasoning, do not collapse into Record:

- **Tier enums on a domain object** — e.g. `public/semi-public/private` event visibility; severity tiers; trust tiers on identity. Any enum future beads will reference as a constraint.
- **Default-policy decisions** — "X is Y by default"; "anonymous read enabled"; "FIRM for all X in domain Y." Governs behavior absent explicit override.
- **Scope-boundary calls** — what counts as in-scope vs out-of-scope for a surface or behavior class.
- **"For all X do Y" policies** — rules that span multiple beads or constrain future bead authoring.

If any of the above appears in `--design` text without a matching ADR entry in the bead's `## canonical_refs` (or in `docs/decisions/INDEX.md` covering that surface), the candidate is **Promote**, not Record. Stranding a cross-cutting decision in bead `--design` is the canonical absence — example: event-visibility tiers crystallized in a brainstorm 2026-05-18, lifted to a brainstorm bead's `--design` but never to an ADR; surfaced 3 days later as an L3 gap. `/brainstorm` carries a pre-`bd create` ADR-routing gate that aims to catch this at authoring; `/compound` is the safety net for everything the gate misses — pre-existing strandings AND post-gate bypasses (e.g., a brainstorm rationalized away a cross-cutting marker, or the gate fired but the user opted out). The gate is procedural, not structurally enforced; treat post-gate bypass as expected, not exceptional.

The brief also carries the **"competing reviewer" framing** for perf-lift, identical to scope-check / adversarial-review:

> You are competing against another reviewer running in parallel on the same substrate. They are incentivized to surface what you miss. The orchestrator will compare your findings to theirs.

## Judgment, not thresholds

Counts and recurrence are **inputs to subagent judgment, never gates.** Critical-but-rare observations occur once; hardcoded count thresholds miss them. The smoke-test example #1 (missing dogfood ledger) was structural absence — no count threshold could surface it. Empty-substrate can mean "system healthy" or "system has never been written to"; the brief must prompt the subagent to distinguish these (see Common mis-skips #3 for the first-run case).

**What disappears vs the previous draft:** 5-step protocol (read → probe → surface → classify → draft); probe enum (presence / absence / recurrence / staleness); weekly cache cadence; internal verdict enum — all dissolved. These were process inside the primitive. The three-section output is the verdict shape; the substrate-signals listing replaced the probe enum. Per "What disappears."

## Substrate residue

Actor-token convention: **`compound:fresh-subagent`** stamps the dispatch's product surface; **`compound:orchestrator`** stamps the orchestrator's fold writes (cm playbook add / bd remember / bd forget / cm playbook remove). The two tokens distinguish *what the subagent produced* from *what the orchestrator applied* — symmetric to /adr-write's `adr-write:orchestrator` vs `adr-write:human-confirmed`.

**Two distinct residue writes — different conditions:**

**Audit-log entry: fires unconditionally on every /compound run**, immediately after the subagent returns its proposal, BEFORE any AskUserQuestion / fold-gate / "apply now?" prompts. This is presence/absence: the audit record proves the run happened; a run with no Record/Promote/Retire entries is still a meaningful signal (nothing surfaced). Do NOT defer or skip based on whether fold steps ran. The audit-log stamp MUST precede all fold-gate logic.

**`compounded` label: fires on bead-scoped and epic-scoped runs only** — not on window-scoped (`--since`) runs where there is no single bead/epic to stamp.

```bash
# 1. Audit-log entry — UNCONDITIONAL, every run
echo '{"kind":"compound-run","issue_id":"<id>","extra":{"scope":"epic|bead|window","record_count":<N>,"promote_count":<N>,"retire_count":<N>,"signals_consulted":["cass","cm","bd_memories","adr_index","recent_adrs","closed_beads","open_bead_notes","git"],"signals_empty":["<list of expected-but-absent signals>"]}}' \
 | BEADS_ACTOR=compound:fresh-subagent bd audit record --stdin

# 2. Stamp presence/absence label on the bead/epic (epic-scoped and bead-scoped runs only — skip for window-scoped)
BEADS_ACTOR=compound:fresh-subagent bd update <id> --add-label=compounded
```

The `BEADS_ACTOR` env var on the `bd audit record` invocation is the only honored actor field — the actor JSON field inside the payload is ignored (per procedural memory: the actor field inside the JSON payload is a no-op). Always set `BEADS_ACTOR` on audit invocations.

`compounded` label is **presence/absence**, not pass/fail. Distinct from `verdict:*` (own-work review outcome) and `scope-checked` (outward neighbor enumeration). No freshness predicate — deferred until a real consumer asks, matching scope-check's identical deferral.

The audit-log entry's `extra.scope=window` distinguishes window-scoped runs for downstream readers; `bead` or `epic` for the other shapes.

Fold-time writes (orchestrator applying Record/Promote/Retire entries) use `BEADS_ACTOR=compound:orchestrator` on each `cm` / `bd` invocation — keeps the dispatch-vs-fold attribution legible.

## Composition with `/adr-write`

The chain — quoted explicitly:

> `/compound` Promote → orchestrator → `/adr-write` → alignment question → in-place edit per firmness

`/compound` proposes; `/adr-write` authors. `/compound` does not author L3 itself — not even on a "quick" L3 candidate. The orchestrator decides which Promote entries to act on and invokes `/adr-write` per entry as a separate composition step. `/adr-write` owns the alignment-question discipline and in-place rules.

## What this skill is NOT

- Not scope-check — scope-check is outward-look (neighbors of a proposed bead); this is inward-look (signal distillation after closed work). Same dispatch pattern; different substrate and direction.
- Not adversarial-review — does not judge own-work correctness; surfaces memory-substrate candidates.
- Not an ADR author — Promote entries route to `/adr-write`; `/compound` does not draft or apply L3 changes itself.
- Not algorithm-prescribing — no step sequence, no probe enum, no thresholds. The skill lists substrate signals; the subagent composes by judgment. Substrate-thick, process-thin .
- Not a cron job — `/compound` is invoked, not scheduled; default-on at epic close, judgment-routed otherwise.

## Working substrate

- `bd close <id>` / `bd show <id> --json | jq -r '.[0].type == "epic"'` — epic-close trigger evaluation (type-based sharpened 2026-05-13)
- `bd dep tree <id>` — confirm closing bead has closed children (trigger check)
- fresh-context dispatch — single fresh-context dispatch
- `cm playbook add --category=<observation|calibration> "<content>"` — fold Record → L2A (see CASSMS mapping below; scope is workspace-implicit, not a CLI flag)
- `cm playbook remove <id>` / accelerated-decay annotation — fold Retire → L2A
- `bd remember --key=<key>` with frontmatter+structured-body per bd-memories-write/SKILL.md (methodology home) — fold Record → L2B
- `bd forget <key>` — fold Retire → L2B
- `Edit .claude/harness.md §<section>` — fold Record → harness.md (harness-shaped lessons recognition pattern)
- `BEADS_ACTOR=compound:fresh-subagent bd update <id> --add-label=compounded` — label stamp (bead/epic runs only)
- `echo '{"kind":"compound-run",...}' | BEADS_ACTOR=compound:fresh-subagent bd audit record --stdin` — audit-log (unconditional, every run)

**CASSMS kind-mapping (path b — translation table):** The `cm playbook add` CLI does not accept a `--kind` flag. Pass the L2A kind via `--category=<kind>`. The stored JSON has `kind: workflow_rule` (CASSMS constant) and `category: <kind>` (the semantic discriminator). Downstream readers (e.g. `/compound` subagent) MUST use the `category` field, not `kind`, to identify observation vs calibration entries. Do NOT embed `kind:` text in the content string — that was the Run B bug that caused `workflow_rule` to appear where the semantic kind was expected. The canonical fold line:

```bash
cm playbook add --category=<observation|calibration> "<content text only, no kind prefix>"
```

Path (a) — `--kind` flag — was tested and rejected: `cm playbook add --kind=observation` returns `unknown option '--kind=observation'`. The `--scope` flag likewise does not exist in the CLI; scope (global vs workspace) is workspace-implicit context, not a CLI parameter. Path (c) — content-prefix workaround — is not needed; `--category` carries the kind semantically even though the stored `kind` field is always `workflow_rule`.

## Canonical refs

- **compound-primitive build bead** — acceptance contract for this skill build.
- **adr-write/SKILL.md (methodology home)** — the L3 authorship handoff target on Promote section; owns alignment-question discipline.
- **trigger-sharpening bead** (resolved 2026-05-13) — trigger sharpening: use bd's built-in `type=epic` field; the label convention is retired before adoption.
