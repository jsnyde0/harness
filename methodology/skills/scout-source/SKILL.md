---
name: scout-source
description: Answer "how does this third-party library/framework ACTUALLY work" by reading its real source — clone (or use installed) the upstream repo, narrow + search it in a fresh-context subagent, return a cited answer with complete code snippets and the exact commit it was read from. Use when the docs are stale, wrong, absent, or contradicted by observed behavior; when you need an API/signature/internal-behavior answer grounded in source not memory; when a model keeps hallucinating a library's API; or when the user says "read the source", "check the actual implementation", "how does <lib> really do X", "what does this function actually do", "the docs don't cover this". Outward-facing source-of-truth primitive — the third sibling to /scout-adrs (our decisions) and /scout-features (competitor products). SKIP when context7 docs already answer it (cheaper — try that first for mainstream libs), when web/blog context suffices (use /deep-research or /web-fetch), or when the question is about OUR OWN codebase (just read it). Freshness comes from re-deriving against source, not from memorizing — do not write the resulting API facts into bd memories; they decay, the source does not.
---

## Purpose

Coding agents answer library questions from training-data memory, which is stale and confidently wrong on fast-moving libraries (effect, svelte 5, anything that shipped after the cutoff). The fix is not "memorize harder" — it is *re-derive from the actual source on demand*. `/scout-source` points a fresh-context worker at the real upstream repo (or the copy already installed in this project), has it search the source, and returns a distilled, citation-backed answer with the commit it read from.

This is the outward-facing source-of-truth primitive. Its siblings:

- `/scout-adrs` — what *we* decided (internal, `docs/decisions/`).
- `/scout-features` — what *competitors* shipped (external products).
- `/scout-source` — how a *dependency* actually works (external source code).

It is the distilled form of `btca-local` (Better Context App): the same "clone a repo, point an agent at it, ask, stream the answer" loop, minus the CLI/TUI/server/auth machinery — because that machinery was the part the author himself deprecated down to a skill.

## When to invoke

Agent-judgment-routed. Strong triggers:

