/**
 * role-loader.mjs — pi role-loader for the subagent extension
 *
 * Exports:
 *   parseFrontmatter(content)  — parse YAML-ish frontmatter from a role .md file
 *   loadRole(name, rolesDir, skillsDir) — load + expand a named role file
 *   resolveTask(task, config, topLevel, index, rolesDir, skillsDir) — async task resolver
 *   validateFinalLine(task, finalLine) — output-contract validator
 *   DEFAULT_CONFIG — default SubagentConfig
 *   MODEL_TIERS, THINKING_LEVELS — re-exported constants
 *
 * Design notes (ADR-002 D3/D4):
 *   - Role files live at <rolesDir>/<name>.md
 *   - CC reads `model:` (Anthropic keyword); pi reads `pi-model:` (provider/model slug)
 *   - This loader reads ONLY `pi-model:` — never `model:` (which is CC's concern)
 *   - inline task (no role) continues to work (ADR-001 D2 additive)
 *   - No hardcoded role identity: resolved by the caller's `role` param name
 */

import { readFile } from "node:fs/promises";
import path from "node:path";

// ─── Constants (mirror index.ts; role-loader.mjs is the ESM-testable source) ──

export const MODEL_TIERS = /** @type {const} */ (["basic", "medium", "smart", "max"]);
export const THINKING_LEVELS = /** @type {const} */ (["off", "minimal", "low", "medium", "high", "xhigh"]);

export const DEFAULT_CONFIG = {
	defaultModelTier: "medium",
	defaultTools: ["read", "grep", "find", "bash"],
	maxParallelTasks: 8,
	maxConcurrency: 4,
	timeoutMs: 600000,
	modelTiers: {
		basic: { model: "haiku", thinking: "minimal" },
		medium: { model: "sonnet", thinking: "low" },
		smart: { model: "opus", thinking: "medium" },
		max: { model: "opus", thinking: "high" },
	},
};

// ─── parseFrontmatter ─────────────────────────────────────────────────────────

/**
 * Parse YAML frontmatter (between `---` delimiters) from a markdown file.
 * Returns { frontmatter: Record<string, string | string[]>, body: string }.
 *
 * Supports the role-file schema per ADR-002 D3:
 *   name, description (plain or `>` block), tools, skills, model, pi-model,
 *   output-contract.
 *
 * This is a purposeful minimal parser for the role schema — not a general YAML
 * parser. It handles:
 *   - Simple scalar: `key: value`
 *   - Block scalar (folded `>`): key with continuation lines indented by 2+
 *   - No YAML lists (tools/skills are comma-separated strings in this schema)
 */
export function parseFrontmatter(content) {
	// Find opening ---
	const firstNewline = content.indexOf("\n");
	if (firstNewline === -1) return { frontmatter: {}, body: content };
	const firstLine = content.slice(0, firstNewline).trim();
	if (firstLine !== "---") return { frontmatter: {}, body: content };

	// Find closing ---
	const rest = content.slice(firstNewline + 1);
	const closingIdx = rest.search(/^---\s*$/m);
	if (closingIdx === -1) return { frontmatter: {}, body: content };

	const frontmatterText = rest.slice(0, closingIdx);
	const body = rest.slice(closingIdx).replace(/^---\s*\n?/, "").trimStart();

	const frontmatter = parseFrontmatterBlock(frontmatterText);
	return { frontmatter, body };
}

/**
 * Parse the inner YAML-ish block (no delimiters).
 * Handles simple scalars and block scalars (folded > and literal |).
 */
function parseFrontmatterBlock(text) {
	const result = {};
	const lines = text.split("\n");
	let i = 0;
	while (i < lines.length) {
		const line = lines[i];
		// Skip blank lines
		if (line.trim() === "") { i++; continue; }
		// Key: value or Key: > (block scalar marker)
		const match = line.match(/^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)/);
		if (!match) { i++; continue; }
		const key = match[1];
		let value = match[2].trim();
		// Block scalar (folded > or literal |)
		if (value === ">" || value === "|") {
			const blockLines = [];
			i++;
			while (i < lines.length && (lines[i].startsWith("  ") || lines[i].trim() === "")) {
				const stripped = lines[i].startsWith("  ") ? lines[i].slice(2) : "";
				blockLines.push(stripped);
				i++;
			}
			// Fold: join with space, trim trailing whitespace
			value = blockLines.map(l => l.trimEnd()).filter(l => l.length > 0).join(" ").trim();
		} else {
			i++;
		}
		// Strip surrounding quotes if present
		if ((value.startsWith('"') && value.endsWith('"')) ||
			(value.startsWith("'") && value.endsWith("'"))) {
			value = value.slice(1, -1);
		}
		result[key] = value === '""' || value === "''" ? "" : value;
	}
	return result;
}

