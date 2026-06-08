#!/usr/bin/env node

import { spawn, execSync } from "node:child_process";
import puppeteer from "puppeteer-core";

const useProfile = process.argv[2] === "--profile";

if (process.argv[2] && process.argv[2] !== "--profile") {
	console.log("Usage: start.js [--profile]");
	console.log("\nOptions:");
	console.log("  --profile  Copy your default Chrome profile (cookies, logins).");
	console.log("             Requires that your normal Chrome be quit first — this");
	console.log("             script will NOT kill it for you.");
	console.log("\nExamples:");
	console.log("  start.js            # Launch dedicated Chrome alongside your normal one");
	console.log("  start.js --profile  # Same, but seeded with a copy of your profile");
	process.exit(1);
}

// 1. If an automation Chrome is already listening on :9222, just reuse it.
//    This makes the script idempotent and safe for parallel agents that all
//    want the same shared automation session.
async function tryConnect() {
	try {
		const browser = await puppeteer.connect({
			browserURL: "http://localhost:9222",
			defaultViewport: null,
		});
		await browser.disconnect();
		return true;
	} catch {
		return false;
	}
}

if (await tryConnect()) {
	// If --profile was requested but :9222 is already up, we can't know whether
	// the running instance was started with --profile. Refuse rather than silently
	// ignore the flag — the user expected profile state and would be confused.
	if (useProfile) {
		console.error("✗ Chrome is already running on :9222.");
		console.error("  --profile is ignored when an existing instance is reused.");
		console.error("  To start a fresh instance with --profile:");
		console.error("    pkill -f 'remote-debugging-port=9222'");
		console.error("    (then quit your normal Chrome, then re-run with --profile)");
		process.exit(1);
	}
	console.log("✓ Chrome already running on :9222 (reusing)");
	process.exit(0);
}

// 2. If --profile, we need to rsync the user's Chrome profile, which requires
//    that Chrome NOT be holding the source profile open. Refuse rather than
//    silently killing the user's session.
if (useProfile) {
	let chromeRunning = false;
	try {
		execSync("pgrep -x 'Google Chrome'", { stdio: "ignore" });
		chromeRunning = true;
	} catch {}

	if (chromeRunning) {
		console.error("✗ Cannot use --profile while Google Chrome is running.");
		console.error("  Copying the profile requires Chrome to be fully quit (it holds");
		console.error("  exclusive locks on cookie/session files).");
		console.error("");
		console.error("  Options:");
		console.error("    1. Quit Chrome, then re-run with --profile.");
		console.error("    2. Re-run without --profile to launch a fresh dedicated");
		console.error("       Chrome instance alongside your normal one (no sign-in state).");
		process.exit(1);
	}

	const src = `${process.env["HOME"]}/Library/Application Support/Google/Chrome/`;
	execSync("mkdir -p ~/.cache/scraping", { stdio: "ignore" });
	execSync(`rsync -a --delete "${src}" ~/.cache/scraping/`, { stdio: "pipe" });
} else {
	execSync("mkdir -p ~/.cache/scraping", { stdio: "ignore" });
}

// 3. Spawn a dedicated Chrome instance with its own user-data-dir. This runs
//    alongside the user's normal Chrome without conflict — different profile
//    dir, different process, only this one listens on :9222.
spawn(
	"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
	[
		"--remote-debugging-port=9222",
		`--user-data-dir=${process.env["HOME"]}/.cache/scraping`,
		"--no-first-run",
		"--no-default-browser-check",
	],
	{ detached: true, stdio: "ignore" },
).unref();

// Wait for CDP to respond, then ensure at least one page exists. With
// --no-first-run we sometimes get zero pages on a fresh profile — create a
// blank one ourselves rather than waiting for Chrome to spawn its own.
let ready = false;
for (let i = 0; i < 30; i++) {
	try {
		const browser = await puppeteer.connect({
			browserURL: "http://localhost:9222",
			defaultViewport: null,
		});
		const pages = await browser.pages();
		if (pages.length === 0) {
			await browser.newPage();
		}
		await browser.disconnect();
		ready = true;
		break;
	} catch {}
	await new Promise((r) => setTimeout(r, 500));
}

if (!ready) {
	console.error("✗ Failed to start Chrome on :9222 (CDP never became responsive)");
	process.exit(1);
}

console.log(`✓ Chrome started on :9222${useProfile ? " with your profile" : ""}`);
