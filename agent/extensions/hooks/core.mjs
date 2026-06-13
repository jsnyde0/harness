/**
 * Generic hooks-manifest runner for pi.
 *
 * Loops a hooks-manifest and wires each entry via pi.on(entry.piEvent) -> pi.exec(entry.script).
 * Fully generic: no hardcoded event names, script names, or per-matcher code branches.
 * The toolNames field in each manifest entry is the pi-native filter (table-driven data).
 *
 * Manifest schema (agent/hooks-manifest.json):
 *   {
 *     "hooks": [
 *       {
 *         "ccEvent":       "PreToolUse",          // CC event name (data; for documentation)
 *         "matcher":       "Bash",                // CC matcher pattern (data; for documentation)
 *         "piEvent":       "tool_call",           // pi event to subscribe to
 *         "toolNames":     ["bash"],              // pi toolName filter ([] = all tools)
 *         "script":        "dcg",                 // executable to run
 *         "scriptArgs":    ["test", "--format", "json"],  // static CLI args
 *         "inputArgField": "command",             // optional: append event.input[field] as last arg
 *         "outputFormat":  "json"                 // optional: "json" → check for decision:deny in stdout
 *       }
 *     ]
 *   }
 */

import os from "node:os";
import path from "node:path";

/**
 * Resolve script path prefixes to absolute paths.
 *
 * Handles portable prefix conventions:
 *   $CLAUDE_HOME/<rest>    → <homedir>/.claude/<rest>
 *   $DOTPI_AGENT_DIR/<rest>→ <homedir>/.pi/agent/<rest>
 *   ~/<rest>               → <homedir>/<rest>
 *
 * Plain binaries (e.g. "dcg") and absolute paths pass through unchanged.
 * $CLAUDE_HOME and $DOTPI_AGENT_DIR are unset in every shell at runtime —
 * resolving them here ensures pi.exec receives an absolute path.
 *
 * @param {string} script
 * @returns {string}
 */
export function resolveScriptPath(script) {
  if (script.startsWith("$CLAUDE_HOME/")) {
    return path.join(os.homedir(), ".claude", script.slice("$CLAUDE_HOME/".length));
  }
  if (script.startsWith("$DOTPI_AGENT_DIR/")) {
    return path.join(os.homedir(), ".pi", "agent", script.slice("$DOTPI_AGENT_DIR/".length));
  }
  if (script.startsWith("~/")) {
    return path.join(os.homedir(), script.slice(2));
  }
  return script;
}

/**
 * Validate a manifest object.
 * @param {unknown} raw
 * @returns {import("./types.mjs").HooksManifest}
 * @throws {Error} if invalid
 */
export function validateManifest(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("invalid manifest: must be an object");
  }
  if (!Array.isArray(raw.hooks)) {
    throw new Error("invalid manifest: hooks must be an array");
  }
  for (const entry of raw.hooks) {
    // piEvent is OPTIONAL: absent/null means CC-only (no pi analog) — skip validation for those fields.
    const hasPiEvent = typeof entry.piEvent === "string" && entry.piEvent;
    if (hasPiEvent) {
      if (typeof entry.script !== "string" || !entry.script) {
        throw new Error(`invalid manifest entry: script must be a non-empty string (got ${JSON.stringify(entry.script)})`);
      }
      if (!Array.isArray(entry.toolNames)) {
        throw new Error(`invalid manifest entry: toolNames must be an array (got ${JSON.stringify(entry.toolNames)})`);
      }
    }
  }
  return raw;
}

/**
 * Try to parse a string as JSON, returning undefined on failure.
 * @param {string} text
 * @returns {unknown | undefined}
 */
function tryParseJson(text) {
  const trimmed = typeof text === "string" ? text.trim() : "";
  if (!trimmed) return undefined;
  try {
    return JSON.parse(trimmed);
  } catch {
    return undefined;
  }
}

/**
 * Build the reason string from a block result.
 * @param {import("./types.mjs").ExecResult} result
 * @param {unknown} parsed
 * @returns {string}
 */
function buildBlockReason(result, parsed) {
  if (parsed && typeof parsed === "object" && typeof parsed.reason === "string") {
    return parsed.reason;
  }
  if (result.stderr) return result.stderr;
  if (result.stdout) return result.stdout;
  return `script exited with code ${result.code}`;
}

