/**
 * Tests for the generic hooks-manifest runner.
 *
 * Tests cover:
 * 1. Runner loops a manifest with >=1 entry and wires pi.on(piEvent) for each
 * 2. Adding a second manifest entry wires it with ZERO runner code change
 * 3. matcher->toolNames translation is table-driven (manifest data, no runner code branches)
 * 4. Generic exec is called with the right args when an event fires
 * 5. Block response is returned when exec exits non-zero
 * 6. Block response is returned when JSON output contains decision:deny
 */

import assert from "node:assert/strict";
import { test } from "node:test";
import { wireManifest, validateManifest, resolveScriptPath } from "./core.mjs";

// ---------------------------------------------------------------------------
// Helpers: minimal pi mock
// ---------------------------------------------------------------------------

function makePiMock() {
  const registeredHandlers = new Map(); // piEvent -> handler[]
  const execCalls = []; // { script, args } recorded calls

  const pi = {
    on(event, handler) {
      if (!registeredHandlers.has(event)) registeredHandlers.set(event, []);
      registeredHandlers.get(event).push(handler);
    },
    async exec(script, args, _opts) {
      execCalls.push({ script, args });
      // Default: success
      return { stdout: "", stderr: "", code: 0, killed: false };
    },
    registeredHandlers,
    execCalls,
  };
  return pi;
}

// Fire a pi event through registered handlers (returns array of results)
async function fireEvent(pi, piEvent, eventObj) {
  const handlers = pi.registeredHandlers.get(piEvent) ?? [];
  const results = [];
  for (const h of handlers) {
    results.push(await h(eventObj, {}));
  }
  return results;
}

// ---------------------------------------------------------------------------
// Test 1: Runner registers pi.on for each manifest entry (≥1 entry)
// ---------------------------------------------------------------------------

test("wires pi.on for each manifest entry", async () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "my-script.sh",
        scriptArgs: ["--check"],
      },
    ],
  };

  const pi = makePiMock();
  wireManifest(pi, manifest);

  // pi.on("tool_call", ...) must have been called once
  assert.ok(pi.registeredHandlers.has("tool_call"), "should register tool_call handler");
  assert.equal(pi.registeredHandlers.get("tool_call").length, 1, "should register exactly one handler");
});

// ---------------------------------------------------------------------------
// Test 2: A second manifest entry wires with ZERO runner code change
// (Runner is called with a 2-entry manifest; both entries produce distinct
//  handlers — the loop is data-driven)
// ---------------------------------------------------------------------------

test("wires two manifest entries with zero runner code change", async () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "script-a.sh",
        scriptArgs: [],
      },
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "script-b.sh",
        scriptArgs: [],
      },
    ],
  };

  const pi = makePiMock();
  wireManifest(pi, manifest);

  // Both handlers registered under tool_call
  assert.ok(pi.registeredHandlers.has("tool_call"));
  assert.equal(pi.registeredHandlers.get("tool_call").length, 2, "two entries → two handlers");

  // Fire a bash tool_call; both scripts should be exec'd
  await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "bash",
    toolCallId: "test-1",
    input: { command: "echo hello" },
  });

  const scripts = pi.execCalls.map((c) => c.script);
  assert.ok(scripts.includes("script-a.sh"), "script-a.sh exec'd");
  assert.ok(scripts.includes("script-b.sh"), "script-b.sh exec'd");
});

// ---------------------------------------------------------------------------
// Test 3: toolNames filter is table-driven — handler only fires for matching toolNames
// ---------------------------------------------------------------------------

