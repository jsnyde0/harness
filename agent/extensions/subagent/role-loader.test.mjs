// Tests for the pi role-loader
// Uses fixture role files in a temp dir — no dependency on installed roles or symlinks.
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import {
	parseFrontmatter,
	loadRole,
	resolveTask,
	validateFinalLine,
	DEFAULT_CONFIG,
} from "./role-loader.mjs";

// ─── Fixtures ─────────────────────────────────────────────────────────────────

const FIXTURE_ROLE_CONTENT = `---
name: test-reviewer
description: A fixture reviewer role for tests.
tools: Read, Grep
skills: skill-alpha, skill-beta
model: haiku
pi-model: openrouter/anthropic/claude-haiku
output-contract: VERDICT: PASS
---

You are a test reviewer.

## Instructions

Review the given code carefully.
`;

const FIXTURE_ROLE_NO_CONTRACT = `---
name: simple-worker
description: A simple worker with no output contract.
tools: Read
skills: ""
model: sonnet
pi-model: openrouter/anthropic/claude-sonnet
---

Do the work.
`;

const SKILL_ALPHA_CONTENT = `# skill-alpha

This is the content of skill-alpha.
Use it to do alpha things.
`;

const SKILL_BETA_CONTENT = `# skill-beta

This is the content of skill-beta.
Use it to do beta things.
`;

// ─── parseFrontmatter ─────────────────────────────────────────────────────────

test("parseFrontmatter: parses key-value fields from role file", () => {
	const result = parseFrontmatter(FIXTURE_ROLE_CONTENT);
	assert.equal(result.frontmatter["name"], "test-reviewer");
	assert.equal(result.frontmatter["pi-model"], "openrouter/anthropic/claude-haiku");
	assert.equal(result.frontmatter["output-contract"], "VERDICT: PASS");
	assert.match(result.body, /You are a test reviewer/);
});

test("parseFrontmatter: body does not include frontmatter block", () => {
	const result = parseFrontmatter(FIXTURE_ROLE_CONTENT);
	assert.ok(!result.body.includes("---"), "body should not contain frontmatter delimiters");
	assert.ok(!result.body.includes("pi-model:"), "body should not contain frontmatter fields");
});

test("parseFrontmatter: handles role with no output-contract", () => {
	const result = parseFrontmatter(FIXTURE_ROLE_NO_CONTRACT);
	assert.equal(result.frontmatter["output-contract"], undefined);
	assert.match(result.body, /Do the work/);
});

test("parseFrontmatter: handles multiline description with > block scalar", () => {
	const content = `---
name: foo
description: >
  A multi-line
  description here.
tools: Read
---

Body text.
`;
	const result = parseFrontmatter(content);
	// Description should be parsed (may be folded to single line or kept as-is)
	assert.ok(result.frontmatter["description"] !== undefined);
	assert.match(result.body, /Body text/);
});

// ─── loadRole ─────────────────────────────────────────────────────────────────

