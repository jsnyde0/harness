# ADR-008: ADR Invalidation Predicates + WHY-Aware PLAN Phase

**Status:** Accepted (revised 2026-05-13)
**Date:** 2026-04-24 (revised 2026-04-30)
**Design:** [Phase 2 Design](../../history/2026-04-24-workflow-loop-phase2-design.md); parent picture [Workflow Loop Design](../../history/2026-04-24-workflow-loop-design.md)
**Research basis:** [`2026-04-24-workflow-loop-brainstorm-research.md`](../../history/2026-04-24-workflow-loop-brainstorm-research.md) — Alexandre Castro fitness-function retrospective, Agentless hierarchical scope-resolution, SWE-bench PASS_TO_PASS anti-tangent data, Yegge's `discovered-from` dep.
**Related:**
- [ADR-005](ADR-005-beadify-redesign.md) D4/D5 — ADR template updates for mechanical checks and Alternatives completeness
- [ADR-007](ADR-007-primitive-loop.md) — the loop this layer plugs into
- [ADR-009](ADR-009-loop-composability.md) — epic composability (consumes the scope-resolution + discovered-from rules)

## Context

ADR-007's primitive loop has rigorous reviewers and a hard retry cap but "done" is still just `--acceptance` passing. That means:

1. The loop has no mechanical check that the code respects existing ADRs — the single cheapest stop-condition signal available.
2. PLAN is blind to architectural WHY. Agents re-reason approaches humans already rejected (the single most-stated user requirement).
3. There's no rule for scope resolution — how many ADRs/files to consider.
4. There's no rule for mid-loop discovery — bugs noticed in passing can either get fixed (scope creep, SWE-bench PASS_TO_PASS anti-pattern) or lost.

This ADR fills those gaps with four decisions that layer on top of ADR-007 without modifying it.

## Decisions

### D1: ADRs may carry an optional inline `Invalidation check` block; it is shell, co-located, and loop-runnable

**Firmness: FIRM**

Each ADR decision may optionally carry a block titled `**Invalidation check (mechanical, optional):**` containing a single shell invocation that exits 0 when the ADR holds and non-zero when it may be violated. The block lives **inside the ADR**, below the prose `What would invalidate this:` field.

Rules:
- Optional. Decisions that genuinely resist mechanical checking carry no block.
- Fast (seconds, not minutes).
- Self-contained. No references to sidecar files, other ADRs, or external indices.
- Exit code is the signal. Stdout/stderr may inform humans but the orchestrator reads only the exit code.

**Rationale:** Alexandre Castro's retrospective (captured in research doc) is explicit: separate fitness-function files **die** from sync drift. ADR evolves, check doesn't; or vice versa. The fix is co-location — the check lives with the decision and evolves with it. Shell-exit-based matches the trust model from ADR-007 D2 (orchestrator runs validators, trusts exit codes). Optional because mandatory mechanical checks degrade to fake checks; forcing it produces noise.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Inline optional shell check (chosen) | Co-evolves with decision; exit-code trust; optional for non-checkable cases | No machine-typed format; authors can write fake checks |
| Separate `.fitness/*.sh` sidecar files | Clean separation | Alexandre abandoned this; sync drift. **external:** Alexandre Castro fitness-function retrospective (`history/2026-04-24-workflow-loop-brainstorm-research.md`): separate sidecar files die from sync drift in practice; the ADR evolves, the check doesn't |
| Mandatory check per decision | Discipline | Forces fake checks for decisions that can't be mechanically verified. **reasoned:** mandatory checks for uncheckable decisions produce syntactically valid but semantically meaningless checks; mandatory-fake is worse than optional-present |
| Rich DSL (YAML with assertions) | Machine-typed | Over-engineered; authors avoid it; starts as ergonomic barrier. **reasoned:** a rich DSL trades mechanical guarantees for adoption; if authors avoid it, the checks aren't written, and the mechanical guarantee is theoretical |