test("toolNames filter uses manifest data, not hardcoded branches", async () => {
  // Two entries: one for "bash" only, one for "read" only
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "bash-hook.sh",
        scriptArgs: [],
      },
      {
        ccEvent: "PreToolUse",
        matcher: "Read",
        piEvent: "tool_call",
        toolNames: ["read"],
        script: "read-hook.sh",
        scriptArgs: [],
      },
    ],
  };

  const pi = makePiMock();
  wireManifest(pi, manifest);

  // Fire a "bash" tool_call
  await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "bash",
    toolCallId: "t1",
    input: { command: "ls" },
  });

  let execScripts = pi.execCalls.map((c) => c.script);
  assert.ok(execScripts.includes("bash-hook.sh"), "bash hook fires for bash tool_call");
  assert.ok(!execScripts.includes("read-hook.sh"), "read hook does NOT fire for bash tool_call");

  // Reset exec calls
  pi.execCalls.length = 0;

  // Fire a "read" tool_call
  await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "read",
    toolCallId: "t2",
    input: { file_path: "/tmp/test.txt" },
  });

  execScripts = pi.execCalls.map((c) => c.script);
  assert.ok(!execScripts.includes("bash-hook.sh"), "bash hook does NOT fire for read tool_call");
  assert.ok(execScripts.includes("read-hook.sh"), "read hook fires for read tool_call");
});

// ---------------------------------------------------------------------------
// Test 4: Empty toolNames array means "all tools" (wildcard matcher)
// ---------------------------------------------------------------------------

test("empty toolNames array means all tools (wildcard)", async () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "",
        piEvent: "tool_call",
        toolNames: [],
        script: "wildcard-hook.sh",
        scriptArgs: [],
      },
    ],
  };

  const pi = makePiMock();
  wireManifest(pi, manifest);

  await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "bash",
    toolCallId: "t1",
    input: { command: "ls" },
  });

  await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "read",
    toolCallId: "t2",
    input: { file_path: "/tmp/x" },
  });

  assert.equal(pi.execCalls.length, 2, "wildcard hook fires for all tool types");
});

// ---------------------------------------------------------------------------
// Test 5: inputArgField passes the named field from event.input as last CLI arg
// ---------------------------------------------------------------------------

test("inputArgField appends named event.input field as last CLI arg", async () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "dcg",
        scriptArgs: ["test", "--format", "json"],
        inputArgField: "command",
      },
    ],
  };

  const pi = makePiMock();
  wireManifest(pi, manifest);

  await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "bash",
    toolCallId: "t1",
    input: { command: "echo hello" },
  });

  assert.equal(pi.execCalls.length, 1);
  assert.deepEqual(pi.execCalls[0].args, ["test", "--format", "json", "echo hello"],
    "command from event.input appended as last arg");
});

// ---------------------------------------------------------------------------
// Test 6: Non-zero exit code → block: true
// ---------------------------------------------------------------------------

test("non-zero exit code produces block:true result", async () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "guard.sh",
        scriptArgs: [],
        inputArgField: "command",
      },
    ],
  };

  const pi = makePiMock();
  // Override exec to return non-zero
  pi.exec = async (script, args) => {
    pi.execCalls.push({ script, args });
    return { stdout: "", stderr: "denied", code: 1, killed: false };
  };

  wireManifest(pi, manifest);

  const results = await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "bash",
    toolCallId: "t1",
    input: { command: "rm -rf /" },
  });

  assert.ok(results[0]?.block === true, "should return block:true on non-zero exit");
});

// ---------------------------------------------------------------------------
// Test 7: JSON output with decision:deny → block: true (dcg protocol support)
// ---------------------------------------------------------------------------

test("JSON output with decision:deny produces block:true when outputFormat is json", async () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "dcg",
        scriptArgs: ["test", "--format", "json"],
        inputArgField: "command",
        outputFormat: "json",
      },
    ],
  };

  const pi = makePiMock();
  pi.exec = async (script, args) => {
    pi.execCalls.push({ script, args });
    // dcg returns code 0 but decision:deny
    return {
      stdout: JSON.stringify({ decision: "deny", reason: "compound command blocked", rule_id: "compound" }),
      stderr: "",
      code: 0,
      killed: false,
    };
  };

  wireManifest(pi, manifest);

  const results = await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "bash",
    toolCallId: "t1",
    input: { command: "echo a && echo b" },
  });

  assert.ok(results[0]?.block === true, "decision:deny → block:true");
  assert.ok(typeof results[0]?.reason === "string", "reason should be a string");
});

