# ADR-007: Primitive Loop — Blocking State Machine with Rigorous Reviewers

**Status:** Accepted (revised 2026-05-13)
**Date:** 2026-04-24
**Design:** [Phase 1 Design](../../history/2026-04-24-workflow-loop-phase1-design.md); parent picture [Workflow Loop Design](../../history/2026-04-24-workflow-loop-design.md)
**Research basis:** [`2026-04-24-workflow-loop-brainstorm-research.md`](../../history/2026-04-24-workflow-loop-brainstorm-research.md) — metaswarm v0.4.0 pivot, Alexandre Castro rationalization findings, OpenHands delegation patterns, Ralph stateless re-prompt.
**Related:**
- [ADR-005](ADR-005-beadify-redesign.md) — beadify organize+target; loop consumes beadify output
- [ADR-006](ADR-006-workflow-modernization.md) — bead-as-substrate + entry-point resolution
- [ADR-008](ADR-008-adr-predicates-and-plan.md) — ADR predicates + WHY-aware PLAN (layered on this loop)
- [ADR-009](ADR-009-loop-composability.md) — epic composability (layered on this loop)

## Context

`/send-it` today is a multi-phase sequential pipeline. Phases are convention, not enforced, and subagent self-reports drive transitions. Two failure modes observed repeatedly:

- **Advisory gates skipped under time pressure.** Metaswarm's v0.4.0 pivot documents this from 3 weeks of operational data: advisory quality gates silently get bypassed. Redesign to blocking state machine.
- **Reviewer rationalization.** Alexandre Castro's fitness-function retrospective: an agent sees a violation, rationalizes it as an exception, dismisses it. Without explicit anti-rationalization rules, reviewers rubber-stamp as autonomy grows.

This ADR defines the **primitive loop**: a blocking state machine that runs for one bead, with orchestrator-enforced transitions, rigorous reviewers, and a retry cap. Epics are handled by the same primitive via composition (see ADR-009).

## Decisions

### D1: Loop is a four-state blocking machine: PLAN → REVIEW-PLAN → IMPLEMENT → REVIEW-CODE — **canonical recipe for code-shaped beads with runnable acceptance**

**Firmness: FLEXIBLE** *(demoted from FIRM 2026-05-08 per ADR-012 D3 — the 4-state machine is no longer a mandatory pipeline; it is a canonical recipe invoked by judgment when a bead has runnable acceptance and code-shaped work. Substrate-enforced default-on adversarial review (ADR-012 D3) replaces the mandatory state-machine framing.)*

When invoked as a recipe, the loop consists of four states, run sequentially on a single bead. Each state is a fresh `Task()` subagent invocation. State transitions are **enforced by the orchestrator** (not by the subagent self-reporting) and require an explicit PASS signal. For non-code-shaped work (research, ADR authoring, content, ops calibrations), other recipes apply per ADR-012 D3.

**Rationale:** Separate PLAN from IMPLEMENT so weak plans get rejected before code is written. Separate REVIEW-PLAN from REVIEW-CODE because they check different artifacts with different criteria. Metaswarm's anti-pattern #6 ("combining phases") is explicit on this. Blocking state machine prevents phase-skipping under pressure (metaswarm v0.4.0 pivot).

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| 4-state blocking (chosen) | Separates planning from execution; rejects weak plans early; phases can't be skipped | More subagent invocations than a single-pass loop |
| 2-state (IMPLEMENT → REVIEW) | Simpler | No pre-implementation gate; bad plans waste IMPLEMENT cycles. **reasoned:** without a PLAN gate, weak plans enter IMPLEMENT silently; the cost of IMPLEMENT on a bad plan is higher than the cost of REVIEW-PLAN on a good plan |
| N>4 phases (e.g. add DESIGN) | More checkpoints | Diminishing returns; every phase is a retry surface. **reasoned:** each phase is a failure point; beyond 4, the marginal review benefit is outweighed by the retry surface added |
| Advisory phases (status quo) | Familiar | Skip-able under pressure (metaswarm v0.4.0 lesson). **external:** metaswarm v0.4.0 pivot — 3 weeks of operational data documented that advisory quality gates silently get bypassed under time pressure |

