# ADR-014: Personal-repo bd storage model — Dolt embedded + JSONL-carrier

- **Scope:** `tooling`
- **Status:** Active (authored 2026-06-02)
- **Originator:** `/compound` Promote on a normalization epic close → `/adr-write` (human-confirmed FIRM)

## Context

`bd` (beads) is the issue/memory tracker used across the user's two personal machines — the **development laptop** (the canonical methodology home) and a **second always-on machine**. bd 1.0.x uses Dolt as its storage backend, with two modes: **server** (a long-lived `dolt sql-server` against `.beads/dolt/<db>/`) and **embedded** (in-process Dolt against `.beads/embeddeddolt/<db>/`, the 1.0.5 default).

On 2026-06-01 the canonical methodology home repo wedged: a bd 1.0.5 CLI opening a 1.0.4-era Dolt store crashed the server mid-migration (`0006_add_wisp_is_blocked`) on every write. Recovery surfaced that bd 1.0.5 also stores Dolt data in the git remote (`refs/dolt/data`) and **auto-adopts** it on `bd init`/`bootstrap` — and the remote's snapshot was itself stale and unmigratable (crashes on a missing `wisps` table). The fix rebuilt the methodology home repo as embedded + re-import from `issues.jsonl`, and the same normalization was then applied to the user's other own repos under a normalization epic.

This ADR canonicalizes the storage model that the recovery validated. It does not open a new question — the decision has been operating and proven across 6 repos (methodology home + a private approvals project, a private log-ingest project, a private containerized-agent safety project, a private personal project, `dotpi`) and verified cross-machine.

## Decisions

### D1 — Embedded Dolt only; server mode banned for personal repos. **[FIRM]**

All personal bd repos run Dolt in **embedded** mode (`.beads/embeddeddolt/<db>/`). Server mode (`.beads/dolt/<db>/` + a live `dolt sql-server`) is not used.

**Rationale:** Server mode caused both 2026-06-01 failure classes — the migration-lock wedge (a long-lived server crashing mid-migration on every write under version skew) and the historical flat-`.beads/dolt/` cross-clone bug. Embedded mode has no long-lived server, migrates in-process, and tested clean under 20-way concurrent read+write (the hook-traffic concern that originally argued for server mode did not reproduce).

### D2 — `issues.jsonl` (always `--include-memories`) is the cross-machine carrier; each machine rebuilds its own local store. **[FIRM]**

`.beads/issues.jsonl` is the git-tracked source of truth that travels between machines. Each machine builds its **own** local embedded Dolt store from it. **No versioned Dolt store ever crosses machines.** Every export that writes the canonical `issues.jsonl` MUST pass `--include-memories` (a plain `bd export` silently strips memories).

**Rationale:** A versioned Dolt store crossing machines is exactly what enables cross-machine schema-skew crashes (machine A on bd 1.0.4, machine B on 1.0.5 → migration crash). Per-machine rebuild from a plain JSONL interchange file eliminates that failure mode: each machine migrates its own store at its own bd version. The `--include-memories` flag is load-bearing because bd memories ride `issues.jsonl` and the default export drops them.

### D3 — No git-remote-dolt push; `sync.remote` cleared; stale `refs/dolt/data` deleted. **[FIRM]**

`bd dolt push` / git-remote-dolt is not used. Each repo's `.beads/config.yaml` has `sync.remote: ""`. Any stale `refs/dolt/data` on a remote is deleted.

**Rationale:** `bd init`/`bootstrap` **auto-adopt** whatever `sync.remote` points at — and the *real* adoption trigger is the `sync.remote` value in `config.yaml`, not the git origin (detaching the git origin does **not** prevent adoption; confirmed on a private approvals project and a private personal project). An adopted stale ref crashes on open. Worse, `bd init` auto-*populates* `sync.remote` from the process CWD's git origin, so initializing one repo from inside another's directory cross-contaminates the target's config. Clearing `sync.remote` is the only reliable guard, and under D2 there is nothing for git-remote-dolt to do anyway.

### D4 — `export.auto: false`. **[FIRM]**

