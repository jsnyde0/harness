# Testing and Evaluation for Pi Extensions and Skills

Use this reference when a Pi skill, extension, package, prompt template, or workflow has enough complexity to regress.

## Skill trigger evals

Create realistic prompts that:

- should trigger the skill
- should not trigger the skill
- are terse or ambiguous but should still trigger
- are near misses that should not trigger
- mention adjacent ecosystems like Claude Code, MCP, or Cursor and should be translated to Pi-native primitives

Record expected behavior in simple fixtures so future edits to `description` or `SKILL.md` can be checked.

## Behavior evals

For each important behavior, define:

- prompt
- input files/config
- expected output or design shape
- objective assertions
- forbidden behaviors
- old-vs-new or with-skill-vs-without-skill comparison

Good assertions are concrete: chosen Pi primitive, security decision, generated file path, package layout, tool schema, CLI contract, or final-line marker.

## Extension unit tests

Test deterministic logic outside Pi first:

- policy allow/block functions
- path resolution and symlink handling
- config loading, defaults, validation, unknown-key handling
- CLI wrapper parsing and exit-code mapping
- output truncation behavior
- timeout/cancellation behavior
- redaction of secrets in logs/errors
- fallback/fail-open/fail-closed logic

Keep Pi-specific glue thin so most behavior can be tested without launching Pi.

## Custom tool integration checks

Manually or automatically validate:

- TypeBox schema rejects invalid parameters
- `promptSnippet` and `promptGuidelines` are concise and accurate
- large outputs are truncated and full output location is reported
- failed execution throws from `execute()` and appears to the model as an error
- file mutations use `withFileMutationQueue()` over the whole read/modify/write window
- structured `details` are useful but not huge

## Extension/Pi integration checks

Validate in the modes users will actually use:

- interactive TUI
- non-interactive print mode, if relevant
- JSON/RPC mode, if relevant
- missing dependency/config cases
- cancellation/abort behavior
- protected path and dirty repo behavior
- conflicting or missing extensions
- `/reload` behavior from auto-discovered paths
- startup/shutdown cleanup (`agent_end`, footer/status widgets, background processes)

## Subagent/workflow evals

For subprocess Pi or SDK subagent workflows, test:

- tool allowlists per role/phase
- parseable final outputs
- timeout handling
- partial failure behavior in parallel tasks
- preservation of original subagent output when summarized/truncated
- isolation of session files/artifacts
- restoration of model/thinking/tool state after workflow completion

## Regression practice

When changing a skill or extension:

1. Add or update a fixture for the issue being fixed.
2. Run deterministic tests first.
3. Run a small manual Pi smoke test.
4. Check output size and prompt-context impact.
5. Document any intentional behavior change in README or design notes.