**What would invalidate this:** If REVIEW-PLAN consistently PASSes plans that REVIEW-CODE then FAILs on structural grounds, the split isn't earning its keep — merge REVIEW-PLAN into REVIEW-CODE. Watch for `bd list --label=retry` entries where REVIEW-CODE FAILs cite plan-level issues that REVIEW-PLAN waved through — when that surfaces as a recurring pattern, reconsider the split.

### D2: Orchestrator runs `--acceptance` and other validators directly — never trusts subagent self-report

**Firmness: FIRM** *(scope clarified 2026-05-08 per ADR-012 D3 — applies whenever a primitive-loop recipe is invoked or a bead with runnable `--acceptance` is closed; the trust model is substrate-level, not pipeline-specific.)*

When the loop recipe runs (or any close-time validation occurs on a bead with runnable `--acceptance`), the orchestrator itself runs the bead's `--acceptance` command (and any other validators like lint, typecheck) using the exit code as truth. The subagent's "tests pass" or "done" claim is not a transition signal.

**Rationale:** "Trust nothing, verify everything" (metaswarm). Subagent self-reports degrade as autonomy grows — review rubber-stamping is documented across Galileo, Prassanna, and metaswarm's own v0.4.0 postmortem. The fix is structural: the decision-maker (orchestrator) runs the check itself.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Orchestrator runs validation (chosen) | Structural anti-rationalization; exit codes can't lie | Orchestrator needs shell + test-runner access |
| Trust subagent claim | Simpler orchestrator | Single biggest failure surface per metaswarm. **external:** metaswarm v0.4.0 postmortem — subagent self-reports are documented as the single biggest failure surface; rubber-stamping documented across Galileo, Prassanna, and metaswarm's postmortem |
| Dedicated validator subagent | Separates concerns | Adds another trust boundary; same rubber-stamp risk. **reasoned:** a dedicated validator subagent is still a subagent; the trust model applies equally — it can rationalize and rubber-stamp just as the original subagent could |

