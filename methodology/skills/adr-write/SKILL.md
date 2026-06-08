---
name: adr-write
description: Author or evolve an Anchored Decision Record per ADR-011 D1 in-place-first rule. Applies firmness-asymmetric mutation (FIRM gates on explicit confirmation; FLEXIBLE/EXPLORATORY announce + proceed) per ADR-013 D3, with the alignment question carrying what's locked in. Composes with /compound Promote handoff (ADR-013 D5) as the separate L3 authorship step. Distinct from /compound (which surfaces candidates; this authors) and from a general doc editor.
---

## Purpose

Author or evolve an Anchored Decision Record — a load-bearing cross-cutting L3 canonical entry — applying the firmness-governed mutation rule and alignment-question discipline before any write. The primary intake is a `/compound` Promote handoff (ADR-013 D5), though direct invocation for new ADRs is also valid.

**Spec source:** the originating skill-build bead carries the acceptance contract; the design narrative lives at **ADR-013 D5** (composition contract) and **ADR-012 D3** (primitive pattern). The bead omits a `--design` field because the design lives in those ADRs.

## When to invoke

- **Compose with `/compound` Promote** — after `/compound` produces a Promote section naming load-bearing L3 candidates with countermand reasoning + proposed target (ADR-013 D5), the orchestrator invokes `/adr-write` per Promote entry it acts on. `/adr-write` reads the entry; `/compound` does not author L3 itself.
- **Direct ADR authoring** — when a brainstorm or design session surfaces a genuinely new cross-cutting decision per ADR-012 D2 write filter (load-bearing + cross-cutting), `/adr-write` drafts or finalizes the new file.
- **Direct ADR evolution** — when a firmness-path-appropriate edit to an existing ADR is warranted (decision evolved, not superseded).

