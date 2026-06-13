---
name: tldr
description: Re-emit the previous assistant message applying the countermand test from the brain-of-loop hook — lead with structural shape and the tradeoff, cut showing-your-work prose, re-gloss every bead ID / D-label / Round label / opaque ID as if first mention. Use when the user invokes /tldr or says "too dense", "too detailed", "make it simpler", "design level not detail", "I want to think on architecture level", "give me the executive cut", or any equivalent signal that the previous message overshot on detail or undershot on reference discipline. Recovery macro — the default lives in the session-start hook; this skill is the safety net when that default doesn't land.
---

# /tldr

Re-emit the immediately-previous assistant message applying the countermand test from the session-start "Communicating with me" guidelines.

## What to do

1. Re-read the previous message.
2. Identify what failed: **altitude** (detail-dump when design-level was wanted) or **reference discipline** (bare bead IDs / raw R0/R1/R2 / raw D-labels / opaque IDs) — or both.
3. Emit the revised version. No apology, no preface, no "here's a tighter version" — just emit.

## Keep

- Every load-bearing claim and decision.
- Self-anchoring refs raw (`file.sh:421`, ADR numbers, commit hashes) — these ARE load-bearing (auditable evidence / warrant for a claim); don't compress them away under prose-reduction pressure.

## Cut

- Showing-your-work prose ("here's what I considered…", "let me explain…").
- Paragraphs making the case for a decision already named.
- Bare bead IDs (e.g. a brainstorm bead ID → "third-party ticketing research brainstorm").
- Raw internal labels (`R2` → `R2 (second adversarial-review round)`, `D7` → `D7 (creator-platform cross-reference)`).

## Cold-readable discipline

Glossing is for **understanding**, not labeling. Test before sending: a colleague with zero session context, no access to the bead store, no memory of what was discussed — does the phrase as written mean something to them? If not, **translate, don't append**.

Lead with one short plain-English paragraph naming what was shipped / decided / learned in human terms — what does the system now do that it didn't before. Bead-tree structure, substrate writes, and label sequences come after that lead, not in place of it.

Failure shapes — drawn from real /tldr misfires:

- **Slug-shaped gloss.** An identity-and-trust bead ID glossed as "(identity + trust model epic)" still reads as jargon. Better: "the work to add a trust-cluster identity model — `User.status` enum for tiering, `ProfileClaim` for later account-claiming, and a vouched-signup path alongside the open one."
- **Label-soup children.** `.11 +D2+D3 + auto-Profile reachable / .12 +D3 cleanups` is opaque markers. Translate: "two follow-up beads from re-verifying the parent — `.11` fixed three violations and made auto-created Profile records reachable from the signup flow; `.12` cleaned up two conformance gaps." Cite the D-labels as warrant, not as the description.
- **Memory-slug quoting.** `parent-re-verify-catches-conjunction-drift` is the storage key, not the lesson. State the lesson plainly: "after a multi-bead epic, re-verifying the parent's acceptance once children close catches drift where the children's conjunction no longer satisfies the parent." The slug is an optional pointer afterwards (`bd memories parent-re-verify-catches-conjunction-drift`), not the content.
- **Substrate-jargon without translation.** `/compound folded — L2B: ... L2A: ...` assumes the reader knows what folding is and what L2A/L2B mean. Say it: "ran the epic-close retrospective and recorded three lessons in long-term memory (`bd memories`, L2B) plus one calibration in the decaying observation layer (cm playbook, L2A)."

Rule of thumb: if removing all bead IDs, D-labels, memory slugs, and ADR-D references leaves a paragraph that still tells the reader **what happened and why it matters**, the translation is sufficient. The IDs are then added back as auditable pointers, not as the carrier of meaning.

This is a tightening pass at a different altitude — often >50% prose reduction with every load-bearing claim preserved, **and every remaining claim phrased so a cold reader can absorb it without lookups**. Not a summary; not a different answer.
