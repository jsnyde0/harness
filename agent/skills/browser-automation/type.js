#!/usr/bin/env node
// type.js — focus a selector and type text via Puppeteer's REAL keyboard
// (trusted events), which many React autocomplete widgets require.
//
// Usage:
//   type.js [--label=<name>|--url=<sub>] --selector='<css>' --text='hello' [--delay=80] [--clear] [--press=Enter]
//
// --clear   : select-all + backspace before typing
// --press=K : after typing, press key K (e.g. Enter, ArrowDown)
// --delay   : per-keystroke delay in ms (default 60)

import puppeteer from "puppeteer-core";
import { parseTabArgs, pickTab } from "./_tabs.js";

const argv = process.argv.slice(2);
const { label, urlMatch } = parseTabArgs(argv);

function flag(name) {
	const a = argv.find((x) => x.startsWith(`--${name}=`));
	return a ? a.slice(name.length + 3) : null;
}
const selector = flag("selector");
const text = flag("text") ?? "";
const delay = Number(flag("delay") ?? 60);
const press = flag("press");
const clear = argv.includes("--clear");

if (!selector) {
	console.error("Usage: type.js --selector='<css>' --text='...' [--clear] [--press=Enter] [--delay=ms]");
	process.exit(1);
}

const b = await puppeteer.connect({ browserURL: "http://localhost:9222", defaultViewport: null });
const p = await pickTab(b, { label, urlMatch });
if (!p) {
	await b.disconnect();
	process.exit(1);
}

const el = await p.$(selector);
if (!el) {
	console.error(`✗ selector not found: ${selector}`);
	await b.disconnect();
	process.exit(2);
}

await el.focus();
if (clear) {
	await el.click({ clickCount: 3 });
	await p.keyboard.press("Backspace");
}
if (text) await el.type(text, { delay });
if (press) await p.keyboard.press(press);

console.log(`✓ typed ${JSON.stringify(text)} into ${selector}${press ? ` then pressed ${press}` : ""}`);
await b.disconnect();