**Not default-on.** Frame-distance is not load-bearing for ADR authorship — the alignment question is the rigor mechanism. Per ADR-012 D3 bucket (c): the **authorship core does not dispatch** fresh-`Task()`. (One sub-step, ADR-008 D7's overlap-detection on new-ADR creation, IS a dispatch — see "In-place vs new-ADR routing" below. The skill calls that dispatch but is not itself bucket-(a).)

**Invocation context.** `/adr-write` runs from the orchestrator's session — *not* the originating session that surfaced the candidate. When invoked as a Promote handoff, `/compound`'s fresh subagent already broke the authoring frame; the orchestrator then dispatches `/adr-write` to author. The originating session's blind spot does not re-import.

## Firmness-governed mutation paths (ADR-013 D3)

The mutation rule follows the ADR's `Firmness:` label, not the layer placement. Applies whether the noticer is human or agent — if a human surfaced the noticing, the alignment question collapses to a confirmation ("the noticing I surfaced is the warrant — proceed?"); the structural discipline below is unchanged.

**Asymmetric by firmness.** All three paths surface the alignment question; only FIRM gates the write on explicit confirmation. The asymmetry reflects rigor placement: FIRM's inline counter-argument IS the rigor mechanism (rubber-stamping is mitigated structurally per L40); FLEXIBLE/EXPLORATORY decisions are expected to iterate, so gating each iteration on confirmation is friction without rigor — and friction at this step has a worse failure mode than a hasty write: it causes agents to skip `/adr-write` entirely, stranding decisions in bead `--design`.

- **FIRM** — argument required + explicit confirm. Draft must include an inline counter-argument rebutting the original rationale (or showing the original rationale no longer holds). Surface alignment question carrying that counter-argument; **wait for explicit user confirmation before any write.**
- **FLEXIBLE** — substantive observation sufficient; announce + proceed. A concrete real-world case or pattern is enough warrant. Surface the alignment question, then **proceed with the write**. The question announces what's locked in; it does not gate. User countermand triggers a follow-up in-place edit per ADR-011 D1.
- **EXPLORATORY** — noticing sufficient (mutates like L2); announce + proceed. A single direct observation is enough. Surface the alignment question, then **proceed with the write**. Iteration is the contract — this firmness level expects movement.

For **new ADRs** and **new L3 entries**: firmness is declared by the author. EXPLORATORY is the safe default for unproven decisions per ADR-012 D6's dogfooding bar; FIRM/FLEXIBLE are valid when warranted by prior dogfooding or direct evidence.

**Countermand window.** For FLEXIBLE/EXPLORATORY auto-proceeding writes, the substrate residue (commit + bead `--notes` stamp per L99) is the durable trail. CLAUDE.md/skill-file edits remain human-scope per L83 regardless of firmness — only `docs/decisions/ADR-*.md` and co-located `INDEX.md` rows land non-interactively for FLEXIBLE/EXPLORATORY. FIRM is the only path that asks for permission.

## Alignment-question discipline

Before writing any L3 change — in-place edit or new ADR — surface a one-sentence alignment question to the user. The question states: what assumption the change encodes + what it forecloses. Shape, not script:

> "This edit locks in [assumption]. Accepting it forecloses [alternative]. Proceed?"

This is the rigor mechanism for `/adr-write`; no fresh-context dispatch substitutes for it. For Promote-handoff edits, derive the question from `/compound`'s countermand reasoning — do not repeat the Promote entry verbatim.

**Dominant risk on the FIRM path** (replacing the prior /adr-write-doesn't-exist risk named in ADR-013 D5): alignment-question rubber-stamping. The mitigation is FIRM's inline counter-argument requirement: it fires *before* the question, which makes a perfunctory "proceed" structurally visible. FLEXIBLE and EXPLORATORY do not carry this risk — they no longer gate on confirmation per the asymmetric paths above; the announce-and-proceed pattern accepts that lower-firmness decisions iterate, and that auto-proceeding has a better failure mode than orchestrator-skips-`/adr-write`-entirely.

## ADR-008 D1 predicate enforcement

Every new decision and every substantively-edited decision must carry all four predicates:

1. **Firmness label** — `FIRM`, `FLEXIBLE`, or `EXPLORATORY`; annotate if recently changed.
2. **Rationale** — why this option over alternatives.
3. **Alternatives table with warrant tags** — every row's rejection reason carries `direct:` (file/line/issue citation), `external:` (prior art), or `reasoned:` (first-principles argument) per ADR-006 D10. **Inspect every row before write; no floating rejections.**
4. **"What would invalidate this"** — signal-shaped (observable cue that triggers re-evaluation), not a bare numeric threshold per ADR-008 D8.

**Authored ADR also carries** `## canonical_refs` per ADR-008 D5 (FIRM) — every ADR/bead/spec cited inline must be listed; no orphan entries. This is a structural predicate on the *authored output*, distinct from D6's discoverability check on CLAUDE.md.

**Rule P (ADR-008 D2)** applies transitively: when authoring an ADR that depends on neighbor ADRs, list those ADRs in the draft's own `## canonical_refs` and verify the draft does not propose an alternative already rejected in a sibling ADR's Alternatives table.

Trivial corrections (typo fixes, formatting, cross-reference updates) that do not change decision substance are exempt from predicate re-enforcement.

## In-place vs new-ADR routing (ADR-011 D1)

**Prefer in-place edit.** When a decision evolves, replaces, or restricts the firmness of any decision in an existing ADR, apply changes as in-place edits. Annotate the ADR header with `(revised <date>)`; git history carries the predecessor wording.

**New ADR only when:**
1. The decision opens genuine new decision space not covered by the existing corpus (ADR-011 D2 filter), **and**
2. It passes the ADR-012 D2 cross-cutting write filter: revising it would require argument (load-bearing) and it constrains more than one bead/domain/subsystem (cross-cutting).

**Before creating a new ADR, run ADR-008 D7's 5-dim overlap detection** — dispatch a fresh subagent (Haiku-class is sufficient) to score candidate matches against existing ADRs on: (1) problem statement, (2) root cause, (3) solution approach, (4) referenced files, (5) prevention/firmness rules. High overlap (4-5/5) → in-place edit instead. Moderate (2-3/5) → create but flag for consolidation. Low (0-1/5) → create normally. This dispatch is the lone fresh-Task() call inside the skill; the authorship core remains bucket (c).

## Mid-write discovery (ADR-008 D4)

If, during authoring, you notice a sibling-ADR predicate needing update, INDEX.md drift on *sibling* rows (rows for ADRs other than the one currently being written), or a CLAUDE.md inconsistency: **do not silently expand scope.** Create a follow-up bead with `bd create ... --notes='discovered-from: claude-<current-bead>'` and continue authoring the in-scope decision. Per ADR-008 D4 (FIRM), mid-loop discoveries land as new beads, not in-line fixes. (The INDEX row for the ADR currently being written is in-scope per "INDEX.md maintenance" — this exclusion covers rows the current write does not own.)

## Composition with `/compound` Promote handoff (ADR-013 D5)

The handoff contract:

- **`/compound` produces:** Promote section listing load-bearing L3 candidates. Each entry names: the proposed L3 target (ADR-NNN edit / CLAUDE.md section / skill edit) + countermand reasoning (why the candidate still holds after challenge).
- **Orchestrator decides** which Promote entries to act on; invokes `/adr-write` per entry as a separate composition step.
- **`/adr-write` reads** the Promote entry's countermand reasoning + proposed target; determines the firmness path; derives the alignment question; drafts the edit; awaits user confirmation; applies the write.

The chain: `/compound` Promote → orchestrator → `/adr-write` → alignment question → in-place edit per firmness path (ADR-013 D3). The ADR-013 D5 interim-discipline (orchestrator carries L3 authorship inline) retires once both `/adr-write` *and* `/compound` exist; until `/compound` ships, the interim still applies on Promote-shaped invocations the orchestrator drives manually.

## CLAUDE.md and skill-file edits — human-scope

L3 includes CLAUDE.md sections and skill files (ADR-013 D1); `/adr-write` may *propose* such edits but per ADR-008 D6 "instruction files are human-scope" — surface a one-liner suggestion; do **NOT** apply autonomously. Only `docs/decisions/ADR-*.md` files and the co-located `INDEX.md` derivative table (see next section) are written non-interactively after the alignment question.

## INDEX.md maintenance — skill-scope

The `INDEX.md` co-located with the edited ADR (i.e. `<adr-dir>/INDEX.md`, where `<adr-dir>` is `docs/decisions/` for project ADRs or the methodology home's `docs/decisions/` for global) is a *derivative discoverability surface*, not an instruction file. Auto-update is skill-scope, not human-scope — the same alignment-question that gates the ADR write covers the INDEX row update. Treat as part of the same atomic write:

- **New ADR** — append a row to the table: `ADR-NNN | title | scope-tag | status | one-line description`. Scope tag and one-liner are judgment calls; the author just made them and holds the context to call them honestly.
- **Evolved ADR with title / scope / status change** — update the row in place. The (revised YYYY-MM-DD) annotation on the ADR header propagates to the INDEX status column. A bare firmness-flip inside a decision body without a status-line change does not require an INDEX edit.
- **No INDEX present** — surface a one-liner suggestion to create one but do not auto-author the file; format choices (scope-tag vocabulary, columns, "when to consult" section) are first-time judgment, not derivative.

Commit the INDEX row update in the same commit as the ADR change; drift between INDEX rows and `ls ADR-*.md` is the failure shape this section exists to prevent.

## Substrate residue

ADRs are git-tracked files; the primary audit substrate is `git commit`. A commit message naming the ADR file, decision IDs touched, and the firmness path used is the durable trail:

```
adr: evolve ADR-013 D3 — EXPLORATORY → FLEXIBLE; firmness-path: noticing
ADR file: docs/decisions/ADR-013-memory-layer-architecture.md
Decision IDs: D3
Firmness path: EXPLORATORY (noticing)
Originator: /compound run on the originating bead (if applicable)
```

For Promote-handoff edits: stamp the originating bead's `--notes` with a record of the ADR file, decision IDs, and firmness path — makes the handoff auditable without relying on conversation transcript. Use `BEADS_ACTOR=adr-write:orchestrator` (or `adr-write:human-confirmed` when the human is the noticer) on the `bd update` invocation.

Post-write: run ADR-008 D6 discoverability check — grep the methodology home's `CLAUDE.md` (and any project-local `CLAUDE.md`/`AGENTS.md`) for `docs/decisions/`, `docs/decisions/INDEX.md`, and `history/*-design.md` mentions. If any is absent, surface a one-liner suggestion — human-scope; do not apply autonomously.

## No fresh-Task() dispatch on the authorship core

Per ADR-012 D3 bucket (c), the authorship core does not dispatch — the alignment question IS the frame-break. The ADR-008 D7 overlap-detection sub-dispatch (above) does not change the bucket classification; it is a discrete pre-write check, not own-work review.

## Recipe-leak guard on the authored ADR

An ADR is the place to make a decision durable. It is *not* the place to ossify model- or orchestrator-judgment into a deterministic rule when the rule has no real warrant beyond "we currently judge this way." That move is a **recipe leak** — process re-thickening dressed up as substrate. Before writing, check the draft against the firmness label:

- **FIRM** decisions encoding a numeric threshold, a fixed step ordering, a keyword-match rule, or a tier/mode toggle: the alignment question must rebut the alternative *"leave this as orchestrator judgment, governed by the existing primitive loop."* If the rebuttal doesn't hold, drop the firmness to FLEXIBLE/EXPLORATORY, soften to guidance, or don't write the ADR.
- **FLEXIBLE/EXPLORATORY** decisions of the same shape are fine — the firmness label itself signals "this may move."

The recipe-leak shape and call-out vocabulary are defined in `/send-it`'s Anti-patterns section; `/adversarial-review`'s universal rigor checks treat it as a flaggable finding on any reviewed artifact. Authored ADRs are downstream of both — once an ADR canonicalizes a recipe leak, the leak is harder to reverse.

## What this skill is NOT

- Not `/compound` — that surfaces L3 candidates with countermand reasoning; this authors.
- Not a general doc editor — scope is Anchored Decision Records and their co-located `INDEX.md` derivative table (both writable autonomously) plus CLAUDE.md / skill-file *suggestions* (human-scope). Not narrative prose, history docs, or design docs.
- Not a runtime ADR validator — does not check existing ADRs for compliance or run invalidation checks. Predicate enforcement (ADR-008 D1) applies only to decisions being actively authored or substantively edited.
- **Not algorithm-prescribing.** The skill names firmness paths, predicates, and substrate; it does not enumerate a step-by-step write loop. Substrate-thick, process-thin per ADR-012 D1 — the model composes the substrate signals by judgment.

## Working substrate

- `bd show <bead-id> --json | jq -r '.[0]'` — read Promote entry or bead context
- `cat <adr-dir>/ADR-NNN-*.md` — read target ADR before any edit
- `cat <adr-dir>/INDEX.md` — scan by scope tag (ADR-012 D2); `<adr-dir>` is co-located with the ADR being edited (project `docs/decisions/` or the methodology home's `docs/decisions/`)
- `Edit <adr-dir>/INDEX.md` — update row inline as part of the same atomic ADR write (see "INDEX.md maintenance")
- `Task()` (Haiku-class) — fresh subagent for ADR-008 D7 5-dim overlap detection on new-ADR creation (the lone dispatch)
- `Edit` on `docs/decisions/ADR-*.md` — in-place per ADR-011 D1
- `git add docs/decisions/ADR-NNN-*.md && git commit -m "..."` — primary audit substrate
- `BEADS_ACTOR=adr-write:orchestrator bd update <bead-id> --append-notes=<record>` — Promote-handoff audit residue on the originating bead
- `grep -E "docs/decisions/|INDEX.md|history/.*-design.md"` on the methodology home's `CLAUDE.md` — ADR-008 D6 post-write discoverability check

## Canonical refs

- **ADR-013 D3** — firmness-governed mutation rule; the core gate.
- **ADR-013 D5** — `/compound` Promote handoff composition contract; cross-decision reconciliation.
- **ADR-012 D3** — primitive shape pattern + `/adr-write` as primitive #6 (bucket (c) authorship core).
- **ADR-012 D2** — cross-cutting write filter for new ADR creation; D6 — dogfooding bar (referenced by EXPLORATORY-default note).
- **ADR-011 D1** — in-place mutation rule; D2 — new-ADR creation gate.
- **ADR-008 D1** — per-decision predicates on every new/substantive-edited decision.
- **ADR-008 D2** — Rule P (transitive ADRs-consulted discipline applied during draft).
- **ADR-008 D4** — mid-loop discovery routes to new bead with `discovered-from`.
- **ADR-008 D5** — `## canonical_refs` mandate on the authored ADR itself (FIRM).
- **ADR-008 D6** — post-write discoverability check (instruction files human-scope).
- **ADR-008 D7** — 5-dim overlap detection with fresh-subagent dispatch before new-ADR creation.
- **ADR-008 D8** — signal-shaped invalidation (no bare numeric thresholds).
- **ADR-006 D10** — warrant tags (`direct:` / `external:` / `reasoned:`) on Alternatives rejections.
- **originating skill-build bead** — acceptance contract for this skill build.
