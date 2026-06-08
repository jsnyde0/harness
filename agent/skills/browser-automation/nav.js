#!/usr/bin/env node

import puppeteer from "puppeteer-core";
import { pageTargetId, parseTabArgs, pickTab, setLabel } from "./_tabs.js";

const { label, urlMatch, newTab, rest } = parseTabArgs(process.argv.slice(2));
const url = rest[0] ?? null;

if (!url) {
	console.log("Usage: nav.js <url> [--new] [--url=<substring>] [--label=<name>]");
	console.log("\nExamples:");
	console.log("  nav.js https://example.com                       # Navigate most-recent tab");
	console.log("  nav.js https://example.com --new                 # Open in new tab");
	console.log("  nav.js https://example.com --new --label=hn      # New tab, remember as 'hn'");
	console.log("  nav.js https://example.com --label=hn            # Navigate the 'hn'-labeled tab");
	console.log("  nav.js https://example.com --url=foo.com         # Navigate tab whose URL contains 'foo.com'");
	process.exit(1);
}

if (newTab && urlMatch !== null) {
	console.error("✗ --new and --url= are mutually exclusive (use one or the other)");
	process.exit(1);
}
if (label !== null && urlMatch !== null) {
	console.error("✗ --label and --url= are mutually exclusive (use one or the other)");
	process.exit(1);
}

const b = await puppeteer.connect({
	browserURL: "http://localhost:9222",
	defaultViewport: null,
});

let p;
if (newTab) {
	p = await b.newPage();
	await p.goto(url, { waitUntil: "domcontentloaded" });
	if (label !== null) {
		setLabel(label, pageTargetId(p));
		console.log(`✓ Opened (labeled '${label}'):`, url);
	} else {
		console.log("✓ Opened:", url);
	}
} else {
	p = await pickTab(b, { label, urlMatch });
	if (!p) {
		await b.disconnect();
		process.exit(1);
	}
	await p.goto(url, { waitUntil: "domcontentloaded" });
	console.log("✓ Navigated to:", url);
}

await b.disconnect();