**What would invalidate this:** If the orchestrator becomes too complex maintaining validators, offload to a dedicated validator process — but *not* to the IMPLEMENT subagent. Watch for orchestrator shell logic growing unwieldy — if `wc -l` on the orchestrator script exceeds ~200 lines, factor out (don't merge back).

### D3: Every reviewer invocation is a fresh `Task()` — no reuse across retries

**Firmness: FIRM**

Each REVIEW-PLAN and REVIEW-CODE is a new `Task()` subagent with zero memory of prior findings, including when the same bead is re-reviewed after a FAIL→retry cycle. No reviewer sees the previous reviewer's findings.

**Rationale:** Anchoring bias. A reviewer who already knows what was flagged will look for that and miss the new thing. Fresh reviewer finds a different slice of the problem space. Metaswarm codifies this as a non-negotiable rule; our subagent model already enforces it by default (no shared context between Task() invocations), but without an ADR it can be "optimized away" by someone trying to save tokens.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Fresh Task() every time (chosen) | Structural anti-anchoring | Slightly more tokens per review |
| Reuse reviewer for re-review | Cheaper | Anchoring bias — #1 reviewer failure per metaswarm. **external:** metaswarm operationalizes fresh-reviewer as a non-negotiable rule specifically to prevent anchoring bias; prior findings anchor subsequent reviewers to the same slice |
| Pass prior findings forward | "Efficiency" | Directly induces the anchoring the rule prevents. **reasoned:** passing prior findings forward gives the re-reviewer a map of what was found before; the map constrains the re-reviewer to look for the same things and miss the new things |

**What would invalidate this:** If re-reviewers consistently produce the same findings as first-reviewers (no new slice), the fresh-context value isn't landing — revisit whether reviewers need different prompts or different scope. Watch for retry cycles where the re-reviewer's findings are an exact subset of the original reviewer's — when that pattern is observable in loop output, something's wrong with fresh-context value.

### D4: Reviewers follow three rules: file:line evidence, binary verdict, err to FAIL

**Firmness: FIRM**

Every reviewer subagent (REVIEW-PLAN, REVIEW-CODE) has these three rules embedded verbatim in its prompt:

1. **Evidence or silence.** If you can't cite a file path + line number for a claim, do not make the claim. "The code looks correct" is not valid. "Tests appear to cover this" is not valid.
2. **Binary verdict.** Output ends with `VERDICT: PASS` or `VERDICT: FAIL`. Nothing else. No "approved with comments."
3. **Err to FAIL.** When in doubt, FAIL. A missed issue costs more than a false alarm.

**Rationale:** Alexandre Castro documented rationalization as the #1 reviewer failure mode. The fix is prompt discipline with zero wiggle room. Binary verdicts force a decision; evidence requirements prevent handwaving; err-to-FAIL breaks the tie in the safe direction. Metaswarm's adversarial-review-rubric is built on these exact three rules and it's the load-bearing piece of their quality system.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Three rules verbatim (chosen) | Zero-wiggle discipline; portable across reviewers | Reviewers may feel constrained on nuanced cases |
| Softer guidance ("try to cite evidence") | More flexible | Exactly the flexibility that produces rationalization. **external:** Alexandre Castro documented rationalization as the #1 reviewer failure mode; soft guidance provides the wiggle room that lets agents rationalize non-issues away |
| Four-tier verdict (PASS/CONCERNS/MINOR/FAIL) | More granular | Invites "CONCERNS-that-should-be-FAIL" — the rubber-stamp vector. **reasoned:** intermediate tiers give reviewers a safe landing short of FAIL; they become the path for rationalizing real issues as "just CONCERNS" |
| Rubric file separate from skill prompt | Reusable | Phase 3 optimization; not needed now (ADR-007 target is one loop). **reasoned:** a separate rubric file is a future optimization; coupling the discipline to the prompt it governs is simpler at current scale |

**What would invalidate this:** If the three rules produce a high rate of false-FAILs (reviewer FAILs for surface issues that aren't actually problems), soften "err to FAIL" slightly — but do not remove it. Watch for a recurring pattern of loop retries triggered by FAIL verdicts that the human then immediately overrides as non-issues — that's the false-FAIL signal. Conversely, if PASS verdicts stop surfacing any findings at all, reviewers are too lax.

### D5: 3-retry cap per gate via `bd label`; fourth failure escalates to human — **applies when the primitive-loop recipe is invoked**

**Firmness: FLEXIBLE** *(demoted from FIRM 2026-05-08 per ADR-012 D3 — the retry cap is the termination gate for the D1 recipe, which is itself FLEXIBLE under thesis-v2.1; the cap travels with the recipe. Extended 2026-04-26 with stall detection per GSD revision-loop evidence.)*

Each state transition has its own retry cap of 3. Retries are tracked via `bd label add <bead-id> retry:<N>`. On the 4th failure at the same gate, the orchestrator adds `waiting:human` and exits the loop for that bead. `bd ready` subsequently skips it.

**Stall detection (in addition to the cap).** Between iterations, the orchestrator tracks the count of non-fold-in findings (Defer + Raise buckets per D7) returned by the review gate. If the count does not strictly decrease from iteration N-1 to iteration N, escalate to `waiting:human` immediately, even if the 3-retry cap has not been hit. A producer that's stuck on the same issues across iterations cannot be unstuck by more iterations of the same loop — escalating early is cheaper than burning the full cap.

**Term hygiene:** "iteration" in D5 refers to a Phase B outer loop pass (PLAN → REVIEW-PLAN → IMPLEMENT → REVIEW-CODE). `/review-v2`'s internal convergence cycles (D7) are **rounds** — distinct concept, tracked by that skill, not by this retry cap.

**Rationale:** Subscription-token ceiling. A loop stuck on a genuinely hard case will burn through your month. Metaswarm proved 3 is a useful cap. Using `bd label` keeps state visible without adding infrastructure — labels are queryable, diffable, and survive across loop runs.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| 3-retry cap via bd label (chosen) | Cheap; visible; survives restarts | Per-gate counter means a pathological bead could fail 3 at each gate = 12 total retries |
| Single retry cap across whole bead | Tighter total budget | Obscures which gate is the problem. **reasoned:** a single cap across all gates hides which specific gate is stuck; per-gate counters let the escalation message identify the failing gate |
| Exponential backoff on retries | Delays runaway cost | Doesn't prevent it; same eventual escalation. **reasoned:** backoff adds latency to the runaway but doesn't change the terminal outcome; the same escalation happens, just slower and with more wall-clock cost |
| No cap (human interrupts) | "Maximally autonomous" | Token runaway; no safe overnight use. **external:** metaswarm proved 3 retries is a useful cap via operational data; uncapped loops burned through token budgets on stuck cases |
| No stall detection — rely solely on retry cap | Simpler logic | Burns iterations on stuck producers; GSD's `references/revision-loop.md:30-40` operational evidence shows count-not-decreasing is a more reliable terminator than a fixed cap. **direct:** GSD `references/revision-loop.md:30-40` — operational evidence that count-not-decreasing is a stronger termination signal than exhausting a fixed cap |

**What would invalidate this:** If beads consistently hit `waiting:human` at 3 retries on problems humans solve in seconds, the cap is too tight. If runaway cost still happens within 3 retries × 4 gates, tighten further. Watch for `bd list --status=waiting:human` accumulating beads where the human resolution note describes an operator-trivial fix (typo, wrong path, missing env var) — when that pattern surfaces repeatedly, the cap is too low or failure signal is too sensitive.

### D6: Stateless re-prompt — each iteration reads bead state from disk, no context carryover

**Firmness: FIRM**

The orchestrator is a shell process that runs one bead through the state machine and exits. Each subagent invocation gets a fresh context containing only: the bead ID, the state it's running, and any orchestrator-provided instructions. The subagent reads its own needed context via `bd show`, `cat`, `git log`. No parent transcripts, no session carryover.

**Rationale:** Ralph's core insight: "progress lives in files and git, not in context." Fresh context per iteration is what makes long loops viable. HumanLayer's critique of Anthropic's Stop-hook ralph-wiggum plugin: reusing one session's context degrades performance — the whole point of Ralph is "carve off small bits of work into independent context windows." Our loop honors that.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Stateless re-prompt (chosen) | Fresh context per iteration; scales to long loops | Subagents must re-read state — small cost each invocation |
| Long-running orchestrator session | Lower per-iteration overhead | Context pollution; performance degrades over time. **external:** Ralph's core insight ("progress lives in files and git, not in context") — reusing one session's context degrades performance; HumanLayer critique of Anthropic's Stop-hook plugin documents this empirically |
| Partial state carryover ("summary") | Middle ground | Summaries lose signal; agents anchor on them. **reasoned:** summaries are lossy compressions of state; agents anchor on the framing in the summary and miss what the summary omitted, combining anchoring bias with signal loss |

**What would invalidate this:** If read-state-from-disk proves too slow at scale (e.g., `bd show` takes >1s and we run 100+ iterations), cache within a single orchestrator run. If carryover proves necessary despite rationale, that's a sign the primitive loop has grown too complex — split it. Watch for orchestrator runs where `bd show` latency becomes noticeable (e.g. measurable seconds-per-call at normal iteration counts) — when that surfaces, cache within the orchestrator run.

### D7: One `/review` skill with `--mode=design|plan|implementation`; orchestrator triages and runs an internal convergence loop — **describes the v2 `/review-v2` skill specifically**

**Firmness: FIRM** *(scope narrowed 2026-05-08 per ADR-012 D5 — describes the v2 `/review-v2` skill, which is invoked by explicit slash command (`disable-model-invocation: true`). Thesis-v2.1's adversarial-review primitive (ADR-012 D3) is a separate, lighter-weight composition that carries forward the rigor rules (D4) and adversarial-stance discipline (D8) but not the convergence-loop machinery, triage buckets, or `--mode` parameterization. Added 2026-04-25; extended with triage + severity rules + N semantic 2026-04-25; mode-specific N defaults added 2026-04-26 per GSD deep-read evidence; redesigned to internal convergence loop 2026-04-28 per dogfood evidence.)*

There is a single `/review` skill, parameterized by `--mode`:

- `--mode=design` — reviews an epic's design narrative (`--design`) + paired ADR. Pre-loop scope (replaces the prior `/review-design` skill).
- `--mode=plan` — reviews a bead's iteration plan in `--notes`. Loop's REVIEW-PLAN state.
- `--mode=implementation` — reviews a bead's code changes (diff + bead state) for **architectural alignment** — scope match, ADR conformance, acceptance coverage. Code-level concerns (bugs, naming, edge cases) are NOT in scope here; those are caught by the code-reviewer subagent inside `/implement-v2` per TDD cycle. Loop's REVIEW-CODE state.

Across all modes:
- **Three rigor rules apply** (D4): file:line evidence, binary verdict, err to FAIL.
- **Reviewers are silent on severity.** They cite findings and declare PASS/FAIL. They do NOT propose fixes, do NOT label findings Critical/Important/Minor, do NOT rationalize violations as exceptions. Anchorless severity labels degrade into rubber-stamping.
- **Fresh Task() per round** (D3) regardless of mode.

**N is round-floor, mode-agnostic.** `--N` sets the **floor** — minimum review rounds before the orchestrator may exit on PASS. Default `--N=1`. Hardcoded **ceiling = 3 rounds**. Per round, the orchestrator dispatches **one** reviewer subagent (fresh Task), triages findings, applies fold-ins, then judges whether another round is warranted by reading the post-fold-in artifact. Rounds run sequentially, not in parallel. `--N` may be set up to ceiling; values above are clamped.

This replaces the prior parallel-N model (mode-specific defaults: 1 impl/plan, 2 design). Two dogfood sessions on 2026-04-28 showed parallel-N's value-add — disagreement-surfacing — was paid for in tokens but not actually surfaced: when the two design reviewers disagreed (R1 PASS / R2 FAIL), the orchestrator collapsed to "any FAIL = FAIL" and moved on. The internal convergence loop captures the value (rigor + multi-pass when it matters) without the cost (no parallel duplication when round 1 already converges).

**Triage buckets (4):**

1. **Fold in** — small / unambiguous / clearly within scope → orchestrator applies before exit. Pending fold-ins are always applied before any verdict is emitted, regardless of round count or exit reason.
2. **Defer** — judgment call, user preference, non-FIRM-ADR — orchestrator notes the finding for the **final report only**; no mid-loop user input. Surfaced alongside the verdict in the final summary.
3. **Raise** — finding contradicts a FIRM ADR → presented to the human as a Decision Challenge (signals *alignment needed*, not just a fix). Raises are the only bucket that requires user input.
4. **Discard** — clearly wrong / overengineered → orchestrator silently drops with a one-line rationale logged.

The orchestrator **rewrites the artifact coherently** after fold-ins — the reviewed artifact (epic `--design`, `## Iteration plan` section of `--notes`, etc.) is updated in place; no `## Review findings (round N)` residue is left in the primary artifact. Audit residue lands in `--notes` under `## Review findings (round N)`.

**Exit verdicts (ternary):**

- `VERDICT: PASS` — artifact converged; no Raises queued; reviewer PASS or remaining issues are Defers only.
- `VERDICT: FAIL` — ceiling hit and reviewer still FAILing on substantive findings, with no Raises queued.
- `VERDICT: NEEDS_DECISION` — Raises queued requiring user input. Phase B's outer loop interprets this as a `waiting:human` transition; manual Phase A use surfaces the Raises inline before exit.

VERDICT reflects post-fold-in, post-triage state of the artifact. The final line of skill output is exactly one of `VERDICT: PASS` / `VERDICT: FAIL` / `VERDICT: NEEDS_DECISION` for orchestrator grep.

**Term hygiene:** within `/review-v2`, an internal cycle is a **round** (1..ceiling=3). The word "iteration" is reserved for D5's outer Phase B loop pass; the two are distinct.

What differs across modes: the artifact path read, the contracts checked against, and the mode-specific prompt section. The rigor primitive is identical.

**Rationale:** The three reviews share the same primitive — read artifact, check against contracts, output verdict with evidence. Splitting them would triplicate the rigor rules and create three drift surfaces. One skill, three modes keeps the discipline DRY. Report-don't-decide on severity extends Alexandre Castro's rationalization-prevention into structural roles: a reviewer that proposes fixes or labels severity becomes invested in its own framing one step away from rationalizing violations as not-violations. Severity grading requires full context (bead, ADRs, plan, diff) which only the orchestrator holds — pushing severity to the orchestrator preserves the categorization without anchoring the reviewers.

The 2026-04-28 redesign moves /review-v2 from one-shot assessment to convergence loop because dogfooding showed assessment alone leaves the artifact unfinished — both sessions ended `VERDICT: FAIL` with prose caveats noting that the post-fold-in artifact would have PASSed. The orchestrator already has the context to apply mechanical fold-ins and judge whether re-review is warranted. Surfacing only Raises (which actually need user input) and Defers (in the final report) avoids interrupting the user with judgment calls that resolve to informational anyway. Single-reviewer-per-round with ceiling=3 is cheaper in tokens than parallel-N=2 in the worst case (3 sequential vs 2 parallel × however many outer iterations), and it converges instead of just judging.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Internal convergence loop, single reviewer per round, floor=`--N` (default 1), ceiling=3 hardcoded, ternary verdict (chosen) | Converges artifact instead of just judging; orchestrator judges round-continuation per round; ternary verdict cleanly separates "needs human" from "broken"; cheaper than prior parallel-N=2 in worst case | Adds loop logic inside the skill; "round" vs "iteration" term hygiene needed to avoid collision with D5 |
| Parallel-N (mode-specific defaults: 1 impl/plan, 2 design) — prior decision, superseded 2026-04-28 | Disagreement-surfacing in design mode | Paid token cost for disagreement-surfacing that wasn't actually surfaced when reviewers diverged in dogfood; one-shot assessment left orchestrator unable to converge artifact without re-invocation. **direct:** two dogfood sessions on 2026-04-28 showed parallel-N's value-add was not surfaced when two design reviewers disagreed (R1 PASS / R2 FAIL); the orchestrator collapsed to "any FAIL = FAIL" without resolving the divergence |
| Three separate skills (`/review-design`, `/review-plan`, `/review-code`) | Each skill optimized for its artifact | Triplicate rigor rules; three drift surfaces. **reasoned:** the rigor primitive is identical across modes; splitting into three skills triples the maintenance surface for the same discipline |
| Reviewers grade severity (Critical/Important/Minor) | Familiar; matches old `/review` | Direct anchoring path to rationalization (Castro); severity calls without full context are noisy. **external:** Alexandre Castro's rationalization findings — severity grading without full context produces noisy ratings that anchor reviewers to a framing they invented |
| Reviewer also proposes fixes | "Helpful" output | Direct path to rationalization — reviewer becomes invested in the violation being benign. **reasoned:** a reviewer who proposes a fix is now invested in the fix being accepted; this creates incentive to rationalize the original violation as not-a-violation to protect the proposed fix |
| 3-bucket triage (fold/defer/raise) | Simpler | Discard is a legitimate operational outcome (reviewer got it wrong); collapsing it leaks noise into the final report. **reasoned:** without a Discard bucket, reviewers' wrong findings must go into Defer (clouding the report) or be silently dropped (no audit trail); Discard with a one-line rationale is the correct outcome |
| Surface Defers to user mid-loop (prior behavior) | User sees borderline calls early | Interrupts loop for findings that don't need user alignment — Raises are the only bucket that genuinely needs input. **reasoned:** Defers are judgment calls that the orchestrator can park for the final report; interrupting the user mid-loop for informational findings defeats the multi-session-parallelism goal |
| Floor>1 default | More rigor by construction | Most artifacts converge in round 1; forcing extra rounds on every PASS is token waste — adversarial-stance prompt (D8) carries the rigor at single-reviewer cadence. **reasoned:** D8's adversarial-stance prompt carries rigor in a single round; adding mandatory extra rounds on already-passing artifacts is cost without benefit |
| User-tunable ceiling | Maximum flexibility | Token-runaway risk; ceiling is a safety cap, not a knob — fixed at 3. **reasoned:** a safety cap must be inviolable to function as a safety cap; a user-tunable ceiling converts a hard limit into a preference, removing the protection |
| `/review --mode=implementation` covers code-level concerns too | One review surface | Duplicates code-reviewer subagent inside `/implement-v2`; conflates architectural with line-level. **reasoned:** architectural review and code-level review check different things (ADR conformance vs. bug correctness); conflating them in one review surface misapplies the wrong expertise to each concern |

**What would invalidate this:** (a) If most reviews terminate at the floor (round 1) with PASS and never benefit from rounds 2-3, the multi-round design isn't earning its keep — drop to single-round and trust adversarial stance fully. Watch for loop run output where round 2 or 3 is never invoked — when that's consistently the pattern in real use, simplify back to single-round. (b) If `NEEDS_DECISION` is the modal verdict, upstream design-v2/brainstorm-v2 isn't surfacing FIRM-ADR conflicts early enough — fix upstream, not here. (c) If orchestrator triage consistently mis-categorizes (esp. Fold-in things that should have been Raise), tighten triage rules. (d) If mode-specific needs diverge enough that the shared skill becomes a switch statement with little shared body, split.

### D8: Reviewer prompts include an adversarial-stance block + named go-soft failure modes

**Firmness: FIRM** *(added 2026-04-26)*

Every reviewer subagent (REVIEW-PLAN, REVIEW-CODE, design-mode review) carries an adversarial-stance block in its prompt, verbatim, alongside the rigor rules from D4. The block has two parts:

1. **Stance.** A single-paragraph framing instruction: the reviewer's starting hypothesis is that the artifact does NOT meet its goal — the burden is on codebase evidence to falsify that hypothesis, not on the reviewer to find a problem. (Wording is owned by the skill that dispatches reviewers — `review-v2/SKILL.md` — but the structural element is FIRM.)

2. **Named failure modes.** A short enumerated list of "ways reviewers go soft" that the reviewer must not exhibit. Examples: trusting summary bullets without reading the code; assuming a passing test means the goal was met; rationalizing a finding as "probably fine"; treating a missing claim as "must have been intended." The list is named explicitly so the reviewer can self-monitor rather than relying on the implicit anti-rationalization rules from D4.

**Rationale:** This pattern is GSD's `agents/gsd-verifier.md:25-39` — they get serious adversarial behavior from a single reviewer with a strong stance prompt. Naming the failure modes inline turns implicit anti-rationalization (which D4 already targets) into explicit self-monitoring. This is what makes the D7 single-reviewer-per-round design viable: with adversarial stance carrying rigor at single-reviewer cadence, multi-pass coverage comes from sequential rounds + fresh Task() per round, not from parallel reviewers. Without D8, single-reviewer rounds would meaningfully weaken review quality; with it, the reduction is structural-cost only.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Adversarial stance + named failure modes (chosen) | Cheap prompt-only insurance; turns implicit rules into explicit self-monitoring; observed effective in GSD over 6 months | Adds prompt length; reviewer-prompt becomes longer than D4 alone |
| Rely solely on D4 rigor rules | Smaller prompts | Insufficient at single-reviewer cadence — D4 alone leaves anti-rationalization implicit, observed go-soft pattern in our prior /review work. **direct:** go-soft pattern observed in prior `/review` work before D8 was added; D4 alone was not sufficient to prevent it |
| Inline only the stance, no named failure modes | Shorter | Failure modes are the operational teeth; without them, "adversarial stance" becomes a vibe. **external:** GSD `agents/gsd-verifier.md:25-39` — named failure modes inline is the mechanism that produces adversarial behavior from a single reviewer; the stance framing alone is insufficient |
| Add as a separate `/adversarial-review` skill | Composable | Conflicts with D7's "one /review skill, three modes" decision; fragments the discipline surface. **direct:** D7 of this ADR establishes one `/review` skill with three modes; a separate skill would fragment the rigor discipline across two surfaces |

**What would invalidate this:** If reviewers with adversarial-stance + named failure modes consistently produce go-soft verdicts (rationalizing FIRM-ADR violations, missing scope-creep), the structural mitigation isn't landing — raise the D7 floor (force ≥2 rounds) or strengthen the stance language. Watch for loop runs where round 2 (after a PASS at round 1 floor) surfaces findings the round-1 reviewer missed — when that surfaces as a recurring observation rather than the occasional exception, the adversarial stance isn't carrying the expected rigor.

## Related

- Implementation guidance lives in the phase design doc, not this ADR. Phase 1 design doc includes the full state diagram, retry-cap bash template, and timeout fallback chain.
- Paired entry-point resolver: ADR-006 D8.
- D7 collapses the prior `/review-design` skill into mode=design and the loop's separate REVIEW-PLAN / REVIEW-CODE skill calls into mode=plan / mode=implementation. The state machine names (REVIEW-PLAN, REVIEW-CODE) are unchanged — they describe loop states, not skill identities.