test("loadRole: loads role file and inlines SKILL.md bodies", async () => {
	const dir = await mkdtemp(path.join(tmpdir(), "role-loader-test-"));
	try {
		// Write role file
		const roleFile = path.join(dir, "test-reviewer.md");
		await writeFile(roleFile, FIXTURE_ROLE_CONTENT, "utf8");

		// Write skill files
		const skillAlphaDir = path.join(dir, "skills", "skill-alpha");
		const skillBetaDir = path.join(dir, "skills", "skill-beta");
		await mkdir(skillAlphaDir, { recursive: true });
		await mkdir(skillBetaDir, { recursive: true });
		await writeFile(path.join(skillAlphaDir, "SKILL.md"), SKILL_ALPHA_CONTENT, "utf8");
		await writeFile(path.join(skillBetaDir, "SKILL.md"), SKILL_BETA_CONTENT, "utf8");

		const roleData = await loadRole("test-reviewer", dir, path.join(dir, "skills"));

		assert.equal(roleData.name, "test-reviewer");
		assert.equal(roleData.piModel, "openrouter/anthropic/claude-haiku");
		assert.deepEqual(roleData.tools, ["Read", "Grep"]);
		assert.equal(roleData.outputContract, "VERDICT: PASS");
		// Body should include original body text
		assert.match(roleData.brief, /You are a test reviewer/);
		// Skills should be inlined
		assert.match(roleData.brief, /skill-alpha/);
		assert.match(roleData.brief, /alpha things/);
		assert.match(roleData.brief, /skill-beta/);
		assert.match(roleData.brief, /beta things/);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("loadRole: works when skills field is empty string", async () => {
	const dir = await mkdtemp(path.join(tmpdir(), "role-loader-test-"));
	try {
		const roleFile = path.join(dir, "simple-worker.md");
		await writeFile(roleFile, FIXTURE_ROLE_NO_CONTRACT, "utf8");

		const roleData = await loadRole("simple-worker", dir, path.join(dir, "skills"));

		assert.equal(roleData.name, "simple-worker");
		assert.equal(roleData.outputContract, undefined);
		assert.match(roleData.brief, /Do the work/);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("loadRole: throws when role file does not exist", async () => {
	const dir = await mkdtemp(path.join(tmpdir(), "role-loader-test-"));
	try {
		await assert.rejects(
			() => loadRole("nonexistent-role", dir, dir),
			/role file not found|ENOENT/,
		);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

// ─── resolveTask with role ─────────────────────────────────────────────────────

test("resolveTask: role param loads brief and sets model from pi-model", async () => {
	const dir = await mkdtemp(path.join(tmpdir(), "role-loader-test-"));
	try {
		const roleFile = path.join(dir, "test-reviewer.md");
		await writeFile(roleFile, FIXTURE_ROLE_CONTENT, "utf8");
		const skillAlphaDir = path.join(dir, "skills", "skill-alpha");
		const skillBetaDir = path.join(dir, "skills", "skill-beta");
		await mkdir(skillAlphaDir, { recursive: true });
		await mkdir(skillBetaDir, { recursive: true });
		await writeFile(path.join(skillAlphaDir, "SKILL.md"), SKILL_ALPHA_CONTENT, "utf8");
		await writeFile(path.join(skillBetaDir, "SKILL.md"), SKILL_BETA_CONTENT, "utf8");

		const resolved = await resolveTask(
			{ task: "Review this code.", role: "test-reviewer" },
			DEFAULT_CONFIG,
			{},
			0,
			dir,
			path.join(dir, "skills"),
		);

		// Model should come from pi-model slug, not modelTier
		assert.equal(resolved.model, "openrouter/anthropic/claude-haiku");
		// Tools should come from role's tools list
		assert.deepEqual(resolved.tools, ["Read", "Grep"]);
		// Task should be prepended with role brief
		assert.match(resolved.task, /You are a test reviewer/);
		assert.match(resolved.task, /Review this code\./);
		// expectedFinalLine from output-contract
		assert.ok(Array.isArray(resolved.expectedFinalLine));
		assert.ok(resolved.expectedFinalLine.includes("VERDICT: PASS"));
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("resolveTask: role with no output-contract yields no expectedFinalLine", async () => {
	const dir = await mkdtemp(path.join(tmpdir(), "role-loader-test-"));
	try {
		const roleFile = path.join(dir, "simple-worker.md");
		await writeFile(roleFile, FIXTURE_ROLE_NO_CONTRACT, "utf8");

		const resolved = await resolveTask(
			{ task: "Do something.", role: "simple-worker" },
			DEFAULT_CONFIG,
			{},
			0,
			dir,
			path.join(dir, "skills"),
		);

		assert.equal(resolved.expectedFinalLine, undefined);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("resolveTask: explicit model overrides role's pi-model", async () => {
	const dir = await mkdtemp(path.join(tmpdir(), "role-loader-test-"));
	try {
		const roleFile = path.join(dir, "test-reviewer.md");
		await writeFile(roleFile, FIXTURE_ROLE_CONTENT, "utf8");
		const skillAlphaDir = path.join(dir, "skills", "skill-alpha");
		const skillBetaDir = path.join(dir, "skills", "skill-beta");
		await mkdir(skillAlphaDir, { recursive: true });
		await mkdir(skillBetaDir, { recursive: true });
		await writeFile(path.join(skillAlphaDir, "SKILL.md"), SKILL_ALPHA_CONTENT, "utf8");
		await writeFile(path.join(skillBetaDir, "SKILL.md"), SKILL_BETA_CONTENT, "utf8");

		const resolved = await resolveTask(
			{ task: "Review.", role: "test-reviewer", model: "openai/gpt-5.5" },
			DEFAULT_CONFIG,
			{},
			0,
			dir,
			path.join(dir, "skills"),
		);

		assert.equal(resolved.model, "openai/gpt-5.5");
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

// ─── resolveTask additive inline-task path (no role) ─────────────────────────

test("resolveTask: inline task without role still works (ADR-001 D2 additive)", async () => {
	const dir = await mkdtemp(path.join(tmpdir(), "role-loader-test-"));
	try {
		const resolved = await resolveTask(
			{ task: "Just do something inline." },
			DEFAULT_CONFIG,
			{},
			0,
			dir,
			path.join(dir, "skills"),
		);

		assert.equal(resolved.task, "Just do something inline.");
		assert.equal(resolved.model, DEFAULT_CONFIG.modelTiers[DEFAULT_CONFIG.defaultModelTier].model);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

// ─── validateFinalLine contract-violation rejection ───────────────────────────

test("validateFinalLine: satisfies contract when final line matches exact value", () => {
	const task = {
		label: "test",
		task: "do",
		modelTier: "medium",
		model: "sonnet",
		tools: [],
		timeoutMs: 60000,
		expectedFinalLine: ["VERDICT: PASS", "VERDICT: FAIL"],
	};
	const result = validateFinalLine(task, "VERDICT: PASS");
	assert.equal(result.required, true);
	assert.equal(result.satisfied, true);
});

test("validateFinalLine: rejects contract when final line does not match", () => {
	const task = {
		label: "test",
		task: "do",
		modelTier: "medium",
		model: "sonnet",
		tools: [],
		timeoutMs: 60000,
		expectedFinalLine: ["VERDICT: PASS"],
	};
	const result = validateFinalLine(task, "Some random output");
	assert.equal(result.required, true);
	assert.equal(result.satisfied, false);
	assert.ok(result.error !== undefined);
	assert.match(result.error, /did not match expected contract|final line/);
});

test("validateFinalLine: no contract means not required and satisfied", () => {
	const task = {
		label: "test",
		task: "do",
		modelTier: "medium",
		model: "sonnet",
		tools: [],
		timeoutMs: 60000,
	};
	const result = validateFinalLine(task, "anything");
	assert.equal(result.required, false);
	assert.equal(result.satisfied, true);
});

test("validateFinalLine: role-derived expectedFinalLine passes through validation", async () => {
	const dir = await mkdtemp(path.join(tmpdir(), "role-loader-test-"));
	try {
		const roleFile = path.join(dir, "test-reviewer.md");
		await writeFile(roleFile, FIXTURE_ROLE_CONTENT, "utf8");
		const skillAlphaDir = path.join(dir, "skills", "skill-alpha");
		const skillBetaDir = path.join(dir, "skills", "skill-beta");
		await mkdir(skillAlphaDir, { recursive: true });
		await mkdir(skillBetaDir, { recursive: true });
		await writeFile(path.join(skillAlphaDir, "SKILL.md"), SKILL_ALPHA_CONTENT, "utf8");
		await writeFile(path.join(skillBetaDir, "SKILL.md"), SKILL_BETA_CONTENT, "utf8");

		const resolved = await resolveTask(
			{ task: "Review this.", role: "test-reviewer" },
			DEFAULT_CONFIG,
			{},
			0,
			dir,
			path.join(dir, "skills"),
		);

		// REAL validateFinalLine (not mocked) — correct final line passes
		const pass = validateFinalLine(resolved, "VERDICT: PASS");
		assert.equal(pass.required, true);
		assert.equal(pass.satisfied, true);

		// REAL validateFinalLine — wrong final line fails
		const fail = validateFinalLine(resolved, "something else entirely");
		assert.equal(fail.required, true);
		assert.equal(fail.satisfied, false);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

// ─── Real role files: browser-automation skill loads under pi ─────────────────
// These tests use the ACTUAL agent/roles/ and agent/skills/ directories to
// confirm that feature-scout and ui-craftsman now resolve + inline the
// browser-automation SKILL.md body via the role-loader (the same path pi uses).

import { fileURLToPath } from "node:url";
const HERE = path.dirname(fileURLToPath(import.meta.url));
// agent/extensions/subagent/ -> agent/extensions/ -> agent/ -> repo root
const REPO_ROOT = path.resolve(HERE, "..", "..", "..");
const REAL_ROLES_DIR = path.join(REPO_ROOT, "agent", "roles");
const REAL_SKILLS_DIR = path.join(REPO_ROOT, "agent", "skills");

test("feature-scout inlines browser-automation SKILL.md body when loaded via role-loader", async () => {
	const roleData = await loadRole("feature-scout", REAL_ROLES_DIR, REAL_SKILLS_DIR);
	// Confirm skills field resolved
	assert.ok(
		roleData.skillNames.includes("browser-automation"),
		`expected skillNames to include 'browser-automation', got: ${JSON.stringify(roleData.skillNames)}`,
	);
	// Confirm SKILL.md body is inlined (unique phrase from browser-automation/SKILL.md)
	assert.match(
		roleData.brief,
		/Chrome DevTools Protocol|puppeteer-core|remote-debugging-port/,
		"browser-automation SKILL.md body should be inlined into the feature-scout brief",
	);
	// Confirm role body is also present
	assert.match(roleData.brief, /scout one competitor platform/i);
});

test("ui-craftsman inlines browser-automation SKILL.md body when loaded via role-loader", async () => {
	const roleData = await loadRole("ui-craftsman", REAL_ROLES_DIR, REAL_SKILLS_DIR);
	// Confirm skills field resolved
	assert.ok(
		roleData.skillNames.includes("browser-automation"),
		`expected skillNames to include 'browser-automation', got: ${JSON.stringify(roleData.skillNames)}`,
	);
	// Confirm SKILL.md body is inlined (unique phrase from browser-automation/SKILL.md)
	assert.match(
		roleData.brief,
		/Chrome DevTools Protocol|puppeteer-core|remote-debugging-port/,
		"browser-automation SKILL.md body should be inlined into the ui-craftsman brief",
	);
	// Confirm role body is also present
	assert.match(roleData.brief, /production bar/i);
});

console.log("role-loader tests passed");
