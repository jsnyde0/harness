// Shared helpers for tab targeting (--url, --label) and label persistence.
//
// Labels are stored in a sidecar JSON at ~/.cache/scraping/tab-labels.json
// keyed by user-supplied label → Chromium targetId. Stale labels (pointing at
// closed tabs) are pruned lazily when we fail to resolve them.

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const LABELS_PATH = join(homedir(), ".cache", "scraping", "tab-labels.json");

export function pageTargetId(page) {
	// puppeteer-core stores it as a private field on Target; the prototype
	// exposes no accessor. Falls back if a future version renames it.
	return page.target()._targetId ?? page.target()._targetInfo?.targetId;
}

export function loadLabels() {
	if (!existsSync(LABELS_PATH)) return {};
	try {
		const raw = readFileSync(LABELS_PATH, "utf8");
		const parsed = JSON.parse(raw);
		return parsed && typeof parsed === "object" ? parsed : {};
	} catch {
		return {};
	}
}

function saveLabels(labels) {
	mkdirSync(dirname(LABELS_PATH), { recursive: true });
	const tmp = `${LABELS_PATH}.tmp`;
	writeFileSync(tmp, JSON.stringify(labels, null, 2));
	renameSync(tmp, LABELS_PATH);
}

export function setLabel(label, targetId) {
	const labels = loadLabels();
	labels[label] = targetId;
	saveLabels(labels);
}

export function removeLabel(label) {
	const labels = loadLabels();
	if (label in labels) {
		delete labels[label];
		saveLabels(labels);
	}
}

// Returns the Page whose target matches the labeled id, or null if the label
// is unknown or points at a tab that has since closed. Prunes stale entries.
async function resolveLabel(browser, label) {
	const labels = loadLabels();
	const targetId = labels[label];
	if (!targetId) return null;
	for (const p of await browser.pages()) {
		if (pageTargetId(p) === targetId) return p;
	}
	removeLabel(label);
	return null;
}

// Unified tab picker. Targeting options are mutually exclusive:
//   { label: "foo" }            — labeled tab (errors if unknown/stale)
//   { urlMatch: "lobste.rs" }   — first tab whose URL contains substring
//   { }                         — last tab in browser.pages() (existing default)
//
// On miss, prints a helpful tab listing on stderr and returns null. Callers
// should disconnect and exit on null.
export async function pickTab(browser, { label = null, urlMatch = null } = {}) {
	if (label !== null && urlMatch !== null) {
		console.error("✗ --label and --url= are mutually exclusive (use one or the other)");
		return null;
	}
	if (label !== null) {
		const p = await resolveLabel(browser, label);
		if (!p) {
			const labels = loadLabels();
			console.error(`✗ No tab matches --label=${label}`);
			if (Object.keys(labels).length === 0) {
				console.error("  No labels are currently set.");
			} else {
				console.error("  Known labels:");
				for (const [k, id] of Object.entries(labels)) {
					console.error(`    ${k} → target ${id}`);
				}
			}
			console.error("  Create a new label with:");
			console.error("    nav.js <url> --new --label=<name>");
			console.error("  Open tabs:");
			for (const pg of await browser.pages()) console.error(`    ${pg.url()}`);
		}
		return p;
	}
	if (urlMatch !== null) {
		const pages = await browser.pages();
		const p = pages.find((pg) => pg.url().includes(urlMatch));
		if (!p) {
			console.error(`✗ No tab matches --url=${urlMatch}`);
			console.error("  Open tabs:");
			for (const pg of pages) console.error(`    ${pg.url()}`);
		}
		return p ?? null;
	}
	const p = (await browser.pages()).at(-1);
	if (!p) console.error("✗ No active tab found");
	return p ?? null;
}

// Parser shared across scripts. Strips --label=<v>, --url=<v>, --new from argv
// and returns { label, urlMatch, newTab, rest }. `rest` holds whatever the
// caller wants to interpret (the url for nav.js, the code for eval.js, etc.).
export function parseTabArgs(argv) {
	let label = null;
	let urlMatch = null;
	let newTab = false;
	const rest = [];
	for (const a of argv) {
		if (a.startsWith("--label=")) label = a.slice("--label=".length);
		else if (a.startsWith("--url=")) urlMatch = a.slice("--url=".length);
		else if (a === "--new") newTab = true;
		else rest.push(a);
	}
	return { label, urlMatch, newTab, rest };
}
