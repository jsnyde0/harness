---
name: scout-features
description: Survey 2+ EXTERNAL competitor products to fuel your own feature brainstorming. Dispatches one `feature-scout` subagent per platform in parallel, then the orchestrator runs multi-lens synthesis (evidence audit → parity matrix → JTBD clustering → white-space mapping) in its own context. Use when about to brainstorm features for a category with established players, when researching "how do other tools handle X", when the user names 2+ external competitor platforms, or when about to write a product spec/PRD for a competitive market. Triggers on "scout competitors", "competitor feature analysis", "look at how X / Y / Z do it", "find inspiration from [external products]", "feature comparison across [products]". SKIP when: only ONE platform is named (dispatch `feature-scout` directly, no skill needed); when "competitive analysis" refers to internal artifacts/ADRs/this-codebase (use `/scout-adrs`); when the user already knows the landscape and wants to brainstorm directly. Composes with `/brainstorm` downstream — produces synthesis brief that the orchestrator pastes as initial context for the Socratic loop.
---

## Purpose

Before brainstorming features for your own product, ground the design in what comparable products actually ship. This skill produces a **synthesis brief** — parity matrix, job-clusters, white-space candidates, evidence caveats — that flows into `/brainstorm` as raw material.

It is *not* a feature-dump generator. Naive "list all competitor features" is the canonical failure mode (Cagan: feature factory; Torres: solution-as-opportunity confusion). The synthesis lenses below exist to prevent that.

## When to invoke

Orchestrator-judged. Strong triggers:

- About to brainstorm features for a category with established players ("I'm designing a task manager — what do Linear, Asana, Height do?").
- User names 2+ competitor platforms in one prompt.
- About to write a product spec / PRD / feature design and the design surface intersects a well-mapped market.
- User says "find inspiration", "what do other tools do for X", "look at how Y does it".