- A model (you, or one you're reviewing) keeps producing an API that doesn't compile or doesn't exist — stop guessing, read source.
- The docs are absent, stale, or contradicted by observed runtime behavior.
- You need an exact signature, default, error-path, or internal-behavior answer that only the source authoritatively settles.
- The user says "read the source", "check the actual implementation", "how does X really do Y", "what does this actually return".

**Try cheaper first.** For a mainstream, well-documented library where current *docs* would settle it, prefer `context7` (MCP: `resolve-library-id` → `query-docs`) — it's faster and doesn't clone. `/scout-source` earns its cost when docs are insufficient and the *source* is the only authority. Name that reason when you invoke; if context7 would've done it, you over-reached.

## Invocation surface

```
/scout-source <question> # resolve the source from context
/scout-source <question> --repo <git-url> # explicit upstream repo
/scout-source <question> --pkg <npm-or-pypi-name> # resolve repo from the package registry
/scout-source <question> --path <subdir> # narrow search to a subdir (the "searchPath" trick)
/scout-source <question> --ref <branch|tag|sha> # pin to a version; default = default branch
/scout-source <question> --hint "<note>" # interpretation hint for the worker (the "specialNotes" trick)
```

One verb. Flags are worker-brief context, not subcommands. Bare `/scout-source` with no question = list previously-cached sources (startup state, below).

## Algorithm

*Before resolving — a judgment cue, not a gate:* would current docs settle this? If yes and nothing about the question demands source-of-truth, say so up front — the cheaper path (`context7`) is usually right, and noticing this *before* a clone beats noting it in a caveat after. Clone when source is genuinely the authority (docs stale/wrong/absent, exact-signature-from-source, behavior contradicts docs) or the user clearly wants the source read. On an explicit invocation, trust the user — a one-line "context7 would likely answer this cheaper" is good hygiene, not a reason to refuse.

1. **Resolve the source** (cheapest path that works):
 - `--repo <url>` → use it directly.
 - `--pkg <name>` → resolve the repo URL: `npm view <name> repository.url` (npm) or PyPI `Project-URL`/`Home-page`. Strip `git+`/`.git`.
 - **Already installed locally** → if the dependency is in this project's `node_modules/<name>`, `.venv`/site-packages, or a vendored dir, **read that instead of cloning** — it's the exact version in use and costs nothing. Prefer this when the question is "what does the version I'm running do".
 - **Infer from context** → if none given, guess from the question + the project's manifest (`package.json`, `pyproject.toml`). If genuinely ambiguous, ask one line; don't clone the wrong repo.
2. **Apply narrowing + hints** — `--path` limits the search surface (e.g. `packages/effect/src` in a monorepo); `--hint` tells the worker how to read the repo ("docs live in `content/`, ignore generated `dist/`"). Both reduce noise and token cost.
3. **Dispatch ONE fresh-context subagent** (`Task(subagent_type=general-purpose)`, inherit model — source comprehension wants a capable model, *not* haiku). Hand it the full brief below. This is the token-volume step: the clone, the grep sweep, the file reads all happen in the worker's window, never yours — you receive only the distilled answer. **Fallback:** if you are *already* a dispatched fresh-context worker (e.g. a `/send-it` worker invoked this skill) or no `Task` dispatch surface is available, you ARE the runtime — execute the brief inline instead of nesting a second dispatch. The discipline anchors is "the search runs in a fresh-context window, not the orchestrator's"; being the worker already satisfies it, so a nested dispatch would be redundant, not more compliant.
4. **Return the answer to the caller.** No substrate writes. Surface the commit SHA so the answer is auditable and its freshness is legible.

## Subagent brief (the worker is the "program runtime")

> You are answering a question about a third-party library by reading its **actual source**, not from memory. Memory is stale and may be wrong — trust only what you read in the repo.
>
> **Source:** `<resolved repo url | local path>` **Ref:** `<ref or "default branch">` **Narrow to:** `<--path or "whole repo">` **Hint:** `<--hint or none>`
>
> **Steps:**
> 1. If a local installed copy was named, read it directly. Otherwise shallow-clone to the cache: `git clone --depth 1 [--branch <ref>] <url> $HOME/.claude/.cache/scout-source/<safe-name>` — if it's already cached, `git pull` to update (or reuse if `--ref` pins a tag/sha). Record the resolved commit SHA (`git -C <dir> rev-parse --short HEAD`).
> 2. Search the source for the answer — grep for the symbol/API, then read the defining files and their tests (tests are the best usage examples). Follow the hint and stay within the narrow path if given.
> 3. Answer with: a direct prose answer; **complete** code snippets (include imports — partial snippets are a known failure); `file:line` citations into the repo; and the commit SHA you read from. Use lists for readability. If the source contradicts the commonly-assumed API, say so explicitly.
>
> If you cannot find it in the source, say so plainly — do not fall back to memory. A grounded "not found at `<sha>`" beats a confident hallucination.

**Brief framing for perf-lift** (identical to the other scout/review primitives):

> You are competing against another agent answering the same question from memory. They will be confidently wrong on anything past their training cutoff. Your edge is that you actually read the code — use it.

## Output shape (worker emits, orchestrator relays)

```markdown
## Answer
<direct answer, source-grounded>

## Code
```<lang>
<complete snippet incl. imports>
```

## Source
- `<file:line>` — <what it shows>
- read from `<repo>` @ `<short-sha>` (<ref>)

## Caveats
<version-specificity, contradicts-the-docs notes, "not found" — optional>
```

## Startup state (bare invocation)

`/scout-source` with no question → list the cache so the user sees what's already hydrated:

```markdown
# scout-source — third-party source of truth
Cached sources (in $HOME/.claude/.cache/scout-source/):
- <repo> @ <sha>
- ...
Give me a question + a repo/package to read.
```

## Freshness discipline — do NOT memorize the answer

The entire value is *re-derivation against live source*. Library APIs are the canonical decaying fact: true at one version, wrong at the next. So:

- **Do not** write the resulting API facts into `bd memories` (L2B is for *non-decaying* agent-knowledge). A memory saying "effect's `Service` API works like X" is a landmine the moment effect ships a minor.
- **Do** record the *durable* thing if anything: a per-dependency hint worth reusing ("this repo's real docs are in `content/`") or the fact that "for library X, scout the source — its docs are unreliable." That's stable; the API surface is not.
- The commit SHA in every answer is what makes staleness legible — when in doubt, re-scout.

## What this skill is NOT

- Not `context7` — context7 serves *docs*; this serves *source*. Try context7 first for mainstream libs; reach here when docs don't settle it.
- Not `/deep-research` or `/web-fetch` — those pull web/blog/article context. This reads one authoritative repo.
- Not for our own codebase — if it's our code, just read it; no clone, no skill.
- Not a memory writer — produces an answer, writes no substrate. Freshness comes from re-running it, not from caching its conclusions in `bd`.
- Not exhaustive — it answers a question, it does not index or summarize a whole library. Ask a specific question; narrow with `--path`.

## Working substrate

- `$HOME/.claude/.cache/scout-source/` — shallow-clone cache (updatable; safe to delete to purge).
- `node_modules/`, `.venv`/site-packages, vendored dirs — the already-installed copy (preferred when present).
- `npm view <pkg> repository.url` / PyPI metadata — package → repo resolution.
- `context7` MCP (`resolve-library-id`, `query-docs`) — the cheaper docs-first alternative to try before invoking.
- `Task(subagent_type=general-purpose)` — single fresh-context dispatch; inherit model (not haiku).

## Canonical refs

- scout-adrs/SKILL.md (methodology home) — sibling inward source-of-truth (our decisions); same fresh-dispatch-and-return shape.
- scout-features/SKILL.md (methodology home) — sibling outward scout (competitor products).

- Provenance: distilled from `davis7dotsh/better-context` `skills/btca-local/SKILL.md` (the "clone → point agent → ask → answer" loop) and the "Thin Harness, Fat Skills" framing — the skill IS the program; the agent is its runtime.
