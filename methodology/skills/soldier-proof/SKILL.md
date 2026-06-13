---
name: soldier-proof
description: Harden a Claude Code skill by running it in isolation with a test agent, reviewing compliance and output quality, and iterating until the skill is clear and complete
---

Harden any Claude Code skill by injecting it into an isolated test agent, reviewing the results across two orthogonal dimensions (compliance and quality), and iterating until the skill is clear and complete.

**Arguments:** `$ARGUMENTS` parsed as:
- `skill-path` — path to target SKILL.md (required). Relative or absolute.
- `--iterations N` — number of loop iterations (default: 3)
- `--model <model>` — if specified, run an additional clarity probe pass with that model after the main loop (e.g. `haiku`, `sonnet`)
- `--baseline` — opt-in flag; if present, dispatch a second naive agent (no skill content) on iteration 1 only; the review agent adds a "Baseline comparison" section for that iteration

**Backward compatibility:** A skill with no `evals/evals.json` and no `--baseline` flag behaves identically to prior soldier-proof runs, except that (a) timing data (`total_tokens`, `duration_ms`) is now captured per agent dispatch and surfaced in the Phase 7 design doc, and (b) at session end you will be prompted once to save the derived prompts to `evals/evals.json`. Both are strict supersets — no existing behavior is removed or broken.

**Examples:**

```
/soldier-proof skills/harness/SKILL.md
/soldier-proof skills/pr/SKILL.md --iterations 5
/soldier-proof skills/brainstorm/SKILL.md --model haiku
/soldier-proof skills/yt-transcript/SKILL.md --iterations 3 --model haiku
```

## Execution

You are the **manager**. You orchestrate the iteration loop, triage findings, and apply trivially-safe fixes.

### Phase 1: Parse arguments

Extract from `$ARGUMENTS`:

1. **skill-path** — first token (or only non-flag argument). Required.
 - Resolve to absolute path: if relative, resolve from the current working directory.
 - Validate the file exists. If it does not exist, **stop and report the path that was tried** — do not proceed with a missing skill.
2. **--iterations N** — if present, extract N as integer. Default: 3.
3. **--model** — if present, extract the model name that follows it (e.g. `haiku`). Store as `clarity_model`. If absent, leave unset.
4. **--baseline** — if present, set `run_baseline = true`. If absent, set `run_baseline = false`. When true, a naive agent (no skill content) is dispatched on iteration 1 only alongside the skilled agent; the review agent adds a "Baseline comparison" section for iteration 1. No baseline run is dispatched on iterations 2..N.

After parsing:
- Read the skill file fully. Store as `skill_content`.
- Store `skill_name` from the frontmatter `name` field (or fallback to the directory name).
- Resolve **repo_root**: walk up the directory tree from the skill-path's parent directory until a `.git` directory is found, or until the filesystem root is reached. Store the first directory containing `.git` as `repo_root`. If no `.git` is found, set `repo_root` to the skill-path's parent directory and note this in output.
- Generate a **session ID**: compact timestamp, e.g. `20260414-1430`. All transcript paths use `/tmp/sp-transcript-{session_id}-{iter}.md`.

### Phase 2: Derive test prompts

Read `skill_content` carefully:

**Pre-step — Branch enumeration and coverage record seeding (do this first):** Before deriving prompts, list all major branches, decision points, and use cases documented in the skill. For example: optional phases, conditional steps, edge cases described in examples, argument variants. Present this list to the user — it will anchor prompt selection and is referenced again in Phase 5.

After enumerating branches, initialize the `coverage_record` — a structured table with one row per branch. Each row has three fields:
- **branch**: the branch identifier from the enumeration (short label, e.g. `"--model flag"`, `"edge case: missing skill"`)
- **iteration_tested**: initially empty (`—`)
- **evidence**: initially empty (`—`)

Store this table in memory as `coverage_record`. It is the authoritative record updated throughout the loop and rendered as-is in Phase 7.

**Load-or-derive step:** Before deriving new prompts, check whether `<skill-dir>/evals/evals.json` exists (where `<skill-dir>` is the directory containing the target SKILL.md).

