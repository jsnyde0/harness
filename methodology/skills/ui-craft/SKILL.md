---
name: ui-craft
description: Build or polish a UI surface to high-end-studio quality (Stripe-level / Linear-level / editorial-grade — depending on register). Gathers project design-context (framework, tokens, components, register), then dispatches the `ui-craftsman` subagent which owns the build → screenshot → read-back → critique → patch loop with `browser-automation` as its eyes. Use when the user says "make this UI nicer", "polish this component", "build a [component] with great UX/UX", "Stripe-level UI", "world-class UI", "design a [page/screen]", or when about to ship a user-facing surface that should clear a studio bar. SKIP when the work is purely backend/data, when the user is asking a design question (use `/guide` or `/brainstorm`), or when the surface is trivial (a single text tweak, a typo). Composes downstream with adversarial-review for a fresh-eyes critique pass after.
---

## Purpose

Land a UI surface that defends in a high-end studio review. The work itself — CSS iteration, screenshot reads, critique-against-bans — is token-volume and happens in the subagent's fresh context. The orchestrator does context-gathering, register judgment, and post-loop review.

Adapted from [pbakaus/impeccable](https://github.com/pbakaus/impeccable) — distilled to one subagent + one skill rather than 23 verbs. Verbs can grow later if the loop holds.

## When to invoke

Strong triggers:
- "Make this UI [nicer / Stripe-level / world-class / polished]"
- "Build a [component / page / screen] with great UX"
- "Design a [surface]" when the next step is implementation, not exploration
- About to ship a user-facing surface that hasn't been through a craft pass

Weak triggers (judgment call):
- Single-component tweak — if the change is mechanical (rename, swap icon, adjust padding by a known amount), do it directly. If it's "make this feel better", invoke.
- Greenfield UI work — invoke, but expect the subagent to ask for framework/token decisions if the project is empty.

Skip when:
- The user is asking a design *question* (tradeoff, recommendation) — use `/guide` or `/brainstorm`.
- The work is non-visual (backend, data, infra).
- The user explicitly wants speed over polish ("just slap something together").

## Algorithm

### Phase 1 — Context gathering (orchestrator, in its own context)

Don't dispatch yet. Build the brief.

1. **Identify the target surface.** What file / route / component? If ambiguous, ask the user.
2. **Read the project's design substrate** — enough to brief the subagent, not exhaustively:
   - Framework: `package.json`, `astro.config`, `next.config`, `vite.config` — whichever exists.
   - Component library entry: `src/components/`, `app/components/`, or equivalent. Note the top-level pattern (Radix, shadcn, custom, etc.).
   - Design tokens: `tokens.css`, `theme.ts`, `tailwind.config`, CSS variables.
   - Icon set: `lucide-react`, `@phosphor-icons/react`, hand-rolled SVG sprites.
3. **Decide register.**
   - **Brand register** — design IS the product. Marketing site, landing page, portfolio, anything where the visual is the value proposition. Bar: editorial, distinctive, refuse the SaaS-cream defaults.
   - **Product register** — design SERVES the product. App surface, internal tool, dashboard. Bar: invisible-when-good, semantic, fast, every state covered, no decorative excess.
   - If the surface mixes both (marketing app with internal dashboards), pick per-target, not per-project.
4. **Resolve design refs.** If the user named anchor refs ("like Stripe's pricing page", "like Linear's command palette"), capture the URLs / file paths. If they named an aesthetic lane that's on the reflex-reject list ("editorial-typographic", "Linear-style gradient mesh"), surface the tradeoff before dispatching — that lane reads AI on contact.
5. **Identify dev URL.** Where will the subagent inspect the work? If no dev server is running, surface that — either start one or note the inspect loop can't run and the subagent will be flying blind.

### Phase 2 — Dispatch the subagent

One `ui-craftsman` per surface. **Do not parallel-fan-out** — multiple subagents touching the same component library / tokens / dev server will collide. If the user wants multiple surfaces crafted, dispatch sequentially.

Dispatch brief:

```
target: <free-text spec OR file path>
register: brand | product
project_context:
  - framework: <what it is + key files>
  - components: <library + path>
  - tokens: <where they live>
  - icons: <which library>
design_refs:
  - <URL / file path / aesthetic anchor — if any>
dev_url: <e.g. http://localhost:3000/foo>
viewports: [375, 768, 1280]  # override if surface has specific requirements
```

The subagent owns the loop. Don't micro-manage. It will return a structured report with `Built / Inspection log / Honest critique / Slop test / Open follow-ups`.

### Phase 3 — Review (orchestrator)

When the subagent returns:

1. **Read its `Honest critique` and `Slop test` sections.** Is the surface defensible? Did it actually run the slop test or just claim "passes"?
2. **Optionally dispatch `adversarial-review`** for a fresh-eyes pass. Worth it when: the surface is high-stakes (public-facing marketing, key product flow), or the subagent's critique reads thin / self-congratulatory. Skip when: the surface is small, the report is honest about defects, and the user can eyeball the result.
3. **Hand back to the user.** Show what was built, surface the open follow-ups, name any tradeoffs the subagent flagged.

## Anti-patterns the orchestrator must guard against

1. **Skipping context-gathering and dispatching with vague brief.** The subagent in fresh context can't see the project's existing design system. If you don't brief it, it will guess — and guesses introduce parallel systems (a second component library, a second icon set, a second token scheme).
2. **Parallel-dispatch for multiple surfaces.** They share dev server + component library + token state. Sequential.
3. **Accepting "looks good" without checking the slop-test section.** The slop test is the single defense against AI-default output. If the report skips it or claims "pass" with no rework, that's a failure signal.
4. **Compressing the register decision.** Brand vs product is load-bearing — different bars, different defaults, different acceptable patterns. Don't let it be implicit.
5. **Treating "tests pass + build clean" as proof the UI works.** Those are defect evidence only. The screenshot-read loop is the actual verification.

## What this skill is NOT

- Not `/brainstorm` — doesn't explore design tradeoffs. It executes against a confirmed direction.
- Not `/guide` — doesn't recommend approaches. Pick the direction first, then invoke this.
- Not a full design system author. If the project lacks tokens / components, this surfaces the gap; it doesn't backfill an entire system.
- Not for trivial changes. A single padding tweak doesn't need a subagent dispatch.

## Composition

- **Upstream:** `/brainstorm` (if direction is unclear), `/guide` (if approach is unclear). Once direction is locked, invoke this.
- **Downstream:** `/adversarial-review` for a fresh-eyes critique pass on the built surface. Optional but recommended for high-stakes work.
- **Parallel:** none. Sequential per surface.

## Working substrate

- ui-craftsman agent (methodology home) — subagent definition (loop, production bar, bans, slop test, hard rules)
- browser-automation/SKILL.md (methodology home) — the subagent's eyes (CDP + Puppeteer)
- Project's framework config, component library, tokens — read in Phase 1 to build the brief

## Lineage

Distilled from [pbakaus/impeccable](https://github.com/pbakaus/impeccable):

- **Lifted:** absolute bans, AI slop test (two altitudes), production bar checklist, "screenshot you didn't read doesn't count", register split (brand vs product), reflex-reject fonts/lanes.
- **Adapted:** one subagent + one skill rather than 23 verbs and a router. Verb sprawl is a future extension once the base loop holds.
- **Dropped:** Codex `image_gen` mock-generation gate (Claude Code lacks it), `PRODUCT.md` / `DESIGN.md` as required files (we have ADRs + bd memories), Live mode infrastructure (huge surface area; `browser-automation` covers the essentials), multi-harness packaging (Claude-Code-only), no-LLM CLI lint (use `/harness` instead).
