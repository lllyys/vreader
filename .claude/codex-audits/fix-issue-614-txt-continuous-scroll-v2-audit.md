---
branch: fix/issue-614-txt-continuous-scroll-v2
threadId: 019e3e68-a4ee-7711-9fe5-99c443d0044b
rounds: 3
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — Bug #180 / GH #614: TXT continuous-scroll reader

Re-scoped fix for Bug #180 (`docs/bugs.md`): abandon PR #681's
boundary-detect-then-swap design and render chaptered TXT in Scroll
layout as one continuous scrollable surface, reusing the chunked
`UITableView` windowing. Implements the 8 work items of
`dev-docs/plans/20260519-bug-180-txt-continuous-scroll.md`.

Codex MCP read-only audit, model gpt-5.2-codex equivalent.

## Round 1 — 3 findings (1 High, 1 Medium, 1 Low)

| File:line | Severity | Finding | Resolution |
|---|---|---|---|
| `TXTReaderContainerView.swift:103` | High | `shouldOpenContinuous` gates only on layout; `.task` calls `openContinuous` unconditionally for every scroll-layout TXT. `TXTService.openChapterBased` synthesizes ≥1 chapter for any non-empty book, so this routes effectively ALL scroll-mode TXT (including non-chaptered) to the continuous chunked path. | **Fixed** — added a `index.chapters.count >= 2` guard in `TXTReaderViewModel.openContinuous`: a book with <2 chapters (every non-chaptered file → one synthetic chapter) falls back to `openChapterBased`. Continuous mode now engages only for genuinely multi-chapter books — exactly the set that suffered the chapter-SWAP. Test `openContinuousSingleChapterFallsBackToNonContinuous` updated to assert `isContinuousMode == false`. |
| `TXTReaderViewModel.swift:500` | Medium | `openContinuous` restored `currentChapterIdx` / `currentChapterLocalUTF16` directly from the saved `(chapterIdx, localOffset)` pair. At an exact chapter-end restore, `resolveChapterPosition` clamps `localOffset` to `textLengthUTF16`, so the computed global offset lands on the next chapter while the VM reports the previous one until the first scroll — a brief stale `txtchapter:` locator. | **Fixed** — the restore block now computes `rawGlobal`, clamps to `[0, totalTextLengthUTF16]`, then DERIVES `currentChapterIdx = chapterContaining(global)` and `currentChapterLocalUTF16 = global - globalStart(derivedIdx)`. The saved idx is no longer trusted. Regression test `restoreAtExactChapterEndDerivesChapterFromGlobalOffset` added. |
| `TXTReaderViewModel.swift:533` | Low | `continuousChapterGlobalStart` / `continuousGlobalOffset` orphaned; old `goToNextChapter` / `goToPreviousChapter` aliases also dead. | **Fixed** by removal — the container's `onNavigate` already publishes the TOC entry's document-global offset straight to `uiState.scrollToOffset` (plan §3.3), so the VM helpers are unnecessary. `goToNext/PreviousChapter` aliases (only used by the rejected boundary-swap) removed. `navigateToChapter` / `navigateToChapterByTitle` / `navigateToGlobalOffset` / `nextChapter` / `previousChapter` KEPT — they still serve the Paged single-chapter path. Orphan-helper tests removed. |

Model-assumption check (round 1): Codex confirmed all referenced
fields/cases exist — `TXTChapter.globalStartUTF16`,
`TXTChapter.textLengthUTF16`, `TXTChapterIndex.totalTextLengthUTF16`,
`EPUBLayoutPreference.scroll` / `.paged`.

## Round 2 — 1 Medium, 1 Low

| File:line | Severity | Finding | Resolution |
|---|---|---|---|
| `TXTReaderViewModel.swift:458` | Medium | The `count >= 2` guard still routes large non-chaptered TXT (synthetic multi-chapter) through continuous mode; suggested carrying `.detected/.synthetic` provenance. | **Withdrawn by auditor in round 3** after evidence. The finding's premise (large non-chaptered files should stay on the legacy `chunkedReaderContent` path) is incorrect: on `origin/main` that path is a *fallback* — `.task` called `openChapterBased` unconditionally, which always produces a chapter index, so the live path for any successfully-opened TXT was `chapterReaderContent` (one synthetic chapter at a time, WITH the swap). Large synthetic-multi-chapter files suffered the exact Bug #180 swap. Gating to detected-only would REGRESS them. The `count >= 2` gate is correct. |
| `TXTReaderViewModel.swift:550` | Low | `navigateToChapter` doc comment still referenced the removed `continuousChapterGlobalStart` helper. | **Fixed** — comment updated to point to the container's `onNavigate` global-offset path. |

## Round 3 — 0 findings

Codex re-checked the pre-fix control flow against `origin/main` and
explicitly agreed: the Medium finding does not hold; the `count >= 2`
gate fixes exactly the swap-affected set (multi-chapter, detected or
synthetic); gating to detected-only would leave large synthetic
multi-chapter books on the rejected swap model. Confirmed the
single-chapter fallback and the derive-on-restore change (both
saved-position and no-saved-position branches) are correct, with no
new issue introduced.

> "No findings. This fix can ship."

## Summary verdict

**ship-as-is.** 3 rounds. Round 1: 1 High + 1 Medium + 1 Low — all
fixed. Round 2: 1 Medium (withdrawn after evidence) + 1 Low (fixed).
Round 3: clean. No open Critical/High/Medium/Low. Build succeeds; the
69 new continuous-scroll tests + 72 existing TXT chapter/highlight/
progress regression tests pass.
