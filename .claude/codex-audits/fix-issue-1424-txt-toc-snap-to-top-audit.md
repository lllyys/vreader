---
branch: fix/issue-1424-txt-toc-snap-to-top
threadId: codex-exec (run-codex.sh, 2 rounds; round 1 timed out at 300s, re-run at 600s)
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex audit — Bug #312 (GH #1424): TXT TOC jump snap-to-top

## Fix summary

A TXT TOC / chapter / bookmark jump reused the search-result navigation path
(intentional 0.25 viewport headroom), so the chapter title landed ~¼ down
(non-chunked) or mid-chunk (continuous-chunked UITableView — the default for
chaptered TXT in scroll layout) instead of pinning to the top.

Design: the intent is encoded in the locator shape — a search hit carries a char
RANGE (highlight the match → keep headroom), a TOC/chapter/bookmark jump carries
only a point offset (no range → snap to top). `handleNavigateToLocator` sets
`scrollSnapToTop = (highlightRange == nil)`. The flag threads through
`TextReaderUIState` → both TXT bridges. Non-chunked: `headroomFraction: 0`.
Chunked: after `scrollToRow(.top)`, add the target glyph's `lineFragment` minY
(`Coordinator.glyphTopY` via `layoutManager.boundingRect`) to `contentOffset.y`
instead of the linear intra-chunk fraction.

Changed files: `ReaderNotificationHandlers.swift`, `TextReaderUIState.swift`,
`TXTTextViewBridge.swift`, `TXTTextViewBridgeCoordinator.swift`,
`TXTChunkedReaderBridge.swift`, `TXTChunkedHighlightHelper.swift`,
`TXTReaderContainerView.swift`, `vreaderTests/.../ReaderNotificationHandlerTests.swift`.

## Round 1 (300s budget — timed out)

The audit did not reach a verdict in 300s (6-file diff + deep questions). It
surfaced incidentally that `MDReaderContainerView` also constructs
`TXTTextViewBridge` — but `snapToTop` has a default of `false`, so MD compiles
and keeps its current behavior (MD TOC snap is out of scope for #312; no
regression). Re-run at 600s.

## Round 2 (600s budget — SUCCEEDED)

| file:line | severity | issue | resolution |
|---|---|---|---|
| TXTTextViewBridge.swift:302 / TXTChunkedReaderBridge.swift:326 | Medium | Scroll dedupe ignored `snapToTop`: both bridges suppress a programmatic jump when the UTF-16 target equals the last target, so a search→TOC (or TOC→search) jump to the SAME offset kept the old positioning instead of switching between 0.25 headroom and top-pin. The practical stale-flag case. | **Fixed.** Added `lastSnapToTop` to both coordinators and made the snap mode part of the dedupe key: non-chunked folds `snapModeChanged` into `shouldScroll`'s `sourceChanged`; chunked ORs `scrollSnapToTop != lastSnapToTop` into the re-scroll guard. A snap-mode change now re-arms the jump even to an unchanged offset. |

Codex explicitly confirmed clean: `glyphTopY` guarded against empty/out-of-range
text; the `attemptChunkRestore` intra-fraction branch, #153 headroom path, #288
immediate broadcast, and #289 restore suppression all intact.

## Verdict

`ship-as-is` — zero open Critical/High/Medium after the round-2 dedupe fix.

## Verification

### Device verification caught a second real bug (overshoot)

Device verification on a real 13M CJK chaptered TXT (`黑暗血时代.txt`, 1860
chapters, chunked path) caught a bug the static audit did not: the initial
`glyphTopY` computed the glyph rect off the **live cell's** `layoutManager`
right after `layoutIfNeeded()`, when the cell's `textContainer` width had not
yet propagated (width ≈ 0). That stacked one char per line, producing an
astronomical y that overscrolled to the chunk end — tapping chapter 8 (offset
20753) landed at 32319 (chapter 12). Instrumented logging confirmed the
degenerate y.

**Fix:** `glyphTopY` now computes in a STANDALONE `NSLayoutManager` at the
cell's known text width (`tableView.bounds.width - 32`), independent of live-cell
layout timing. Re-verified: tapping chapter 18 (offset 49205) →
`glyphTopY = 26870` (sane) → landed position **49203 ≈ chapter 18 start**;
chapter 14 → title visibly pinned to the top (`dev-docs/verification/artifacts/bug-312-verify-ch14-title-pinned-20260603.png`).
The standalone helper is now a **pure unit-tested** function
(`glyphTopY_realWidth_doesNotStackPerLine` asserts the real-width result is far
smaller than the degenerate ≈1-char-width result).

### Test coverage

- Unit: `ReaderNotificationHandlerTests` (intent: point→snap, range→headroom,
  latest-nav tracking) + `TXTChunkedScrollOffsetTests.glyphTopY_*` (real-width
  layout, first-char-at-top, empty/zero-width guards) + existing
  `scrollOffsetForVisibleMatch_zeroHeadroom_*` (non-chunked top-edge) +
  `TXTChunkedReaderBridgeRestoreTests` (restore path unchanged) — all green.
- Device: chunked-path glyph snap verified on `黑暗血时代.txt` — TOC tap lands
  the chapter at its start (position == chapter `globalStartUTF16` ± the
  leading newline), title pinned to the top. Artifacts in
  `dev-docs/verification/artifacts/bug-312-*-20260603.png`.