// ─── loadRole ─────────────────────────────────────────────────────────────────

/**
 * Load a named role file and expand it:
 *   1. Read <rolesDir>/<name>.md
 *   2. Parse frontmatter
 *   3. Inline SKILL.md bodies for each skill listed in `skills`
 *   4. Return a RoleData object
 *
 * @param {string} name - Role name (matches filename without .md)
 * @param {string} rolesDir - Directory containing role .md files
 * @param {string} skillsDir - Directory containing skill subdirectories with SKILL.md
 * @returns {Promise<RoleData>}
 */
export async function loadRole(name, rolesDir, skillsDir) {
	const rolePath = path.join(rolesDir, `${name}.md`);
	let rawContent;
	try {
		rawContent = await readFile(rolePath, "utf8");
	} catch (err) {
		if (err.code === "ENOENT") {
			throw new Error(`role file not found: ${rolePath}`);
		}
		throw err;
	}

	const { frontmatter, body } = parseFrontmatter(rawContent);

	// Parse tools: comma-separated string → string[]
	const toolsRaw = frontmatter["tools"] ?? "";
	const tools = toolsRaw.trim()
		? toolsRaw.split(",").map(t => t.trim()).filter(t => t.length > 0)
		: [];

	// Parse skills: comma-separated string → string[]
	const skillsRaw = frontmatter["skills"] ?? "";
	const skillNames = skillsRaw.trim()
		? skillsRaw.split(",").map(s => s.trim()).filter(s => s.length > 0)
		: [];

	// Read+inline skill bodies
	const inlinedSkills = await inlineSkills(skillNames, skillsDir);

	// Build brief: prepend inlined skills to body
	const brief = inlinedSkills.length > 0
		? `${inlinedSkills.join("\n\n")}\n\n${body}`
		: body;

	const outputContract = frontmatter["output-contract"] !== undefined
		? (frontmatter["output-contract"].trim() || undefined)
		: undefined;

	return {
		name: frontmatter["name"] ?? name,
		description: frontmatter["description"] ?? "",
		piModel: frontmatter["pi-model"] ?? undefined,
		tools,
		skillNames,
		outputContract: outputContract !== "" ? outputContract : undefined,
		brief,
	};
}

/**
 * Read and inline SKILL.md bodies for the given skill names.
 * Missing skill files are silently skipped with a warning comment.
 */
async function inlineSkills(skillNames, skillsDir) {
	const results = [];
	for (const skillName of skillNames) {
		const skillPath = path.join(skillsDir, skillName, "SKILL.md");
		try {
			const content = await readFile(skillPath, "utf8");
			results.push(`<!-- skill: ${skillName} -->\n${content.trim()}`);
		} catch {
			// Missing skill file: include a comment so the missing dep is visible
			results.push(`<!-- skill: ${skillName} — SKILL.md not found at ${skillPath} -->`);
		}
	}
	return results;
}

// ─── validateFinalLine ────────────────────────────────────────────────────────

/**
 * Validate the final assistant line against the task's output contract.
 * This is the REAL validator — not mocked in tests (per bead requirement).
 *
 * @param {object} task - ResolvedTask (needs expectedFinalLine, expectedFinalLinePattern)
 * @param {string} finalLine
 * @returns {{ required: boolean, satisfied: boolean, error?: string }}
 */