- **If `evals/evals.json` exists:** Load it. Extract the `evals` array — each entry has an `id`, `prompt` text, optional `expected_output`, and 0–N `assertions`. Present the loaded prompts and their assertions to the user, formatted clearly. Offer add/edit/delete before the loop starts. Store the result as `session_prompts` (may differ from what was on disk if user edited). Skip the derivation step below; use these prompts as the iteration set. Store any assertions alongside their prompt in memory as `session_assertions` keyed by prompt id.

- **If `evals/evals.json` is absent:** Derive 2–3 prompts as described below. Store as `session_prompts`. Each derived prompt has no assertions initially (`session_assertions` for each is empty). At session end (after Phase 7), ask the user: "Save these prompts to `<skill-dir>/evals/evals.json` for future runs?" — on confirmation, write the file using the `evals.json` schema (an object with `skill_name` and an `evals` array). If assertions were added during triage, include them in the saved entries.

**New prompts added mid-session** (e.g., user requests an additional prompt during triage): append them to `session_prompts` and include them in the session-end save.

- Identify the skill's description, intended use cases, decision branches, and any examples
- Derive **2–3 test prompts** that cover different parts of the skill's intended scope:
 - Target different branches or phases of the skill
 - Vary difficulty and context (not just rephrasings of the same scenario)
 - At least one prompt should exercise an edge case or less-obvious path

**Prompt count guidance:** If the user provides fewer than 2 prompts, derive additional prompts to reach at least 2. If the user provides more than 3, use the first 3 or ask which to prioritize.

**Present the derived prompts to the user before starting the loop.** The user may adjust, replace, or approve them as-is. This is a FLEXIBLE decision (D2) — user judgment is welcome here.

Do not start the iteration loop until the user has approved or adjusted the prompts.

### Phase 3: Running plan

Maintain this structure across all iterations:

