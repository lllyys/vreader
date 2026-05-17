---
branch: fix/issue-776-txt-md-highlight-color
threadId: 019e3426-62ad-7eb2-95b0-1cbc563caba0
rounds: 1
final_verdict: ship-as-is
date: 2026-05-17
---

## Gate 4 — Codex implementation audit, Bug #208 / GH #776

`HighlightableTextView.HighlightingLayoutManager` carried a bare
`[NSRange]` and painted every range with one hardcoded
`UIColor.systemYellow.withAlphaComponent(0.4)`;
`TextHighlightRenderer.apply` and
`TextReaderUIState.refreshPersistedHighlights` dropped
`HighlightRecord.color`. A highlight the user saved as pink/green/blue
still rendered yellow in TXT/MD readers.

Fix: a new Foundation-only `PaintedHighlight { range: NSRange,
colorName: String }` value type is threaded end-to-end —
`TextReaderUIState` → TXT/MD bridges + coordinators → chapter/chunk
translation helpers → `HighlightableTextView.setHighlightRanges` →
`HighlightingLayoutManager`. The layout manager now keeps
`persistedHighlights: [PaintedHighlight]` (each painted via
`HighlightPaintColor.fill(for:)`) plus a separate
`searchHighlightRange: NSRange?` for the transient search/nav
highlight (still `systemYellow`). New `HighlightPaintColor.fill(for:)`
maps the stored color name through `NamedHighlightColor.hex` (the
committed design palette), falling back to yellow for
unknown/legacy/empty values — mirroring
`FoliateHighlightRenderer.foliateColor(from:)`.

Codex MCP, read-only sandbox. Thread `019e3426-62ad-7eb2-95b0-1cbc563caba0`.

## Round 1

**Audit result on GH #776: No findings — clean.**

Codex reviewed the end-to-end flow through `TextReaderUIState`,
`TextHighlightRenderer`, `TXTTextViewBridge`, `TXTReaderContainerView`,
`TXTChapterHighlightHelper`, `TXTChunkedHighlightHelper`, and
`HighlightableTextView`, and confirmed all eight focus areas sound:

- **Correctness** — the fix addresses the root cause on every TXT/MD
  render path: full-text TXT, chapter-mode TXT, chunked large-file
  TXT, and MD all now carry `HighlightRecord.color` to paint time.
- **Edge cases** — unknown / legacy / empty / malformed stored color
  strings fall back safely (`HighlightPaintColor.uiColor(fromHex:)`
  returns nil → yellow). Exact overlap between a persisted highlight
  and the transient search highlight is still deduped in
  `setHighlightRanges`. Zero-length persisted ranges are filtered at
  load/apply time; zero-length active ranges are suppressed.
- **`#if canImport(UIKit)` boundary** — keeping `PaintedHighlight`
  outside the `#if` (so the non-UIKit `ReaderNotificationHandlers` /
  `TXTChapterHighlightHelper` can thread it) and `HighlightPaintColor`
  inside it is correct.
- **Concurrency** — Swift 6 strict concurrency correct: UI mutation
  stays `@MainActor`; `PaintedHighlight` being `Sendable` is
  appropriate.
- **Performance** — `HighlightPaintColor.fill(for:)` runs per visible
  highlight inside `drawBackground` (a hot path), but the palette is
  tiny and visible-highlight counts are low; caching is not required
  unless profiling shows draw cost. Accepted as written.
- **Dead code** — the split `paint(...)` helper in the layout manager
  is a clean dedup. `ReaderNotificationHandlers.handleHighlightRequest`
  has no production caller (test-only exercised); its yellow-only
  optimistic-append path is harmless and pre-existing — not touched
  beyond the mechanical type change.
- **Behavior change** — the persisted-"yellow" shift from
  `systemYellow` to the design `#f0d25a` is intentional, not a
  regression: the new contract is "a persisted highlight matches the
  saved design-palette swatch the user tapped in SelectionPopover."
  The transient search/nav highlight explicitly stays `systemYellow`
  (pre-#208 value), so search-result behavior is unchanged.

## Resolution summary

Zero Critical/High/Medium/Low findings. `xcodebuild build-for-testing`
compiles clean; the Swift Testing unit suite (992 tests, 104 suites)
passes — including the new `HighlightPaintColor` / `PaintedHighlight`
suites and the color-preservation tests added to `TextHighlightRenderer`,
`TextReaderUIState`, `TXTChapterHighlightHelper`,
`HighlightableTextView`, and the `chapterLocalHighlightRanges` suite.
The 7 XCTest failures in the run (`TTSServiceSpeedControlTests`,
`AutoPageTurnerWiringTests`, `BookFileMaterializerTests`) are a
pre-existing process-crash flake documented in prior verification
docs — unrelated to highlights, neither introduced nor worsened by
this change.

**Verdict: ship-as-is.**
