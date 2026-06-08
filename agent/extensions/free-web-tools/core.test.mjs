import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  ProviderError,
  SafetyError,
  defaultConfig,
  isBlockedIp,
  loadApiKeys,
  parseAndValidateUrl,
  providerOrder,
  redactSecrets,
  runWaterfall,
  truncateWindow,
  validateConfig,
  validateUrlSafety,
  webFetch,
} from "./core.mjs";

assert.equal(isBlockedIp("127.0.0.1"), true);
assert.equal(isBlockedIp("10.0.0.1"), true);
assert.equal(isBlockedIp("172.16.1.2"), true);
assert.equal(isBlockedIp("192.168.1.1"), true);
assert.equal(isBlockedIp("169.254.169.254"), true);
assert.equal(isBlockedIp("::ffff:127.0.0.1"), true);
assert.equal(isBlockedIp("8.8.8.8"), false);
assert.throws(() => parseAndValidateUrl("file:///etc/passwd"), SafetyError);
assert.throws(() => parseAndValidateUrl("https://user:pass@example.com"), SafetyError);
assert.throws(() => parseAndValidateUrl("http://127.0.0.1"), SafetyError);
assert.throws(() => parseAndValidateUrl("http://service.internal"), SafetyError);

await assert.rejects(
  () => validateUrlSafety("https://example.com", async () => [{ address: "127.0.0.1", family: 4 }]),
  /blocked address/,
);
await validateUrlSafety("https://example.com", async () => [{ address: "93.184.216.34", family: 4 }]);

const cfg = validateConfig({ searchProviderOrder: ["brave", "unknown", "duckduckgo", "brave"], timeoutMs: 10, defaultFetchChars: 999999 });
assert.deepEqual(cfg.searchProviderOrder.slice(0, 2), ["brave", "duckduckgo"]);
assert.equal(cfg.timeoutMs, defaultConfig().timeoutMs);
assert.equal(cfg.defaultFetchChars, defaultConfig().defaultFetchChars);
assert.deepEqual(providerOrder("search", "auto", defaultConfig(), { brave: "", tavily: "", firecrawl: "", jina: "" }), ["duckduckgo", "jina"]);
assert.deepEqual(providerOrder("fetch", "auto", defaultConfig(), { brave: "", tavily: "", firecrawl: "", jina: "" }), ["jina", "direct"]);

const page = truncateWindow("abcdefghijklmnopqrstuvwxyz", 5, 10);
assert.equal(page.text, "fghijklmno");
assert.equal(page.nextOffset, 15);
assert.equal(page.truncated, true);
assert.equal(redactSecrets("key secret123 key", { jina: "secret123" }), "key [REDACTED] key");
const envDir = await mkdtemp(path.join(tmpdir(), "free-web-tools-env-test-"));
const envFile = path.join(envDir, ".env");
await writeFile(envFile, "JINA_API_KEY=file-jina\nFIRECRAWL_API_KEY=file-firecrawl\n", "utf8");
const keysFromFile = await loadApiKeys(envFile, { JINA_API_KEY: "process-jina" });
assert.equal(keysFromFile.jina, "process-jina");
assert.equal(keysFromFile.firecrawl, "file-firecrawl");
await rm(envDir, { recursive: true, force: true });

const transientResult = await runWaterfall(["a", "b"], async (provider) => {
  if (provider === "a") throw new ProviderError("a", "HTTP 429", { status: 429, transient: true });
  return { provider, ok: true };
});
assert.equal(transientResult.provider, "b");
assert.equal(transientResult.fallbackErrors.length, 1);

await assert.rejects(
  () => runWaterfall(["a", "b"], async (provider) => {
    if (provider === "a") throw new SafetyError("unsafe");
    return { provider };
  }),
  /All providers failed.*unsafe/,
);

const cacheDir = await mkdtemp(path.join(tmpdir(), "free-web-tools-test-"));
const oldFetch = globalThis.fetch;
globalThis.fetch = async () => ({ ok: true, status: 200, headers: new Headers(), text: async () => "<html><title>Hello</title><body><h1>Hello</h1><p>World</p></body></html>" });
try {
  const result = await webFetch({ url: "https://example.com", maxChars: 1000, provider: "direct" }, defaultConfig(), {}, cacheDir);
  assert.equal(result.provider, "direct");
  assert.match(result.text, /Hello/);
  const cached = await webFetch({ url: "https://example.com", maxChars: 1000, provider: "direct" }, defaultConfig(), {}, cacheDir);
  assert.equal(cached.cacheHit, true);
} finally {
  globalThis.fetch = oldFetch;
  await rm(cacheDir, { recursive: true, force: true });
}

const redirectCacheDir = await mkdtemp(path.join(tmpdir(), "free-web-tools-redirect-test-"));
globalThis.fetch = async () => ({ ok: false, status: 302, headers: new Headers({ location: "http://127.0.0.1/secret" }), text: async () => "" });
try {
  await assert.rejects(
    () => webFetch({ url: "https://example.com", maxChars: 1000, provider: "direct" }, defaultConfig(), {}, redirectCacheDir),
    /blocked|All providers failed/i,
  );
} finally {
  globalThis.fetch = oldFetch;
  await rm(redirectCacheDir, { recursive: true, force: true });
}

console.log("free-web-tools core tests passed");