// ---------------------------------------------------------------------------
// Test 8: validateManifest rejects invalid schema
// ---------------------------------------------------------------------------

test("validateManifest rejects manifest without hooks array", () => {
  assert.throws(() => validateManifest({}), /invalid manifest/i);
  assert.throws(() => validateManifest({ hooks: "not-an-array" }), /invalid manifest/i);
});

test("validateManifest accepts valid manifest", () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "dcg",
        scriptArgs: ["test", "--format", "json"],
        inputArgField: "command",
        outputFormat: "json",
      },
    ],
  };
  // Should not throw
  const result = validateManifest(manifest);
  assert.ok(Array.isArray(result.hooks));
});

// ---------------------------------------------------------------------------
// Test 9: cc-hook outputFormat — runner feeds stdin JSON and checks
//         hookSpecificOutput.permissionDecision for block signal
//
// The runner MUST support the cc-hook protocol as a first-class adapter:
//   - Input:  JSON on STDIN → {tool_name, tool_input:{command}}
//   - Output: stdout JSON with hookSpecificOutput.permissionDecision:"deny" → block:true
//   - Exit 0 is NOT a pass signal when outputFormat is cc-hook
// ---------------------------------------------------------------------------

test("cc-hook: stdout permissionDecision:deny → block:true (subprocess gets stdin)", async () => {
  // Manifest entry with outputFormat cc-hook (like block-compound-commands.sh)
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "/fake/block-compound.sh",
        scriptArgs: [],
        inputArgField: "command",
        outputFormat: "cc-hook",
      },
    ],
  };

  const receivedStdin = [];

  // Inject a fake spawnStdin that records the stdin payload and returns a deny response
  function fakeSpawnStdin(script, args, stdinPayload) {
    receivedStdin.push({ script, args, stdinPayload });
    // Simulate cc-hook deny output (like block-compound-commands.sh)
    const stdout = JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Split into separate Bash calls:\n(1) echo a\n(2) echo b",
      },
    });
    return Promise.resolve({ stdout, stderr: "", code: 0, killed: false });
  }

  const pi = makePiMock();
  wireManifest(pi, manifest, { spawnStdin: fakeSpawnStdin });

  const results = await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "bash",
    toolCallId: "t1",
    input: { command: "echo a && echo b" },
  });

  // Block must be true
  assert.ok(results[0]?.block === true, "cc-hook permissionDecision:deny → block:true");

  // Stdin must have been passed as a JSON object with tool_input.command
  assert.equal(receivedStdin.length, 1, "spawnStdin called once");
  const payload = JSON.parse(receivedStdin[0].stdinPayload);
  assert.equal(
    payload.tool_input?.command,
    "echo a && echo b",
    "stdin payload carries tool_input.command from event.input.command",
  );
});

test("cc-hook: stdout permissionDecision:ask → block:true (no user prompt in pi)", async () => {
  // restrict-sensitive-paths.sh outputs "ask" not "deny" — in pi, treat as block
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Read",
        piEvent: "tool_call",
        toolNames: ["read"],
        script: "/fake/restrict-sensitive-paths.sh",
        scriptArgs: [],
        inputArgField: "file_path",
        outputFormat: "cc-hook",
      },
    ],
  };

  function fakeSpawnStdin(script, args, stdinPayload) {
    const stdout = JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: "Access denied: sensitive file",
      },
    });
    return Promise.resolve({ stdout, stderr: "", code: 0, killed: false });
  }

  const pi = makePiMock();
  wireManifest(pi, manifest, { spawnStdin: fakeSpawnStdin });

  const results = await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "read",
    toolCallId: "t2",
    input: { file_path: "/home/user/.ssh/id_rsa" },
  });

  assert.ok(results[0]?.block === true, "cc-hook permissionDecision:ask → block:true in pi");
});

