---
name: browser-automation
description: Drive a real Chrome browser via small CLI scripts (start, nav, eval, wait, screenshot, pick, type) using Puppeteer + CDP. Use when you need to navigate web pages, scrape rendered content, evaluate JS in a live page, wait for content/redirects, take screenshots, type into fields with a real keyboard, or interactively pick DOM elements. Triggers on "open the browser", "navigate to", "screenshot this page", "run JS on a page", "wait for", "pick an element", "type into a field", "scrape with a real browser", "drive Chrome", "browser automation". Prefer this over WebFetch when the page is JS-rendered or needs session state, and prefer this over `web-fetch --provider firecrawl` when you need to interact with the page across multiple steps in the same session.
---

# Browser Automation

Seven small CLI scripts that drive a real Chrome over the Chrome DevTools Protocol via `puppeteer-core`. Adapted from Mario Zechner's pattern ([source](https://mariozechner.at/posts/2025-11-02-what-if-you-dont-need-mcp/)).

This is the canonical worked example of the "CLI > MCP for local + no-auth" heuristic in `design-claude-extension`.

## Paths — set `$SKILL` first

This skill is a single canonical source shared across harnesses (one directory, symlinked into each harness's skill tree). Its scripts resolve their own `node_modules`/`_tabs.js` relative to the script file, so `node $SKILL/<tool>.js` runs from **any** working directory — no `cd` needed. Set `$SKILL` once per session to this skill's directory:

```bash
export SKILL=$HOME/.claude/skills/browser-automation                    # Claude Code
export SKILL=$HOME/.pi/agent/skills/browser-automation               # pi (via install.sh symlink)
```

All commands below use `$SKILL/` so the same text works in either harness.

## When to use

- Page is JS-rendered or behind an SPA router (WebFetch returns shell HTML).
- You need session state across multiple page interactions (logged in, multi-step flow).
- You want to evaluate JS in the page's own context (inspect window/DOM/network state).
- You want a screenshot of the rendered viewport.

**Prefer over**: `WebFetch` (no JS), `web-fetch --provider firecrawl` (one-shot, no session), Playwright/Chrome-DevTools MCP (heavier tool surface).
**Don't use for**: batch scraping of many independent URLs (use `scrape-websites`), one-off static-HTML fetches (use `WebFetch`).

## Setup (first time only)

```bash
npm --prefix "$SKILL" install
```

Installs `puppeteer-core` into the canonical skill directory (no Chromium download — uses your installed Chrome). Because the skill is one symlinked source, this single `node_modules` is shared by every harness.

## Tab targeting (shared across nav, eval, wait, screenshot, pick, type)

Every per-tab script accepts the same targeting flags (mutually exclusive):

- *(none)* — last tab in `browser.pages()`. **Only reliable when there's exactly one tab.** Order is not creation-order or focus-order; with multiple tabs (including stale tabs restored from the persistent `~/.cache/scraping` profile), you may hit an unrelated tab.
- `--url=<substring>` — first tab whose URL contains the substring. Errors loudly if no tab matches.
- `--label=<name>` — the tab previously labeled `<name>` (see below). Errors loudly if the label is unknown or its tab has closed (and prunes the stale entry).

### Stable tab handles with `--label`

Open and label a tab in one step:

```bash
node $SKILL/nav.js https://news.ycombinator.com --new --label=hn
node $SKILL/nav.js https://lobste.rs            --new --label=lob
```

Then drive each tab independently by name:

```bash
node $SKILL/eval.js --label=hn 'document.title'
node $SKILL/wait.js --label=lob --selector='.story'
node $SKILL/screenshot.js --label=hn
```

Labels are stored in `~/.cache/scraping/tab-labels.json` as `{label: targetId}`. They persist across CLI invocations and survive `start.js` reconnects. If a labeled tab is closed, the next reference reports the miss and removes the stale entry.

## The seven tools

All scripts target Chrome on `localhost:9222`. Always run `start` first.

### `start` — launch Chrome with remote debugging

```bash
node $SKILL/start.js
node $SKILL/start.js --profile
```

Launches a **dedicated** Chrome instance on `localhost:9222` with its own user-data dir at `~/.cache/scraping`. Runs **alongside** your normal Chrome — it does not kill or interfere with browsers you have open. Idempotent: if the dedicated instance is already running, just reuses it (so parallel agents safely share one automation session).

`--profile` rsyncs your default Chrome profile in first (cookies, logins). It requires both:

1. **Your normal Chrome must be quit** (Chrome holds exclusive locks on profile files; `start.js` will refuse rather than nuke your session — quit Chrome manually, then re-run).
2. **No existing instance on `:9222`** (`start.js` will refuse rather than silently ignore `--profile` and reuse a non-profile instance). If a dedicated Chrome is already up, kill it first: `pkill -f 'remote-debugging-port=9222'`.

All per-tab tools accept the shared targeting flags from above (`--url=`, `--label=`). Examples below show the most common use; mix in `--label=<name>` instead of `--url=` when you've labeled the tab.

### `nav` — navigate

```bash
node $SKILL/nav.js <url>
node $SKILL/nav.js <url> --new
node $SKILL/nav.js <url> --new --label=hn
node $SKILL/nav.js <url> --label=hn
node $SKILL/nav.js <url> --url=foo.com
```

`--new` opens a fresh tab. Combine with `--label=<name>` to record a stable handle in one step. Without `--new`, `--label=<name>` navigates the existing labeled tab.

### `eval` — run JS in a tab

```bash
node $SKILL/eval.js 'document.title'
node $SKILL/eval.js 'Array.from(document.querySelectorAll("h2")).map(h => h.textContent)'
node $SKILL/eval.js --label=hn 'document.title'
```

Wraps the expression in an `AsyncFunction` so `await` works. Arrays of objects are pretty-printed as `key: value` blocks.

**Gotcha:** the argument must be a **single expression**, not a statement list — `eval.js` does `return (<your-code>)`. If you need multiple statements (click + return something), use an IIFE:

```bash
node $SKILL/eval.js '(() => { document.querySelector("button.btn-primary").click(); return "clicked"; })()'
```

### `wait` — wait for a condition

```bash
node $SKILL/wait.js --selector='article h2'
node $SKILL/wait.js --text='Welcome back'
node $SKILL/wait.js --url=/dashboard --timeout=10000
node $SKILL/wait.js --fn='document.readyState === "complete"'
node $SKILL/wait.js --label=hn --selector='.athing'
```

Polls the tab until exactly one condition is satisfied:

- `--text=<substring>` — `document.body.innerText` contains substring
- `--selector=<css>` — selector matches at least one element
- `--url=<substring>` — current tab URL contains substring (e.g. wait for redirect)
- `--fn=<js>` — JS expression returns truthy (same single-expression rule as `eval.js`)

`--timeout=<ms>` defaults to 30000, `--poll=<ms>` to 250. Exit code 0 on success, 2 on timeout, 1 on usage/targeting error.

**Note:** in `wait.js` only, `--url=` is a *condition*, not tab targeting. Target a specific tab with `--label=<name>`.

Use this instead of writing `await new Promise(r => setTimeout(r, ms))` inside `eval.js` IIFEs.

### `screenshot` — viewport screenshot

```bash
node $SKILL/screenshot.js
node $SKILL/screenshot.js --url=foo.com
node $SKILL/screenshot.js --label=hn
```

Prints the temp-file path on stdout. Read it with the Read tool to view.

### `pick` — interactive element picker

```bash
node $SKILL/pick.js "Click the submit button"
node $SKILL/pick.js --url=foo.com "Click the submit button"
node $SKILL/pick.js --label=hn "Click the submit button"
```

Injects an overlay into the page. The human clicks an element (Cmd/Ctrl+click to multi-select, Enter to finish, Esc to cancel). Returns the element's tag, id, class, text, outerHTML (truncated), and parent chain. Use when you need the human to point at something you can't reliably select via JS.

**Only call `pick.js` from the top-level conversation, not a subagent.** A subagent that invokes `pick.js` will block waiting for a click, but the user has no visibility into the subagent's stdout and won't know to click — the call will hang until timeout. If you're in a subagent and you need a human click, return control to the parent and let the parent invoke `pick.js`.

### `type` — type into a field (real keyboard)

```bash
node $SKILL/type.js --selector='input[name=q]' --text='hello'
node $SKILL/type.js --selector='.search' --text='effect' --press=Enter
node $SKILL/type.js --label=hn --selector='#query' --text='svelte' --clear
```

Focuses the selector and types via Puppeteer's **real keyboard** (trusted key events), which many React autocomplete / combobox widgets require — setting `.value` through `eval.js` won't fire their listeners. `--clear` select-all + backspaces before typing; `--press=<Key>` presses a key after typing (e.g. `Enter`, `ArrowDown`); `--delay=<ms>` sets per-keystroke delay (default 60). Exit code 2 if the selector isn't found.

## Composition patterns

Tools output to stdout / files on disk, so compose with shell or sequential calls:

```bash
# Open a logged-in tab and screenshot it
node $SKILL/start.js --profile
node $SKILL/nav.js https://app.example.com/dashboard
node $SKILL/screenshot.js  # prints /tmp/screenshot-....png
```

```bash
# Extract data after rendering
node $SKILL/nav.js https://news.example.com
node $SKILL/eval.js 'Array.from(document.querySelectorAll("article h2")).map(h => ({ title: h.textContent.trim(), href: h.querySelector("a")?.href }))'
```

```bash
# Drive two tabs side-by-side with stable handles
node $SKILL/nav.js https://news.ycombinator.com --new --label=hn
node $SKILL/nav.js https://lobste.rs            --new --label=lob
node $SKILL/wait.js --label=hn  --selector='.athing'
node $SKILL/wait.js --label=lob --selector='.story'
node $SKILL/eval.js --label=hn  'document.querySelectorAll(".athing").length'
node $SKILL/eval.js --label=lob 'document.querySelectorAll(".story").length'
```

```bash
# Post-login redirect: wait for the URL to change, then act
node $SKILL/nav.js https://app.example.com/login
# ... user/automation submits credentials ...
node $SKILL/wait.js --url=/dashboard --timeout=15000
node $SKILL/screenshot.js
```

## Token economics

This entire skill (frontmatter + body + scripts on disk) costs <500 discovery tokens. The equivalent Playwright MCP or Chrome-DevTools MCP would cost 13k–18k tokens of always-loaded schemas — and you'd have less flexibility to add `pick.js`-style human-in-the-loop operations.

## Adding a new tool

Drop a new `.js` file in this directory, add a section above. That's it. No server to restart, no schema to extend. If a script needs new node deps, `npm --prefix "$SKILL" install <pkg>`.
