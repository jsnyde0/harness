/**
 * Schema validation tests for hooks-manifest.schema.json
 *
 * Verifies that the tightened oneOf schema:
 * 1. Still validates the real hooks-manifest.json (all 9 entries)
 * 2. Rejects garbage entries:
 *    (a) {} — no fields at all
 *    (b) {ccEvent:"X"} — ccEvent but neither script nor ccHooks
 *    (c) ccHooks not an array of {type,command}
 *
 * Uses Ajv v8 (draft-2019-09 / draft-07 compat) from global node_modules.
 * NOTE: Ajv v8 defaults to draft-2019-09. For draft-07, we use addSchema with
 * the correct meta-schema or just use the validator directly.
 */

import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

// ---------------------------------------------------------------------------
// Bootstrap: load Ajv from global node_modules (happy-coder installs it)
// ---------------------------------------------------------------------------

const require = createRequire(import.meta.url);

// Try to find Ajv — first local, then global
let Ajv;
try {
  Ajv = require("ajv");
} catch {
  try {
    Ajv = require("/opt/homebrew/lib/node_modules/happy-coder/node_modules/ajv");
  } catch (e) {
    throw new Error(`Cannot find Ajv: ${e.message}. Install ajv as a dev dependency.`);
  }
}

// Ajv v8 exports as default or as the module itself
const AjvClass = Ajv.default ?? Ajv;

// Use draft-07 compat mode (Ajv v8 with strict:false for draft-07 schemas)
const ajv = new AjvClass({ strict: false, allErrors: true });

// ---------------------------------------------------------------------------
// Load the schema and the real manifest
// ---------------------------------------------------------------------------

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const agentDir = path.resolve(__dirname, "../../");

const schema = JSON.parse(readFileSync(path.join(agentDir, "hooks-manifest.schema.json"), "utf8"));
const manifest = JSON.parse(readFileSync(path.join(agentDir, "hooks-manifest.json"), "utf8"));

// Compile a validator for a single HookEntry (from the schema definitions)
const hookEntrySchema = {
  ...schema.definitions.HookEntry,
  definitions: schema.definitions,
  $schema: schema.$schema,
};

const validateHookEntry = ajv.compile(hookEntrySchema);

// Compile the full manifest schema
const validateManifestSchema = ajv.compile(schema);

// Helper: assert entry is valid
function assertValid(entry, label) {
  const ok = validateHookEntry(entry);
  if (!ok) {
    const errors = (validateHookEntry.errors || []).map(e => `${e.instancePath} ${e.message}`).join("; ");
    throw new Error(`Expected VALID but got INVALID for "${label}": ${errors}`);
  }
}

// Helper: assert entry is invalid
function assertInvalid(entry, label) {
  const ok = validateHookEntry(entry);
  if (ok) {
    throw new Error(`Expected INVALID but got VALID for "${label}": ${JSON.stringify(entry)}`);
  }
}

// ---------------------------------------------------------------------------
// Test 1: Real manifest validates against tightened schema (all 9 entries)
// ---------------------------------------------------------------------------

test("real hooks-manifest.json validates against tightened schema", () => {
  const ok = validateManifestSchema(manifest);
  if (!ok) {
    const errors = (validateManifestSchema.errors || []).map(e => `${e.instancePath} ${e.message}`).join("\n  ");
    throw new Error(`Real manifest failed validation:\n  ${errors}`);
  }
  assert.equal(manifest.hooks.length, 9, "manifest has 9 entries");
});

// ---------------------------------------------------------------------------
// Test 2: Shared-logic entries (the 4 PreToolUse entries) are valid individually
// ---------------------------------------------------------------------------

test("shared-logic entry with script is valid (shape 1)", () => {
  assertValid({
    ccEvent: "PreToolUse",
    matcher: "Bash",
    piEvent: "tool_call",
    toolNames: ["bash"],
    script: "dcg",
    scriptArgs: ["test", "--format", "json"],
    inputArgField: "command",
    outputFormat: "json",
  }, "shared-logic entry with all fields");
});

test("shared-logic entry without piEvent is valid (CC-only PreToolUse)", () => {
  assertValid({
    ccEvent: "PreToolUse",
    script: "some-guard.sh",
  }, "shared-logic entry without piEvent");
});

// ---------------------------------------------------------------------------
// Test 3: CC-only lifecycle entries (the 5 new entries) are valid individually
// ---------------------------------------------------------------------------

test("CC-only lifecycle entry with ccHooks is valid (shape 2)", () => {
  assertValid({
    ccEvent: "SessionStart",
    ccHooks: [
      { type: "command", command: "bd prime" }
    ],
    description: "session start hook",
  }, "CC-only lifecycle entry");
});

test("CC-only entry with multiple ccHooks items is valid", () => {
  assertValid({
    ccEvent: "SessionStart",
    description: "sync memory in",
    ccHooks: [
      { type: "command", command: "$CLAUDE_HOME/hooks/sync-memory-in.sh" },
      { type: "command", command: "$CLAUDE_HOME/hooks/bd-prime-with-cm.sh" },
      { type: "command", command: "$CLAUDE_HOME/hooks/brain-of-loop.sh" }
    ],
  }, "CC-only entry with multiple ccHooks");
});

// ---------------------------------------------------------------------------
// Test 4: Garbage entries MUST fail validation (the three required cases)
// ---------------------------------------------------------------------------

test("(a) empty object {} fails validation", () => {
  assertInvalid({}, "empty object");
});

test("(b) entry with ccEvent but neither script nor ccHooks fails validation", () => {
  assertInvalid(
    { ccEvent: "PreToolUse" },
    "ccEvent but no script or ccHooks"
  );
});

test("(b) entry with ccEvent and description but no script or ccHooks fails validation", () => {
  assertInvalid(
    { ccEvent: "SessionStart", description: "bare description" },
    "ccEvent + description but no script or ccHooks"
  );
});

test("(c) ccHooks not an array fails validation", () => {
  assertInvalid(
    { ccEvent: "SessionStart", ccHooks: "not-an-array" },
    "ccHooks is a string not array"
  );
});

test("(c) ccHooks array with wrong item shape fails validation", () => {
  assertInvalid(
    { ccEvent: "SessionStart", ccHooks: [{ wrongField: "x" }] },
    "ccHooks items missing type and command"
  );
});

test("(c) ccHooks array with items missing command fails validation", () => {
  assertInvalid(
    { ccEvent: "SessionStart", ccHooks: [{ type: "command" }] },
    "ccHooks items missing command"
  );
});

test("(c) ccHooks array with items missing type fails validation", () => {
  assertInvalid(
    { ccEvent: "SessionStart", ccHooks: [{ command: "bd prime" }] },
    "ccHooks items missing type"
  );
});

console.log("hooks schema validation tests loaded");
