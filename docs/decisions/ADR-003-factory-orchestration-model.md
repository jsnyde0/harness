# ADR-003: Orchestration model for the self-driving bead factory

Date: 2026-06-05
Originated from: brainstorm of the factory observability + human-interface child + the recursion-handoff child

## Status

Proposed — **all decisions FLEXIBLE or EXPLORATORY.** This is the runtime-orchestration model for the self-driving bead factory (the factory-orchestration-model epic), captured up-front per the front-load-design constraint but **dogfood-pending**: the firmness labels say "this will move." Do not treat any decision here as binding architecture. The factory is sequenced to be built after the full W1–W4 harness program (the W1–W4 harness program epic); these decisions gate the design of its children, not their immediate implementation.

## Context

The self-driving bead factory evolves `/send-it` into an AFK software factory: ready epics pull orchestrator-agents that run unattended inside a containerized-agent environment, externalize all state to bead labels (crash-resumable), coordinate mechanically, and surface to the human only when needed. Two design-open questions blocked the factory's AFK proof-of-concept and were front-loaded as their own children: **how a parent orchestrator hands off to a child epic's orchestrator without holding live state**, and **how the human watches the AFK fleet and is pulled in when a session needs them**. A brainstorm (2026-06-05) converged both; this ADR canonicalizes the cross-cutting decisions so the factory's other children (state schema, Governor, trigger/proof) can be designed against a single source of truth rather than against bead `--design` prose.

The two questions share a spine: "a parent waits on child work without holding it in a process" (`.7`) has the same answer as "engage a raise, then hand control back without losing state" (`.6`) — both reduce to *the orchestrator is a disposable process whose state lives in the bead graph*.

**Underpinning axioms (NOT canonicalized here).** Two load-bearing principles motivate these decisions: (1) **beads ARE goals**; (2) **state-in-beads = crash-resumable** (substrate-residue-as-signal). They remain EXPLORATORY design-axioms in `docs/vision-self-driving-bead-factory.md` (§3), promotion-to-FIRM dogfood-pending. They are cited here as the *warrant* for D1/D2, not minted as firm decisions by this ADR.

**Harness constraint that shapes D2.** pi (the primary harness, ADR-002 D1) exposes no mechanical "needs-human" signal. Confirmed against the SDK (`@earendil-works/pi-coding-agent` v0.78.0): the only yield edge is `agent_end`, which fires every time the agent loop yields control but carries **no reason code** — it cannot distinguish "done" from "needs human." pi has no notification / permission / ask-user event. Its one interception point is `tool_call` (the DCG-equivalent gate). So any "why did it stop" is irreducibly part self-report — which D2 treats as a reason to *not* rely on self-report at v0.

## Decisions

### D1: Orchestrator lifecycle — exit-and-resume, not stay-alive