Weak triggers (consider but don't auto-invoke):

- Single-platform deep-dive — one `feature-scout` dispatch is enough; no synthesis needed.
- The user already knows the competitive landscape and just wants to brainstorm — skip scouting, go straight to `/brainstorm`.

## Invocation surface

```
/scout-features <topic> --platforms <p1>,<p2>,<p3> [--focus <narrowing>] [--screenshots]
```

- `--platforms` accepts platform names (homepage URLs are resolved by the scout) or explicit `name=url` pairs.
- `--focus` narrows the scout (e.g. `--focus "AI features"`, `--focus "free-tier limits"`). Optional; absent = full feature surface.
- `--screenshots` enables screenshot capture for pricing pages + UI-evidence features. Off by default.

Free-text invocations work too: "scout features from Linear, Asana, and Height for task-prioritization UX."

## Algorithm

### Phase 1 — Scope

1. Resolve platform list. If the user gave names only, look up canonical URLs (homepage). If unsure between two products with similar names, raise — emit at `/tldr` altitude (decision + tradeoff).
2. Decide `focus`. If absent and the platform list is broad, ask the user to narrow OR proceed full-surface with a note that the synthesis brief will be coarse.
3. Fan-out is orchestrator-judged against scout cost (~1 Sonnet scout per platform). As N grows, surface the cost trade-off to the user. Beyond ~10 platforms in one dispatch, raise — that's a multi-session research project, not a single skill invocation.

### Phase 1.5 — Browser session pre-start (only if any scout will need it)

If any scouted platform is likely JS-rendered or you set `screenshots: true`, start the shared browser session *before* fan-out so parallel scouts don't race on CDP initialization:

```bash
node $HOME/.claude/skills/browser-automation/start.js
```

Skip this if all targets are static-HTML and screenshots are off.

### Phase 2 — Parallel scout dispatch

Dispatch one `feature-scout` per platform **in a single message with multiple `Agent` tool calls** so they run concurrently. Each scout gets:

- `platform` — `{name, homepage_url}`
- `focus` — passed through verbatim, or `null`
- `screenshots` — passed through, default `false`
- `max_features` — default 25; lower if `focus` is narrow

Each scout returns a JSON array of feature records (schema in the feature-scout agent definition). The scout's labeled browser tabs are scout-private — never cross-touch.

### Phase 3 — Synthesis (orchestrator runs this in its own context)

**This is the brain's job.** Do not dispatch a synthesizer subagent — the multi-lens judgment is exactly what the orchestrator's context is for. The scouts paid the token cost of reading pages; you pay the token cost of synthesis.

The four lenses below answer different questions. Default sequence: **Evidence audit → Parity → JTBD → White-space** — credibility-filter first so downstream lenses don't build on laundered evidence. Reorder when judgment says so (e.g. if scout output is uniformly high-credibility, audit collapses to a quick pass).

#### Lens A — Evidence audit (credibility filter, run first)

Bucket every scout record by `source_type`:

- **High-credibility:** `changelog`, `pricing-page`, `docs` — load-bearing for parity claims.
- **Medium:** `marketing-page`, `ui-screenshot` — usable but flag in caveats; down-weight in parity ✓.
- **Low:** `third-party`, `inferred:true` — never promote to a confident parity ✓; mark `~` and surface in caveats.

Records with `pricing_tier: "unknown"` or `"unreachable"` get noted as pricing-blind; do not claim tier-gating in the parity matrix for these.

The output of this lens is a credibility-annotated record set the next three lenses operate on.

#### Lens B — Parity matrix (table-stakes view)

Build a `features × platforms` grid. Cells: ✓ (high-credibility direct evidence), ~ (medium-credibility or inferred), ✗ (absent in scouted sources — NOT proven absent in product). **Required column: "Underlying job"** — every row must name the job the feature serves, in user-language. This forces job-shaped reasoning before parity-shaped reasoning and structurally resists the feature-checklist trap.

**Use it to:** identify the table-stakes floor — features most platforms address (regardless of vendor name). Working below that floor is parity, not differentiation.

**Don't:** read ✗ as "competitor lacks this." Read it as "scout didn't see it."

#### Lens C — JTBD clustering (semantic view)

Group features by underlying job, not vendor name. Linear's "Cycles" and Asana's "Sprints" both serve `job: "time-box work into iterations"`. Cluster, name the job in the user's language, list each platform's *shape* of the surface for it.

**Use it to:** see what competitors are really solving. Brainstorm fuel lives here — once the shared job is visible, "is there a better way to serve this job?" becomes askable.

**Don't:** cluster by `category` (vendor-imposed). Cluster by job (user-imposed). Categories lie about overlap.

**Coverage rule (load-bearing):** before moving to Lens D, every scouted record must be either (a) assigned to at least one job cluster, or (b) explicitly excluded with a one-line reason (duplicate-of-X, off-scope-for-focus, evidence-too-weak, etc.). This is the structural defense against silent omission: the canonical failure mode is the orchestrator synthesizing from features it noticed and missing whole jobs that only one platform addresses (e.g. "discover trending content outside my social graph" / "package and sell what I do without an inbound request"). Touch every record. Per-platform record sweep is acceptable for high-N corpora — but no record may be left unaccounted for.

#### Lens D — White-space mapping (open-question view)

For each clustered job, note: which platforms address it richly, which poorly, which not at all. Flag jobs the `focus` topic implies but no scouted platform addresses.

**Use it to:** generate **open questions for `/brainstorm`** — not feature candidates. The white-space is *evidence an opportunity may exist*, never *evidence a feature should be built*.

**Don't:** write "we should build X." Write "no platform addresses [job]; is that an opportunity or a graveyard?" The next step is brainstorm, not roadmap.

### Phase 4 — Output: the synthesis brief + raw sidecar

The deliverable is **two files**: the synthesis brief (Markdown) and a raw-records sidecar (JSON). The brief compresses; the sidecar preserves. Without the sidecar, downstream `/brainstorm` cannot reach the underlying evidence without navigating subagent JSONL paths — research effectively becomes lost.

The five Markdown sections below are **required** in the brief — omitting any of them means the brief is incomplete (an evidence caveats section with zero entries is a valid signal; omitting the section is not).

```markdown
# Scout brief: <topic>

**Scouted:** <platform list> · **Focus:** <focus or "full surface"> · **Date:** YYYY-MM-DD

## Parity matrix

| Underlying job (user-language) | Feature (any name) | <P1> | <P2> | <P3> | Notes |
| --- | --- | --- | --- | --- | --- |
| <job in user-language> | <name> | ✓ | ~ | ✗ | <one-line> |

Table-stakes observations: <which jobs most platforms address>.

## Job clusters

### Job: <name in user-language>
- **<Platform> — <feature name>**: <one-line on the surface they ship>
- ...
- **Shared shape:** <one-line observation across the cluster>
- **Shape variance:** <where the platforms diverge — this is where differentiation hides>

### Job: ...

## Open questions (white space)

- **<Job or sub-job>** — addressed by: <none / weakly / [P]>. Open question for brainstorm: <one-line — phrase as a question, not a feature>. Why might this gap be intentional? <one-line — graveyards exist>.

## Evidence caveats

- <Claims resting on inferred/marketing evidence — which job rows are affected>
- <Sources that 4xx'd, required auth, or hit `pricing_tier: unreachable`>
- <Changelog age / data staleness>

## Brainstorm hand-off

The above is **evidence of opportunities and shared jobs**, not a feature list to build. Use the next step to validate:

- Paste this brief verbatim as initial context for `/brainstorm <topic>` — the Socratic loop will interrogate the open questions, not consume the parity matrix.
- OR pick one job cluster and re-invoke `/scout-features --focus "<that job>"` to deepen before brainstorming.
- Raw records sidecar: `history/scout-features-<topic>-raw/` — the per-platform-per-round feature corpus the brief was synthesized from. Read individual files when brainstorming on a cluster needs the texture the brief compressed away.
- Do NOT route this brief into `/beadify` or `/decompose` directly — beads require a `--design` that this brief is not yet.
```

**Raw sidecar — required deliverable alongside the brief.** After writing the brief, write `history/scout-features-<topic>-raw/` as a directory containing:

- `README.md` — round structure (which platforms got R1 only vs R1+R2, why), evidence-mix caveats, pointer back to the brief.
- One JSON file per (platform × round): `<platform>-r1.json`, `<platform>-r2.json` — verbatim feature-record array as the scout returned it. **Keep R1 files even when R2 superseded** — the diff between docs-leaning R1 and authenticated R2 is itself useful evidence (it shows the marginal value of the auth pass and tells the next orchestrator which surfaces docs misrepresent).

The brief is the synthesis; the sidecar directory is the substrate. A brainstorm session that wants to deepen a cluster should be able to read a single platform's file without sifting a 200-record merged blob — and should be able to diff R1 vs R2 to see what authentication unlocked.

**Hard rules for this section:**
- **No "we should build…" statements.** Every white-space entry is phrased as a question.
- **No "competitor X has Y, we should ship Y."** The parity matrix exists to show shared jobs, not to be a build list.
- **Every parity-matrix row carries an `Underlying job` value.** Rows without a named job get held back — if you can't name the job, the row isn't ready for synthesis.
- **The raw sidecar must be written alongside the brief**, and its path referenced in the Brainstorm hand-off section.

## Anti-patterns the orchestrator must guard against

Structural defenses exist where listed; the rest are discipline.

1. **Dump-the-list.** The output template requires named jobs per row + "Open questions" framing — these structurally resist the dump shape. If you find yourself producing a `## Features` flat list instead of the five required sections, you've regressed.

2. **Solution-as-opportunity (Torres).** Hard rule in Phase 4: white-space entries are phrased as questions, not features. If you write "we should build X" you've violated the contract.

3. **Ship-because-competitor-has-it (Cagan).** The "Underlying job" required column forces job-shaped reasoning before parity-shaped. A row with no nameable job gets held back, not promoted to roadmap candidate.

4. **Evidence laundering.** Lens A runs first; marketing-page and inferred records can never become confident parity ✓. The credibility annotation is load-bearing for every downstream lens.

5. **Cross-platform contamination during scouting.** Scouts run in parallel with labeled tabs; cross-platform reasoning happens *only* in the orchestrator's synthesis context.

6. **Skipping focus narrowing.** Wide-open scope produces useless dumps. Phase 1 step 2 makes narrowing explicit before fan-out.

7. **Routing the brief into `/beadify` or `/decompose` directly.** The brief is brainstorm fuel, not a design. Acceptance criteria don't exist yet. Phase 4's hand-off section names this explicitly.

## What this skill is NOT

- Not `/brainstorm` — does not generate new feature ideas. It produces fuel; brainstorm consumes it.
- Not `/scout-adrs` — that scouts internal ADR substrate; this scouts external products.
- Not a PRD writer. The brief is brainstorm input, not a spec.
- Not a market-research report. Drops competitive positioning, pricing strategy, GTM analysis — that's a separate exercise.

## Composition

- **Upstream:** none required. User invokes when starting a feature design.
- **Downstream:** `/brainstorm <topic>` consumes the brief. Or the user picks one cluster and re-invokes `/scout-features` with narrower `--focus` for depth.
- **Parallel:** `feature-scout` dispatches are parallel-safe; each holds a labeled browser tab. Synthesis is single-threaded in the orchestrator.

## Working substrate

- feature-scout agent (methodology home) — agent definition (extraction schema, browser usage, hard rules)
- browser-automation/SKILL.md (methodology home) — JS-rendered page handling for scouts
- `Agent(subagent_type=feature-scout)` — one parallel dispatch per platform
- Today's date via shell `date +%Y-%m-%d` — passed into scout briefs as `captured_at`

## Canonical refs

- fresh-Task-per-dispatch ADR — fresh-`Task` per dispatch; load-bearing for parallel scout fan-out in Phase 2.
- substrate-thick-process-thin ADR — substrate-thick / process-thin discipline; synthesis stays in orchestrator (the brain's judgment pass), not in a synthesizer subagent.
- scout-adrs/SKILL.md (methodology home) — sibling outward-look primitive; this is its external-product counterpart.
- content-extractor agent (methodology home) — schema-pinned extraction precedent; `feature-scout` is the same pattern with browser ability + light classification.
- bd memory `orchestration-research-2026-05-14` — convergent finding: subagent = context offload; brain pays for judgment, workers pay for volume. Also: Cagan / Torres / Ulwick anti-patterns that shape the synthesis lenses and output discipline.