/**
 * Protocol adapters — table-driven enum: outputFormat → adapter function.
 *
 * Each adapter receives (result, entry, event) and returns a result appropriate for the event type,
 * or undefined on allow/no-op.
 * Adding a new hook that uses an existing protocol requires ZERO code changes here.
 * Adding a NEW protocol requires adding one entry to this map.
 *
 * outputFormat values:
 *   undefined / "exit-code"      — default: non-zero exit → block (tool_call)
 *   "json"                       — dcg protocol: stdout JSON with decision:"deny" → block (fallthrough to exit-code)
 *   "cc-hook"                    — Claude Code hook protocol: stdout JSON with
 *                                  hookSpecificOutput.permissionDecision:"deny"|"ask" → block;
 *                                  exit code 2 or non-zero → block; exit 0 + no deny → allow
 *   "system-prompt-append"       — before_agent_start protocol: stdout text appended to event.systemPrompt;
 *                                  non-zero exit → undefined (skip, never block session start)
 */

/** @type {Record<string, (result: import("./types.mjs").ExecResult, parsed: unknown, event?: unknown) => unknown>} */
const OUTPUT_ADAPTERS = {
  /**
   * dcg-json protocol: stdout JSON with decision:"deny" → block.
   * Falls through to the exit-code check if no deny signal in JSON.
   */
  json(result, parsed) {
    if (parsed && typeof parsed === "object" && parsed.decision === "deny") {
      return { block: true, reason: buildBlockReason(result, parsed) };
    }
    // Fall through to exit-code check
    return undefined;
  },

  /**
   * system-prompt-append protocol: before_agent_start injection.
   * - Exit 0: append stdout to event.systemPrompt, return { systemPrompt: combined }
   * - Non-zero exit: return undefined (skip injection; never block session start)
   *
   * @param {import("./types.mjs").ExecResult} result
   * @param {unknown} _parsed
   * @param {unknown} event - the before_agent_start event with .systemPrompt
   */
  "system-prompt-append"(result, _parsed, event) {
    if (result.code !== 0 || result.killed) {
      return undefined; // Skip; never block session start
    }
    const injectedText = result.stdout.trim();
    if (!injectedText) return undefined;
    // SINGLE-HANDLER ASSUMPTION: reads event.systemPrompt, which reflects the
    // value at the time this handler was called. If a second before_agent_start
    // handler is ever added, each handler sees the ORIGINAL event.systemPrompt
    // (pi does not thread-update the event between handlers), so only the last
    // handler's injection survives — earlier injections are silently dropped.
    // Multi-handler chaining would require a reduce pass over ordered handlers
    // (accumulating systemPrompt across results) or pi runtime cooperation
    // (pi updating event.systemPrompt after each handler returns). Today there
    // is exactly one system-prompt-append handler, so this does not bite.
    const currentPrompt = (event && typeof event === "object" && typeof event.systemPrompt === "string")
      ? event.systemPrompt
      : "";
    return { systemPrompt: currentPrompt + "\n\n" + injectedText };
  },

  /**
   * cc-hook protocol: Claude Code hook I/O contract.
   * - Block if stdout JSON contains hookSpecificOutput.permissionDecision in {"deny","ask"}
   * - Block if exit code is non-zero (including exit 2 — CC's explicit block code)
   * - Allow if exit 0 and no block signal in stdout
   * Scripts stay unchanged (do NOT rewrite methodology-home hook scripts).
   */
  "cc-hook"(result, parsed) {
    // Check stdout JSON for CC block signal
    if (parsed && typeof parsed === "object") {
      const hso = parsed.hookSpecificOutput;
      if (hso && typeof hso === "object") {
        const decision = hso.permissionDecision;
        if (decision === "deny" || decision === "ask") {
          const reason =
            typeof hso.permissionDecisionReason === "string"
              ? hso.permissionDecisionReason
              : buildBlockReason(result, parsed);
          return { block: true, reason };
        }
      }
    }
    // Exit code non-zero (CC convention: 2 = explicit block, any non-zero = error/block)
    if (result.code !== 0 || result.killed) {
      return { block: true, reason: buildBlockReason(result, undefined) };
    }
    // Exit 0 + no block signal → allow
    return undefined;
  },
};

