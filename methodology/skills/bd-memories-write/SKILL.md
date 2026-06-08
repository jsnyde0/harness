---
name: bd-memories-write
description: Reference discipline for writing entries to bd memories (L2B non-decaying agent-knowledge substrate per ADR-013 D2/D8) — frontmatter convention, structured body (Why/How-to-apply), kind/scope/source semantics, tiebreak rules, and worked examples. Use before calling `bd remember --key=...`, when /compound routes a Record entry to L2B (target: L2B), or when writing any procedural-lesson, anti-pattern, user-pref, project-anchor, or reference entry.
---

## Purpose

bd memories (L2B) is the non-decaying agent-knowledge substrate. Entries persist indefinitely; no half-life. The CLI does not enforce schema — the discipline lives entirely in the body content. This skill is the body-convention reference.

**Spec source:** the memory-write redesign epic D2; ADR-013 D8 (kind enum).

---

## Frontmatter convention block

Every bd memories entry body MUST begin with a YAML frontmatter block:

```markdown
---
kind: procedural-lesson | anti-pattern | user-pref | project-anchor | reference
scope: global | workspace
created: YYYY-MM-DD
source: <origin pointer — see Source field semantics>
---
```

All four fields are required for **new** entries. bd does not parse this frontmatter — it is reader-side convention. `/compound` reads `created:` directly from the body for age-aware reasoning. `bd prime` surfaces title + preview (kind tag not yet in index — deferred enhancement).

**Grandfathering:** entries written before `source:` was introduced (2026-06-03) are not retroactively non-conformant. Backfill `source:` opportunistically when re-writing an old entry for another reason — do not run a bulk migration.

---

## Structured body discipline

After the frontmatter, every entry MUST have:

```markdown
One-line summary.

**Why:** Reason this matters; often a past incident or strong preference.
**How to apply:** When/where this guidance kicks in.
```

Optional additions (include when relevant):
- Free-form body paragraphs after the required fields
- Cross-references to other bd memories via `[[other-key]]` notation

**Why** and **How to apply** are required. A body without both fields is non-conformant.

---

## Kind enum semantics

| Kind | Use when |
|---|---|
| `procedural-lesson` | A calibration or workflow rule learned from incident/calibration that should persist permanently |
| `anti-pattern` | A PITFALL-marked warning about a specific failure mode |
| `user-pref` | A rule whose WHY is "user told me to do / not do X" |
| `project-anchor` | State, conventions, build flags, migration status of *this current repo* |
| `reference` | Pointer to external systems / repos / docs (origin-of-content is external, regardless of frequency-of-use) |

---

## Scope semantics

| Scope | Use when |
|---|---|
| `global` | Applies across all projects — default for `user-pref`, most `procedural-lesson` and `anti-pattern` entries |
| `workspace` | Applies only to current repo/project — typical for `project-anchor`; sometimes for `procedural-lesson` tied to a specific codebase quirk |

When in doubt: `global`. Scope narrows later by re-write; broadening is harder.

---

## Source field semantics

`source:` records **where the entry came from** — the origin you could trace back to re-judge whether the lesson still holds. It is the auditability counterpart to `created:` (when) and `kind:` (what). The principle is borrowed from knowledge-graph memory systems (Golem XIV pins every fact to the cognition that produced it via an `actualizes` edge); here it is a reader-side pointer rather than a graph topology.

Pick the **most specific** value that applies:

| Value | Use when |
|---|---|
| `user-directive` | The user stated this directly ("always use uv", "never read .env"). Natural pairing for `user-pref`. |
| `bead:<id>` | The lesson emerged from work on a specific bead (e.g. `bead:the-originating-bead`). |
| `session:<YYYY-MM-DD>` | Emerged from a session with no single owning bead. |
| `adr:<NNN>` | Derived from, or a pointer toward, an ADR (e.g. `adr:013`). |
| `incident` | Learned from a concrete failure with no clean bead/session handle. Natural pairing for `anti-pattern`. |
| `external:<url-or-repo>` | The origin-of-content is external. Natural pairing for `reference` (e.g. `external:github.com/xemantic/golem-xiv`). |

**Why required, not optional:** an unsourced non-decaying entry is unauditable — months later you cannot tell whether its originating context still holds, so you cannot safely retire it. Forcing `source:` at write-time is the same discipline as forcing the L2A/L2B decay choice (D2): the question is cheap to answer now and expensive to reconstruct later. There is always a fillable value (`user-directive` / `session:` / `incident` are the always-available fallbacks).

**`/compound` interaction:** when `/compound`'s Record step routes an entry to L2B, populate `source:` with the closing bead (`bead:<id>`) or the session date that triggered the record. When the Retire step finds a fulfilled pointer (e.g. `source: adr:013` on an entry that was a placeholder until that ADR landed), `source:` is the evidence the pointer is now resolved.

**Deliberately NOT added:** a `confidence:` field. L2B is a non-decaying store of things asserted as *true*; inviting low-confidence writes would poison it. Uncertain beliefs belong in L2A (decaying) or stay unwritten.

---

## Do NOT capture (gate before choosing a kind)

L2B is **non-decaying** — an entry written today is still asserted months from now, after the environment that produced it has changed. That makes a *wrong* entry actively harmful, not merely noise: it becomes a self-imposed constraint the agent cites against itself long after the cause is gone. Reject these before writing:

