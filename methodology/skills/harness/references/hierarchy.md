# Verification Hierarchy Patterns

## The Spectrum

```
FAST / DETERMINISTIC SLOW / SEMANTIC
───────────────────────────────────────────────────────────────────→
compile → typecheck → lint → unit test → integration → E2E → LLM judge → human
 (milliseconds) (seconds) (minutes)
```

## Computational vs. Inferential (Fowler)

Martin Fowler distinguishes two categories:

**Computational (deterministic, fast):** Tests, linters, type checkers, structural analysis. Milliseconds to seconds. Reproducible. Cheap to run on every change.

**Inferential (semantic, slower):** LLM-as-judge assessments. Non-deterministic. Expensive. Use only when computational verification can't answer the question.

Hybrid approach: computational first (baseline quality), inferential second (catch semantic issues), human spot-check (calibrate judges).

## Spotify Honk's Three Tiers

1. **Deterministic verifiers** — Format, lint, build, test. Activate based on project contents (e.g., `pom.xml` → Maven verifier). Extract error messages via regex for concise agent feedback.
2. **LLM-as-judge** — Evaluates proposed diffs against original prompt. Catches scope violations. Vetoes ~25% of sessions; agents self-correct ~50% of the time.
3. **Human review** — For ambiguous cases the judge can't resolve.

## Anthropic's Three-Tier Grader Framework

- **Code-based graders**: String matching, binary tests, static analysis. Fast, cheap, objective. Brittle to valid variations.
- **Model-based graders**: Rubric-based scoring, natural language assertions. Flexible, captures nuance. Non-deterministic, expensive.
- **Human graders**: Gold-standard accuracy. Expensive, slow, requires expert access.

Strategic recommendation: deterministic where possible, LLM where semantic judgment needed, human for calibration.

## Speed = Quality

Teams that cut test suites from 15 minutes to 90 seconds saw dramatic agent improvement. The faster the feedback, the more iterations the agent can make. Deterministic verification (tests, linters, type checkers) provides binary signals agents can act on without human judgment.

## LangChain's Reasoning Sandwich

Variable reasoning budgets across phases:
- **xhigh** reasoning for planning
- **high** for implementation
- **xhigh** again for verification

Result: 66.5% vs 53.9% at constant xhigh (due to timeouts) and 63.6% at constant high.

## Linters as Upstream Targets (Factory.ai)

"Agents write the code; linters write the law."

Instead of using linters as downstream QA, make them the primary iteration target. In Factory.ai's framing, lint green = definition of Done. (In *our* substrate this is the gradient, not the finish line: lint/Signal green is the hillclimbing target you iterate against, necessary-not-sufficient — done = harness green AND acceptance met, including the prose remainder no linter reaches.) Seven domains: grep-ability, glob-ability, architectural boundaries, security, testability, observability, documentation signals.

The migration engine pattern: encode legacy patterns (detectable) and target APIs (required) → agent-driven large refactors.

---

## Coverage Rubric for Behavioral Acceptance Checks

*(Added 2026-04-27, source: ce-work/SKILL.md Phase 2 — "test scenario completeness check")*

The speed hierarchy above is **orthogonal** to coverage breadth. Fast feedback is only valuable if the check actually exercises the relevant behavior paths.

For every **behavioral bead** (i.e., a bead that changes observable behavior, not just docs or config), `/harness compose` should flag if any of the four categories is absent from the `--acceptance` contract:

| Category | What it covers | When mandatory |
|---|---|---|
| **Happy path** | The intended use case works end-to-end | Always |
| **Edge case** | Boundary inputs, empty collections, zero values, max values | When the implementation has branches |
| **Error path** | Bad input, missing deps, failure modes — system degrades gracefully | When the code can receive invalid inputs or dependencies can fail |
| **Integration** | At least one test uses real objects (not mocks) to verify the system fires correctly end-to-end | When the feature involves callbacks, middleware, observers, or event handlers |

**Usage during `/harness compose`:** If the proposed `--acceptance` only covers happy path, flag the missing categories and propose additions. Missing a category is acceptable only if:
- The bead is a pure doc/config change (no behavioral surface).
- A category genuinely does not apply (e.g. a pure math function with no external dependencies may not need an "integration" scenario).

In both cases the justification must be explicit, not a silent omission.

**Relationship to the speed hierarchy:** Run the fastest signal available for each category. An edge-case check as a unit test is better than a slow E2E check — but only if the unit test actually uses real objects where the integration surface matters (see Mock trap in the Anti-Patterns section of harness/SKILL.md).
