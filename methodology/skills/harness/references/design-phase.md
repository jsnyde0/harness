# Grounding During the Design Phase

The hardest phase to ground — there's no code to test yet. Most design failures stem from untested assumptions, not bad ideas. 70% of product features fail because teams build from untested assumptions (McKinsey).

## Pattern: Spike First, Design Second

**Design spikes** are time-boxed experiments (1-3 days, max 5) to reduce uncertainty before commitment. Build a throwaway prototype that answers the core question.

For agent work, this can be much faster:
- 30 minutes to stand up a minimal proof-of-concept
- Run one command to see if the core assumption holds
- Throw it away and write the design doc based on observed reality

**When to spike:** Only for genuine uncertainty — "I don't know if this approach will work." Don't spike on garden-variety implementation details.

**A containerized-agent project example:** Spent 15 minutes on research and design docs. Then `docker exec ... unset BEADS_DOLT_SERVER_MODE && bd list` answered the real question in 2 seconds. The spike should have come first.

## Pattern: Falsifiable Design Hypotheses

Frame each design decision as: "We believe X. We'll know we're right when Y."

Examples:
- "We believe embedded Dolt works in containers. We'll know when `bd list` succeeds inside a container without server env vars."
- "We believe the API can handle 1000 req/s. We'll know when a load test shows p99 < 200ms."
- "We believe this refactor is backwards-compatible. We'll know when the existing test suite passes unchanged."

Then test Y before committing to the design. If Y fails, the design needs revision.

## Pattern: Assumption Mapping

Explicitly list every assumption the design rests on. Categorize by:
- **Impact**: If this assumption is wrong, how bad is it?
- **Uncertainty**: How confident are we this is true?

Test high-impact, high-uncertainty assumptions first. Low-impact or high-confidence assumptions can wait.

For architecture decisions:
- Feasibility assumptions: "Can we do this technically?"
- Performance assumptions: "Will this be fast enough?"
- Compatibility assumptions: "Will this break existing behavior?"
- Dependency assumptions: "Does this library/tool actually work this way?"

## Pattern: Run the Existing System First

Before designing a change, observe current behavior:
- `docker exec` into the running system
- `curl` the current API endpoints
- Query the actual database
- Read the actual logs
- `git log` the recent changes

Understand what IS before designing what SHOULD BE. Many design docs are wrong because they describe a system that doesn't match reality.

## Pattern: Pre-Mortem

Before committing to a design, imagine it failed. Ask:
- "It's 3 months later and this approach completely failed. What went wrong?"
- Across PEOPLE, PROCESS, TECHNOLOGY, EXTERNAL factors
- Rate each failure mode by likelihood and impact

Pre-mortems increase problem identification by 30% by combating optimism bias.

## What's Missing

The field hasn't yet formalized:
- ADRs with mandatory verification sections ("How to verify this decision")
- Go/no-go criteria for "when to stop researching and start experimenting"
- Systematic assumption mapping applied to software architecture (it exists for product design)

These are opportunities, not blockers. An agent with good judgment can apply these patterns without formal frameworks.