**What would invalidate this:** If meaningful inline checks remain rare across the corpus and the pattern isn't earning its keep, either stop the guidance or invest in better authoring tools. If every decision has a check including obvious fakes, the optionality isn't respected — strengthen authoring rules.

### D2: Any plan or contract reads in-scope ADRs including Alternatives tables; Rule P forbids rejected-alternative approaches

**Firmness: FIRM** *(scope broadened 2026-05-08 per ADR-012 D3 — applies to **any** agent-authored plan, contract, or decomposition tree, not just the v2 PLAN subagent. Rule P is a substrate-level discipline, not a v2-pipeline-only check.)*

Whenever an agent authors a plan, contract, or decomposition tree (whether via the v2 PLAN subagent, the thesis-v2.1 scope-check + harness compose primitives, or any other recipe), the authoring prompt includes, for each in-scope ADR:
1. Context section
2. Decision text
3. Alternatives Considered table *verbatim*
4. Rationale

And this rule:

> **Rule P.** Your plan must not propose an approach listed in any in-scope ADR's "Alternatives Considered" as a rejected option. If your planning leads there, either (a) show the specific reason the original rejection is no longer valid, and flag the ADR for human update, or (b) pick a different approach.

The authored artifact (bead `--notes`, contract field, or decomposition output) must include an `## ADRs consulted (iteration N)` section noting each in-scope ADR and whether the plan conflicts with its alternatives. The downstream adversarial-review primitive (ADR-012 D3) — or, when the v2 recipe is invoked, REVIEW-PLAN (ADR-007 D1) — checks this section exists and FAILs the plan if any in-scope ADR is unlisted.

**Rationale:** This is the core WHY-preservation mechanism. The single user-stated requirement that drove this whole brainstorm: "without WHY, agents re-reason problems and pick alternatives we already evaluated and rejected." Loading the full Alternatives table into PLAN's context makes that structurally harder — the agent literally sees the rejection — and Rule P makes it a violation to do so silently. Pairs with ADR-005 D5 (review-design flags empty Alternatives tables upstream).

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Full Alternatives in PLAN + Rule P (chosen) | Structural WHY preservation; hard to bypass | More tokens in PLAN prompt |
| Only Decision + Rationale (no Alternatives) | Cheaper | Exactly what doesn't work — the rationale says "we picked X"; the agent doesn't know what was rejected. **reasoned:** rationale explains why the chosen path was taken; without alternatives, the agent has no way to know that the path it's about to take was already evaluated and rejected |
| Full ADR in PLAN prompt | Maximally informed | Token bloat; most sections are review-relevant not plan-relevant. **external:** Agentless hierarchical scope-resolution — SWE-bench Verified data shows over-scoping measurably hurts accuracy; the same principle applies to over-populating PLAN context |
| Rule P without full Alternatives | Impossible to follow | Agent can't know what's rejected. **reasoned:** a rule that says "don't pick rejected approaches" with no table of rejected approaches is structurally unenforceable; the agent can't comply with a rule whose content is withheld |

**What would invalidate this:** If PLAN repeatedly violates Rule P despite the table being in context, the rule's framing isn't landing — strengthen wording or add mid-plan gates. If PLAN's ADRs-consulted section becomes rubber-stamped ("all ADRs consulted, no conflicts") and REVIEW-PLAN waves it through, the check is structural rather than substantive — strengthen REVIEW-PLAN's reading of the section.

### D3: Top-3 ADRs + Top-5 files scope cap for plan-shaped authoring; full ADR index for review

**Firmness: FIRM** *(scope clarified 2026-05-08 per ADR-012 D3 — applies to any plan-shaped authoring, including the thesis-v2.1 scope-check primitive. The asymmetric plan-narrow / review-wide pattern is the canonical scope cap for the scope-check primitive.)*

Plan-shaped scope (PLAN subagent in the v2 recipe; scope-check primitive output in thesis-v2.1) is resolved by an LLM hierarchical ranker (not embeddings — per Agentless data, embedding rerank *hurts* accuracy). Input: bead text + candidate ADR titles + candidate file paths. Output: at most 3 ADR paths and 5 file paths. Orchestrator truncates if the ranker returns more.

