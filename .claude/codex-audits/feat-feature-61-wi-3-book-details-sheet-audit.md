---
branch: feat/feature-61-wi-3-book-details-sheet
threadId: 019e3b13-88c4-72b1-8768-592eb46c0bf7
rounds: 2
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex audit — feature #61 WI-3 (Book Details sheet, stacked + More-menu route)

Gate-4 implementation audit for feature #61 WI-3 — the reader Book
Details sheet (stacked layout) and the More-menu route rewire.

## Scope audited

New files:
- `vreader/Views/Reader/ReaderMoreMenuEffect.swift`
- `vreader/Views/Reader/BookDetails/BookDetailsSheet.swift`
- `vreader/Views/Reader/BookDetails/BookDetailsMetadataRow.swift`
- `vreader/Views/Reader/BookDetails/BookDetailsActionRow.swift`
- `vreader/Views/Reader/BookDetails/BookDetailsTagFlow.swift`
- `vreaderTests/Views/Reader/BookDetails/BookDetailsRouteTests.swift`

Modified:
- `vreader/Views/Reader/ReaderContainerView.swift`
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift`
- `vreader/Views/Reader/ReaderMoreMenuRow.swift`
- `vreader/Views/Reader/ReaderNotifications.swift`
- `vreaderTests/Views/Reader/ReaderMoreMenuRowTests.swift`

## Round 1 — findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | BookDetailsSheet.swift | High | Missing the design's title-bar trailing Share button (`vreader-book-details.jsx` `<Sheet trailing={Share}>`); the sheet rendered the fallback close button — a visible design omission, not an action-wiring deferral. | **Fixed.** Added an inert `shareButton` (28pt circular `square.and.arrow.up`) passed as `ReaderSheetChrome`'s `trailing`. Per `ReaderSheetChrome.trailingSlot`, a non-`EmptyView` `trailing` replaces the default close button — matching the design (Share, no X; dismiss via swipe). `onClose` dropped from `BookDetailsSheet`; `bookDetailsSheet` + the test call sites updated. Share action wiring is WI-4. |
| 2 | ReaderContainerView.swift | Medium | `.presentationDetents([.large])` is full-height; design specifies a 660pt partial sheet. | **Fixed.** `.presentationDetents([.height(660), .large])` — 660pt initial (design height) with `.large` available for expansion. |
| 3 | BookDetailsTagFlow.swift | Medium | A single tag wider than `maxWidth` was stored at full intrinsic width; `placeSubviews` centered that width → overflow past both edges; zero-width proposal reported width 0 while placing nonzero content. | **Fixed.** `measure(_:maxWidth:)` proposes `ProposedViewSize(width: maxWidth, height: nil)` and clamps the result to `maxWidth`; measured sizes are cached per-chip in `Row.items` and reused by `placeSubviews` (no re-measure drift). The tag chip `Text` gained `.lineLimit(1)` + `.truncationMode(.tail)`, so a long collection name truncates inside the clamped chip. Row width can no longer exceed `bounds.width`, keeping the centering offset non-negative. |
| 4 | docs/architecture.md:68 | Low | Stale claim — "The five app sheets share `ReaderSheetChrome`" did not mention the new Book Details sheet. | **Fixed.** Dropped the brittle "five" count; added `BookDetailsSheet` to the `ReaderSheetChrome` consumer list. |

## Round 2 — verification

Codex re-reviewed the diff after the four fixes: **clean.** Each fix
verified — Share button + close-button replacement correct and
design-matching, no dangling `onClose` references, detents correct,
`BookDetailsTagFlow` clamping/cached-size-reuse/empty-subviews/zero-width
paths all sound, architecture.md updated. No new
correctness / concurrency / SwiftUI regression introduced.

One residual non-blocking note: `ReaderNotifications.swift:88` still
documented `.readerMoreBookDetails` as opening the old settings interim.
**Fixed** in the same commit (rule 22 — comment maintenance).

## Verdict

**ship-as-is.** Zero open Critical/High/Medium findings after round 2.
The `ReaderMoreMenuEffect` route seam and the extra `BookDetailsTagFlow.swift`
file split were both confirmed justified (the testable route seam the
plan's `BookDetailsRouteTests` requires; keeping `BookDetailsSheet.swift`
under the ~300-line guideline). `@State var showBookDetails` (internal,
not the plan's stated `private`) confirmed as a necessary cross-file
visibility correction — `handleMoreMenuAction` + `bookDetailsSheet` live
in the `+Sheets.swift` extension. WI-3/WI-4 split honored: WI-3 ships the
rendered surface, WI-4 wires the actions.
