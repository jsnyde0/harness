# ADR-004: Soldier-Proof Skill Design

**Status:** Accepted
**Date:** 2026-04-14
**Design:** [Soldier-Proof Design](../2026-04-14-soldier-proof-design.md)

## Context

Skills are written by the same model that will use them, in the same context, with the same implicit knowledge. This creates a blind-spot: the author fills in gaps unconsciously. When a real isolated agent follows the skill, it either improvises around the gaps or fails silently.

The `improve-iteratively` skill (a private work-product platform repo) addresses a related problem — testing full task workflows — but is domain-coupled (platform-specific creation workflows, Chrome inspection, ADRs) and not portable. We need a general-purpose skill hardening loop.

The Reddit "soldier-proofing" pattern ("write the skill, spawn a subagent to complete the task, iterate until the subagent can do it perfectly, then repeat with a smaller model") captures the core idea but needs design discipline to avoid overfitting and misusing the smaller-model phase.

## Decisions

### D1: Skill injection over agent definitions

**Firmness: FIRM**

The test agent receives the target skill's content injected directly into its prompt, not via a pre-configured agent definition in `.claude/agents/`.

**Rationale:** Agent definitions are project-specific and require upfront setup. They also may include other skills beyond the one under test, polluting isolation. Direct injection gives: (a) true isolation — only the target skill, nothing else, (b) portability — works in any repo without setup, (c) explicit test surface — the injected content is exactly what's being evaluated.

**Alternatives considered:**

| Approach | Pros | Cons |
|----------|------|------|
| Direct injection (chosen) | Portable, fully isolated, no setup | Slightly verbose prompt construction |
| Pre-configured agent definition | Reuses existing infrastructure | Project-specific, may include other skills, requires setup per skill |
| No injection (plain subagent) | Simplest | Subagents don't inherit parent skills — agent would have nothing to follow |

**What would invalidate this:** A Claude Code mechanism emerges for dynamically composing agent definitions at runtime without filesystem setup.

### D2: Manager-derived test prompts, not user-supplied

**Firmness: FLEXIBLE**

The manager reads the skill and derives 2-3 test prompts covering different parts of the skill's intended scope. The user does not provide test prompts.

**Rationale:** User-supplied prompts tend to cluster around the user's mental model of the skill, which is often narrower than the full intended scope. Manager-derived prompts can explicitly target different branches, difficulty levels, and use cases documented in the skill. This also eliminates user prep work.

**Alternatives considered:**

| Approach | Pros | Cons |
|----------|------|------|
| Manager-derived (chosen) | Structurally diverse, no user prep, explicit scope coverage | Manager may miss nuances the user would catch |
| User-supplied | User knows edge cases | Clusters around user's mental model, may not cover full scope |
| Hybrid: manager derives, user can override | Best of both | Added complexity |

**What would invalidate this:** Managers consistently generate narrow or unrepresentative prompts in practice. If so, move to hybrid with user review of generated prompts before iteration starts.

### D3: Overfitting guard is a first-class review prompt instruction

**Firmness: FIRM**

Every proposed improvement is challenged in the review agent's prompt with an explicit generalization question: "Does this fix address a gap in the skill's full intended scope, or does it only patch this specific test case?"

**Rationale:** The core failure mode of iterative skill improvement is narrowing — the skill gets tuned to the test prompt until it works, but only for that prompt. This is not detectable by looking at improvement proposals in isolation; it requires stepping back and asking whether the proposed change restricts the skill's applicability. Making this a mandatory step in the review prompt ensures it happens every iteration.

**Alternatives considered:**

| Approach | Pros | Cons |
|----------|------|------|
| First-class review instruction (chosen) | Always happens, explicit evidence surfaced | Review agent may still miss subtle narrowing |
| User awareness only (no prompt instruction) | No overhead | Easily forgotten, relies on user to catch narrowing |
| Post-loop overfitting audit | Can look across all changes | Too late — narrowing should be caught per proposal |

**What would invalidate this:** A better signal for overfitting emerges (e.g., testing the skill against a held-out prompt after each iteration).

