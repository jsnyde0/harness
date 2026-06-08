#!/usr/bin/env node

import { tmpdir } from "node:os";
import { join } from "node:path";
import puppeteer from "puppeteer-core";
import { parseTabArgs, pickTab } from "./_tabs.js";

const { label, urlMatch, rest } = parseTabArgs(process.argv.slice(2));
const showHelp = rest.includes("-h") || rest.includes("--help");

if (showHelp) {
	console.log("Usage: screenshot.js [--url=<substring>] [--label=<name>]");
	console.log("\nExamples:");
	console.log("  screenshot.js                       # Screenshot most-recent tab");
	console.log("  screenshot.js --url=foo.com         # Screenshot tab whose URL contains 'foo.com'");
	console.log("  screenshot.js --label=hn            # Screenshot the labeled tab");
	process.exit(0);
}

const b = await puppeteer.connect({
	browserURL: "http://localhost:9222",
	defaultViewport: null,
});

const p = await pickTab(b, { label, urlMatch });
if (!p) {
	await b.disconnect();
	process.exit(1);
}

const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
const filename = `screenshot-${timestamp}.png`;
const filepath = join(tmpdir(), filename);

await p.screenshot({ path: filepath });

console.log(filepath);

await b.disconnect();