- **Firmness:** FLEXIBLE
- **Decision:** When a parent orchestrator hits a handoff (a child that is itself an epic, pulling its own orchestrator off the ready-frontier) **or** a raise, the orchestrator **process EXITS**; all coordination state is in bead labels. When re-pulled (the blocking dependency clears), it **RESUMES its persisted session** (`pi --session <id>`), **not** a cold respawn. Resume-the-same-session for the same logical orchestrator/epic continuing; a genuinely-new epic gets a new session. **Critical constraint:** re-pull must be a re-**READ** (prior decomposition decisions read back as cached bead-labels, zero LLM recomputation), **not** a re-**COMPUTE**. The `.1` write-as-you-go state discipline is what guarantees this.
- **Rationale:** Nothing crash-fragile is held in a live process, so axiom (2) (state-in-beads = crash-resumable) survives — killing an orchestrator costs nothing. Yet resuming a recent session is cheap (prefix-cached), so the cost worry that motivated "stay alive" dissolves without sacrificing crash-resumability. This separates **process liveness** (the OS process can exit) from **session persistence** (the conversation persists and resumes), which the original stay-alive-vs-cold-respawn binary conflated.
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | (a) Parent stays alive while the sub-epic runs | Simplest control flow; no re-spawn cost | **Rejected** — reasoned: holds live coordination state in a process, in direct tension with axiom (2) crash-resumability; long-lived parents accumulate unbounded state and a crash loses it (the InMemorySaver failure mode). |
  | (b) Cold-respawn a fresh session on every re-pull | Purest stateless model | **Rejected** — reasoned: burns tokens re-computing the decomposition the orchestrator already did; the user flagged that several raises can fire in quick succession, so cold-restarting each is expensive. Session-resume is the cheaper equivalent. |
  | (d) Resident-by-default, suspend-on-child-wait (DBOS / Restate / Inngest journal-suspend) | The closest production analogue to this decision — the workflow stays "logically alive" but its process is suspended and its journal externalized while it waits | **Adopted in substance, not in form** — external: DBOS keeps the workflow resident-by-default but suspends-on-child-wait; Restate push-resumes from a journal. Our D1 is this pattern with pi's session-persistence as the journal: the orchestrator is logically the same continuation (resumed session) but its OS process does not stay resident. We take the suspend-and-journal-resume semantics and reject only the "stays resident in RAM" framing, for the same crash-resumability reason as (a). |
  | (e) No parent at all (dissolve into fungible workers, Jeffrey Emanuel's no-ringleaders) | Eliminates the handoff question entirely | **Rejected** — reasoned: the factory deliberately keeps a runtime-adaptive orchestrator for JIT decomposition (see the factory-orchestration-model epic design); this ADR makes that orchestrator disposable rather than removing it. |

- **What would invalidate this:** re-pull is observed re-running LLM passes (re-compute, not re-read) — meaning `.1`'s state schema is insufficient to make resume a pure read; OR session-resume proves more expensive in practice than a cold context-rebuild (e.g. resumed sessions carry too much stale context to be cheaper than starting fresh); OR the **detach start-race** bites — the parent stamps the blocking dependency and exits, but the child orchestrator's spawn fails silently, leaving a bead-graph dependency that never clears and the factory **stalls with no raise** (a silent deadlock). The mitigation (confirm the child durably started before the parent exits) belongs in `.1`'s state schema + `.4`'s trigger; if it can't be made reliable, exit-and-resume is the wrong model.

### D2: HITL surfacing — a single `agent_end` chokepoint; v0 logic = "always call the human"

- **Firmness:** the **single-chokepoint architecture** (every `agent_end` routes through one hook; "call less" = smarten that one hook) is **FLEXIBLE** — reasoned + pi-SDK-evidenced, expected to hold. The **v0 predicate ("always")** is **EXPLORATORY** — deliberately the dumbest thing, expected to move first. The split matters: downstream children should treat the chokepoint as stable and the always-predicate as the part that will get smarter.
- **Reconciliation with the epic's "surfaced ONLY on raises" goal:** the factory's *matured* target is surfacing the human only on legitimate raises (the AFK value prop). v0 deliberately does the opposite — it surfaces on **every** `agent_end` — because that is the reliable dumb baseline. "Only on raises" is reached by *evolving the predicate down* + the Governor child preventing a non-raise stop from masquerading as done; it is **not** a v0 bar. The AFK proof child must therefore verify the surfacing *mechanism* works (human reached via the built interface on yield) and that the Governor blocks masquerade — **not** raise-only filtering, which v0 does not yet do.
- **Decision:** The factory does **not** try to deduce "human-needed." Every `agent_end` routes through **one hook chokepoint** (riding dotpi's existing `pi.on(event)→pi.exec(script)` hooks pattern in `agent/extensions/hooks/` — the same table-driven runner that currently maps `tool_call`; adding an `agent_end→emit` row is the minimal in-pattern change). At **v0**, that hook's logic is literally **"always"**: stamp coordination state on the bead, notify the human (cmux ring / ntfy — see D4), and exit (D1). **No** raise-sentinel or raise-tool, **no** done-vs-stuck distinction, **no** keep-going hook at v0. The one cheap-foresight investment: because the call-the-human decision lives at this **single chokepoint**, "call the human less over time" later = making that one hook smarter, with **no re-architecture**.
- **Rationale:** Two reasons "always" beats any v0 attempt at cleverness. (i) **Self-report is the fallible derived layer.** Since pi's `agent_end` carries no reason code (see Context), "I need a human" can only be an agent-set flag — and an agent that forgets to set it yields *silently* and the human is never called. A structural "always" is strictly more reliable than a v0 self-report. (ii) **"Done" is not a safe no-call case.** A completed epic frequently has valid follow-up questions (which beads next, was the scope right) — so even successful completion often wants the human (user direction 2026-06-05). With both "stuck" and "done" wanting the human, the v0 predicate collapses to `true`. This mirrors cmux's existing "agent needs you" on every stop.
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | (a) pi-extension on `agent_end` + a minimal raise-sentinel/tool the agent sets | Robust *that* it yielded; shrinks the agent's obligation to one in-context flag | **DEFERRED, not rejected** — reasoned: becomes *one optional input* to the chokepoint's predicate later, only if pure-structure deduction proves insufficient. It is a refinement of the same single-chokepoint architecture, not a rival to it. |
  | (b) `agent_end` while the bead isn't closed ⇒ human (deduce from state) | No bespoke raise primitive; rides existing bead state | **Rejected for v0** — reasoned: a completed-but-has-questions epic *closes* its bead yet still needs the human, so "bead-closed" is not a safe no-call predicate. A correct state-predicate is exactly the post-dogfood smartening this decision defers. |
  | Bespoke "raise move" designed into the pi agent up front | A clean explicit raise channel | **Rejected** — reasoned: designing a raise primitive before dogfooding is a detour that builds the fallible self-report layer first; start with the reliable structural "always" and earn the smarter version from evidence. |

- **What would invalidate this:** dogfood shows always-call is too noisy to tolerate even briefly → pull forward the first subtraction (the obvious one: skip the call when the bead ready-frontier still has autonomous work to advance). The architecture (single chokepoint) is unchanged by that; only the predicate gets smarter.

### D3: Two planes — factory (caged, always-on) vs cockpit (cmux on the Mac, present-when-human-is)

- **Firmness:** FLEXIBLE
- **Decision:** The system splits into two planes. The **factory** = orchestrators running AFK in a containerized-agent environment, state in beads, always-on; it runs whether or not anyone is watching — the engine. The **cockpit** = `cmux` on the human's Mac: the *view onto* and *engage surface for* the factory, present only when the human is. cmux being GUI-coupled / not-headless (its control socket is served by the running GUI) is **correct, not a limitation** — cmux is the window, not the engine. The split keeps orchestrators behind the container boundary: **orchestrators write beads; the trusted cockpit reads** — so the cockpit's control socket never needs to reach into the container, avoiding the cmux-demo footgun of disabling an agent's sandbox to allow socket comms. **The reverse direction is closed too:** the containerized `agent_end` hook never drives the cmux socket either (cmux's socket-auth defaults to `cmuxOnly`, and weakening it to `automation`/`password` to let a containerized process call `cmux notify` would re-open a control surface — any reacher could then `cmux send-key`/`new-pane`, not just `notify`). Instead the containerized hook writes the bead + fires the ntfy push, and the **cockpit** raises the cmux ring from the bead/event stream it already reads (see D4 "notify direction"). So nothing crosses the container boundary in either direction via the cmux socket. When the human is away, raises accrue as bead labels; on opening cmux the cockpit reconstructs the view from the event stream + bead graph.
- **Rationale:** The factory's value (AFK operation) requires it to be independent of any human-side GUI; the cockpit's value (rich watch + engage) requires a GUI. Separating them lets each be what it is without compromising the other, and the write-beads / read-beads asymmetry preserves the containerized-agent safety boundary (established by the containerized-agent safety project's ADRs) instead of punching a control hole through it.
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | Single plane — the cockpit IS the factory (orchestrators run inside cmux panes) | One system, no split; cmux can drive sessions directly | **Rejected** — reasoned: couples AFK operation to a running GUI on one Mac, and the cmux demo's way to let an external orchestrator drive the socket was to disable the agent's sandbox — unacceptable for containerized AFK agents. |
  | Headless cockpit (custom web service, no cmux) | Always-present, multi-device | **Rejected (for now)** — reasoned: rebuilds the rich watch/engage surface cmux already gives for free; the present-only-when-human cockpit is sufficient while the factory is single-human / single-Mac. |

- **What would invalidate this:** a headless / always-present cockpit becomes necessary — e.g. multiple humans, or remote engagement without the Mac — at which point the cockpit needs to be a service, not a GUI app.

### D4: Cockpit surfaces — watch = roster pane, engage = jump-into-session, alert = ntfy-over-Tailscale

- **Firmness:** FLEXIBLE (roster / engage / alert) — EXPLORATORY (graduation path). One sub-decision is firmer than the rest: **the structured-state-channel (beads+events, not screen-scrape)** is load-bearing — it is what makes the away-then-reconstruct property (D3) work and is the discriminating check in the cockpit-verification bead's harness target; treat it as the FLEXIBLE element least expected to move.
- **Decision:**
  - **WATCH = a roster pane, not a tail.** Each orchestrator collapses to **one row** — state (`running` / `idle` / **`RAISED`** / `done` / `failed`) + one activity line — built from the **bead ready-frontier** + cmux agent-lifecycle events. Build **simplest-composable-first**: a live-markdown pane (the factory rewrites a file, `cmux markdown open`) or a tiny TUI reading beads + `cmux events`; **graduate** to a cmux native browser-pane dashboard only if glancing at a file stops being enough. It is a thing-that-reads-beads, not a new system.
  - **ENGAGE = jump-into-the-session.** Selecting the `RAISED` row focuses that orchestrator's cmux pane on the already-resumed session (D1); the human types to steer. An inline accept/edit/respond **inbox is DEFERRED** (the more-enmeshed build, only if raise-volume makes jumping painful).
  - **AFK ALERT = phone push via ntfy over Tailscale.** cmux's native ring only fires when the human is at the Mac; genuinely-AFK needs an out-of-band push. Assumes a Tailscale-reachable always-on factory host that pushes to phone via ntfy.
  - **STATE CHANNEL = structured, not screen-scrape** for everything load-bearing: coordination state comes from beads + events (the `.3` Governor already reads bead-label predicates). A light `read-screen` / pi `/tree` glance is acceptable **only** for the cosmetic activity line, where nothing depends on it.
  - **NOTIFY DIRECTION = the cage never drives the cmux socket.** The caged `agent_end` hook (D2) stamps the bead and fires the **ntfy** push *only*; it does **not** call `cmux notify`. The cmux **ring** is raised by the **cockpit** — the trusted Mac-side reader — off the bead/event stream it already watches. This keeps the cage→cmux socket path closed (D3) and sidesteps cmux's `cmuxOnly` socket-auth without weakening it.
- **Rationale:** A roster (one row per agent) scales past ~4 agents where literal side-by-side tails do not — the consistent finding across the observability prior art (disler multi-agent dashboards, the joelhooks cmux×pi fleet widget, recon/overstory roster TUIs). Keeping load-bearing state on the structured bead+event channel (not screen-scrape) is what lets the cockpit be reconstructed after an absence (D3) and keeps the Governor's predicates trustworthy.
- **Alternatives:**

  | Option | Why considered | Verdict |
  |---|---|---|
  | Side-by-side live session tails (one pane per agent) | Direct, no abstraction | **Rejected** — external: every fleet-observability prior art converges on roster-not-tail because tails stop fitting the screen past a handful of agents. |
  | Screen-scrape the session panes for state | Works without instrumenting the agents | **Rejected** — reasoned: load-bearing coordination state must be reliable and reconstructable; scraping a TUI is brittle and breaks the away-then-reconstruct property. Beads + events are the structured channel. |
  | Build the inline accept/edit/respond inbox now | Smoother engage UX | **Deferred** — reasoned: jump-into-session is simpler and composable; build the enmeshed inbox only if raise-volume proves jumping painful. |

- **What would invalidate this:** the roster stops scaling (too many orchestrators to glance), or jump-into-session becomes painful at raise-volume → build the deferred inline inbox; or glancing at a markdown file stops conveying enough → graduate to the browser-pane dashboard.

## Deferred / parked (named here for discoverability)

- **The keep-going (drive-to-acceptance) driver** — what would make `agent_end` reliably mean "done-or-stuck" by re-injecting "keep going" when the epic still has ready work, instead of yielding mid-walk — is **owned by child `.3`** (its premature-stop Governor *is* this hook) and is **dogfood-gated**: build it only if a real epic is observed stopping mid-walk-children without a labeled raise. Not v0; not a new bead.
- **Smart "only-when-really-needed" HITL filtering + batched human-calls** — the post-dogfood smartening of D2's chokepoint predicate. Deferred until enough dogfood evidence exists to design it from data rather than guesswork. Tracked as a parked follow-up bead.

## Consequences

- The state-schema child must capture, on handoff/raise-exit, exactly what makes re-pull a pure re-read (D1): the session id to resume, the blocking-dependency stamp, and the decomposition decisions-so-far as bead labels.
- The Governor child must treat a re-pulled, session-resumed orchestrator as normal (not a premature stop), and owns the deferred keep-going driver.
- The observability/interface child closes (brainstorm done) and spawns an interface impl-successor that builds the D3/D4 cockpit + the D2 `agent_end→surface` chokepoint hook; that successor inherits the blocking-dependency edge so the AFK proof verifies a BUILT surface.
- The recursion-handoff child closes against D1.
- The AFK proof child consumes D1 (recursion-handoff) and verifies D2/D4 (human surfaced via the built interface) on its proof run.

## canonical_refs

- `docs/vision-self-driving-bead-factory.md` — factory north-star (§2 interface, §3 principles + axioms, §4 recursion model, §5 open questions).
- `docs/2026-06-05-factory-interface-recursion-brainstorm.md` — the brainstorm this ADR canonicalizes (landed decisions + condensed pi/cmux/durable-execution/observability research).
- `docs/2026-06-04-agentic-engineering-field-research.md` — evidence base (Jeffrey Emanuel / IndyDevDan / pi).
- `docs/decisions/ADR-002-cross-harness-substrate.md` — D1 (pi-primary topology, beads-as-interface) + D2 (the `pi.on(event)→pi.exec` hook-runner this ADR's D2 chokepoint rides). Additive: ADR-002 builds the hook mechanism; ADR-003 adds an orchestration consumer of it.
- `docs/decisions/ADR-001-minimal-pi-subagent-subprocess-primitive.md` — the `subagent` primitive orchestrators dispatch executors through; orthogonal layer.
- A private containerized-agent safety project's ADR-002 (containers), ADR-019 (pi-agent support) D4/D7, and ADR-024 (prompt-injection threat model) — the containerized-agent AFK safety boundary the two-planes split (D3) preserves.
- pi SDK `@earendil-works/pi-coding-agent` v0.78.0 — `agent_end`-no-reason-code constraint underpinning D2.
- cmux — `github.com/manaflow-ai/cmux` (session persistence/resume = D1's mechanism; ring/notify/roster surfaces = D4).