### D4: Smaller model as clarity probe, not success target

**Firmness: FIRM**

The smaller-model phase (optional, `--model haiku`) is a clarity probe, not a capability benchmark. The goal is to find skill clarity failures — ambiguity, unexplained jargon, missing context — not to make the smaller model succeed.

Review categorizes failures as:
- **Clarity failure** → fixable skill problem (skill is ambiguous, model had to guess)
- **Capability limit** → known limit, do not simplify the skill to compensate

**Rationale:** Smarter models paper over skill ambiguities by inferring context. Weaker models cannot — they either fail or take wrong paths. This makes weaker models useful as clarity detectors, not quality evaluators. Conflating the two leads to dumbing down skills to accommodate model limitations, which reduces guidance quality for capable models.

**Alternatives considered:**

| Approach | Pros | Cons |
|----------|------|------|
| Clarity probe only (chosen) | Finds real skill problems without downgrading | Requires careful failure categorization |
| Success benchmark (make haiku pass) | Clear pass/fail signal | Forces skill simplification, damages quality for capable models |
| No smaller-model phase | Simpler | Misses clarity issues capable models paper over |

**What would invalidate this:** We find that haiku failures are consistently capability limits (no clarity signal), making the phase not worth running.

### D5: ADR awareness is conditional, not required

**Firmness: FLEXIBLE**

The review agent checks for `docs/decisions/ADR-*.md` at the start of each review pass. If ADRs exist, it reads relevant ones and surfaces conflicts. If no ADRs exist, the step is skipped.

**Rationale:** ADR awareness is valuable when present — it prevents the review agent from proposing changes that override prior design decisions without surfacing the conflict. But requiring ADRs would make the skill non-portable to repos that don't use them (the majority). Conditional check preserves portability while adding value where ADRs exist.

Same surfacing logic as `improve-iteratively`: FIRM decisions flag as conflicts, FLEXIBLE decisions note the tension, the user decides.

**Alternatives considered:**

| Approach | Pros | Cons |
|----------|------|------|
| Conditional (chosen) | Portable across repos | Requires filesystem check each run |
| Required | Consistent behavior | Breaks portability, imposes ADR adoption |
| Never check ADRs | Maximum portability | Misses real conflicts in repos that have them |

**What would invalidate this:** A standard location/format for design decisions emerges across repos, making the check always applicable.

### D6: Two compliance + quality dimensions, not a single pass/fail score

**Firmness: FIRM**

The review evaluates two orthogonal dimensions: compliance (did the agent follow the skill's prescribed steps?) and quality (was the output correct/good?). These are surfaced separately, not collapsed into a score.

**Rationale:** The two dimensions point to different root causes and different fixes:

| Agent behavior | Diagnosis | Fix |
|----------------|-----------|-----|
| Compliant + good output | Skill working | No change needed |
| Compliant + bad output | Skill guidance is wrong | Fix the skill's instructions |
| Non-compliant + good output | Skill isn't compelling enough | Strengthen skill structure/clarity |
| Non-compliant + bad output | Skill has gaps + agent improvised poorly | Add missing steps |

Collapsing to pass/fail loses the diagnostic signal.

**Alternatives considered:**

| Approach | Pros | Cons |
|----------|------|------|
| Two dimensions (chosen) | Clear diagnostic signal per finding | Slightly more complex review output |
| Single pass/fail | Simple | Loses root cause signal |
| Numeric score | Quantitative comparison across iterations | False precision, hides qualitative issues |

**What would invalidate this:** In practice, compliance and quality are always correlated — if compliance is high, quality is always high. Then the distinction adds no value. (We believe this is unlikely: a skill can prescribe wrong steps.)

## Related

- [Soldier-Proof Design](../2026-04-14-soldier-proof-design.md) — full design document
- improve-iteratively skill (a private work-product repo, not linkable across repos) — domain-specific predecessor, inspiration for manager/agent/review pattern
- ADR format reference (a private methodology-home ADR that does not publish to core)
