# Pi Ecosystem Patterns

Use this reference for examples and design patterns observed in Pi community packages. Treat package behavior as inspiration, not an API guarantee. Review source before depending on any third-party package.

## Large external tool surfaces

Observed pattern: expose a small proxy/search/describe/call interface instead of dumping every external tool into prompt context.

Good for:

- MCP bridge extensions
- API catalogs
- local service adapters
- documentation/search tools

Design lessons:

- lazy-start expensive services
- cache metadata
- keep prompt context small
- make direct tools opt-in for high-value operations
- provide preview/dry-run for config changes

## Workflow commands and phased execution

Observed pattern: slash commands start explicit phases such as planning, review, implementation, and verification.

Design lessons:

- register slash commands as entrypoints
- load skill/prompt content for the current phase
- temporarily set active tools per phase
- block disallowed tool calls with `tool_call` guards
- restore tools/state on `agent_end`
- store plans as files for inspectability and recovery
- use human approval loops with structured feedback

## Subagent/delegation tools

Observed pattern: model role agents in markdown/config and run them via subprocess `pi` or SDK sessions.

Design lessons:

- prefer subprocess `pi` for strongest isolation and fresh context
- prefer SDK sessions when speed/shared registry matters
- define explicit role prompts and tool allowlists
- capture status, output, and errors separately
- truncate or summarize large outputs while preserving originals
- validate final-line or JSON contracts for rigorous workflows

## Interactive shell tools

Observed pattern: expose structured tools/commands around long-running TUI, REPL, or dev-server processes.

Design lessons:

- support attach/dismiss/status commands
- distinguish foreground, hands-free, dispatch, and monitor modes
- wake the agent only on relevant events
- clean up background processes on shutdown
- do not use normal `bash` when interactive state must persist

## LSP and code intelligence

Observed pattern: lazy-start language servers and expose targeted diagnostics/hover/definition/reference tools.

Design lessons:

- sync Pi reads/writes/edits to the server
- append diagnostics after edits only when useful
- expose narrow location-based tools
- avoid bloating every prompt with full diagnostic state
- handle missing language servers gracefully

## Context pruning and document parsing

Observed pattern: summarize or prune huge context while preserving originals behind query/read tools.

Design lessons:

- custom tools must truncate large output
- save full parsed documents or tool outputs to files when needed
- tell the model where full output is stored
- make preserved originals queryable
- be prompt-cache aware; pruning too often can hurt cache reuse

## Companion skill + tool pair

Observed pattern: pair a low-level tool with a companion skill that teaches when/how to use it.

Good for:

- ask/review tools
- document parsers
- security tools
- workflow packages

Design lessons:

- the tool enforces/executes
- the skill teaches methodology and trigger conditions
- both should document limitations and expected outputs

## UI/status extensions

Observed pattern: status/footer/resource-management extensions compose through named slots or scoped commands.

Design lessons:

- make state visible without requiring UI for correctness
- support command-based status for non-interactive use
- clear status widgets on shutdown
- distinguish global and project scope

## Shared ecosystem lesson

Minimize context, expose narrow operations, make state visible, support non-interactive fallback, document stable contracts, and keep package trust explicit.
