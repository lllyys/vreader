---
branch: feat/132-wi3-toc-contents-sheet
threadId: 019f5040-36fa-7270-8b41-4a137f8c2181
rounds: 2
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-3 (TocContentsSheet + TocSheetRows)

Independent Codex audit (rule 53 `scripts/run-codex.sh`, read-only sandbox, model
gpt-5.6-sol) of the Android reader Contents sheet — the `vreader-panels.jsx`
`TOCSheet` **Contents tab** as a single-pane `ModalBottomSheet` (rule 51).

Files audited:
- `android/app/src/main/kotlin/com/vreader/app/reader/nav/TocContentsSheet.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/nav/TocSheetRows.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/nav/TocContentsSheetTest.kt`

## Round 1 — verdict: block-recommended (3 findings)

Thread `019f5038-b108-7702-8a3b-88ace6ae345c`. Raw: `.reports/wi3-audit.txt`.

| # | Severity | Finding | Fix |
| --- | --- | --- | --- |
| 1 | High | Rule-51 fidelity: wrong sheet title. The committed `TOCSheet` `Sheet` header uses the BOOK TITLE (`title="Pride and Prejudice"`); the diff invented a `"Contents"` heading. Removing the Bookmarks tab is correct, but that does not authorize replacing the designed title. | `TocContentsSheet` / `TocContentsSheetContent` now take a `bookTitle` param and render it centered-serif (17sp/600, `ink`) with a bottom rule — the design's `Sheet` chrome. The Bookmarks tab selector stays omitted (single-pane; #135 promotes to two tabs). New test `header_showsBookTitle_notInventedHeading`. |
| 2 | Medium | Current-row highlight colors don't match the design. Design tint is `rgba(140,47,47,0.08)` (light) / `rgba(214,136,90,0.12)` (dark); the diff used `accent.copy(alpha=0.10f/0.14f)`. | Highlight now uses the theme accent (which IS the design's `140,47,47`/`214,136,90`) at the exact design alphas: `0.08f` light, `0.12f` dark. |
| 3 | Medium | Row a11y discards useful info — `contentDescription = title` collapses each actionable row to only its title. | The row `contentDescription` now announces chapter number + title + page label + current-chapter state (`"Chapter 2, Chapter Two, page 17, current chapter"`). |

## Round 2 — verdict: ship-as-is

Thread `019f5040-36fa-7270-8b41-4a137f8c2181`. Raw: `.reports/wi3-audit-r2.txt`.

All three round-1 findings confirmed resolved; no new blocking or follow-up
findings. Behavior confirmed by the auditor:

- Faithful single-pane extraction of the `TOCSheet` Contents tab; no dead Bookmarks control.
- Book-title `Sheet` header (rule 51) with the design's bottom rule.
- Dismiss-on-success: `onDismiss()` fires only when `onJump(index)` returns `true`; a failed
  jump leaves the sheet open with NO invented error surface (rule 51 §nav-error-presentation).
- `currentTocIndex` drives the accent tint + accent/weight-600 title + the current marker.
- Empty entries render `toc-empty`, no rows.
- State-and-callback-driven composables using the `ReaderTheme` token map (the `ReaderTopChrome` sibling).
- testTags `toc-sheet` / `toc-row-$index` / `toc-empty` (+ `toc-title`, `toc-page-$index`, `toc-current-marker`); ≥48dp row targets; richer row a11y.
- Untitled entries, missing page labels, nested depth, and out-of-range current indices degrade safely.

Note: the auditor ran a static re-audit only (did not execute the Android instrumentation
suite in the read-only sandbox). The instrumented `TocContentsSheetTest` compiles green
(`:app:compileDebugAndroidTestKotlin`) + the JVM unit suite is green
(`RUN-ANDROID-TESTS RESULT: SUCCEEDED`); the live Compose run rides a WI-5/WI-8 connected slice.
