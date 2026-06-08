#!/usr/bin/env node

import puppeteer from "puppeteer-core";
import { parseTabArgs, pickTab } from "./_tabs.js";

// Targeting: --label=<name> (or last tab as fallback).
// Conditions (one required): --text, --selector, --url, --fn.
// Optional: --timeout=<ms> (default 30000), --poll=<ms> (default 250).
//
// Note: --url= is a *condition* here (wait until URL matches), not tab
// targeting — that diverges from nav/eval/screenshot/pick. Target a specific
// tab with --label instead.

const raw = process.argv.slice(2);
let timeoutMs = 30000;
let pollMs = 250;
let text = null;
let selector = null;
let urlPattern = null;
let fn = null;
const passthrough = [];
for (const a of raw) {
	if (a.startsWith("--timeout=")) timeoutMs = Number(a.slice("--timeout=".length));
	else if (a.startsWith("--poll=")) pollMs = Number(a.slice("--poll=".length));
	else if (a.startsWith("--text=")) text = a.slice("--text=".length);
	else if (a.startsWith("--selector=")) selector = a.slice("--selector=".length);
	else if (a.startsWith("--fn=")) fn = a.slice("--fn=".length);
	else if (a.startsWith("--url=")) urlPattern = a.slice("--url=".length);
	else passthrough.push(a);
}
// Re-parse only the label flag from passthrough; --url is a condition here.
const { label } = parseTabArgs(passthrough);

const conditions = [text, selector, urlPattern, fn].filter((c) => c !== null);
if (conditions.length === 0) {
	console.log("Usage: wait.js [--label=<name>] [--timeout=<ms>] [--poll=<ms>] <condition>");
	console.log("\nConditions (exactly one):");
	console.log("  --text=<substring>     Wait until document text contains substring");
	console.log("  --selector=<css>       Wait until CSS selector matches at least one element");
	console.log("  --url=<substring>      Wait until the tab's URL contains substring");
	console.log("  --fn=<js>              Wait until JS expression returns truthy");
	console.log("\nExamples:");
	console.log("  wait.js --selector='article h2'");
	console.log("  wait.js --text='Welcome back'");
	console.log("  wait.js --url=/dashboard --timeout=10000");
	console.log("  wait.js --fn='document.readyState === \"complete\"'");
	console.log("  wait.js --label=hn --selector='.athing'");
	process.exit(1);
}
if (conditions.length > 1) {
	console.error("✗ Pass exactly one of --text, --selector, --url, --fn");
	process.exit(1);
}

if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
	console.error("✗ --timeout must be a positive number of milliseconds");
	process.exit(1);
}
if (!Number.isFinite(pollMs) || pollMs <= 0) {
	console.error("✗ --poll must be a positive number of milliseconds");
	process.exit(1);
}

const b = await puppeteer.connect({
	browserURL: "http://localhost:9222",
	defaultViewport: null,
});

const p = await pickTab(b, { label });
if (!p) {
	await b.disconnect();
	process.exit(1);
}

const started = Date.now();
const deadline = started + timeoutMs;

// Build a single page-side check function. Returning a truthy value resolves
// the wait; we evaluate it on each poll. Errors inside the page (e.g. a bad
// --fn expression) bubble up and abort the wait — better to fail loudly than
// silently keep polling.
async function check() {
	if (urlPattern !== null) {
		return p.url().includes(urlPattern);
	}
	return await p.evaluate(
		({ kind, payload }) => {
			if (kind === "text") {
				return (document.body?.innerText ?? "").includes(payload);
			}
			if (kind === "selector") {
				return document.querySelector(payload) !== null;
			}
			// kind === "fn"
			const AsyncFunction = (async () => {}).constructor;
			return new AsyncFunction(`return (${payload})`)();
		},
		text !== null
			? { kind: "text", payload: text }
			: selector !== null
				? { kind: "selector", payload: selector }
				: { kind: "fn", payload: fn },
	);
}

let satisfied = false;
let lastErr = null;
while (Date.now() < deadline) {
	try {
		if (await check()) {
			satisfied = true;
			break;
		}
	} catch (e) {
		lastErr = e;
	}
	await new Promise((r) => setTimeout(r, pollMs));
}

const elapsed = Date.now() - started;
await b.disconnect();

if (satisfied) {
	console.log(`✓ Condition met after ${elapsed}ms`);
	process.exit(0);
}

console.error(`✗ Timeout after ${elapsed}ms waiting for condition`);
if (lastErr) console.error(`  Last evaluation error: ${lastErr.message}`);
process.exit(2);