/**
 * Wire all manifest entries to the pi extension API.
 * Generic: no hardcoded event names, script names, or per-matcher code branches.
 *
 * @param {object} pi - pi ExtensionAPI (or test mock)
 * @param {import("./types.mjs").HooksManifest} manifest
 * @param {{ spawnStdin?: (script: string, args: string[], stdinPayload: string) => Promise<import("./types.mjs").ExecResult> }} [options]
 */
export function wireManifest(pi, manifest, options = {}) {
  const { spawnStdin } = options;

  for (const entry of manifest.hooks) {
    const {
      piEvent,
      toolNames,
      scriptArgs = [],
      inputArgField,
      outputFormat,
    } = entry;

    // CC-only entries (absent/null piEvent) have no pi analog — skip silently.
    if (!piEvent || typeof piEvent !== "string") {
      continue;
    }

    // Resolve prefix tokens ($CLAUDE_HOME/, $DOTPI_AGENT_DIR/, ~/) to absolute paths.
    // The manifest uses portable prefixes; these env vars are unset at pi runtime.
    // Plain binaries (e.g. "dcg") and absolute paths pass through unchanged.
    // Must be called after the CC-only guard: CC-only entries have no script field.
    const script = resolveScriptPath(entry.script);

    pi.on(piEvent, async (event, _ctx) => {
      // Table-driven toolNames filter:
      // - empty array [] means "all tools" (wildcard)
      // - non-empty array means "only these toolNames"
      if (toolNames.length > 0 && !toolNames.includes(event.toolName)) {
        return undefined;
      }

      let result;

      if (outputFormat === "cc-hook") {
        // CC-hook protocol: pass the full event.input as tool_input JSON on stdin.
        // The script reads INPUT=$(cat) and extracts e.g. .tool_input.command or .tool_input.file_path.
        const stdinPayload = JSON.stringify({
          tool_name: event.toolName,
          tool_input: event.input ?? {},
        });
        const execWithStdin = spawnStdin ?? defaultSpawnStdin;
        result = await execWithStdin(script, scriptArgs, stdinPayload);
      } else {
        // Standard protocols: build CLI args and use pi.exec
        const inputArg =
          inputArgField != null && event.input != null
            ? event.input[inputArgField]
            : undefined;
        const args = [
          ...scriptArgs,
          ...(inputArg != null ? [String(inputArg)] : []),
        ];
        result = await pi.exec(script, args);
      }

      // Select the output adapter by outputFormat (table-driven enum)
      const adapter = outputFormat != null ? OUTPUT_ADAPTERS[outputFormat] : undefined;
      if (adapter) {
        const parsed = tryParseJson(result.stdout);
        const adapterResult = adapter(result, parsed, event);
        if (adapterResult) return adapterResult;
        // Adapters that don't return a block result may still fall through to exit-code check.
        // cc-hook and system-prompt-append handle their own exit-code checks, so we don't fall through.
        if (outputFormat === "cc-hook" || outputFormat === "system-prompt-append") return undefined;
      }

      // Exit-code protocol (default + json fallthrough): non-zero exit → block
      if (result.code !== 0 || result.killed) {
        return { block: true, reason: buildBlockReason(result, undefined) };
      }

      return undefined;
    });
  }
}

// ---------------------------------------------------------------------------
// Default spawnStdin implementation using Node.js child_process.
// Used in production (not in tests, which inject a fake via options.spawnStdin).
// ---------------------------------------------------------------------------

/**
 * Spawn a subprocess, write stdinPayload to its stdin, and return stdout/stderr/code.
 * Used by the cc-hook adapter to pass the CC hook input JSON to shell scripts.
 *
 * @param {string} script
 * @param {string[]} args
 * @param {string} stdinPayload
 * @returns {Promise<import("./types.mjs").ExecResult>}
 */
async function defaultSpawnStdin(script, args, stdinPayload) {
  const { spawn } = await import("node:child_process");
  return new Promise((resolve) => {
    const proc = spawn(script, args, {
      shell: false,
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    let killed = false;

    proc.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    proc.stderr.on("data", (chunk) => { stderr += chunk.toString(); });

    proc.on("close", (code) => {
      resolve({ stdout, stderr, code: code ?? 0, killed });
    });

    proc.on("error", (err) => {
      resolve({ stdout, stderr, code: 1, killed: false });
    });

    // Write stdin and close it so the script's `cat` unblocks
    proc.stdin.write(stdinPayload);
    proc.stdin.end();
  });
}
