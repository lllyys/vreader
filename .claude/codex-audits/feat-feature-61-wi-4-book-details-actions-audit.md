---
branch: feat/feature-61-wi-4-book-details-actions
threadId: 019e3b13-88c4-72b1-8768-592eb46c0bf7
rounds: 2
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex audit — feature #61 WI-4 (Book Details actions wiring)

Gate-4 implementation audit for feature #61 WI-4 — the final WI:
wiring the Book Details sheet's action controls (WI-3 shipped them
inert). Audited on the same Codex thread as WI-3 (full #61 context).

## Scope audited

New files:
- `vreader/Views/Reader/BookDetails/BookDetailsSheet+Actions.swift`
- `vreaderTests/Views/Reader/BookDetails/BookDetailsActionsTests.swift`

Modified:
- `vreader/Views/Reader/BookDetails/BookDetailsSheet.swift`
- `vreader/Views/Reader/ReaderContainerView.swift`
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift`
- `vreaderTests/Views/Reader/BookDetails/BookDetailsRouteTests.swift`

## Round 1 — findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | ReaderContainerView+Sheets.swift | Medium | The export route dismissed Book Details and presented the annotations panel in the same state update — both are sibling `.sheet` presenters on `ReaderContainerView`, so SwiftUI can drop the second presentation. | **Fixed.** Added `@State var exportAnnotationsAfterBookDetailsDismiss`. The "Export annotations…" closure now only sets that flag + `showBookDetails = false`. The Book Details `.sheet` gained an `onDismiss:` that, when the flag is set, clears it and *then* opens the annotations panel — the panel is presented strictly after Book Details has dismissed. A normal swipe-dismiss leaves the flag false → `onDismiss` is a no-op. |
| 2 | BookDetailsActionsTests.swift | Low | WI-4's routing branches were mostly unpinned (labels + pasteboard copy were tested; the router itself was not). | **Fixed.** Added `coverActionPresentsCoverPickerForBook` (asserts `handleAction(.cover)` arms the injected `CoverPickCoordinator.bookForCover`) and `exportActionInvokesHostRoute` (asserts `handleAction(.exportAnnotations)` invokes the injected host closure). The `.share` / `.reveal` branches only flip the `showShareSheet` `@State`, which is not reliably readable outside a SwiftUI render pass — they stay covered at the Gate-5 XCUITest level rather than with a flaky `@State`-readback test. |

## Round 2 — verification

Codex re-reviewed the diff after both fixes: **clean.** The `onDismiss`
flag handshake is correct (flag cannot get stuck — `onDismiss` no-ops
when false; swipe-dismiss path unaffected). Both new tests are sound
under the `@MainActor` suite. No new correctness / concurrency / routing
regression.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium findings after round 2.
All five action controls (cover-swap, title-bar Share, "Share book…",
"Export annotations…", Fingerprint copy, Location reveal) route to the
documented engines (`CoverPickCoordinator`, `ShareSheet`, the
annotations-panel export route, `UIPasteboard`). The shared
`showShareSheet` for "Share book" + "reveal location" is consistent
with plan Risk 2. `BookDetailsSheet+Actions.swift` split keeps
`BookDetailsSheet.swift` under the ~300-line guideline. WI-4 wires
exactly the plan's WI-4 scope — nothing out of scope, nothing left
unwired.