export function validateFinalLine(task, finalLine) {
	const exact = task.expectedFinalLine ?? [];
	const patterns = task.expectedFinalLinePattern ?? [];
	const required = exact.length > 0 || patterns.length > 0;
	if (!required) return { required: false, satisfied: true };
	if (exact.includes(finalLine)) return { required: true, satisfied: true };
	for (const pattern of patterns) {
		try {
			if (new RegExp(pattern).test(finalLine)) return { required: true, satisfied: true };
		} catch (error) {
			return {
				required: true,
				satisfied: false,
				error: `invalid expectedFinalLinePattern ${JSON.stringify(pattern)}: ${error.message}`,
			};
		}
	}
	return {
		required: true,
		satisfied: false,
		error: `final line ${JSON.stringify(finalLine)} did not match expected contract`,
	};
}

// ─── resolveTask ──────────────────────────────────────────────────────────────

/**
 * Async version of resolveTask that handles optional `role` loading.
 *
 * When `task.role` is provided:
 *   1. Load the named role from rolesDir
 *   2. Set model from role's `pi-model:` (unless explicit model overrides)
 *   3. Set tools from role (unless explicit tools override)
 *   4. Derive expectedFinalLine from `output-contract`
 *   5. Prepend role brief to task text
 *
 * When no role: behaves identically to the original synchronous resolveTask
 * (ADR-001 D2 additive — inline task without role still works).
 *
 * @param {object} taskInput - TaskInput (may include .role field)
 * @param {object} config - SubagentConfig
 * @param {object} topLevel - top-level SubagentInput overrides
 * @param {number} index - task index for label generation
 * @param {string} rolesDir - path to role .md files directory
 * @param {string} skillsDir - path to skill directories
 * @returns {Promise<ResolvedTask>}
 */
export async function resolveTask(taskInput, config = DEFAULT_CONFIG, topLevel = {}, index = 0, rolesDir, skillsDir) {
	const modelTier = taskInput.modelTier ?? topLevel.modelTier ?? config.defaultModelTier;
	const tierConfig = config.modelTiers[modelTier];

	if (taskInput.role) {
		// Role-based path (ADR-002 D3/D4)
		const roleData = await loadRole(taskInput.role, rolesDir, skillsDir);

		// Explicit model overrides role's pi-model (ADR-002 D4)
		const explicitModel = taskInput.model ?? topLevel.model;
		const model = explicitModel ?? roleData.piModel ?? tierConfig.model;

		// Explicit tools override role's tools
		const tools = taskInput.tools ?? topLevel.tools ?? roleData.tools;

		// Derive expectedFinalLine from output-contract
		const roleContract = roleData.outputContract
			? [roleData.outputContract]
			: undefined;
		const expectedFinalLine = taskInput.expectedFinalLine ?? topLevel.expectedFinalLine ?? roleContract;

		// Prepend role brief to task text
		const fullTask = roleData.brief.trim()
			? `${roleData.brief.trim()}\n\n---\n\n${taskInput.task}`
			: taskInput.task;

		return {
			label: taskInput.label ?? `subagent-${index + 1}`,
			task: fullTask,
			modelTier,
			model,
			thinking: taskInput.thinking ?? topLevel.thinking ?? (explicitModel ? undefined : tierConfig.thinking),
			tools,
			expectedFinalLine,
			expectedFinalLinePattern: taskInput.expectedFinalLinePattern ?? topLevel.expectedFinalLinePattern,
			timeoutMs: taskInput.timeoutMs ?? topLevel.timeoutMs ?? config.timeoutMs,
		};
	}

	// Inline-task path (no role) — ADR-001 D2 additive; identical to original resolveTask
	const explicitModel = taskInput.model ?? topLevel.model;
	return {
		label: taskInput.label ?? `subagent-${index + 1}`,
		task: taskInput.task,
		modelTier,
		model: explicitModel ?? tierConfig.model,
		thinking: taskInput.thinking ?? topLevel.thinking ?? (explicitModel ? undefined : tierConfig.thinking),
		tools: taskInput.tools ?? topLevel.tools ?? config.defaultTools,
		expectedFinalLine: taskInput.expectedFinalLine ?? topLevel.expectedFinalLine,
		expectedFinalLinePattern: taskInput.expectedFinalLinePattern ?? topLevel.expectedFinalLinePattern,
		timeoutMs: taskInput.timeoutMs ?? topLevel.timeoutMs ?? config.timeoutMs,
	};
}
