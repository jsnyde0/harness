# Rule-shape vs Signal-shape Guidance

When you author **text-for-an-agent** — skill bodies, subagent prompts, recipes, MCP tool descriptions — you face a separate axis from "which extension type." How much should the content prescribe the answer versus name what to attend to and trust the agent to judge?

This file is the deep treatment. SKILL.md has the short framing.

## The distinction

- **Rule-shape** prescribes the answer: "must X before Y", "fail if Z > 10%", "always close the bead before closing the worktree."
- **Signal-shape** names what to attend to and trusts the agent to judge: "if a slot grew during refinement, consider splitting", "would you contradict this in some real case? (countermand test)", "watch for X surfacing in practice."

A useful sharpening from Diataxis: rule-shape content is *action-oriented* (how-to); signal-shape content is *understanding-oriented* (explanation / orientation).

## Default to signal-shape

Three reasons, in order of weight:

### 1. Fragility

Static prompts can't route. LLMs interpolate between conditional strategies in proportion to textual weight rather than selecting per instance ([Single-Prompt Ceiling, arXiv 2604.18897](https://arxiv.org/html/2604.18897)). A rule fires confidently in cases the author didn't anticipate — and the more confident the wording, the more confidently the misfire happens.

### 2. Anticipation

The author rarely understands a rule's full firing surface at write-time. Edge cases the author hasn't met yet will hit the rule and get wrongly handled. Signals re-judge in context every time, so cases the author didn't think of get judged on their merits.

### 3. Scaling

Rules cap the agent at the author's foresight forever. Signals appreciate as the model gets sharper. Anthropic's own context-engineering writing puts it directly:

> *"Smarter models require less prescriptive engineering, allowing agents to operate with more autonomy."* — [Anthropic, *Effective Context Engineering for AI Agents* (Sept 2025)](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

Rules you write today are the ceiling on what the agent will do tomorrow. Signals are floors that lift as the underlying intelligence improves.

## The asymmetry: positive vs. negative directives

Rules don't earn their keep symmetrically. Empirically — across ~5,000 SWE-bench Verified runs in [*Do Agent Rules Shape or Distort?* (arXiv 2604.11088)](https://arxiv.org/abs/2604.11088) — **negative constraints shape; positive directives distort.**

- **Hard avoidance rules shape** without much collateral damage:
  - "Do not refactor unrelated code"
  - "No force-push to main"
  - "Never modify in_progress beads without claim"
  - "Do not commit secrets"
- **Positive prescriptions distort** — they fire in cases that should have gone differently:
  - "Follow code style"
  - "Always validate inputs"
  - "Prefer X over Y"
  - "Use the most expressive name"

Positive prescriptions get applied broadly because they're stated unconditionally; the model doesn't know which cases the author had in mind. Negative constraints land more cleanly because "don't do X" carves a smaller surface than "always do X."

**Practical default:**
- For *positive directives*, signal-shape unless you have strong evidence otherwise.
- For *negative/avoidance guardrails*, rule-shape is more often earned — especially when the failure mode is catastrophic.

Same paper found that **14 of 18 hand-curated rules each broke ≥2 tasks**, and that **random rules helped nearly as much as curated ones** — suggesting much of the benefit of "rules in the prompt" comes from context priming rather than from the rule's specific content. This is a hint that authors over-attribute the value of their rules to their wording.

## Three-part test for rule-shape

Use rule-shape only when *all three* hold:

1. **Catastrophic if wrong.** The failure mode is unrecoverable, expensive, or violates a hard contract.
2. **Well-understood firing surface.** You can confidently anticipate every case the rule will fire in.
3. **Doesn't benefit from a smarter model.** Future model improvements wouldn't change the right answer (e.g. "no force-push to main" — pure constraint, no judgment to improve).

If any criterion fails, signal-shape it.

This test is itself **signal-shape, not rule-shape**. A sharper agent should be able to judge "is rule-shape earned here?" better than any checklist will. The three parts are an attention-anchor — three angles to feel the discomfort from. If you find yourself satisfying the checklist mechanically without any discomfort, you're using it wrong.

### Worked example: tool descriptions pass the test

Tool descriptions (MCP tool docstrings, function signatures, parameter docs) **earn rule-shape**:

1. *Catastrophic if wrong:* yes — Claude calling the wrong tool or with wrong args is hard to recover from at decision time.
2. *Well-understood firing surface:* yes — the firing surface is the tool itself, and the author knows the tool's contract.
3. *Doesn't benefit from a smarter model:* type info, parameter schemas, and "use this BEFORE X" hints stay correct regardless of model intelligence.

Anthropic's [*Writing Tools for Agents*](https://www.anthropic.com/engineering/writing-tools-for-agents) is consistent with this — small refinements in tool descriptions yield outsized wins. **Most skill body content does not pass the test** and should default to signal-shape.

## Substrate-rigidity match

A rule expressed as text in a SKILL.md isn't actually a rule — it's a strong-worded instruction interpreted by an agent. Once you've decided rule-shape is earned, ask: **does the substrate match the rigidity?**

| Rule needs… | Skill text works? | Better substrate |
|-------------|:-----------------:|------------------|
| Counting / measurement / stateful tracking ("if >10% wrong", "after every 5 runs") | **No** | Script, hook, or instrumented tool. Otherwise reframe as a signal. |
| Binary procedural check (exit code, file exists, dep cycle) | Yes | Either text or code works. |
| Pure model judgment (semantic match, intent check) | Yes — but call it what it is | Signal-shape it. |

In eval-literature terms: **measurable-output thresholds** (latency, JSON validity, F1 score) are enforceable; **in-prompt thresholds** are not. Don't dress the second as the first.

The substrate question often collapses back into "this should be a signal." If your would-be rule needs counting, agents won't count for you across runs — so either you instrument the count externally, or you turn it into a signal that the agent can attend to in the moment ("watch for X-failures becoming common, tighten the criteria when they do").

## Signal-shape patterns

Patterns to draw on when you choose signal-shape:

- **Countermand test.** "Would you contradict this rule yourself in some real case? If yes, signal-shape it." Hand the question back to the agent at decision time. Best for: cases where the rule "feels right" most of the time but the author can already imagine plausible exceptions.
- **Watch-for.** "Watch for X surfacing in practice" — name the pattern, leave the threshold open. Best for: emerging concerns where you have a hunch but not a clear bright line.
- **Growth-triggered.** "If a slot grew during refinement, consider splitting" — condition the attention on observable change. Best for: drift detection, scope creep, growing complexity.
- **Attention-anchor.** A vivid example or one-liner the agent can recognize cases against, without committing to a numeric rule. Best for: teaching a *kind* of mistake without enumerating all instances.

## Anti-patterns

### Falsifiability theater

Numeric thresholds with no instrumentation, no triggering mechanism, no one reading them. Looks rigorous, does nothing. Common in "What would invalidate this" sections of design docs and ADRs:

- "Invalidate if >10% of auto-accepts are wrong"
- "Sample 20 outputs; if >25% FAIL, revisit"
- "After 6 months, if <20% of decisions show meaningful checks, drop the gate"

No one is sampling 20 outputs. No one is counting decisions over 6 months. The numbers were chosen to satisfy the template, not because they're operational. Strip them and replace with qualitative signals ("watch for X surfacing in practice → tighten the criteria") or remove the section entirely if there's no instrumentation behind it.

### Rigidity-substrate mismatch

Mechanical content (counting, measurement) written into a non-mechanical substrate (skill text). This and falsifiability theater are surface forms of the **same underlying mistake**: putting work into a substrate that can't do it. The fix is one of: (a) move the work to a substrate that can do it (script, hook, MCP tool); (b) reframe as a signal the agent can attend to in-context.

### Out-ruling the model

Hand-tuned rules calibrated for one model's blind spots become dead weight (or active distortion) when the model improves. Random rules help nearly as much as curated ones — rules work mostly via *context priming*, not specific instruction (per arXiv 2604.11088). Don't over-invest in rule precision; the marginal return on tuning is lower than authors assume, and the rule will outlive its calibration.

### Too-vague-to-fire signals

Signal-shape fails too. A countermand test that never triggers because nothing felt contradicted is worse than a clear rule. A "watch for X" that's so abstract the agent never recognizes a hit is just noise. Signals need a concrete enough trigger that the agent will actually notice them — vivid examples, observable change conditions, or named patterns help. If a signal can't be made concrete enough to fire, you may be punting on a question that needs a real answer.

### Author-info loss

A signal that defers judgment to the model in cases where the *author* genuinely had information the agent doesn't. If the right answer depends on knowledge only you have (a past incident, a stakeholder constraint, a system invariant the agent can't infer from context), encode it — don't punt to in-context judgment. Signal-shape is the wrong choice when the agent's situational reasoning isn't enough; in those cases, write the rule (and explain *why* so future-you can judge edge cases later).

## Diagnostic questions for skill authors

When reviewing a piece of skill text, run through:

1. Is this rule-shape or signal-shape?
2. If rule-shape: does it pass the three-part test? If not, can I reframe as a signal?
3. If rule-shape: does the substrate match the rigidity? If it needs counting, am I shipping the counter (script/hook)? If not, reframe.
4. If signal-shape: is the trigger concrete enough that the agent will recognize a hit? If not, sharpen.
5. If signal-shape: is there author-info the agent doesn't have that I'm wrongly punting? If yes, encode it.
6. Is this a positive directive or a negative constraint? If positive, the bar for staying rule-shape is higher.

## Sources

- [Anthropic Engineering: *Effective Context Engineering for AI Agents*](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — canonical Anthropic statement on minimum-specification, Goldilocks zone, and scaling-with-intelligence.
- [Anthropic Engineering: *Writing Tools for Agents*](https://www.anthropic.com/engineering/writing-tools-for-agents) — the worked counter-example: tool descriptions earn rule-shape.
- [*Do Agent Rules Shape or Distort? Guardrails Beat Guidance in Coding Agents* (arXiv 2604.11088)](https://arxiv.org/abs/2604.11088) — empirical asymmetry: negative constraints shape, positive directives distort; random rules ≈ curated rules.
- [*Less is More: Cognitive Load and the Single-Prompt Ceiling* (arXiv 2604.18897)](https://arxiv.org/html/2604.18897) — mechanism behind fragility: LLMs interpolate rather than route.
- [Diátaxis framework](https://diataxis.fr/) — vocabulary for action-oriented vs understanding-oriented content.