- **Accepted proposals** — improvements confirmed by user during triage
- **Rejected proposals** — with rationale (so future iterations don't re-propose the same thing)
- **Trivially-folded changes** — changes applied between iterations without approval (logged here so the review agent sees what changed)

### Phase 4: Iteration loop (N hard iterations)

**N iterations is a hard requirement, not a target.** Do not skip iterations because early results look good. The only early exit is an explicit user block.

```
For iteration = 1 to N:
 Step 1: Dispatch test agent
 Step 2: Extract transcript
 Step 3: Dispatch review agent
 Step 4: Triage findings with user
 Step 5: Apply trivially-safe fixes before next iteration
```

#### Step 1: Dispatch test agent

Launch a fresh subagent using the Agent tool. Use **direct skill injection** (D1 FIRM — do not use pre-configured agent definitions). The test agent receives only the target skill's content and the test prompt — nothing else.

**Test agent prompt template:**

```
You have access to the following skill. Follow it for this task.

--- SKILL: {skill_name} ---
{skill_content}
---

Task: {test prompt for this iteration}

IMPORTANT: Execute this task from scratch. Do not reuse prior results.
```

**Prompt rotation:** Use prompt 1 for iteration 1, prompt 2 for iteration 2, etc. If N > number of prompts, cycle back. **Exception — fix validation:** After user-approved fixes are applied to the skill, re-run the same prompt that triggered those fixes before advancing to the next prompt. Only rotate to a new prompt when the current prompt produces no new compliance or quality findings. This ensures fixes are validated before moving on.

**Timing capture:** When the Agent tool returns a completion notification for each dispatched agent, record `total_tokens` and `duration_ms` from that notification. Store these per iteration in memory as `timing_records[iter] = {total_tokens, duration_ms}`. If the notification does not include these fields, record `—`. Do NOT write a separate JSON file; the timing data is surfaced in the Phase 7 design doc.

**Baseline dispatch (only when `run_baseline = true` and iteration = 1):** Immediately after dispatching the skilled test agent (and before extracting its transcript), dispatch a second naive agent with the same prompt but without skill content:

```
You are a capable assistant. Complete this task to the best of your ability.

Task: {test prompt for this iteration}

IMPORTANT: Execute this task from scratch. Do not reuse prior results.
```

Extract and store the naive agent's transcript at `/tmp/sp-transcript-{session_id}-{iter}-naive.md`. Record its `total_tokens` and `duration_ms` separately as `timing_records[iter]["naive"]`. Pass both transcripts (skilled + naive) to the review agent in Step 3 for the Baseline comparison section. No baseline dispatch on iterations 2..N.

**Error handling:** If the test agent errors, stalls, or times out, that is valuable data. Capture whatever transcript exists and proceed to review. A failed run reveals exactly where the skill breaks.

#### Step 2: Extract transcript

After the test agent completes, extract a readable transcript from its JSONL.

**You MUST call the Skill tool with `skill: "claude-session-transcript"`.**
Do NOT write custom Python scripts to parse JSONL. Do NOT read the JSONL manually and summarize it.

The Agent tool returns an `agentId`. Locate the JSONL:
```bash
find $HOME/.claude -name "agent-{agentId}.jsonl" -type f
```

Then call:
```
Skill tool → skill: "claude-session-transcript"
```

Run the extraction script with:
- INPUT_PATH = the JSONL path found above
- OUTPUT_PATH = `/tmp/sp-transcript-{session_id}-{iter}.md`

**What the transcript contains:** The extracted transcript includes the agent's narrative (thinking + prose), all tool calls with their parameters, 200-character result previews per tool call, and `[line N]` JSONL references pointing to the raw JSONL line for each tool call.

**Deep-diving into specific tool calls:** When the review agent needs to inspect a tool call in full (e.g., to verify exact parameters or the full result), it can read the JSONL directly using the `[line N]` reference. Pass the JSONL path alongside the transcript path in Step 3 so the review agent can use it.

#### Step 3: Dispatch review agent

Launch a subagent with the review prompt below. Pass the extracted transcript and the running plan as context.

**Review agent prompt:**

```
Review iteration {iteration} of a /soldier-proof run.

## Context
Target skill: {skill_name}
Test prompt used: "{test prompt}"
Transcript: /tmp/sp-transcript-{session_id}-{iteration}.md
JSONL: {jsonl_path}
{if run_baseline and iteration == 1: "Naive baseline transcript: /tmp/sp-transcript-{session_id}-{iteration}-naive.md"}
{if assertions defined for this prompt: "Assertions for this prompt: {assertions list}"}

## Skill under test
{skill_content}

## ADR check (conditional)
Check whether ADR files exist at `{repo_root}/docs/decisions/` (absolute path).
- If ADRs exist: read any that are relevant to the skill's domain or the test prompt.
 For each proposal you make, check whether it conflicts with a FIRM ADR decision.
 If it does, flag it explicitly: "CONFLICTS WITH ADR-NNN: [what the ADR decided]"
 A conflict doesn't mean the proposal is wrong — the ADR may need updating — but
 it MUST be surfaced, never silently overridden.
- If no ADRs exist or the path does not exist: skip this step entirely.

## Compliance dimension (D6 FIRM)
Did the test agent follow the skill's prescribed steps?
- Which phases/steps did the agent execute as specified?
- Where did it deviate or improvise?
- Were deviations necessary (skill gap) or incidental (agent choice)?

## Quality dimension (D6 FIRM)
Was the output good, independent of whether the agent followed the skill?
- Did the output meet the success criteria implied by the test prompt?
- Diagnostic matrix:
 - Compliant + good output → skill working, no change needed
 - Compliant + bad output → skill guidance is wrong, fix the instructions
 - Non-compliant + good output → skill isn't compelling/clear enough
 - Non-compliant + bad output → skill has gaps and agent improvised poorly

## Per-assertion grading (augments quality dimension — do not replace it)
This section augments the quality dimension above; the narrative quality judgment
(the diagnostic matrix) must still be produced even when assertions are present.

**If assertions were provided for this prompt:**
For each assertion, output a grading block:
- **Assertion:** "{assertion text}"
- **Result:** PASS or FAIL
- **Evidence:** quoted transcript excerpt or specific observation supporting the verdict.
 Evidence MUST be concrete — a direct quote from the transcript, a tool call observed,
 or a specific output artifact. Do not give the benefit of the doubt; require concrete
 evidence for a PASS.

Organize as a numbered list. End with a summary line: "Assertions: X/Y passed."

**If no assertions were provided for this prompt:**
Produce the narrative quality judgment only. Add a note at the end:
"No assertions defined for this prompt — consider adding some to evals/evals.json
to make future grading more objective."

## Baseline comparison (only when naive baseline transcript is provided)
When a naive baseline transcript is provided (iteration 1 with --baseline flag):
Read both the skilled transcript and the naive baseline transcript. Produce a
"Baseline comparison" section with:
- A brief characterization of the naive agent's output (what did it do without the skill?)
- A verdict: did the skilled agent meaningfully outperform the naive agent?
- Specific differences in approach, completeness, or output quality, with quoted evidence
 from both transcripts.
- If the skill added no meaningful lift, flag this prominently — it may indicate the skill
 is not providing useful guidance or the test prompt is too easy.

This section appears only for iteration 1 when --baseline is active.

## Tool dependency check
Flag any tool calls the test agent made that are NOT referenced in the skill text.
These represent implicit dependencies the skill assumes but does not document.

## External dependency check
If the test agent could not resolve a file or resource referenced in the skill
(recipes, ADRs, related docs), categorize this as an **external dependency** finding,
not a test infrastructure failure. These findings surface portability issues.

## Overfitting guard (D3 FIRM)
For EVERY proposed improvement, you MUST ask:
"Does this fix address a gap in the skill's full intended scope, or does it only
patch this specific test case?"

Proposals that narrow the skill below its design intent must be flagged as
potential overfitting. Do not propose changes that make the skill work for this
test case at the cost of reducing its applicability to other cases.

## Context leakage check
The test agent inherits the parent session's CLAUDE.md, project memory, and hooks — context
that is NOT present in the injected skill text and will not be present when the skill runs
in other repos.

Flag any behavior where the test agent appears to rely on knowledge not present in the
injected skill text (for example: project conventions from CLAUDE.md, environment setup
from hooks, repo-specific paths or tool names). Categorize each as:
"CONTEXT LEAK: [knowledge source] — [what the agent relied on]"

This tells the user that the finding may not reproduce in other repos or for other users.

## Description-trigger check
For EVERY finding you surface, consider in addition to the body-text fix:
"Would adding (or revising) an about-to-violate trigger phrase in the skill's
frontmatter `description:` field improve the chance of the skill firing in
this scenario?"

This is a distinct fix-shape from body-text edits. A skill only fires when
the harness's description-matching engages with the agent's about-to-act state;
a sound skill body cannot rescue a description that doesn't trigger. Surface
description-trigger proposals as their own labeled class so triage sees them
separately from body edits.

When to propose: the test agent failed to invoke the skill, OR the agent
invoked it only after explicit prompting, OR a violation symptom (the kind
of state where the skill should fire) is observable in the transcript but
absent from the skill's current `description:`.

Format each proposal as:
- **Symptom phrase to add** (literal text candidate)
- **Why it improves trigger fit** (what about-to-act state it would catch)
- **Generalization** — is this symptom common to the skill's full scope, or only this test case?

Do NOT propose: rationalization tables, red-flag STOP sections, or pressure-
mode prescriptions. Those over-prescribe judgment-composable substrate
primitives. Description triggers and body-text edits are the fix-shape
vocabulary for this skill.

## Prior iteration context
{running plan: accepted proposals, rejected proposals with rationale,
trivially-folded changes applied between iterations}

Do not re-propose items already rejected unless you have new evidence.

## Output format
For each finding, provide:
- **What to change** and why
- **Which dimension** it affects (compliance, quality, or both)
- **Evidence** — specific transcript excerpt or tool call observation
- **Generalization assessment** — does this apply to the full skill scope, or just this test case?
- **Overfitting flag** (if applicable): mark clearly

Organize into:
1. Compliance findings
2. Quality findings
3. Tool/external dependency findings
4. Context leakage findings (CONTEXT LEAK: ... entries)
5. Overfitting-flagged proposals (separate section so they don't get silently included)
6. Description-trigger proposals (labeled category — see "Description-trigger check" above)
```

#### Step 4: Triage

Present findings to the user. Default posture: surface before including.

**Recommend including** — state the proposed improvement and why, briefly. User confirms or pushes back.

**Recommend skipping** — state why it's not worth it. User can override.

**Need discussion** — genuine tradeoffs, competing concerns, or unclear home for the improvement.

**Trivially-safe fixes** are applied between iterations without user approval. These are changes where the cost of being wrong is near-zero:
- Typo fixes and spelling corrections
- Formatting corrections (indentation, markdown rendering)
- Factual updates to tool names, paths, or version references
- Fixing broken links or broken example commands

**NOT trivially safe** (always require user approval):
- Adding a new step or phase
- Removing a step or phase
- Changing decision logic or branching conditions
- Reordering phases
- Altering success criteria or done-when conditions
- Editing the skill's frontmatter `description:` field (description-trigger proposals): changes the skill's trigger surface and can affect when the skill fires in unrelated sessions — always requires user approval, never auto-applied between iterations

Log all trivially-safe fixes in the running plan under "Trivially-folded changes."

Rejected proposals are recorded with rationale in the running plan.

#### Step 4b: Update coverage record

After triage, update the `coverage_record` for this iteration:

1. For each branch in the `coverage_record`, determine whether this iteration's test agent exercised it. A branch is exercised if the transcript shows the agent taking the corresponding path or producing output relevant to that branch.
2. For every exercised branch that was previously untested (`iteration_tested` = `—`):
 - Set `iteration_tested` to the current iteration number (e.g. `1`)
 - Set `evidence` to an citation: transcript filename + line number (e.g. `sp-transcript-20260428-1430-1.md:L42`) or document filename + section ID if the finding traces to a design doc
3. Branches that were already tested in a prior iteration: do NOT overwrite their record — first-test iteration is the canonical one.
4. Branches not exercised this iteration remain with their current values unchanged.

This update is performed in memory and does not require user confirmation. The record must contain one entry for every branch from Phase 2's enumeration — no additions, no deletions.

#### Step 5: Apply trivially-safe fixes

Before the next iteration, apply any trivially-safe fixes agreed upon or auto-applied:
1. **Edit the target SKILL.md file on disk** using the Edit tool (do not update only the in-memory variable — changes must persist to disk).
2. **Re-read the file** after editing to update `skill_content` to the current on-disk state.

The next test agent must receive the updated skill from the re-read `skill_content`.

### Phase 5: Coverage assessment (post-loop)

The `coverage_record` has been updated incrementally after each iteration (Step 4b). At this point, review its final state:

1. Read the `coverage_record` as maintained — it already reflects which branches were tested and in which iteration
2. Identify any branches where `iteration_tested` is still `—` — these are untested branches
3. List **untested branches** explicitly — these are gaps in the hardening session
4. Suggest specific test prompts that would cover the untested branches in a future run

Present this to the user as a structured list. The row count of `coverage_record` must equal the number of branches enumerated in Phase 2. If it does not, a branch was lost — reconstruct from the Phase 2 enumeration before proceeding to Phase 7.

### Phase 6: Clarity probe (only if --model specified)

**This phase only runs if `--model` was specified in the arguments. Skip entirely if not.**

Run 1–2 additional iterations using the Agent tool's `model` parameter set to `clarity_model`. Use the same direct skill injection approach (D1 FIRM).

After each clarity probe run, the review agent categorizes each failure as one of:
- **Clarity failure** — the skill is ambiguous, uses unexplained jargon, or has missing context that a capable model would infer but a weaker model cannot. These are fixable skill problems.
- **Capability limit** — the model genuinely cannot reason through this domain regardless of how the skill is written. Document as a known limit; do NOT simplify the skill to compensate (D4 FIRM).

The goal is not to make the smaller model succeed. It is to find clarity issues that smarter models paper over. Do not propose changes that dumb down the skill to accommodate capability limits.

After each clarity probe run, update `coverage_record` following Step 4b — number each clarity-probe iteration continuing from the Phase 4 count (e.g. if Phase 4 ran 3 iterations, label the first clarity-probe run iteration 4) — if the clarity-probe agent exercised a branch not yet tested, record the iteration number and an evidence citation (transcript filename + line number); first-test iteration remains canonical and must not be overwritten.

### Phase 7: Write design doc

Determine the output filename with collision avoidance:

1. Start with the candidate path `history/YYYY-MM-DD-sp-{skill-name}.md` (today's date, `skill_name` from Phase 1).
2. Check whether that file already exists on disk.
3. If it does **not** exist, use it as-is.
4. If it **does** exist, try `history/YYYY-MM-DD-sp-{skill-name}-2.md`. If that also exists, try `-3`, `-4`, and so on, incrementing until a path that does not exist is found. **Never overwrite an existing file.**
5. The first non-colliding path found is the **chosen filename**.

The path is relative to the CWD of the invoking session (typically the repo root). Create `history/` if it does not exist before writing (`mkdir -p history/`).

Content:
- **Test prompts used** — all prompts derived or loaded in Phase 2, with rationale for each
- **Coverage table** — render directly from the `coverage_record` maintained across the loop. Do NOT re-derive from iteration prose. The table must have exactly these columns:

 | Branch | Iteration tested | Evidence |
 |--------|-----------------|----------|
 | (branch label from Phase 2) | (iteration number, or `—` if untested) | (transcript filename + line number, or `—`) |

 Every branch from Phase 2's enumeration must appear as a row. Untested branches are marked `—` in both the iteration-tested and evidence columns. A reviewer can verify completeness by counting rows against the Phase 2 enumeration count.

- **Per-iteration timing table** — render from `timing_records` collected during the loop. Include one row per iteration (and one for the naive baseline if `--baseline` was used on iteration 1). Columns:

 | Iteration | Agent | total_tokens | duration_ms |
 |-----------|-------|-------------|-------------|
 | 1 | skilled | (value or `—`) | (value or `—`) |
 | 1 | naive (baseline) | (value or `—`) | (value or `—`) |
 | 2 | skilled | ... | ... |
 | ... | | | |

 This table is the authoritative timing record for the session. No separate JSON file is written.

- **Per-iteration findings** — for each iteration: compliance issues, quality gaps, key transcript evidence, proposals accepted/rejected
- **Per-prompt assertion grading rollup** — if assertions were used for any prompt during the session, include a summary table. Columns:

 | Prompt id | Iteration | Assertion | Result | Evidence (excerpt) |
 |-----------|-----------|-----------|--------|-------------------|
 | (prompt id) | (iter) | (assertion text) | PASS / FAIL | (quoted evidence) |

 Only include this section if at least one prompt had assertions. If no assertions were used, omit this section entirely.

- **Trivially-folded changes** — full log of changes applied between iterations without approval
- **Improvement plan** — prioritized list of accepted proposals, each with what/why/where/generalization assessment. Group proposals by category, with **Description-trigger proposals** as a distinct labeled subsection (separate from body-text edits) so the user sees frontmatter `description:` changes as their own class.
- **Rejected proposals** — with rationale, for future reference
- **Clarity probe findings** — if Phase 6 ran: failures categorized as clarity failure vs capability limit

After writing the file, **report the chosen filename** in the user-facing output. The report must include the exact path used (e.g. `history/2026-04-28-sp-my-skill-2.md`), so the user knows which file to reference.

### Phase 8: Next steps

Offer the user these options:

- "Ready for `/beadify` to create trackable improvement work?" — when the improvement plan has actionable items
- "Want to run another pass with a different model?" — when the clarity probe revealed issues worth exploring further, or when coverage gaps remain
