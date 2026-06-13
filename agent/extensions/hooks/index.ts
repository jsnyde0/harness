/**
 * Generic pi hook-runner extension.
 *
 * Loads the shared hooks-manifest (agent/hooks-manifest.json) and wires each
 * entry via pi.on(entry.piEvent) -> pi.exec(entry.script). Generalizes the
 * existing agent/extensions/dcg.ts one-event pattern.
 *
 * GENERIC: grep of this file for any hardcoded event/script name = 0.
 * The toolNames filter is table-driven from manifest data (ADR-002 D2).
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readFile, realpath } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { validateManifest, wireManifest, resolveScriptPath } from "./core.mjs";

// Resolve the real path of this file (following symlinks) so that ../..
// navigation reaches the dotpi repo root even when loaded via ~/.pi/agent symlinks.
const THIS_DIR = path.dirname(
  await realpath(fileURLToPath(import.meta.url)).catch(
    () => fileURLToPath(import.meta.url),
  ),
);

const MANIFEST_RELATIVE_PATH = path.join(THIS_DIR, "..", "..", "hooks-manifest.json");

export default async function hooksRunner(pi: ExtensionAPI) {
  let raw: unknown;
  try {
    const text = await readFile(MANIFEST_RELATIVE_PATH, "utf8");
    raw = JSON.parse(text);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[hooks-runner] Failed to load manifest from ${MANIFEST_RELATIVE_PATH}: ${message}`);
    return;
  }

  let manifest: ReturnType<typeof validateManifest>;
  try {
    manifest = validateManifest(raw);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[hooks-runner] Invalid manifest: ${message}`);
    return;
  }

  // Resolve $CLAUDE_HOME/ and ~/ prefixes in manifest script paths (non-mutating copy).
  // CC-only entries (no piEvent) carry no `script` — leave those untouched so we
  // never call resolveScriptPath on undefined.
  const resolvedManifest = {
    ...manifest,
    hooks: manifest.hooks.map((entry) => ({
      ...entry,
      script: entry.script ? resolveScriptPath(entry.script) : entry.script,
    })),
  };

  wireManifest(pi, resolvedManifest);

  pi.registerCommand("hooks-status", {
    description: "Show loaded hooks-manifest entries",
    handler: async (_args, ctx) => {
      const lines = [
        `hooks-runner: ${resolvedManifest.hooks.length} entries loaded`,
        `manifest: ${MANIFEST_RELATIVE_PATH}`,
        "",
        "entries:",
      ];
      for (const entry of resolvedManifest.hooks) {
        const filter = entry.toolNames.length === 0 ? "all tools" : entry.toolNames.join("|");
        lines.push(
          `  [${entry.piEvent}] matcher=${entry.matcher || "*"} tools=${filter} → ${entry.script}`,
        );
      }
      ctx.ui.notify(lines.join("\n"), "info");
    },
  });
}
