import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";
import { loadRole, validateFinalLine } from "./role-loader.mjs";

export const CONFIG_PATH = path.join(os.homedir(), ".pi", "agent", "extensions", "subagent", "config.json");
// NOTE: ROLES_DIR is populated by the install skill; production role dispatch requires it.
export const ROLES_DIR = path.join(os.homedir(), ".pi", "agent", "roles");
export const SKILLS_DIR = path.join(os.homedir(), ".pi", "agent", "skills");
export const SIGKILL_GRACE_MS = 2000;
export const OUTPUT_PREVIEW_CHARS = 4000;

export const MODEL_TIERS = ["basic", "medium", "smart", "max"] as const;
export type ModelTier = (typeof MODEL_TIERS)[number];

export const THINKING_LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh"] as const;
export type ThinkingLevel = (typeof THINKING_LEVELS)[number];

type TierConfig = {
	model: string;
	thinking?: ThinkingLevel;
};

export type SubagentConfig = {
	defaultModelTier: ModelTier;
	defaultTools: string[];
	maxParallelTasks: number;
	maxConcurrency: number;
	timeoutMs: number;
	modelTiers: Record<ModelTier, TierConfig>;
};

export type TaskInput = {
	label?: string;
	task: string;
	role?: string;
	modelTier?: ModelTier;
	model?: string;
	thinking?: ThinkingLevel;
	tools?: string[];
	expectedFinalLine?: string[];
	expectedFinalLinePattern?: string[];
	timeoutMs?: number;
};

export type SubagentInput = {
	label?: string;
	task?: string;
	role?: string;
	tasks?: TaskInput[];
	modelTier?: ModelTier;
	model?: string;
	thinking?: ThinkingLevel;
	tools?: string[];
	expectedFinalLine?: string[];
	expectedFinalLinePattern?: string[];
	timeoutMs?: number;
};

export type ResolvedTask = {
	label: string;
	task: string;
	modelTier: ModelTier;
	model: string;
	thinking?: ThinkingLevel;
	tools: string[];
	expectedFinalLine?: string[];
	expectedFinalLinePattern?: string[];
	timeoutMs: number;
};

export type ValidationResult =
	| { ok: true; mode: "single" | "parallel"; tasks: TaskInput[] }
	| { ok: false; errors: string[] };

export type Usage = {
	input?: number;
	output?: number;
	cacheRead?: number;
	cacheWrite?: number;
	totalTokens?: number;
	cost?: unknown;
};

export type SubagentResult = {
	label: string;
	taskPreview: string;
	command: string;
	args: string[];
	exitCode: number | null;
	signal: NodeJS.Signals | null;
	timedOut: boolean;
	aborted: boolean;
	durationMs: number;
	stdoutBytes: number;
	stderr: string;
	outputPreview: string;
	finalLine: string;
	contractRequired: boolean;
	contractSatisfied: boolean;
	contractError?: string;
	resolved: Omit<ResolvedTask, "task">;
	usage?: Usage;
	parseErrors: string[];
};

