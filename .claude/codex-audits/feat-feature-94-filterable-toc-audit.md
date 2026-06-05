---
branch: feat/feature-94-filterable-toc
threadId: 019e9832-2b5c-7bf3-b76e-e10a7bacc6fe
rounds: 2
final_verdict: follow-up-recommended
date: 2026-06-05
---

# Gate-4 audit — Feature #94 (filterable TOC) WI-1

A client-side filter field atop the Contents tab of `TOCSheet`: narrows the
loaded chapter entries by title as you type (case-insensitive, diacritic-folded,
CJK-aware substring via Foundation `range(of:options:)`), a live "N of M
chapters" count, match-highlighting (15% accent tint + accent underline on all
occurrences), a no-match "Search full text" escape hatch, and a pinned current
"Reading" row. NEW `TOCTitleFilter.swift` (pure) + `TOCFilterField.swift` +
`TOCSheet+Filter.swift`; MODIFIED `TOCSheet.swift` + `TOCSheetRows.swift`.

## Round history

| Round | Findings | Resolution |
|---|---|---|
| 1 (`019e9827`) | **M1** the design's pinned current-chapter "Reading" row is missing when the active chapter is filtered out — the user loses location context. Lows: focused-field `Cancel` affordance omitted; `TOCSheet.swift` still 327 lines (the Gate-2 "extract under 300" only partially honored). | see below |
| 2 (`019e9832`) | **clean** — M1 resolved; no new Critical/High/Medium; all files within the size guideline. | — |

## Fixes applied

**M1 (pinned "Reading" row)** — added the pure `TOCTitleFilter.isActiveFilteredOut(entries:activeIndex:query:)`
+ the `TOCSheet.pinnedCurrentEntry` derivation (in `+Filter`) + a `PinnedCurrentRow`
view (`TOCSheetRows.swift`, per the `PinnedCurrentRow` artboard: a "READING"
accent label + serif accent title + "p.{page}", accent-tinted box, bottom rule,
tappable → navigate). Rendered in `contentsBody` between the field and the
list/no-match, so the current location stays reachable while filtering. Pinned by
3 `isActiveFilteredOut` tests (hidden / visible / edge cases).

**Low (focused Cancel)** — added a "Cancel" button to `TOCFilterField`, shown
when the field is focused, that clears the query + resigns focus.

**Low (file size)** — moved `tocEntryList` (the filtered list + inner ScrollView +
the auto-scroll ladder) from `TOCSheet.swift` to `TOCSheet+Filter.swift`. All five
files are now within the ~300-line guideline (`TOCSheet.swift` 294, `+Filter` 192,
`+Rows` 286, `TOCFilterField` ~124, `TOCTitleFilter` ~152).

## The Gate-2 fixes (all honored in code — round-1 verified)

original-index (`filtered` returns `(index, entry)`; rows use `pair.index`),
scroll-split (outer `ScrollView` removed; Contents = pinned field + inner
`ScrollViewReader { ScrollView { LazyVStack } }`; Bookmarks own scroll; scroll-to-
current `.task` preserved), Foundation matching + NFKC-out-of-scope doc,
clear-filter re-scroll (`scrollLadderKey` folds `filterQuery.isEmpty`),
non-private `filterQuery`, the pure-derivation tests.

## Verdict

`follow-up-recommended`. #94 is clean (2 audit rounds → 0 open Critical/High/Medium).
The single follow-up is a Gate-5 on-device visual check of the match-underline
COLOUR (rendered via the UIKit attribute scope `underlineColor` since SwiftUI
`Text.LineStyle` is monochrome) — the dominant match treatment is the accent
BACKGROUND tint, which is fully reliable; the underline-colour is a visual nicety
worth eyeballing once. 58 tests across the TOCTitleFilter + TOCSheet suites pass.
