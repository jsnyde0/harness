import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

type DcgJson = {
	decision?: string;
	reason?: string;
	explanation?: string;
	rule_id?: string;
	pack_id?: string;
	severity?: string;
	command?: string;
};

type LastDecision = {
	command: string;
	allowed: boolean;
	reason: string;
	ruleId?: string;
	at: string;
};

const DCG_BIN = "dcg";
const DCG_TIMEOUT_MS = 2500;

function extractCommand(input: unknown): string | undefined {
	if (!input || typeof input !== "object") return undefined;
	const command = (input as { command?: unknown }).command;
	return typeof command === "string" ? command : undefined;
}

function parseDcgJson(stdout: string): DcgJson | undefined {
	const trimmed = stdout.trim();
	if (!trimmed) return undefined;
	try {
		return JSON.parse(trimmed) as DcgJson;
	} catch {
		return undefined;
	}
}

function formatBlockReason(prefix: string, result?: DcgJson): string {
	const rule = result?.rule_id ? ` (${result.rule_id})` : "";
	const reason = result?.reason || result?.explanation || "command was denied";
	return `${prefix}${rule}: ${reason}`;
}

export default function (pi: ExtensionAPI) {
	let lastDecision: LastDecision | undefined;

	pi.on("tool_call", async (event) => {
		if (event.toolName !== "bash") return undefined;

		const command = extractCommand(event.input);
		if (!command) {
			lastDecision = {
				command: "<missing>",
				allowed: false,
				reason: "Blocked by DCG: bash tool call did not include a command string",
				at: new Date().toISOString(),
			};
			return { block: true, reason: lastDecision.reason };
		}

		const result = await pi.exec(DCG_BIN, ["test", "--format", "json", command], { timeout: DCG_TIMEOUT_MS });
		const parsed = parseDcgJson(result.stdout);

		if (result.killed) {
			const reason = `Blocked by DCG: verification timed out after ${DCG_TIMEOUT_MS}ms`;
			lastDecision = { command, allowed: false, reason, at: new Date().toISOString() };
			return { block: true, reason };
		}

		if (result.code === 0 && parsed?.decision !== "deny") {
			lastDecision = {
				command,
				allowed: true,
				reason: parsed?.reason || "Allowed by DCG",
				at: new Date().toISOString(),
			};
			return undefined;
		}

		if (parsed?.decision === "deny") {
			const reason = formatBlockReason("Blocked by DCG", parsed);
			lastDecision = {
				command,
				allowed: false,
				reason,
				ruleId: parsed.rule_id,
				at: new Date().toISOString(),
			};
			return { block: true, reason };
		}

		if (result.code === 127 || /not found|ENOENT/i.test(result.stderr)) {
			const reason = `Blocked by DCG: '${DCG_BIN}' was not found. Install/configure destructive_command_guard or disable the dcg Pi extension.`;
			lastDecision = { command, allowed: false, reason, at: new Date().toISOString() };
			return { block: true, reason };
		}

		if (!parsed) {
			const reason = "Blocked by DCG: verification returned invalid JSON";
			lastDecision = { command, allowed: false, reason, at: new Date().toISOString() };
			return { block: true, reason };
		}

		const reason = `Blocked by DCG: verification failed with exit code ${result.code}`;
		lastDecision = { command, allowed: false, reason, at: new Date().toISOString() };
		return { block: true, reason };
	});

	pi.registerCommand("dcg", {
		description: "Show DCG guard status for Pi bash tool calls",
		handler: async (_args, ctx) => {
			const probe = await pi.exec(DCG_BIN, ["--version"], { timeout: DCG_TIMEOUT_MS });
			const available = probe.code === 0;
			const lines = [
				"DCG guard: enabled",
				`binary: ${DCG_BIN} ${available ? "found" : "not found"}`,
				`timeout: ${DCG_TIMEOUT_MS}ms`,
				"failure policy: fail-closed",
			];

			if (lastDecision) {
				lines.push(
					"",
					"last decision:",
					`- at: ${lastDecision.at}`,
					`- allowed: ${lastDecision.allowed}`,
					`- command: ${lastDecision.command}`,
					`- reason: ${lastDecision.reason}`,
				);
			}

			ctx.ui.notify(lines.join("\n"), available ? "info" : "warning");
		},
	});
}
