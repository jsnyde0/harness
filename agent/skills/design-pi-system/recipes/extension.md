# Extension Recipe

Use this recipe when the smallest reliable Pi-native layer is TypeScript code loaded by Pi.

## Use an extension for

- Agent-callable custom tools via `pi.registerTool()`.
- User slash commands via `pi.registerCommand()`.
- Enforced behavior via event hooks such as `tool_call`, `user_bash`, `before_agent_start`, `context`, or `agent_end`.
- UI/status/confirmation flows through `ctx.ui`.
- Thin adapters around CLIs/libraries that own durable domain logic.

## Avoid using an extension for

- Pure methodology or taste: use a skill.
- Static reusable prompts: use a prompt template.
- Logic that should be shared with humans/scripts/CI: put that logic in a CLI/library and wrap it thinly.
- Invisible large workflows that the user cannot inspect or interrupt.

## Minimal shape

```ts
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerTool(...);
  pi.registerCommand(...);
  pi.on("tool_call", async (event, ctx) => { ... });
}
```

## Checklist

- Narrow schemas and explicit descriptions for model-facing tools.
- Tool results are concise and truncate large output.
- Mutating tools guard paths and use safe read/modify/write semantics.
- Hooks ignore quickly when out of scope.
- Failure policy is explicit: fail-open for convenience, fail-closed for safety.
- UI is helpful but not required for correctness.
- Runtime/private state stays out of git.
- Tests/evals cover policy, config, parsing, timeout, and missing dependencies.
