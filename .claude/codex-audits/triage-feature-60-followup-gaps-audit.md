---
branch: triage/feature-60-followup-gaps
threadId: 019e317f-81c2-79e0-ad04-90325c07d883
rounds: 1
final_verdict: ship-as-is
date: 2026-05-17
---

## Scope

Docs-only triage commit closing the feature #60 follow-up accounting gap. Touches `docs/features.md` (3 new feature rows + a #56 scope note), `docs/bugs.md` (Bug #208 severity Medium→High), `project.yml` / `project.pbxproj` (version bump 3.27.1/415 → 3.27.2/416).

**No Swift source files changed.** The audit-gate hook fires on `project.pbxproj` in the diff — false positive of the Swift-file heuristic.

## Audit basis — Codex thread 019e317f

The triage rests on an independent Codex audit (read-only, thread `019e317f-81c2-79e0-ad04-90325c07d883`) run before recording. Codex verified, against the actual repo state:

- **Feature #60 verified on v1 criteria (a)–(g) only** — CONFIRMED via `dev-docs/verification/feature-60-20260516.md`. Book Details / annotations split / search panel were never in the verified acceptance table.
- **Book Details sheet — untracked** — CONFIRMED. Only the More-menu row exists (`ReaderMoreMenuRow.swift:25`); its handler sets `showSettings = true` (`ReaderContainerView+Sheets.swift:223`). No `BookDetailsSheet`/`BookDetailsView` Swift file.
- **Annotations split — untracked** — CONFIRMED. `AnnotationsPanelView.swift:4` states it covers the design's `TOCSheet` + `HighlightsSheet` "as one 4-tab sheet". No split files exist.
- **Search panel re-skin — untracked** — CONFIRMED. Production still presents the old `SearchView` (`NavigationStack` + `.searchable` + plain `List`); plan deferred it; no feature row.
- **Bilingual** — PARTIALLY-CORRECT: feature #56 (TODO) owns the backing mode, but the More-menu bilingual *row* (named "WI-6d", never created) has no home after #60 verified.

Codex verdict: "3 designed surfaces genuinely lack an implementation tracker home: Book Details sheet, annotations split, and search results panel re-skin."

## What this commit records

- **Feature #61** (Book Details sheet) — new row, TODO, `GH: #800`. Design source `feature-60-followups.md §1` + `vreader-book-details.jsx`.
- **Feature #62** (Annotations panel split) — new row, TODO, `GH: #801`. Design source `feature-60-followups.md §3` + `vreader-annotations.jsx`.
- **Feature #63** (Search results panel v2 re-skin) — new row, TODO, `GH: #802`. Design source `vreader-search.jsx`.
- **Feature #56** — scope note added: #56's scope explicitly includes the More-menu bilingual toggle row (the WI-6d orphan); #56's eventual plan implements the row alongside the backing mode.
- **Bug #208** — severity Medium → High. The 4-color SelectionPopover is a shipped-but-broken capability in a VERIFIED feature (user picks pink/green/blue, always sees yellow, no feedback/workaround). The inline severity note in the row is updated to match and recommends prioritising the fix above the #61/#62/#63 re-skin features.

All three new features are TODO follow-ons of feature #60 (VERIFIED, terminal) — new rows per the close gate, not a #60 reopen. GH issues created at triage time matching the recent #54–#60 precedent.

## Verdict

ship-as-is — documentation only, no code risk. The three features go through `/feature-workflow` when picked up; Bug #208 through `/fix-issue`.
