---
name: adversarial-review
description: Fresh-context adversarial review of own-work artifacts — `--design`, `--acceptance`, plan, decomposition tree, bead set, cumulative diff. Use when about to stamp `verdict:pass` on own work, about to first-dispatch children in a multi-bead unit (review the *scoping*, not each item — boundaries, ordering, dependency edges, missing items), about to mark a unit complete, just drafted a `--design` / `--acceptance` / decomposition tree, or about to invoke `bd close` on a non-trivial bead. Triggers on "sanity-check this", "review my plan", "ready to ship the design", "before we start", "is this scoped right", "did I miss anything". Default-on for own work per ADR-012 D3 — never review your own contract, plan, or decomposition tree without fresh-context dispatch. One reviewer per round, orchestrator-judged convergence via countermand-test, three-state exit (pass / fail / raise). Distinct from review-v2 (heavy reference composition with mode switching and convergence-loop machinery).
---

## Purpose

Provide fresh-context adversarial rigor over any "own-work" artifact — a bead's `--design`, a proposed plan, a decomposition tree — so authors don't silently mark their own work converged. The fresh-`Task()` dispatch is the load-bearing element: agents inside the author frame inherit the author's blind spots; a separate fresh context breaks the frame.

**Spec source:** the originating adversarial-review design bead (the full decision narrative with ADR-008 D1 predicates, alternatives tables with ADR-006 D10 warrant tags, and "what would invalidate" predicates lives on that bead).

## When to invoke