export const DEFAULT_CONFIG: SubagentConfig = {
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

function isRecord(value: unknown): value is Record<string, unknown> {
	return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isModelTier(value: unknown): value is ModelTier {
	return typeof value === "string" && (MODEL_TIERS as readonly string[]).includes(value);
}

function isThinkingLevel(value: unknown): value is ThinkingLevel {
	return typeof value === "string" && (THINKING_LEVELS as readonly string[]).includes(value);
}

function asStringArray(value: unknown): string[] | undefined {
	if (value === undefined) return undefined;
	if (!Array.isArray(value) || value.length === 0) return undefined;
	if (value.some((item) => typeof item !== "string" || item.length === 0)) return undefined;
	return value;
}

function asPositiveInteger(value: unknown): number | undefined {
	return typeof value === "number" && Number.isInteger(value) && value > 0 ? value : undefined;
}

function mergeConfig(raw: unknown): SubagentConfig {
	if (!isRecord(raw)) return DEFAULT_CONFIG;

	const modelTiers: Record<ModelTier, TierConfig> = { ...DEFAULT_CONFIG.modelTiers };
	if (isRecord(raw.modelTiers)) {
		for (const tier of MODEL_TIERS) {
			const rawTier = raw.modelTiers[tier];
			if (!isRecord(rawTier)) continue;
			const model = typeof rawTier.model === "string" && rawTier.model.length > 0 ? rawTier.model : modelTiers[tier].model;
			const thinking = isThinkingLevel(rawTier.thinking) ? rawTier.thinking : modelTiers[tier].thinking;
			modelTiers[tier] = { model, thinking };
		}
	}

	return {
		defaultModelTier: isModelTier(raw.defaultModelTier) ? raw.defaultModelTier : DEFAULT_CONFIG.defaultModelTier,
		defaultTools: asStringArray(raw.defaultTools) ?? DEFAULT_CONFIG.defaultTools,
		maxParallelTasks: asPositiveInteger(raw.maxParallelTasks) ?? DEFAULT_CONFIG.maxParallelTasks,
		maxConcurrency: asPositiveInteger(raw.maxConcurrency) ?? DEFAULT_CONFIG.maxConcurrency,
		timeoutMs: asPositiveInteger(raw.timeoutMs) ?? DEFAULT_CONFIG.timeoutMs,
		modelTiers,
	};
}

export function loadConfig(configPath = CONFIG_PATH): SubagentConfig {
	try {
		return mergeConfig(JSON.parse(fs.readFileSync(configPath, "utf8")));
	} catch (error) {
		const code = (error as NodeJS.ErrnoException).code;
		if (code === "ENOENT") return DEFAULT_CONFIG;
		throw new Error(`Failed to load subagent config from ${configPath}: ${(error as Error).message}`);
	}
}

function validateTaskShape(task: unknown, index: number): string[] {
	const prefix = `tasks[${index}]`;
	if (!isRecord(task)) return [`${prefix} must be an object`];
	const errors: string[] = [];
	if (typeof task.task !== "string" || task.task.trim().length === 0) errors.push(`${prefix}.task must be a non-empty string`);
	if (task.label !== undefined && typeof task.label !== "string") errors.push(`${prefix}.label must be a string`);
	if (task.role !== undefined && (typeof task.role !== "string" || task.role.trim().length === 0)) errors.push(`${prefix}.role must be a non-empty string`);
	if (task.modelTier !== undefined && !isModelTier(task.modelTier)) errors.push(`${prefix}.modelTier must be one of ${MODEL_TIERS.join(", ")}`);
	if (task.model !== undefined && (typeof task.model !== "string" || task.model.trim().length === 0)) errors.push(`${prefix}.model must be a non-empty string`);
	if (task.thinking !== undefined && !isThinkingLevel(task.thinking)) errors.push(`${prefix}.thinking must be one of ${THINKING_LEVELS.join(", ")}`);
	if (task.tools !== undefined && !asStringArray(task.tools)) errors.push(`${prefix}.tools must be a non-empty string array`);
	if (task.expectedFinalLine !== undefined && !asStringArray(task.expectedFinalLine)) errors.push(`${prefix}.expectedFinalLine must be a non-empty string array`);
	if (task.expectedFinalLinePattern !== undefined && !asStringArray(task.expectedFinalLinePattern)) errors.push(`${prefix}.expectedFinalLinePattern must be a non-empty string array`);
	if (task.timeoutMs !== undefined && !asPositiveInteger(task.timeoutMs)) errors.push(`${prefix}.timeoutMs must be a positive integer`);
	return errors;
}

export function validateInput(input: unknown, config: SubagentConfig = DEFAULT_CONFIG): ValidationResult {
	if (!isRecord(input)) return { ok: false, errors: ["input must be an object"] };

	const hasTask = Object.prototype.hasOwnProperty.call(input, "task");
	const hasTasks = Object.prototype.hasOwnProperty.call(input, "tasks");
	const errors: string[] = [];

	if (hasTask === hasTasks) errors.push("exactly one of task or tasks must be provided");
	if (input.role !== undefined && (typeof input.role !== "string" || input.role.trim().length === 0)) errors.push("role must be a non-empty string");
	if (input.modelTier !== undefined && !isModelTier(input.modelTier)) errors.push(`modelTier must be one of ${MODEL_TIERS.join(", ")}`);
	if (input.model !== undefined && (typeof input.model !== "string" || input.model.trim().length === 0)) errors.push("model must be a non-empty string");
	if (input.thinking !== undefined && !isThinkingLevel(input.thinking)) errors.push(`thinking must be one of ${THINKING_LEVELS.join(", ")}`);
	if (input.tools !== undefined && !asStringArray(input.tools)) errors.push("tools must be a non-empty string array");
	if (input.expectedFinalLine !== undefined && !asStringArray(input.expectedFinalLine)) errors.push("expectedFinalLine must be a non-empty string array");
	if (input.expectedFinalLinePattern !== undefined && !asStringArray(input.expectedFinalLinePattern)) errors.push("expectedFinalLinePattern must be a non-empty string array");
	if (input.timeoutMs !== undefined && !asPositiveInteger(input.timeoutMs)) errors.push("timeoutMs must be a positive integer");

	if (hasTask) {
		if (typeof input.task !== "string" || input.task.trim().length === 0) errors.push("task must be a non-empty string");
		if (input.label !== undefined && typeof input.label !== "string") errors.push("label must be a string");
		if (errors.length > 0) return { ok: false, errors };
		return { ok: true, mode: "single", tasks: [{ ...(input as SubagentInput), task: input.task as string }] };
	}

	if (hasTasks) {
		if (!Array.isArray(input.tasks)) {
			errors.push("tasks must be an array");
		} else {
			if (input.tasks.length === 0) errors.push("tasks must contain at least one task");
			if (input.tasks.length > config.maxParallelTasks) errors.push(`tasks must not exceed maxParallelTasks (${config.maxParallelTasks})`);
			input.tasks.forEach((task, index) => errors.push(...validateTaskShape(task, index)));
		}
	}

	if (errors.length > 0) return { ok: false, errors };
	return { ok: true, mode: "parallel", tasks: input.tasks as TaskInput[] };
}

export async function resolveTask(task: TaskInput, config: SubagentConfig = DEFAULT_CONFIG, topLevel: Omit<SubagentInput, "task" | "tasks" | "label"> = {}, index = 0, rolesDir = ROLES_DIR, skillsDir = SKILLS_DIR): Promise<ResolvedTask> {
	const modelTier = task.modelTier ?? topLevel.modelTier ?? config.defaultModelTier;
	const tierConfig = config.modelTiers[modelTier];

	if (task.role) {
		// Role-based path (ADR-002 D3/D4):
		// Load role file from rolesDir, inline skills, read pi-model slug.
		// NOTE: reads `pi-model:` only — never `model:` (that's CC's concern).
		// No hardcoded role identity — resolved by task.role name.
		const roleData = await loadRole(task.role, rolesDir, skillsDir);

		// Explicit model overrides role's pi-model (ADR-002 D4)
		const explicitModel = task.model ?? topLevel.model;
		const model = explicitModel ?? (roleData.piModel as string | undefined) ?? tierConfig.model;

		// Explicit tools override role's tools
		const tools = task.tools ?? topLevel.tools ?? (roleData.tools as string[]);

		// Derive expectedFinalLine from output-contract
		const roleContract = (roleData.outputContract as string | undefined)
			? [(roleData.outputContract as string)]
			: undefined;
		const expectedFinalLine = task.expectedFinalLine ?? topLevel.expectedFinalLine ?? roleContract;

		// Prepend role brief to task text
		const brief = (roleData.brief as string).trim();
		const fullTask = brief ? `${brief}\n\n---\n\n${task.task}` : task.task;

		return {
			label: task.label ?? `subagent-${index + 1}`,
			task: fullTask,
			modelTier,
			model,
			thinking: task.thinking ?? topLevel.thinking ?? (explicitModel ? undefined : tierConfig.thinking),
			tools,
			expectedFinalLine,
			expectedFinalLinePattern: task.expectedFinalLinePattern ?? topLevel.expectedFinalLinePattern,
			timeoutMs: task.timeoutMs ?? topLevel.timeoutMs ?? config.timeoutMs,
		};
	}

	// Inline-task path (no role) — ADR-001 D2 additive; original behavior preserved
	const explicitModel = task.model ?? topLevel.model;
	return {
		label: task.label ?? `subagent-${index + 1}`,
		task: task.task,
		modelTier,
		model: explicitModel ?? tierConfig.model,
		thinking: task.thinking ?? topLevel.thinking ?? (explicitModel ? undefined : tierConfig.thinking),
		tools: task.tools ?? topLevel.tools ?? config.defaultTools,
		expectedFinalLine: task.expectedFinalLine ?? topLevel.expectedFinalLine,
		expectedFinalLinePattern: task.expectedFinalLinePattern ?? topLevel.expectedFinalLinePattern,
		timeoutMs: task.timeoutMs ?? topLevel.timeoutMs ?? config.timeoutMs,
	};
}

export async function resolveTasks(input: SubagentInput, config: SubagentConfig = DEFAULT_CONFIG): Promise<ResolvedTask[]> {
	const validation = validateInput(input, config);
	if (!validation.ok) throw new Error(validation.errors.join("; "));
	const topLevel = {
		role: input.role,
		modelTier: input.modelTier,
		model: input.model,
		thinking: input.thinking,
		tools: input.tools,
		expectedFinalLine: input.expectedFinalLine,
		expectedFinalLinePattern: input.expectedFinalLinePattern,
		timeoutMs: input.timeoutMs,
	};
	return Promise.all(validation.tasks.map((task, index) => resolveTask(task, config, topLevel, index)));
}

export function buildChildCommand(task: ResolvedTask): { command: string; args: string[] } {
	const args = ["--mode", "json", "-p", "--no-session", "--model", task.model];
	if (task.thinking) args.push("--thinking", task.thinking);
	if (task.tools.length > 0) args.push("--tools", task.tools.join(","));
	args.push(task.task);
	return { command: "pi", args };
}

function extractTextContent(message: unknown): string {
	if (!isRecord(message) || !Array.isArray(message.content)) return "";
	return message.content
		.filter((part): part is { type: string; text: string } => isRecord(part) && part.type === "text" && typeof part.text === "string")
		.map((part) => part.text)
		.join("\n");
}

function maybeUsage(value: unknown): Usage | undefined {
	return isRecord(value) ? (value as Usage) : undefined;
}

function applyJsonEvent(event: unknown, state: { finalAssistantText: string; usage?: Usage }) {
	if (!isRecord(event)) return;
	if (event.type === "message_end" && isRecord(event.message) && event.message.role === "assistant") {
		const text = extractTextContent(event.message);
		if (text) state.finalAssistantText = text;
		state.usage = maybeUsage(event.message.usage) ?? state.usage;
	}
	if (event.type === "turn_end" && isRecord(event.message) && event.message.role === "assistant") {
		const text = extractTextContent(event.message);
		if (text) state.finalAssistantText = text;
		state.usage = maybeUsage(event.message.usage) ?? state.usage;
	}
	if (event.type === "agent_end" && Array.isArray(event.messages)) {
		for (let i = event.messages.length - 1; i >= 0; i--) {
			const message = event.messages[i];
			if (isRecord(message) && message.role === "assistant") {
				const text = extractTextContent(message);
				if (text) state.finalAssistantText = text;
				state.usage = maybeUsage(message.usage) ?? state.usage;
				break;
			}
		}
	}
}

export function getFinalLine(text: string): string {
	const lines = text.trimEnd().split(/\r?\n/).map((line) => line.trim()).filter((line) => line.length > 0);
	return lines.at(-1) ?? "";
}


function preview(text: string, limit = OUTPUT_PREVIEW_CHARS): string {
	return text.length <= limit ? text : `${text.slice(0, limit)}…`;
}

export async function runResolvedTask(task: ResolvedTask, signal?: AbortSignal): Promise<SubagentResult> {
	const started = Date.now();
	const { command, args } = buildChildCommand(task);
	const child = spawn(command, args, { cwd: process.cwd(), stdio: ["ignore", "pipe", "pipe"] });
	const state = { finalAssistantText: "", usage: undefined as Usage | undefined };
	const parseErrors: string[] = [];
	let stdoutBytes = 0;
	let stdoutBuffer = "";
	let stderr = "";
	let timedOut = false;
	let aborted = false;
	let settled = false;
	let killTimer: NodeJS.Timeout | undefined;

	const terminate = (reason: "timeout" | "abort") => {
		if (settled) return;
		if (reason === "timeout") timedOut = true;
		if (reason === "abort") aborted = true;
		child.kill("SIGTERM");
		killTimer = setTimeout(() => {
			if (!settled) child.kill("SIGKILL");
		}, SIGKILL_GRACE_MS);
	};

	const timeout = setTimeout(() => terminate("timeout"), task.timeoutMs);
	const onAbort = () => terminate("abort");
	if (signal) signal.addEventListener("abort", onAbort, { once: true });

	child.stdout.on("data", (chunk: Buffer) => {
		stdoutBytes += chunk.length;
		stdoutBuffer += chunk.toString("utf8");
		let newline = stdoutBuffer.indexOf("\n");
		while (newline >= 0) {
			const line = stdoutBuffer.slice(0, newline).trim();
			stdoutBuffer = stdoutBuffer.slice(newline + 1);
			if (line.length > 0) {
				try {
					applyJsonEvent(JSON.parse(line), state);
				} catch (error) {
					parseErrors.push(`failed to parse JSONL line: ${(error as Error).message}`);
				}
			}
			newline = stdoutBuffer.indexOf("\n");
		}
	});
	child.stderr.on("data", (chunk: Buffer) => {
		stderr += chunk.toString("utf8");
	});

	return await new Promise((resolve) => {
		child.on("close", (exitCode, closeSignal) => {
			settled = true;
			clearTimeout(timeout);
			if (killTimer) clearTimeout(killTimer);
			if (signal) signal.removeEventListener("abort", onAbort);
			const trailing = stdoutBuffer.trim();
			if (trailing.length > 0) {
				try {
					applyJsonEvent(JSON.parse(trailing), state);
				} catch (error) {
					parseErrors.push(`failed to parse trailing JSONL: ${(error as Error).message}`);
				}
			}
			const finalLine = getFinalLine(state.finalAssistantText);
			const contract = validateFinalLine(task, finalLine);
			resolve({
				label: task.label,
				taskPreview: preview(task.task, 500),
				command,
				args,
				exitCode,
				signal: closeSignal,
				timedOut,
				aborted,
				durationMs: Date.now() - started,
				stdoutBytes,
				stderr: preview(stderr),
				outputPreview: preview(state.finalAssistantText),
				finalLine,
				contractRequired: contract.required,
				contractSatisfied: contract.satisfied,
				contractError: contract.error,
				resolved: {
					label: task.label,
					modelTier: task.modelTier,
					model: task.model,
					thinking: task.thinking,
					tools: task.tools,
					expectedFinalLine: task.expectedFinalLine,
					expectedFinalLinePattern: task.expectedFinalLinePattern,
					timeoutMs: task.timeoutMs,
				},
				usage: state.usage,
				parseErrors,
			});
		});
	});
}

export async function mapWithConcurrency<TIn, TOut>(items: TIn[], concurrency: number, fn: (item: TIn, index: number) => Promise<TOut>): Promise<TOut[]> {
	const limit = Math.max(1, Math.min(concurrency, items.length));
	const results = new Array<TOut>(items.length);
	let next = 0;
	await Promise.all(
		new Array(limit).fill(null).map(async () => {
			while (next < items.length) {
				const index = next++;
				results[index] = await fn(items[index], index);
			}
		}),
	);
	return results;
}

async function runAll(input: SubagentInput, config: SubagentConfig, signal?: AbortSignal): Promise<{ mode: "single" | "parallel"; results: SubagentResult[] }> {
	const validation = validateInput(input, config);
	if (!validation.ok) throw new Error(validation.errors.join("; "));
	const resolved = await resolveTasks(input, config);
	const concurrency = validation.mode === "single" ? 1 : Math.min(config.maxConcurrency, resolved.length);
	const results = await mapWithConcurrency(resolved, concurrency, (task) => runResolvedTask(task, signal));
	return { mode: validation.mode, results };
}

const thinkingSchema = Type.Union([
	Type.Literal("off"),
	Type.Literal("minimal"),
	Type.Literal("low"),
	Type.Literal("medium"),
	Type.Literal("high"),
	Type.Literal("xhigh"),
]);
const modelTierSchema = Type.Union([Type.Literal("basic"), Type.Literal("medium"), Type.Literal("smart"), Type.Literal("max")]);

const taskSchema = Type.Object({
	label: Type.Optional(Type.String({ description: "Display label for this child task" })),
	task: Type.String({ description: "Full inline role brief and task for the child Pi process" }),
	role: Type.Optional(Type.String({ description: "Named role to load from ~/.pi/agent/roles/<name>.md; sets model/tools/brief/output-contract" })),
	modelTier: Type.Optional(modelTierSchema),
	model: Type.Optional(Type.String({ description: "Concrete model override; bypasses modelTier resolution and role pi-model" })),
	thinking: Type.Optional(thinkingSchema),
	tools: Type.Optional(Type.Array(Type.String(), { description: "Tool allowlist override for the child Pi process; overrides role tools" })),
	expectedFinalLine: Type.Optional(Type.Array(Type.String())),
	expectedFinalLinePattern: Type.Optional(Type.Array(Type.String())),
	timeoutMs: Type.Optional(Type.Number({ description: "Child timeout in milliseconds" })),
});

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "subagent",
		label: "Subagent",
		description: "Run one inline task, or a bounded tasks[] set, in fresh child Pi subprocesses with structured results and final-line contract checks.",
		parameters: Type.Object({
			label: Type.Optional(Type.String({ description: "Display label for a single child task" })),
			task: Type.Optional(Type.String({ description: "Full inline role brief and task for one child Pi process" })),
			role: Type.Optional(Type.String({ description: "Named role to load from ~/.pi/agent/roles/<name>.md for a single task; sets model/tools/brief/output-contract" })),
			tasks: Type.Optional(Type.Array(taskSchema, { description: "Bounded parallel child tasks" })),
			modelTier: Type.Optional(modelTierSchema),
			model: Type.Optional(Type.String({ description: "Concrete model override; bypasses modelTier resolution and role pi-model" })),
			thinking: Type.Optional(thinkingSchema),
			tools: Type.Optional(Type.Array(Type.String(), { description: "Default tool allowlist for child task(s); overrides role tools" })),
			expectedFinalLine: Type.Optional(Type.Array(Type.String())),
			expectedFinalLinePattern: Type.Optional(Type.Array(Type.String())),
			timeoutMs: Type.Optional(Type.Number({ description: "Default child timeout in milliseconds" })),
		}),
		async execute(_toolCallId, params, signal) {
			const config = loadConfig();
			const validation = validateInput(params, config);
			if (!validation.ok) {
				return {
					content: [{ type: "text", text: `subagent validation failed:\n- ${validation.errors.join("\n- ")}` }],
					details: { ok: false, errors: validation.errors, configPath: CONFIG_PATH },
				};
			}

			const { mode, results } = await runAll(params as SubagentInput, config, signal);
			const failed = results.filter((result) => result.exitCode !== 0 || result.timedOut || result.aborted || !result.contractSatisfied);
			const summary = results
				.map((result) => {
					const status = result.exitCode === 0 && !result.timedOut && !result.aborted && result.contractSatisfied ? "ok" : "failed";
					const contract = result.contractRequired ? ` contract=${result.contractSatisfied ? "ok" : "failed"}` : " contract=not-required";
					return `- ${result.label}: ${status} exit=${result.exitCode} timeout=${result.timedOut}${contract} final=${JSON.stringify(result.finalLine)}`;
				})
				.join("\n");
			return {
				content: [{ type: "text", text: `subagent ${mode} completed ${results.length} task(s), ${failed.length} failed\n${summary}` }],
				details: { ok: failed.length === 0, mode, configPath: CONFIG_PATH, results },
			};
		},
	});
}