- **Environment-dependent failures** — missing binaries, fresh-install errors, unset credentials, `command not found`, post-migration path mismatches. The user can fix these; they are not durable rules. If a setup step IS the lesson, capture the *fix* (the install/config command) as a `procedural-lesson` — never "X doesn't work" as a standalone constraint.
- **Negative capability claims** — "browser tools don't work", "can't use Y from execute_code", "tool Z is broken". These harden into refusals the agent quotes against itself long after the underlying problem was fixed. Highest-cost poisoning mode for a non-decaying store.
- **Transient errors that resolved before the work ended** — if a retry worked, the lesson is the retry pattern, not the original failure.
- **One-off task narratives** — "summarized the Q2 deck", "analyzed PR #123". Episodic, not a class of work — that's CASS/transcript territory, not L2B.

If the candidate is genuinely time-bound or situational, it belongs in **L2A (decaying cm playbook)**, not here. The decay/non-decay split IS the filter: ask "will this still be true and useful after the environment turns over?" — if no, it is not an L2B entry.

---

## Tiebreak rules

When kind is ambiguous, apply in order:

1. **`reference` vs `project-anchor`:** Use `project-anchor` if it concerns *this current repo's* state/conventions; use `reference` if the origin-of-content is external. Frequency-of-use is NOT the discriminator — origin-of-content is. Example: a note about a cloned third-party repo's API → `reference`; a note about which branch of this repo to work from → `project-anchor`.

2. **`user-pref` vs `procedural-lesson`:** Use `user-pref` if WHY is "user told me to"; use `procedural-lesson` if WHY is "we learned from incident/calibration".

3. **`procedural-lesson` vs `anti-pattern`:** Use `anti-pattern` if the body warns against a specific failure mode with a PITFALL marker; use `procedural-lesson` otherwise.

**Fallback (no kind fits after tiebreak):** Raise to orchestrator before committing. Do NOT invent a new kind; surface the misfit with the ambiguity description. Recovery: document the raise reason, proceed with remaining entries, open a follow-up bead for unresolved cases.

---

## When to invoke this skill

Triggers:
- About to call `bd remember --key=...`
- `/compound`'s Record step routing an entry to L2B (`target: L2B (bd remember --key=<key>)`)
- Writing any `procedural-lesson`, `anti-pattern`, `user-pref`, `project-anchor`, or `reference` entry

---

## CLI invocation pattern

```bash
bd remember --key=<derived-key> "$(cat <<'EOF'
---
kind: procedural-lesson
scope: global
created: 2026-05-19
source: session:2026-05-19
---

One-line summary of the lesson.

**Why:** Brief incident or preference rationale.
**How to apply:** Specific trigger condition and action.

Optional additional context or [[cross-ref-key]] notation.
EOF
)"
```

The body field carries the entire frontmatter + structured body block. bd does not natively parse the frontmatter — the convention is reader-side discipline. `/compound` reads `created:` from the body directly for age-aware reasoning. `bd prime` surfaces only title + preview (no kind tag in index yet — deferred enhancement).

Key naming convention: kebab-case, descriptive, no namespace prefix required (bd is already scoped per project).

---

## Worked examples

### Well-formed entry (procedural-lesson)

```bash
bd remember --key=feedback_uv_workflow "$(cat <<'EOF'
---
kind: procedural-lesson
scope: global
created: 2026-05-19
source: user-directive
---

Use uv CLI commands instead of hand-editing pyproject.toml.

**Why:** Hand-editing pyproject.toml caused dependency resolution failures in multiple sessions; uv's lockfile discipline prevents these.
**How to apply:** Whenever adding, removing, or updating Python dependencies — use `uv add <pkg>`, `uv remove <pkg>`, `uv init`. Never open pyproject.toml to add deps by hand.
EOF
)"
```

### Well-formed entry (anti-pattern)

```bash
bd remember --key=anti_subagent_repo_root "$(cat <<'EOF'
---
kind: anti-pattern
scope: global
created: 2026-05-19
source: incident
---

PITFALL: Subagents must use worktree paths, not repo root.

**Why:** Using repo root paths in subagents triggers permission prompts and human-interruption because worktrees are the sandboxed execution context.
**How to apply:** Before dispatching any subagent that touches the filesystem, verify the path is the worktree path (not the origin repo root). Check memory [[feedback_worktree_paths]] for full context.
EOF
)"
```

### AVOID — free-text without frontmatter (non-conformant)

```bash
# BAD: No frontmatter, no structured body — /compound cannot age-reason, kind is
# unrecoverable, tiebreak history is lost. Do NOT write entries like this:
bd remember --key=some_lesson "Always use uv. User told me. Very important."
```

---

## Canonical refs

- [ADR-013](docs/decisions/ADR-013-memory-layer-architecture.md) D2 — architectural source for bd memories body convention
- [ADR-013](docs/decisions/ADR-013-memory-layer-architecture.md) D8 — kind enum (extended with `user-pref`, `project-anchor`, `reference` by the memory-write redesign epic)
- [ADR-013](docs/decisions/ADR-013-memory-layer-architecture.md) D9 — impl-agnostic architecture spec; bd memories is the Claude Code binding for L2B
- compound/SKILL.md (methodology home) — primary consumer of L2B entries; Record→L2B routing path produces output that must follow this convention
- memory-write redesign epic — bead that brought this skill into being (D2 is the spec source)
- `source:` frontmatter field added 2026-06-03, adapted from Golem XIV's knowledge-graph provenance (`actualizes` edge pins every fact to its originating cognition). Field convention is skill-local; ADR-013 D2/D8 delegate frontmatter spec to this skill, so no ADR edit was required.