- **Default-on** for any bead carrying own-work content (`--design`, `--acceptance`, plan in `--notes`, decomposition tree) about to be marked `verdict:pass` by its author. Per ADR-012 D3, *never review your own contract, plan, or decomposition tree* — the rule is legible (this skill exists) and unignorable (orchestrator runs it before stamping), but not mechanically gated.
- **Inherited contract about to be built on** — a bead you didn't author this session (an epic handed to `/send-it`, a `/brainstorm` bead, a `--design` ref) that you're about to decompose against or dispatch children from, carrying no fresh non-author `verdict:pass`. Building on it propagates its flaws into every child — the same hazard as marking your own contract converged, one step earlier. Judgment-routed; the `bd close` warning is the backstop.
- **In-band cue:** `bd close`'s `adversarial-review verdict gap` stderr warning IS a literal trigger per ADR-013 D11 (in-band juncture cues alongside the always-loaded reminder). Acknowledgement does not satisfy the cue — fresh-context dispatch, or an explicit named warrant for the skip (trivial mechanical edit, harness green, parent-bead review still fresh), does. See send-it/SKILL.md (methodology home) "Suppressing `/adversarial-review`" for the failure shape.
- **Judgment-routed** for other rigor passes (e.g. code review of someone else's diff, sanity check on shared documents).
- Callers compose this skill — `/decompose` calls it on the proposed tree; `/scope-check` does not need it (scope-check produces information, not own-work).

## Algorithm

```
/adversarial-review <bead-id>
```

The skill runs an internal loop of up to 3 rounds. One round = one fresh-`Task()` dispatch of a reviewer subagent with no shared context.

For each round (1..3):

1. **Dispatch one fresh-context reviewer subagent via `Task()`** with the reviewer brief (see below). No memory of prior rounds — fresh `Task()` per round per ADR-007 D3.
2. **Reviewer returns findings only** — no verdict, no severity labels, no fix proposals. Per rule 2 of the brief.
3. **Orchestrator triages findings** into four buckets via the countermand test:
   - **Fold-in** — apply to `--design` via `bd update <bead-id> --design-file=<path>`
   - **Discard** — finding is wrong or already addressed
   - **Defer** — legitimate but out of scope ("noted, not relevant now")
   - **Raise** — FIRM-ADR contradiction; orchestrator cannot unilaterally resolve
4. **If any Raise:** exit early with `waiting:human` (see Three-state exit below).
5. **Apply fold-ins.** Write the updated `--design` and append the round's audit residue to `--notes` (see Audit residue below).
6. **Decide round-continuation by countermand test:** *"would the user countermand me re-running another round here?"* If yes → continue to round N+1 (up to ceiling=3). If no → exit with convergence.

Defer is a legitimate verdict, not a signal of author uncertainty. Bucket counts do not mechanically determine stagnation — orchestrator judges by feel. Trust the orchestrator's countermand-test; do not impose metric thresholds.

## Harness-target review (brief instruction for orchestrators)

When dispatching the reviewer on a bead whose `--design` contains a `## Harness target` section, include this instruction in the reviewer brief:

> The artifact under review contains a `## Harness target` section. Consult the agent's **six-criterion review order** (defined in the `adversarial-reviewer` agent file under "## Harness-target review"). Apply criteria in the stated order — **alignment (#1) is the load-bearing first question**; a harness target that passes criteria 2-6 but fails criterion 1 is a REVISE finding regardless. Cite the file path and section of the artifact you read as evidence.

This instruction keeps the orchestrator's dispatch brief and the agent's review structure coherent. The adversarial-reviewer agent file (methodology home) is the single source of truth for the six-criterion order; the SKILL.md carries only the brief-text the orchestrator passes in.

## Reviewer brief contents (universal rigor only)

Every reviewer brief contains, **verbatim from review-v2:129-132** (rules 1-4):

1. **Evidence or silence** — every finding must cite file:line, ADR-decision-ID, or bead-ID. No vague "this seems off."
2. **Findings only, no verdict** — the orchestrator stamps verdict, not you.
3. **Err to surface** — when in doubt, raise the finding; the orchestrator's triage filters noise.
4. **Adversarial stance** — assume the author missed things they should have caught. Read with skepticism, not charity.

Plus universal rigor checks:

- **ADR-008 D1 predicates** on every Decision: firmness label (FIRM / FLEXIBLE / EXPLORATORY) + rationale + alternatives table + "what would invalidate" predicate.
- **ADR-006 D10 warrant tags** on every Alternatives-row rejection: `direct:` / `external:` / `reasoned:`. Flag rows missing the tag.
- **ADR-008 D5** mandatory `## canonical_refs` section on `--design`. Verify every referenced ADR/bead/spec is listed; verify reverse direction too (no orphan canonical_refs entries).
- **Recipe leak.** Flag any place in the artifact where situational judgment has been ossified into a deterministic rule, fixed step ordering, keyword/regex match on agent output, numeric threshold gate, or framework heuristic — when the rule is really model- or orchestrator-judgment. Specific shapes: numbered "Step 1 / Step 2 / Step 3" sequences where the order is situational; enumerated scoring signals presented as decision factors; `pass-N` / `tier=A` / `mode=light|heavy` toggles in framework prose; parsing agent text for "BLOCKED" / "done" / "complete" instead of a structured contract. Not a leak: hard rules from FIRM ADRs, mechanical IO contracts, prose heuristics aimed at a downstream LLM (the LLM still judges). Severity tracks how load-bearing the frozen judgment is.

Plus the **"competing reviewer" framing** (always present even though one reviewer per round runs):

> You are competing against another reviewer running in parallel on the same artifact. They are incentivized to surface what you miss. The orchestrator will compare your findings to theirs.

This is a deliberate prompt-engineering false-framing for perf-lift; acknowledged tensions named in the originating adversarial-review design bead D6.

**Caller-specific DoD** (per the originating adversarial-review design bead D4) is passed in by the caller (`/decompose`, etc.). The skill carries no per-artifact-type DoD — that fan-in-couples and is the review-v2 mode-switching anti-pattern this skill explicitly avoids. Callers brief their own DoD-as-data.

## Three-state exit

| Exit state | Skill action |
|---|---|
| **Convergence** (orchestrator judges round-N findings exhausted, no FIRM-ADR Raise) | Verdict **dual-write** with `BEADS_ACTOR=reviewer:fresh-subagent` (see below). Stamp **strictly after** all fold-ins for the final round are written to `--design`. |
| **Ceiling** (round 3 with findings still surfacing) | Verdict **dual-write** as `verdict:fail` with `BEADS_ACTOR=reviewer:fresh-subagent`. Artifact has unresolved rigor gaps the loop couldn't close. |
| **Raise** (FIRM-ADR contradiction surfaced) | `bd update <bead-id> --add-label=waiting:human`. No verdict label, no audit record. Surface the Raise to user; after resolution and any fold-in, re-enter the loop. |

### Verdict dual-write (load-bearing — read this)

`bd label add` / `bd update --add-label` **do not log `--actor` to `.beads/interactions.jsonl`**. Verdict identity therefore cannot be reconstructed from labels alone — the close-time check (the verdict close-time design bead) reads `interactions.jsonl` for `kind=verdict` entries to compare verdict-actor against bead `created_by`. Stamping the label without the paired audit record makes the verdict invisible to the substrate check (warns as if no review existed).

Two commands, same `BEADS_ACTOR`, in this order:

```bash
# 1. Stamp the label (UX echo, fast queries via bd list --label=verdict:pass)
BEADS_ACTOR=reviewer:fresh-subagent bd update <bead-id> --add-label=verdict:pass

# 2. Record the audit entry (load-bearing — carries actor + timestamp)
echo '{"kind":"verdict","issue_id":"<bead-id>","extra":{"verdict":"pass"}}' \
  | BEADS_ACTOR=reviewer:fresh-subagent bd audit record --stdin
```

For `verdict:fail`, substitute `pass` → `fail` in both invocations.

**Why two writes:** the label gives fast queryability and human legibility; the audit entry gives substrate-readable actor + timestamp. Per the reviewer-identity design bead D3, both pieces work together — neither alone is sufficient.

**Actor source-of-truth:** the `actor` field in the stdin JSON is **ignored** by `bd audit record` — `BEADS_ACTOR` env (or `--actor` flag) is what lands in `interactions.jsonl`. The env-var must be set on the `bd audit record` invocation, not just on the prior `bd update`.

The three states are operationally distinct. **Raise ≠ Fail.** Fail means "review concluded fail"; Raise means "review cannot conclude without user input." Downstream consumers (the close-time check) read the labels separately.

**Stamp-after-fold-in ordering is load-bearing** for freshness (reviewer-identity design bead D3): if `--design` mutates after `verdict:pass` is stamped (e.g. a late user-resolved Raise produces a new fold-in), the verdict is stale per the timestamp predicate and must be re-stamped.

## Audit residue (per round)

Append to bead's `--notes` via `bd update <bead-id> --append-notes`:

```
## Adversarial review record (round N)

**Dispatched:** <date> — one fresh-context reviewer (Task subagent).

**Findings:** <count>. **Triage:** <fold-in> Fold-in / <discard> Discard / <defer> Defer / <raise> Raise.

**Material catches:** [3-5 strongest findings with terse description of what was folded]
**Lighter fold-ins:** [list of minor fold-ins by finding ID]

**Exit reason:** [convergence | ceiling | raise] — [one-line rationale: countermand-test stopped because X / ceiling hit / Raise surfaced FIRM-ADR contradiction Y]

**Discipline check:** competing-reviewer framing applied; reviewer issued findings-only with no `VERDICT:` line; evidence-or-silence rule held (every finding cited file:line, ADR-decision, or bead-design quote).

**Verdict stamped:** verdict:pass | verdict:fail | (none — waiting:human set)
```

## Recipe-vs-substrate seam

The orchestrator runs `bd update --add-label=verdict:pass` with `BEADS_ACTOR=reviewer:fresh-subagent`. The actual fresh-context dispatch happens in the prior `Task()` call inside this skill's loop; substrate cannot distinguish a forged actor token from a real fresh-context dispatch. The recipe (this skill file) enforces the norm. Per the reviewer-identity design bead D2.

**Substrate identity-check limitation** (per the reviewer-identity design bead D3): the close-time check compares verdict-add actor against the bead's create-event actor. For most beads the inequality holds trivially, but it does NOT verify "reviewer subagent ≠ artifact-author" — only "reviewer subagent ≠ bead-create-author." The discipline that a real fresh `Task()` dispatch happened is carried by this skill's contract, not by substrate enforcement.

## Composition with other primitives

- **`/decompose`** — calls this skill on the proposed tree (whole-tree review per the decompose design bead D3); passes its decomposition-specific DoD (conjunction-completeness, coverage map, file-claim map, integration-test bead presence, etc.) as caller-brief inputs.
- **`/scope-check`** — does NOT call this skill. Scope-check produces information (a neighbor checklist), not own-work judgments.
- **Manual bead authoring** — orchestrator invokes this skill before stamping `verdict:pass` on any own-work `--design`.

When both scope-check and adversarial-review are default-on for the same bead, **scope-check runs first** (per the scope-check design bead D8) — folds enrich `--design`'s `## canonical_refs` — then adversarial-review reads the enriched design. Reverse order invalidates the verdict per the reviewer-identity design bead D3 freshness.

## Working substrate

- `bd show <bead-id> --json` — read bead's current state for the brief
- `bd update <bead-id> --design-file=<path>` — apply fold-ins
- `bd update <bead-id> --append-notes=<text>` — append audit residue
- `BEADS_ACTOR=reviewer:fresh-subagent bd update <bead-id> --add-label=verdict:pass` — stamp verdict label (UX echo / fast queries). **Must be paired with `bd audit record` — see "Verdict dual-write" above.**
- `echo '{"kind":"verdict","issue_id":"<id>","extra":{"verdict":"pass"}}' | BEADS_ACTOR=reviewer:fresh-subagent bd audit record --stdin` — record the audit entry the close-time check reads
- `bd update <bead-id> --add-label=waiting:human` — used for Raise exit (no audit-record dual-write needed; not a verdict)
- `Task()` with `subagent_type=reviewer` (or `general-purpose`) — dispatch the fresh-context reviewer

## What this skill is NOT

- Not review-v2 — no `--mode=design/plan/implementation` switching, no ADR pre-filter, no `VERDICT:` stdout contract line, no machine-parseable convergence machinery. Those belong to review-v2 (the heavy reference composition for v2-chain invocations).
- Not scope-check — scope-check is outward-look information-production, not inward own-work review.
- Not a code reviewer — this reviews design/plan/decomposition artifacts, not implementation diffs.

## Canonical refs

- ADR-012 D3 (default-on for own-work; primitive composition)
- ADR-008 D1 (universal predicates), D5 (canonical_refs mandate)
- ADR-007 D3 (fresh-`Task()` per round)
- ADR-006 D10 (warrant tags in Alternatives tables)
- originating adversarial-review design bead (full design with rationale, alternatives, invalidation predicates — read for context beyond what this SKILL.md carries)
- reviewer-identity design bead (verdict label + audit-log actor + freshness predicate)
- close-time verdict design bead (downstream close-time consumer; reads `interactions.jsonl` `kind=verdict` entries — see Verdict dual-write)
- review-v2/SKILL.md (methodology home) lines 129-132 (brief-constants rules 1-4 lifted verbatim), lines 63-67 (4-bucket triage with countermand-test framing)