Review-shaped invocations (REVIEW-PLAN/REVIEW-CODE in the v2 recipe; adversarial-review primitive in thesis-v2.1) receive the **full ADR index** (list of all ADR titles + paths). Reviewers may read any ADR they want. Asymmetric by design: plan narrow, review wide.

**Rationale:** SWE-bench Verified data: top-3 files is empirically correct; >4 is rare; over-scoping measurably hurts. Agentless (SOTA on SWE-bench Verified, 90-92% Hit@3) uses pure LLM hierarchical localization and outperforms embedding-based approaches by a wide margin. Asymmetric width (plan narrow, review wide) mirrors how humans work: you plan focused, you review holistically.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| LLM rank + top-3/5 cap, review-wide (chosen) | Matches SOTA data; PLAN stays focused; REVIEW catches missed scope | Adds a scope-resolver subagent call per iteration |
| Embedding-based scope retrieval | Cheap, fast | Hurts accuracy per Agentless data. **external:** Agentless (SOTA on SWE-bench Verified, 90-92% Hit@3) — pure LLM hierarchical localization outperforms embedding-based approaches; embedding rerank hurts accuracy on hierarchical scope-resolution |
| Fixed scope rules ("all ADRs always") | Simple | Token bloat; degrades PLAN signal. **external:** SWE-bench Verified data — top-3 files is empirically correct; over-scoping measurably hurts; the same principle applies to ADR scope |
| Human picks scope upfront | Most accurate | Eliminates automation benefit. **reasoned:** requiring human scope selection at each iteration removes the latency advantage of the automated loop; it converts a background-capable loop into an interactive one |
| Top-1 ADR | Extra-focused | Under-scopes; misses cross-cutting ADRs. **reasoned:** many decisions are cross-cutting across 2-3 ADRs; a single-ADR cap structurally misses any change that spans multiple decision spaces |

**What would invalidate this:** If the scope ranker consistently misses relevant ADRs that REVIEW-CODE catches, widen the cap. If REVIEW-CODE never adds ADRs beyond what PLAN saw, shrink REVIEW scope or drop the asymmetry.

### D4: Mid-loop discovery uses `discovered-from` dep; newly-filed beads are not worked in the same iteration

**Firmness: FIRM**

During any phase, a subagent that notices work outside the current bead's scope files a follow-up via:

```bash
bd create --title=<what> --type=<bug|task> --parent=<epic-if-any> --description=<where (file:line) + what>
bd dep add <new-bead-id> discovered-from <current-bead-id>
```

Two hard rules:
1. **The current iteration does not modify the discovered surface.** The subagent files the bead and moves on. REVIEW-CODE enforces this via `git diff --name-only` vs planned scope — unexpected files are a FAIL.
2. **The discovered-from dep is non-blocking.** The new bead enters `bd ready` naturally and gets picked up on a future loop iteration.

**Rationale:** SWE-bench PASS_TO_PASS data: agents that "also fix" adjacent bugs score worse because they break things they weren't supposed to touch. Yegge's `discovered-from` dep type exists exactly for this pattern. Captures the discovery (zero work lost) without violating scope (zero tangent cost). This is also the specific user-named workflow friction — being able to file a bug mid-loop without re-running `/brainstorm`.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| `discovered-from` + no-same-iteration rule (chosen) | Captures discovery; preserves scope; matches beads semantics | Requires subagent discipline + diff-check enforcement |
| Fix discovered bug immediately | Fewer iterations | PASS_TO_PASS anti-pattern; scope creep. **external:** SWE-bench PASS_TO_PASS data — agents that "also fix" adjacent bugs score worse because they break things they weren't supposed to touch |
| Don't file anything; rely on human to notice | Simplest subagent | Discoveries lost. **reasoned:** mid-loop context is transient; discoveries not captured as beads vanish when the session ends; human noticing is unreliable across multiple parallel sessions |
| `blocks` dep instead of `discovered-from` | Existing dep type | Wrong semantics — `blocks` implies "can't proceed without" which isn't true here. **direct:** Yegge's `discovered-from` dep type was specifically introduced for this pattern; `blocks` expresses a dependency constraint, not a discovery provenance relationship |

