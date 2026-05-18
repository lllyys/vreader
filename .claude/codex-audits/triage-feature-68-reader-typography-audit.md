---
branch: triage/feature-68-reader-typography
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-18
---

## Scope

Docs-only triage commit. Files one new feature row (#68) in
`docs/features.md` for two reader-typography gaps found in a design-vs-shipped
audit. Touches `docs/features.md` only, plus `project.yml` /
`project.pbxproj` (version bump — rebased onto main: 3.30.2/453 → 3.30.3/454).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Audit basis — independent design-vs-shipped pass

The triage rests on a read-only investigation by a separate agent context
(general-purpose subagent) that read the three v2 design renders now in
the README and cross-checked each against the shipped SwiftUI with
file:line evidence. Author/auditor separation (rule 48) satisfied — the
audit agent was a distinct context from this orchestrator.

## What this commit records

| Audit gap | Classification | Outcome |
|---|---|---|
| Reader drop-cap — large accent first letter on a chapter's first paragraph (`vreader-reader.jsx:383-390`); no drop-cap code in any renderer | Feature (never implemented) | **Feature #68** — GH #867 |
| Reader in-text centered "CHAPTER 1" heading (`vreader-reader.jsx:333-343`); shipped `ChapterTitleOverlay` is a different, TXT-only top-of-screen bar | Feature (never implemented) | grouped into **#68** (same surface, same design region, cross-renderer) |
| Settings profile/stats header card (`vreader-panels.jsx`); `SettingsView` builds no profile header | DUPLICATE — already tracked as feature **#67** ("Settings profile-header card + Stats entry point", TODO, GH #825) | not re-filed |

The drop-cap and in-text chapter heading are grouped as one feature
(#68): same surface (the reading-view text body), adjacent design-source
region, and the same cross-renderer implementation area. A Gate-1 plan
may split them into work items.

## Bug-vs-feature reasoning

Both #68 elements were **never implemented** — no drop-cap or in-text
chapter-heading code exists in any renderer. Per the tracker's binding
rule ("never implemented → feature"), they belong in `docs/features.md`,
not `docs/bugs.md`. They are TODO follow-ons of feature #60 (VERIFIED,
terminal) — new rows per the close gate, consistent with how #64–#67
were filed.

## Verification-integrity finding (escalated, not silently filed)

The two #68 elements are shortfalls against feature #60's VERIFIED
acceptance criterion (b) ("Reader matches the design's chrome + page
layout pixel-close"). `dev-docs/verification/feature-60-20260516.md`
recorded `result: pass` for all 7 criteria; the audit shows two in-text
typographic elements of the reader page layout were never built. This
means #60's evidence file is partially inaccurate — the same shape as
the existing feature #66 finding. The #68 row states this explicitly.
**This triage records the gap; whether to add a correction note to
#60's evidence file or revisit its VERIFIED status is escalated to the
user** — triage classifies and records, it does not re-adjudicate a
terminal-state feature.

## Tracker-hygiene note (not edited)

`docs/features.md` currently has **two rows numbered `64`** — "Styled
highlight-action popover (v2)" (GH #822) and "Cross-format font-size
perceptual calibration" (GH #491). This pre-existing duplicate ID was
not touched here (renumbering affects GH issue titles + refs — a
separate decision). Feature #68's ID is the next free integer after the
max (67); the duplicate `64` does not affect that. Flagged for the user.

## Verdict

ship-as-is — documentation only, no code risk. Feature #68 goes through
`/feature-workflow` when picked up.
