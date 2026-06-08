#!/usr/bin/env node

import puppeteer from "puppeteer-core";
import { parseTabArgs, pickTab } from "./_tabs.js";

const { label, urlMatch, rest } = parseTabArgs(process.argv.slice(2));
const code = rest.join(" ");

if (!code) {
	console.log("Usage: eval.js [--url=<substring>] [--label=<name>] 'code'");
	console.log("\nExamples:");
	console.log('  eval.js "document.title"');
	console.log('  eval.js "document.querySelectorAll(\'a\').length"');
	console.log('  eval.js --url=lobste.rs "document.title"   # pick a tab by URL substring');
	console.log('  eval.js --label=hn "document.title"        # pick the labeled tab');
	process.exit(1);
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

const result = await p.evaluate((c) => {
	const AsyncFunction = (async () => {}).constructor;
	return new AsyncFunction(`return (${c})`)();
}, code);

if (Array.isArray(result)) {
	for (let i = 0; i < result.length; i++) {
		if (i > 0) console.log("");
		for (const [key, value] of Object.entries(result[i])) {
			console.log(`${key}: ${value}`);
		}
	}
} else if (typeof result === "object" && result !== null) {
	for (const [key, value] of Object.entries(result)) {
		console.log(`${key}: ${value}`);
	}
} else {
	console.log(result);
}

await b.disconnect();