**What would invalidate this:** If REVIEW-CODE's scope-diff check regularly catches same-iteration fixes (rule not being followed), the subagent prompts need strengthening. If `discovered-from` beads accumulate in `bd list` without ever getting picked up (discovery captured but ignored), the `bd ready` surfacing isn't working or the priority default is wrong.

### D5: Design narrative must include a mandatory `## canonical_refs` section listing all referenced ADRs and external specs

**Firmness: FIRM** *(added 2026-04-26)*

Every design narrative — primarily epic `--design` fields, also any `history/*-design.md` doc that drives a bead's work — must contain a `## canonical_refs` section listing **all** referenced ADRs and external specs by full path, grouped by topic where helpful. Two hard rules:

1. **No silent omission.** If a design genuinely has no external references, the section must still exist with a single line stating `none` (e.g. `none — this design is self-contained`). An absent section is a structural failure, not a sign of "no references."
2. **No orphan inline mentions.** Phrases like "see ADR-019" or "per the API spec" scattered through prose without a corresponding entry in `## canonical_refs` are forbidden. Every inline reference must trace back to an entry in the section.

The section's purpose is downstream-agent legibility. PLAN (D2) and review-v2's `--mode=design` consume it as the authoritative source of in-scope ADRs; orphan inline mentions are unparseable and degrade scope resolution. REVIEW-PLAN FAILs any plan whose bead `--design` is missing the section, and FAILs any plan whose `## ADRs consulted` cites an ADR not present in the upstream `## canonical_refs`.

**Rationale:** GSD's `templates/context.md:344-352` is explicit on this and earned the rule the hard way: "Inline mentions like 'see ADR-019' scattered in decisions are useless to downstream agents — they need full paths and section references in a dedicated section they can find. If no external specs exist, say so explicitly — don't silently omit." The mandatory-and-explicit pattern matches our broader doctrine of structural anti-rationalization (ADR-007 D4): silence is interpreted by agents as "no constraint applies." Forcing an explicit `none` removes that ambiguity. Pairs with D2 (Rule P): Rule P forbids re-reasoning rejected alternatives; canonical_refs ensures the agent sees *which* ADRs to consult in the first place.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Mandatory `## canonical_refs` with explicit `none` (chosen) | Eliminates silent omission; matches GSD operational pattern; co-located with the narrative it scopes | Adds upfront discipline cost on `/brainstorm-v2` and design-doc authors |
| Optional canonical_refs section, "include if you have refs" | Lower author burden | Silent omission is exactly the failure mode that prompted the rule; "no refs" is information that needs to be expressed, not absence-of-information. **reasoned:** agents interpret silence as "no constraint applies"; an absent refs section is indistinguishable from "I forgot" vs "there are none" |
| Sidecar `*.refs.json` per design | Machine-typed | Sync drift: design evolves, sidecar doesn't (Alexandre Castro's lesson, restated in D1's rejection of sidecar fitness functions). **external:** Alexandre Castro's lesson on sidecar files (D1 source) — the same sync drift that kills sidecar fitness functions kills sidecar refs |
| Inline mentions only, no dedicated section | Less ceremony | Orphan refs unparseable downstream; forces every PLAN run to grep narrative prose for "ADR-NNN" patterns. **external:** GSD `templates/context.md:344-352` explicitly names this as a failure mode: "inline mentions like 'see ADR-019' scattered in decisions are useless to downstream agents" |
| Free-form `## References` section without the `none` rule | Familiar pattern | Authors omit the section when they think there are no refs, which is itself a claim that should be explicit. **reasoned:** the "no references" case is information, not the absence of information; forcing an explicit `none` removes the ambiguity that agents exploit when no refs section exists |

