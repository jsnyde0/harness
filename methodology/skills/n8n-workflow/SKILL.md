---
name: n8n-workflow
description: >
  Build, update, and debug n8n workflows via the n8n MCP server tools
  (n8n_create_workflow, n8n_update_full_workflow, n8n_update_partial_workflow,
  n8n_get_workflow, n8n_test_workflow, etc.).
  Use when the user wants to create an n8n workflow, update n8n nodes,
  debug n8n execution errors, or automate tasks on their n8n instance.
  Also use when you see errors from n8n MCP tools or n8n Code node runtime errors.
  Do NOT use for general JavaScript questions or non-n8n automation.
---

# n8n Workflow Skill

Patterns, pitfalls, and best practices for building n8n workflows via the n8n MCP tools.

## Before you start

1. Confirm the n8n MCP server is connected (`n8n` in `.mcp.json`).
2. Run `n8n_health_check` to verify API connectivity.
3. If the health check fails after `.env` changes, tell the user to run `/mcp` to reconnect — the MCP server caches env vars at startup.

## Creating workflows

### Workflow structure

Every workflow needs:
- At least one **trigger node** (schedule, webhook, or manual)
- If you need API-triggered runs, **always add a webhook trigger** — schedule-only workflows cannot be triggered via the n8n API test endpoint
- A **Code node** for custom logic (use `n8n-nodes-base.code` with `typeVersion: 2`)
- Proper **settings**: `executionOrder: "v1"`, `timezone`, `executionTimeout`

### Use `n8n_create_workflow` for new workflows

Provide complete `nodes`, `connections`, and `settings`. The create tool returns the workflow ID — save it for subsequent operations.

### Persistent state between runs

Use `$getWorkflowStaticData('global')` inside Code nodes to store key-value data that persists across executions. Good for tracking things like "known brands" or "last processed ID" without external storage.

```javascript
const staticData = $getWorkflowStaticData('global');
if (!staticData.lastRun) {
  staticData.lastRun = new Date().toISOString();
}
// staticData is automatically saved after execution
```

## Updating workflows

### Prefer `n8n_update_full_workflow` for Code node changes

`n8n_update_partial_workflow` with `updateNode` is unreliable for large `jsCode` payloads — it often fails with "node not found" errors even when using `nodeId`. For updating Code nodes with substantial JavaScript, use `n8n_update_full_workflow` instead.

**`n8n_update_full_workflow` requires:**
- `id` — workflow ID
- `name` — workflow name (required, even if unchanged)
- `nodes` — complete array of all nodes
- `connections` — complete connections object
- `settings` — workflow settings

**Tip:** Call `n8n_get_workflow` with `mode: "full"` first to get the current state, then modify what you need and send the full payload back.

### Use `n8n_update_partial_workflow` for small changes

It works well for:
- `addNode`, `removeNode`, `moveNode`
- `addConnection`, `removeConnection`
- `updateSettings`, `updateName`
- `activateWorkflow`, `deactivateWorkflow`

For `updateNode` with simple parameter changes (not large jsCode), use `nodeId` (not `name`) to reference nodes — names with special characters (`&`, `'`, etc.) cause lookup failures.

## Code node sandbox limitations

The n8n Code node runs in a **sandboxed V8 environment**, NOT full Node.js. Many globals you'd expect are missing.

### Not available in the sandbox

| Missing global | Replacement |
|---|---|
| `URLSearchParams` | Manual: `Object.entries(params).map(([k,v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v)).join('&')` |
| `Buffer` | Use string manipulation or `btoa()`/`atob()` |
| `require()` / `import` | Not available — all code must be self-contained |
| `process`, `__dirname` | Not available — no filesystem access |
| `setTimeout` (top-level) | Wrap in async: `await new Promise(r => setTimeout(r, ms))` |

### Available in the sandbox

- `fetch()` — for HTTP requests (the primary way to call external APIs)
- `JSON`, `Date`, `Math`, `Array`, `Object` — standard JS built-ins
- `encodeURIComponent()` / `decodeURIComponent()`
- `$getWorkflowStaticData()` — persistent storage
- `$input`, `$json`, `$items()` — n8n data accessors
- `console.log()` — for debugging (visible in execution logs)

### Code node patterns

Always use `async` patterns for HTTP calls:

```javascript
async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Rate-limited fetching with retry
async function fetchWithRetry(url, retries = 0, maxRetries = 5) {
  const response = await fetch(url, {
    headers: { 'User-Agent': 'Mozilla/5.0' }
  });

  if (response.status === 429 && retries < maxRetries) {
    await sleep(15000 * (retries + 1));
    return fetchWithRetry(url, retries + 1, maxRetries);
  }

  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}
```

## Triggering and testing workflows

### Webhook triggers need UI activation

Activating a workflow via the API (`activateWorkflow` operation) does **not** register webhook listeners. The user must:
1. Open the workflow in the n8n UI
2. Either click "Test workflow" or toggle the workflow active from the UI

After that, the webhook URL becomes live at `https://<n8n-host>/webhook/<path>`.

### The n8n test API only supports certain trigger types

`n8n_test_workflow` only works with workflows that have **webhook**, **form**, or **chat** trigger nodes. It cannot trigger schedule-based workflows. If you need API-triggered test runs, add a webhook trigger node to the workflow.

### Execution timeout

For long-running workflows (e.g., scraping many pages), set `executionTimeout` in settings (in seconds). Default is usually 300s. Set it higher for workflows that do pagination with rate limiting.

## Debugging execution errors

When the user reports an n8n error:

1. **Get the workflow**: `n8n_get_workflow` with `mode: "full"` to see current code
2. **Check recent executions**: `n8n_executions` to see execution logs and error details
3. **Common error patterns**:

| Error message | Cause | Fix |
|---|---|---|
| `X is not defined` | Sandbox doesn't have that global | Replace with sandbox-compatible alternative (see table above) |
| `fetch is not a function` | Very old n8n version | Upgrade n8n or use the HTTP Request node instead |
| `Cannot read properties of undefined` | API response structure changed | Add null checks: `data?.products \|\| []` |
| Timeout errors | Execution took too long | Increase `executionTimeout` in settings |
| `$getWorkflowStaticData is not a function` | Wrong Code node version | Use `typeVersion: 2` for Code nodes |

## MCP connection issues

| Problem | Fix |
|---|---|
| n8n MCP auth fails after `.env` change | Run `/mcp` to reconnect — MCP server caches env vars at startup |
| `dotenv` package not found | The npm package is `dotenv-cli`, not `dotenv` |
| API key format wrong | n8n API keys are JWTs starting with `eyJ...` |

## Team-friendly MCP setup

Keep secrets out of `.mcp.json` (which is committed) by using `dotenv-cli`:

```json
{
  "n8n": {
    "command": "npx",
    "args": ["dotenv-cli", "-e", ".env", "--", "npx", "n8n-mcp"],
    "env": {
      "MCP_MODE": "stdio",
      "LOG_LEVEL": "error",
      "DISABLE_CONSOLE_OUTPUT": "true"
    }
  }
}
```

Then `.env` (gitignored) contains:
```
N8N_API_URL=https://your-n8n-instance.com/
N8N_API_KEY=eyJ...
```