Auto-export on write is disabled. Canonical `issues.jsonl` is written by explicit exports (the methodology home's SessionEnd hook; manual re-export during normalization).

**Rationale:** bd's auto-export uses the *default* (memory-stripping) export path, which would silently drop memories from `issues.jsonl` on every write — directly violating D2. Embedded Dolt holds writes durably between explicit exports, so auto-export is both unsafe (strips memories) and unneeded.

### D5 — Scope: the user's OWN repos only. **[FIRM]**

This regime applies to repos the user owns: the methodology home, a private approvals project, a private log-ingest project, a private containerized-agent safety project, a private personal project, `dotpi` (and future own repos). Upstream third-party clones the user has checked out — `coding_agent_account_manager`, `beads_viewer`, `destructive_command_guard`, `agentic_coding_flywheel_setup`, `slb` (all `Dicklesworthstone/*` remotes) — are **out of scope**: their `.beads` carries upstream's issue tracker, the user can't push to them, and normalizing them is churn with no cross-machine payoff.

**Rationale:** The cross-machine reliability goal only applies to repos that are actually the user's and actually sync between the user's machines. (Note: a store-less repo has a separate footgun — running `bd` inside it falls through to the methodology home — but that's a verification hazard recorded in bd memories, not a reason to normalize someone else's repo.)

## Alternatives considered

| Alternative | Rejected because | Warrant |
|---|---|---|
| **Server mode** (live `dolt sql-server`) | Caused the 2026-06-01 wedge (migration-lock crash under version skew) and the historical flat-`.beads/dolt/` cross-clone bug; embedded handled the hook-concurrency concern that motivated it | `direct:` the bd normalization epic, memory `dolt-server-mode-cross-machine-fragile` |
| **git-remote-dolt** (versioned Dolt sync across machines) | Versioned stores crossing machines is the precise enabler of schema-skew crashes; adoption of a stale remote ref crashes on open (`wisps`) | `direct:` memory `bd-1.0.5-stores-dolt-in-git-remote`, the bd normalization epic recovery |
| **no-db mode** (JSONL-only, drop Dolt entirely) | Piloted and reverted — incompatible with memory-bearing repos | `direct:` the no-db pilot epic (closed obsolete) + commit `c038d26` "revert(beads): pilot found no-db incompatible with memory-bearing repos, back to Dolt" |
| **`export.auto: true`** | bd auto-export uses the memory-stripping default; would silently drop memories from the carrier | `direct:` memory `jsonl-carrier-export-needs-include-memories` |
| **Normalize all checked-out repos** (incl. third-party clones) | Their `.beads` is upstream's data; unpushable; pure churn | `reasoned:` cross-machine reliability only applies to the user's own synced repos |

## What would invalidate this

Signal-shaped revisit triggers (per ADR-008 D8) — any one is reason to re-open this ADR:

- **bd/Dolt version evolution changes the storage contract.** bd and Dolt are evolving fast; a future bd version may change embedded-vs-server tradeoffs, the migration model, the git-remote-dolt mechanism, or introduce a first-class cross-machine sync that doesn't carry the schema-skew failure mode. Concrete cues: bd release notes announcing a new sync/storage backend, embedded mode being deprecated, or the `refs/dolt/data` auto-adoption behavior being removed/made opt-in. On any such cue, re-evaluate whether a richer Dolt-native sync now beats JSONL-carrier rebuild for this 2-machine setup.
- **JSONL-carrier loses fidelity.** If `issues.jsonl` (even with `--include-memories`) starts dropping fields that matter (dependency edges, audit/interactions history, labels), per-machine rebuild becomes lossy and the carrier model needs revisiting (e.g. carry `interactions.jsonl` too, or reconsider Dolt sync).
- **The machine count or topology changes.** Embedded + JSONL-carrier is tuned for a small number of personal machines with occasional sync. A team setting, many machines, or a need for real-time shared state would shift the calculus back toward a server/sync model.
- **Embedded concurrency breaks under real load.** The 20-way concurrent read+write test passed; if real hook traffic later produces lock contention or corruption in embedded mode, D1 must be re-examined.

## canonical_refs

- **ADR-013** — Memory Layer Architecture. L2B memories ride `bd` (`issues.jsonl`); this ADR is the storage substrate beneath that layer, and is impl-agnostic-compatible with ADR-013 D9 (which is agnostic to bd's backend).
- **ADR-012 D2** — cross-cutting write filter (this decision clears it: constrains all personal repos + both machines + the sync hooks; the no-db revert proves revising-requires-argument).
- **The bd normalization epic** — normalization that validated this model across 6 repos.
- **The no-db pilot epic** (closed obsolete) — the reverted no-db pilot; the argument-on-revision evidence.
- **bd memories** (operational pitfalls implementing this decision): `dolt-server-mode-cross-machine-fragile`, `bd-1.0.5-stores-dolt-in-git-remote`, `jsonl-carrier-export-needs-include-memories`, `beads-config-sync-remote-cross-project-drift`, `bd-dash-c-read-fallthrough-to-ambient-workspace`.