test("cc-hook: stdin payload contains tool_input with correct field for file_path entries", async () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Read",
        piEvent: "tool_call",
        toolNames: ["read"],
        script: "/fake/restrict-sensitive-paths.sh",
        scriptArgs: [],
        inputArgField: "file_path",
        outputFormat: "cc-hook",
      },
    ],
  };

  const receivedStdin = [];

  function fakeSpawnStdin(script, args, stdinPayload) {
    receivedStdin.push(stdinPayload);
    // Simulate allow (no deny)
    return Promise.resolve({ stdout: "", stderr: "", code: 0, killed: false });
  }

  const pi = makePiMock();
  wireManifest(pi, manifest, { spawnStdin: fakeSpawnStdin });

  await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "read",
    toolCallId: "t3",
    input: { file_path: "/tmp/safe.txt" },
  });

  assert.equal(receivedStdin.length, 1);
  const payload = JSON.parse(receivedStdin[0]);
  assert.equal(payload.tool_input?.file_path, "/tmp/safe.txt", "stdin carries tool_input.file_path");
});

test("cc-hook: exit code 2 → block:true (CC block-by-exit-code convention)", async () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "/fake/hook.sh",
        scriptArgs: [],
        outputFormat: "cc-hook",
      },
    ],
  };

  function fakeSpawnStdin() {
    return Promise.resolve({ stdout: "", stderr: "blocked", code: 2, killed: false });
  }

  const pi = makePiMock();
  wireManifest(pi, manifest, { spawnStdin: fakeSpawnStdin });

  const results = await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "bash",
    toolCallId: "t4",
    input: { command: "echo hi" },
  });

  assert.ok(results[0]?.block === true, "cc-hook exit code 2 → block:true");
});

test("cc-hook: exit code 0 + no deny in stdout → allow (no block)", async () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "/fake/hook.sh",
        scriptArgs: [],
        outputFormat: "cc-hook",
      },
    ],
  };

  function fakeSpawnStdin() {
    return Promise.resolve({ stdout: "", stderr: "", code: 0, killed: false });
  }

  const pi = makePiMock();
  wireManifest(pi, manifest, { spawnStdin: fakeSpawnStdin });

  const results = await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "bash",
    toolCallId: "t5",
    input: { command: "echo hello" },
  });

  assert.ok(results[0] == null, "cc-hook exit 0 + no deny stdout → allow (undefined)");
});

test("cc-hook: adding a new entry with cc-hook protocol needs zero runner code change", async () => {
  // Prove: a NEW cc-hook entry (different script, different field) wires without runner changes.
  // This is the table-driven invariant for the cc-hook protocol enum slot.
  const manifest = {
    hooks: [
      {
        ccEvent: "PreToolUse",
        matcher: "Write",
        piEvent: "tool_call",
        toolNames: ["write"],
        script: "/fake/new-hook.sh",
        scriptArgs: [],
        inputArgField: "new_field",
        outputFormat: "cc-hook",
      },
    ],
  };

  const receivedPayloads = [];

  function fakeSpawnStdin(script, args, stdinPayload) {
    receivedPayloads.push(JSON.parse(stdinPayload));
    return Promise.resolve({ stdout: "", stderr: "", code: 0, killed: false });
  }

  const pi = makePiMock();
  wireManifest(pi, manifest, { spawnStdin: fakeSpawnStdin });

  await fireEvent(pi, "tool_call", {
    type: "tool_call",
    toolName: "write",
    toolCallId: "t6",
    input: { new_field: "some-value" },
  });

  assert.equal(receivedPayloads.length, 1, "new cc-hook entry wired with zero runner code change");
  assert.equal(
    receivedPayloads[0].tool_input?.new_field,
    "some-value",
    "stdin carries the correct inputArgField",
  );
});