**What would invalidate this:** If `## canonical_refs` sections become rubber-stamped (authors list `none` reflexively even when refs exist) and PLAN starts missing in-scope ADRs as a result, the rule is being followed in letter but not in spirit — strengthen `/brainstorm-v2`'s emission discipline (file as a follow-up bead — out of scope for this ADR). If REVIEW-PLAN FAILs start being dominated by canonical_refs/ADRs-consulted structural mismatches rather than substantive plan issues, the rule is too rigid — soften the "every inline reference must trace back" check.

### D6: After writing an ADR or design doc, verify discoverability (including INDEX.md presence); do not auto-edit instruction files

**Firmness: FIRM** *(extended 2026-05-08 per ADR-012 D2 — discoverability check now also verifies that `docs/decisions/INDEX.md` exists and is referenced from CLAUDE.md, since INDEX.md is the routing surface for the broadened ADR scope. Added 2026-04-27, CE fold-in #1.)*

**Source:** `ce-compound/SKILL.md` Phase 2; `docs/solutions/skill-design/discoverability-check-for-documented-solutions-2026-03-30.md`; Wave 7 research capture (workflow-loop brainstorm research, 2026-04-24, in the methodology history archive) §7.5 item 1.

After any ADR-write primitive invocation (whether via `brainstorm-v2`/`design-v2` in the v2 recipe or via the thesis-v2.1 ADR-write primitive directly), the agent must perform a mechanical discoverability check: grep the global agent instructions file and any project-local `CLAUDE.md` or `AGENTS.md` for path mentions of `docs/decisions/`, `docs/decisions/INDEX.md`, and `history/*-design.md`. If all three are mentioned, pass silently. If any is absent, output a suggested one-liner edit to add the pointer — but do NOT modify the instruction files autonomously. The suggestion is surfaced to the user and requires explicit confirmation before application.

`review-v2 --mode=design` includes discoverability as the last gate in its DoD checklist: the design is not "blessed" until discoverability has been verified (or a suggestion has been surfaced to the user).

**Rationale:** Agents in fresh sessions only consult ADRs if instruction files point at them. The mirror at the meta-level of GSD's `canonical_refs` rule (ADR-008 D5): D5 mandates citing ADRs in designs; D6 ensures the instruction file that routes agents *to* the ADR corpus is itself kept current. Asymmetric upside: one-line check vs decisions rotting unread. The human gate on instruction-file edits is deliberate — discoverability decisions are human-scope, not agent-scope.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Propose edit, human gate (chosen) | Preserves human authority over instruction files; check is cheap | Agent can't auto-fix; user must act | `direct:` brainstorm session 2026-04-27; CE design gate enforces same human-authority pattern |
| Auto-apply the one-liner edit | Zero friction | Violates the principle that instruction files are human-scope; silent modifications to global config files are dangerous | `reasoned:` instruction files configure all future sessions — side-effects too broad for autonomous action |
| Skip discoverability entirely | Simpler | ADRs become invisible to fresh-session agents over time | `direct:` Wave 7 §7.5 item 1 explicitly names this as the gap |
| Standalone `/check-discoverability` skill | Composable | Extra skill surface; awkward invocation; `brainstorm-v2` already owns the ADR-creation moment | `reasoned:` the skill that emits the artifact also checks discoverability (wave 7 §7.7 resolution) |

**Falsifiable check:** Run `grep -r "docs/decisions/"` and `grep -r "history.*-design"` on the global agent instructions file — both must return matches, or the discoverability gate would have surfaced a suggestion. If an ADR is written without this check running, that's a protocol violation.

**What would invalidate this:** If the instruction-file check becomes a false alarm repeatedly (paths are present but point at stale conventions), soften to a content-aware check rather than a path-presence check. If users consistently ignore the suggestions, the gating point is wrong — attach to a different moment.

---

### D7: Before creating a new ADR, run 5-dim overlap detection; high-overlap routes to update-in-place

**Firmness: FIRM** *(scope broadened 2026-05-08 per ADR-012 D2 — applies to ADRs across all domains under the broadened scope (Anchored Decision Records), not architecture only. The 5-dim rubric is domain-agnostic. Added 2026-04-27, CE fold-in #2.)*

**Source:** `ce-compound/SKILL.md` Phase 2 (overlap detection rubric); Wave 7 research capture §7.5 item 3.

Before `brainstorm-v2` creates a new ADR file, it dispatches a cheap Haiku subagent to score candidate matches against existing `docs/decisions/ADR-*.md` files on 5 dimensions:
1. Problem statement — do they address the same problem?
2. Root cause — same underlying structural issue?
3. Solution approach — same proposed resolution?
4. Referenced files — same code surfaces involved?
5. Prevention/firmness rules — same behavioral constraints on future work?

Action routing:
- **High overlap (4-5/5):** update the existing ADR in place rather than creating a duplicate; surface this decision to the user before applying changes.
- **Moderate overlap (2-3/5):** create the new ADR; flag in its header for follow-up consolidation review.
- **Low/none (0-1/5):** create the new ADR normally.

**Relationship to D5 (`canonical_refs`):** D5 mandates *citing* relevant ADRs in design narratives (downstream reference discipline). D7 is the upstream sibling — it ensures the new ADR itself isn't a duplicate of one that should be cited instead of created anew. The two decisions are complementary, not redundant.

**Rationale:** As the ADR corpus grows, duplicate ADRs create contradictions that PLAN's Rule P (D2) cannot resolve — the agent sees two conflicting FIRM decisions and has no principled way to pick. Catching duplicates at creation time is asymmetrically cheaper than reconciling them post-hoc. Haiku-tier subagent keeps the cost negligible (the check is a scoring rubric, not a full review).

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| 5-dim Haiku scoring before creation (chosen) | Cheap; catches structural duplicates before they compound; routing is deterministic | Haiku may miss subtle overlaps that a human would catch | `external:` ce-compound/SKILL.md Phase 2 — same rubric operationalized |
| Skip overlap detection entirely | Simplest | ADR corpus grows with silent duplicates; FIRM-conflict explosion as corpus matures | `reasoned:` first-principles: duplicate FIRM decisions create unresolvable conflicts for PLAN's Rule P |
| Embedding-based similarity | Automated | Agentless data (ADR-008 D3) shows embeddings hurt LLM hierarchical selection; same logic applies here | `direct:` ADR-008 D3 cites Agentless SOTA: pure LLM outperforms embeddings for ranked selection |
| Post-hoc dedup via `/ce-compound-refresh` analog | Can batch clean up | Duplicates live and cause confusion until cleaned; no incentive to run the cleanup | `reasoned:` preventive is cheaper than corrective at this scale |

**Falsifiable check:**

```bash
# If a new ADR-NNN file exists, confirm no prior ADR addresses identical problem
# (manual spot-check: pick any two consecutive high-overlap ADRs; one should have been an in-place update)
ls docs/decisions/ADR-*.md | wc -l
```

**What would invalidate this:** If the Haiku subagent consistently scores moderate overlap on ADRs that are genuinely distinct (high false-positive rate), loosen the routing threshold or improve the rubric prompt. If users consistently reject "update in place" suggestions (preferring new ADRs despite high overlap), the 5-dim rubric is not matching human judgment — recalibrate.

---

### D8: Prefer signal-shaped invalidation criteria; reserve numeric thresholds for cases with real instrumentation

**Firmness: FIRM** *(added 2026-04-30)*

**Source:** 2026-04-30 v2 rigid-rules sweep — observed that several `What would invalidate this:` fields in ADR-008 D1–D5 and `history/2026-04-29-pipeline-reordering-design.md` D8 carried numeric thresholds (sample 20, ~10%, <20%, >25%, <50%) with no instrumentation collecting the data and no agent or scheduled process reading the threshold. The thresholds filled a template slot rather than informing decisions.

The prose `What would invalidate this:` field on every decision must take **signal-shaped** form — qualitative cues an agent or human applies in the moment ("watch for X surfacing in practice; if it does, tighten Y") — rather than numeric thresholds, **unless** the threshold is paired with active instrumentation (a scheduled job, a hook, a `bd` query, a harness check) that actually collects the data and an agent or human routinely reads it.

Concretely:

- **Allowed:** "If PLAN repeatedly violates Rule P despite the table being in context, strengthen wording or add mid-plan gates." (in-the-moment signal)
- **Allowed:** Mechanical runtime checks — the `**Invalidation check (mechanical, optional):**` block from D1, with exit-code semantics.
- **Allowed:** Numeric thresholds *paired with named instrumentation* (e.g., "if `bd ready --label=discovered-from` shows beads piling up, …" — the query is the instrumentation).
- **Forbidden:** "Sample 20 outputs at 6 months and check if X exceeds Y%." with no scheduler, no audit table, and no agent reading the result. The threshold could be 10% or 90% and nothing changes because nothing measures it. This is falsifiability theater.

The mechanical `**Invalidation check (mechanical, optional):**` block from D1 is unaffected — that's exit-code-based runtime enforcement, not a prose threshold.

**Rationale:** D1's `What would invalidate this:` field exists so future readers can recognise when a decision should be reconsidered. Numeric thresholds without instrumentation degrade that purpose: they look rigorous but no process triggers re-evaluation, and the numbers are unanchored — a 10% threshold and a 50% one are equally inert when no measurement system exists. Signal-shaped criteria do the actual work — they describe observable conditions that surface during real use, and the noticing itself is the trigger. This mirrors the working pattern across the v2 skills (countermand test in `skills/design-v2/SKILL.md`, sweep-clean in `skills/beadify-v2/SKILL.md`, re-derivability in `skills/brainstorm-v2/SKILL.md`): judgment frames applied at decision time, not metrics measured later.

**Alternatives considered:**

| Approach | Pros | Cons |
|---|---|---|
| Signal-shaped default; thresholds only with instrumentation (chosen) | Eliminates theater; matches the working v2 pattern; keeps numeric criteria available where they earn their keep | Loses the appearance of rigor that unbacked thresholds provided |
| Require numeric thresholds on every decision | Maximum apparent falsifiability | Forces fake numbers; D1 explicitly rejects this pattern for the mechanical-check block, and the same logic applies to prose criteria. **direct:** ADR-008 D1–D5 and `history/2026-04-29-pipeline-reordering-design.md` D8 contained numeric thresholds (sample 20, ~10%, <20%, >25%, <50%) with no instrumentation — the thresholds were identified as falsifiability theater in the 2026-04-30 sweep |
| Drop the `What would invalidate this:` field entirely | Simplest | Loses the future-reader utility; no signal that a decision should ever be reconsidered. **reasoned:** without the field, FIRM decisions have no stated revision condition; the corpus contains decisions that look immutable but are actually contingent on assumptions that may change |
| Allow free-form (status quo before this rule) | No constraint cost | Falsifiability theater proliferates — observed in ADR-008 D1–D5 and pipeline-reordering D8 before retroactive softening. **direct:** the 2026-04-30 v2 rigid-rules sweep observed that several `What would invalidate this:` fields carried numeric thresholds with no process reading them — empirical observation in this corpus |

**What would invalidate this:** If softened invalidation criteria across the corpus become so vague that future readers cannot tell when a decision should be revisited (the field reads as ornamental), the rule is too lax — add structural guidance on what makes a signal "concrete enough." If authors start citing instrumentation that doesn't actually exist (claiming a metric will be collected without anyone building the collection), the rule needs a clarification that imagined instrumentation doesn't qualify as paired instrumentation.

---

## Related

- ADR-005 D4 — mandatory guidance for authors on when to add the optional block.
- ADR-005 D5 — upstream Alternatives-completeness check (prevents empty tables that would silently defeat Rule P).
- ADR-006 D9 — general in-flow follow-up rule; this ADR's D4 is the subset specifically for agent-discovered work mid-loop.
- ADR-007 D2 — orchestrator-runs-validator trust model; ADR invalidation checks plug into the same mechanism.
