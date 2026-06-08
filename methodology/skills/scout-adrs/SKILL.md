---
name: scout-adrs
description: Cheap ADR-discovery primitive — for a topic, bead id, or design ref, dispatch a fresh-context haiku subagent that scans `docs/decisions/INDEX.md` and walks `## canonical_refs` to return in-scope ADRs with firmness + one-line rationale. Use when authoring a new bead `--design` (especially if `## canonical_refs` would otherwise be empty), about to author or evolve an ADR, scoping work that touches a design surface, before claiming a bead whose design references no ADRs, or when the user asks "is there an ADR on X", "what's our position on Y", "what constrains this", "any decisions about Z". Use proactively when a load-bearing decision surfaces mid-implementation. Pure read; no substrate writes — cheap (haiku) and almost always worth running when work touches design surface.
---

## Purpose

Mid-conversation, before contract authoring, or before any architectural decision, you often want to know: *which ADRs are in scope for this?* `/scout-adrs` answers that question cheaply — one fresh-context haiku dispatch reads `INDEX.md`, matches against the topic, optionally walks `canonical_refs` for transitive context, and returns a short list.

Distinct from `/scope-check`'s INDEX-scan signal: scope-check folds ADR matches into a *bead's* `--design ## canonical_refs` during authoring. `/scout-adrs` runs against a *topic or prompt* — typically no bead exists yet, or the agent is mid-deliberation and wants the constraint surface in hand before committing.

## When to invoke

Agent-judgment-routed. Useful triggers:

- Before drafting a design narrative or new ADR — to surface already-decided territory ([ADR-011 D2](../../docs/decisions/ADR-011-adrs-reflect-target-architecture.md)).
- Before scoping a new bead or epic — to know which FIRM decisions constrain the shape.
- When the user asks "is there an ADR on X?" or "what's our position on Y?"
- Mid-implementation when a load-bearing choice surfaces that wasn't anticipated.

No default-on trigger. The agent decides when the ADR-discovery cost is worth paying.

## Invocation surface

```
/scout-adrs <topic>
/scout-adrs --bead <bead-id>
/scout-adrs --design <path-to-design-doc>
```

One verb. Inputs are subagent-brief context, not separate subcommands.

## Algorithm

1. **Resolve the brief input** — for `--bead`, read `bd show <id> --json` and pass `--title`/`--description`/`--design`/`--acceptance` to the subagent. For `--design <path>`, read the file. For free-text topic, pass it directly.
2. **Dispatch one fresh-context subagent** via `Task(subagent_type=general-purpose, model=haiku)` with the brief (see below). Single dispatch; no internal rounds.
3. **Receive the ranked list** (see Output shape).
4. **Return to caller.** No substrate writes. The caller (main agent, user, or another primitive) decides what to do with the list — fold into a `--design ## canonical_refs`, raise a FIRM conflict, hand to `/adr-write`, or just keep in conversation context.

## Output shape (subagent emits)

```markdown
## ADRs in scope

- **ADR-NNN D<k>** (FIRM | FLEXIBLE | EXPLORATORY) — <one-line rationale: which decision is load-bearing for this topic>
- **ADR-MMM** (firmness) — <rationale; cite specific D<k> if a single decision is load-bearing, otherwise the ADR as a whole>
- ...

## Transitive (via canonical_refs)

- **ADR-PPP D<k>** (firmness) — <rationale; reached via ADR-NNN's canonical_refs>
- ...

## Notes

<optional one-line summary of empty-substrate or "nothing in scope" findings>
```

Each section may be empty. An entirely-empty list is a valid "no ADRs in scope" outcome — surface it, don't collapse into "scout failed." Cap output at ~10 entries total; the subagent ranks and truncates if more match.

## Subagent brief (substrate signals named, algorithm not prescribed)

The haiku subagent is briefed with the topic/bead-content + substrate signals; its judgment composes them:

1. **`docs/decisions/INDEX.md`** — the table is the discoverability surface. Match topic against the Scope column (`arch`, `workflow`, `ops`, etc.) and one-line descriptions. INDEX.md's "When to consult" section names the contexts where ADR scan applies.
2. **Full read of title-matching ADRs** — for any ADR whose title or one-line description plausibly intersects the topic, read the ADR file and identify which specific decisions (D1, D2, …) are load-bearing. Carry firmness per decision (FIRM / FLEXIBLE / EXPLORATORY).
3. **`## canonical_refs` walk** — for each matched ADR, scan its `## canonical_refs` section for upstream ADRs. Include transitive matches in the second output section when they constrain the topic.
4. **For `--bead` inputs:** also check the bead's `--notes` for an existing `ADRs: ADR-NNN, ADR-MMM` line (per INDEX.md's bead-linkage convention) — these are already-known constraints; surface them but mark as "(already linked)."

No prescribed order. Capable models compose signals well; prescription becomes scaffolding.

**Brief framing for perf-lift** (identical to scope-check / compound / adversarial-review):

> You are competing against another reviewer running in parallel on the same substrate. They are incentivized to surface what you miss. The orchestrator will compare your findings to theirs.

## What this skill is NOT

- Not `/scope-check` — scope-check authors *bead substrate* (folds into `--design ## canonical_refs`, stamps `scope-checked` label). `/scout-adrs` returns a list; the caller decides what to do with it.
- Not `/adr-write` — does not author or edit ADRs. If the scout finds a gap (topic warrants an ADR that doesn't exist), the caller routes that to `/adr-write` separately.
- Not exhaustive — output is capped. If the topic is too broad, the caller should narrow the topic and re-invoke, not expect the subagent to enumerate everything.
- Not a verdict — produces information, not pass/fail. No labels, no audit-log writes.

## Working substrate

- `docs/decisions/INDEX.md` — the discoverability table
- `docs/decisions/ADR-*.md` — full ADR text for matched entries
- `bd show <bead-id> --json` — bead content for `--bead` invocations
- `Task(subagent_type=general-purpose, model=haiku)` — single fresh-context dispatch

## Canonical refs

- [ADR-011 D2](../../docs/decisions/ADR-011-adrs-reflect-target-architecture.md) — discoverability check before authoring new ADRs (new-decision-space test).
- [ADR-012 D2](../../docs/decisions/ADR-012-substrate-thick-process-thin.md) — INDEX.md cross-cutting filter + Scope-column conventions; substrate-thick / process-thin discipline this skill follows.
- [ADR-008 D5](../../docs/decisions/ADR-008-adr-predicates-and-plan.md) — `## canonical_refs` mandate; the graph this skill walks.
- [ADR-007 D3](../../docs/decisions/ADR-007-primitive-loop.md) — fresh-`Task()` per dispatch.
- scope-check/SKILL.md (methodology home) — the outward-look-during-bead-authoring counterpart; INDEX-scan is one of four signals there, the *only* signal here.