// ---------------------------------------------------------------------------
// Test: pi runner skips CC-only entries (absent/null piEvent) without error
//
// CC lifecycle events (SessionStart, SessionEnd, PreCompact, Stop, PermissionRequest)
// have no pi analog and have no piEvent field in the manifest.
// The runner must skip these entries silently rather than throwing.
// ---------------------------------------------------------------------------

test("validateManifest accepts entry with absent piEvent (CC-only lifecycle event)", () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "SessionStart",
        // No piEvent — CC-only entry
        description: "CC lifecycle event with no pi analog",
      },
    ],
  };
  // Should not throw
  const result = validateManifest(manifest);
  assert.ok(Array.isArray(result.hooks));
  assert.equal(result.hooks.length, 1);
});

test("validateManifest accepts entry with null piEvent (CC-only lifecycle event)", () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "Stop",
        piEvent: null,
        description: "CC lifecycle event with null piEvent",
      },
    ],
  };
  // Should not throw
  const result = validateManifest(manifest);
  assert.ok(Array.isArray(result.hooks));
});

test("wireManifest skips CC-only entries (no piEvent) without registering pi.on or erroring", () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "SessionStart",
        // No piEvent — CC-only
        description: "sync-memory-in.sh on session start",
      },
      {
        ccEvent: "PreToolUse",
        matcher: "Bash",
        piEvent: "tool_call",
        toolNames: ["bash"],
        script: "my-script.sh",
        scriptArgs: [],
      },
    ],
  };

  const pi = makePiMock();
  // Should not throw
  wireManifest(pi, manifest);

  // Only the PreToolUse entry should register a handler; SessionStart (no piEvent) skipped
  assert.ok(pi.registeredHandlers.has("tool_call"), "PreToolUse entry registers tool_call handler");
  assert.equal(pi.registeredHandlers.size, 1, "no extra handlers registered for CC-only entry");
});

test("wireManifest skips CC-only entry with null piEvent without error", () => {
  const manifest = {
    hooks: [
      {
        ccEvent: "Stop",
        piEvent: null,
        description: "CC-only stop hook",
      },
    ],
  };

  const pi = makePiMock();
  // Should not throw and should not register any handler
  wireManifest(pi, manifest);

  assert.equal(pi.registeredHandlers.size, 0, "no handlers registered for CC-only entry with null piEvent");
});

// ---------------------------------------------------------------------------
// Test: resolveScriptPath — $CLAUDE_HOME/ and ~/ prefix resolution
//
// Context A fix: scripts with $CLAUDE_HOME/ prefix must resolve to
// <homedir>/.claude/<rest> so pi.exec receives an absolute path.
// This prevents broken hook paths when $CLAUDE_HOME is unset at runtime.
// ---------------------------------------------------------------------------

import os from "node:os";

test("resolveScriptPath: $CLAUDE_HOME/ prefix resolves to <homedir>/.claude/", () => {
  const result = resolveScriptPath("$CLAUDE_HOME/hooks/block-compound-commands.sh");
  const expected = os.homedir() + "/.claude/hooks/block-compound-commands.sh";
  assert.equal(result, expected,
    `$CLAUDE_HOME/hooks/block-compound-commands.sh must resolve to ${expected}, got: ${result}`);
});

test("resolveScriptPath: ~/ prefix resolves to <homedir>/", () => {
  const result = resolveScriptPath("~/hooks/foo.sh");
  const expected = os.homedir() + "/hooks/foo.sh";
  assert.equal(result, expected,
    `~/hooks/foo.sh must resolve to ${expected}, got: ${result}`);
});

test("resolveScriptPath: plain binary (no prefix) passes through unchanged", () => {
  const result = resolveScriptPath("dcg");
  assert.equal(result, "dcg",
    "plain binary name must pass through unchanged");
});

test("resolveScriptPath: absolute path passes through unchanged", () => {
  const result = resolveScriptPath("/usr/local/bin/dcg");
  assert.equal(result, "/usr/local/bin/dcg",
    "absolute path must pass through unchanged");
});

console.log("hooks runner tests loaded");
