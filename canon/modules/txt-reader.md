---
title: Module — TXT reader
updated: 2026-07-10
status: verified
---

# Module — TXT reader

## Purpose

Reads plain-text books: detects encoding (including CJK codepages), detects chapters with Legado-ported regex rules, lazily loads chapter content, and renders through one of several strategies (whole-text UITextView, chunked UITableView for large files, chapter-based display, continuous scroll, or paged mode). All positions are UTF-16 code-unit offsets to match NSString/TextKit conventions (see [[Module — locator]]).

## Key files and types

- `vreader/Services/TXT/TXTService.swift` — `actor TXTService: TXTServiceProtocol` (676 lines). `open(url:)` full decode; `openChapterBased(url:)` (WI-5) returns `TXTChapterOpenResult`; `static func decodeForDisplayAndSearch(_ data: Data) -> (String, String)?` is the single decode entry point shared with search indexing (bug #99 cause #2); `buildChapterIndexFromFullText` and `buildTXTTOCEntries(data:fingerprint:)` (bug #286: TOC and reader share one decode + one rule selection).
- `vreader/Services/TXT/TXTServiceProtocol.swift` — `TXTServiceProtocol`, `TXTFileMetadata`, `TXTChapterOpenResult`, `TXTServiceError` (`fileNotFound`, `decodingFailed`, `alreadyOpen`, …).
- `vreader/Services/TXT/TXTTocRuleEngine.swift` — `enum TXTTocRuleEngine`: 25 regex rules ported from Legado's `txtTocRule.json`, 14 enabled by default (bug #83 broadened from 8). `detectBestRule(text:rules:)` samples the first `sampleSizeUTF16 = 512 * 1024` UTF-16 units and requires ≥2 matches; rules run with `NSRegularExpression` + `.anchorsMatchLines`.
- `vreader/Services/TXT/TXTTocRule.swift` — `struct TXTTocRule: Codable, Sendable, Identifiable` (id, enabled, name, rule, example, serialNumber).
- `vreader/Services/TXT/TXTChapterIndex.swift` — `TXTChapter` (startByte/endByte plus `globalStartUTF16`/`textLengthUTF16`, -1 until populated) and `TXTChapterIndex`.
- `vreader/Services/TXT/TXTChapterIndexBuilder.swift` — legacy streaming builder: 512 KB blocks (`bufferSize = 512_000`, Legado's pattern), walk-back-to-`0x0A` block boundaries, BOM skip, synthetic ~50 KB chapters (`syntheticChapterSize = 50_000`).
- `vreader/Services/TXT/TXTChapterContentLoader.swift` — `actor TXTChapterContentLoader`: lazy one-time full decode, slices chapters by UTF-16 range, 3-entry proximity cache (`maxCacheSize = 3`; on insertion evicts the cached chapter numerically farthest from the requested index — no access-recency tracking, so it is not LRU), `preloadAdjacent`, and `fullDecodedText()` (bug #180 continuous surface).
- `vreader/Services/TXT/TXTChapterIndexStore.swift` — JSON cache at `{cacheDir}/chapter-index.json` keyed by file byte count + modification time; `load` returns nil on any miss/stale/corrupt.
- `vreader/Services/TXT/TXTFileLoader.swift` — `TXTFileLoader.load` / `loadChapterBased`: open + saved-position restore; prefers the `"txtchapter:{index}:{localOffset}"` locator href over global-offset binary search (GH #30).
- `vreader/Services/TXT/TXTOffsetTranslator.swift` — global UTF-16 ↔ chapter-local translation, O(log n) `chapterContaining`, `populateUTF16Offsets`.
- `vreader/Services/TXT/TXTChapterOffsetIndex.swift` — bug #180: derives `currentChapterIdx` from a document-global offset on the continuous-scroll surface (`chapterContaining`, `chapterLocalFraction`).
- `vreader/Services/TXT/TXTOffsetMapper.swift` — NSRange ↔ UTF-16 validation, `snapToValidBoundary` (surrogate-pair snap-backward), TextKit scroll↔offset mapping (`ensureLayout` before `lineFragmentRect` — bug #102 follow-up), `scrollOffsetForVisibleMatch` with 0.25 headroom fraction (bug #153).
- `vreader/Services/TXT/TXTTextChunker.swift` — splits text into ~16384-UTF-16 chunks at newline boundaries (hard-split for longer lines); joined chunks equal the input exactly.
- `vreader/Services/TXT/TXTContinuousChunkBuilder.swift` — bug #180: `build(fullText:)` returns chunks + cumulative `chunkStartOffsets` (document-global UTF-16) for the continuous-scroll table.
- `vreader/Services/TXT/TXTChunkedLoader.swift` — `@MainActor final class TXTChunkedLoader`: 64 KB byte chunks (`defaultChunkSize = 64 * 1024`), UTF-8 boundary trailing-byte carry-over, viewport windowing, distance-based eviction.
- `vreader/Services/TXT/TXTAttributedStringBuilder.swift` + `TXTChapterStartDecorator.swift` — attributed-string construction off the main thread; feature #92 sets `paragraphStyle.alignment = .justified`; feature #68 WI-2 chapter-start typography (serif heading restyle + accent drop-cap) with the contract that only attributes are added — the backing string is byte-identical.
- `vreader/Services/TXT/ChapterProgressCalculator.swift` — `bookProgress = (chapterIdx + scrollFraction) / totalChapters`, next/previous chapter titles.
- `vreader/Services/TXT/TXTLazyTextProvider.swift` — `actor` concatenating all chapters on demand for AI/search/TTS; caches only successful loads.
- `vreader/Services/TXT/TXTReflowableTextSource.swift` — single-segment `ReflowableTextSource` adapter (empty text → zero segments).

## Rendering strategy and the 500K threshold

The dispatcher-level host is `TXTReaderHost` (see [[Architecture — reader dispatch and format hosts]]). `vreader/Views/Reader/TXTReaderContainerView.swift` declares `static let largeFileThreshold = 500_000` (UTF-16 code units): files above it use chunked `UITableView` rendering via `TXTChunkedReaderBridge` + `TXTTextChunker` to avoid TextKit 1 glyph-storage blowup; smaller files use `TXTTextViewBridge` (UITextView, TextKit 1). Chapter-based display renders only the current chapter. Paged mode uses `NativeTextPageNavigator`/`NativeTextPaginator` (`vreader/Views/Reader/NativeTextPaginator.swift`, TextKit 1 with one `NSTextContainer` per page), NOT the TextKit 2 spike paginator.

## Bridge and rendering helpers

- `vreader/Views/Reader/TXTBridgeShared.swift` + `TXTBridgeShared+SelectionMapping.swift` — functions shared by `TXTTextViewBridge` and `TXTChunkedReaderBridge` coordinators: the shared edit menu (Highlight/Add Note/Define/Translate), tap/gesture-delegate helpers, and selection-notification routing with bilingual display→source offset mapping (feature #56 WI-12b) and the bug #350 synthetic-start projection.
- `vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift` — `TXTTextViewBridge.Coordinator`: `UITextViewDelegate`/`UIGestureRecognizerDelegate` callbacks, scroll tracking, selection changes, and persisted-highlight application for the non-chunked path.
- `vreader/Views/Reader/TXTViewConfig.swift` — `TXTViewConfig`: font/color/spacing/inset appearance struct shared by TXT and MD text-view bridges, plus the bridge delegate protocol.
- `vreader/Views/Reader/TXTChapterHighlightHelper.swift` / `TXTChunkedHighlightHelper.swift` — pure global↔chapter-local highlight-range translation (chapter mode) and highlight application/clearing/chunk-local range computation (chunked mode).
- `vreader/Views/Reader/TXTChapterOverlayViews.swift` — chapter-title overlay shown at the top of the screen when chrome is visible (chapter-display mode).
- `vreader/Views/Reader/TXTChunkedScrollOffset.swift` — pure pixel→char mapping for the chunked reader's scroll-position save path (bug #289 Dynamic-Island content-inset fix).
- `vreader/Views/Reader/TXTPagedChapterAdvance.swift` — pure cross-chapter page-advance decision logic for paged mode (bug #284/GH #1261): boundary-page next/prev loads the adjacent chapter, document start/end clamps.
- `vreader/Views/Reader/TXTReaderContainerView+DebugBridgeHighlight.swift` — DEBUG-only observer creating a byte-identical TXT highlight from a `.debugBridgeHighlightCommand` notification (bug #237 verification harness), compiled out of Release.
- `vreader/Services/ReflowableTextSource.swift` — the `ReflowableTextSource` protocol + `TextSegment` (UTF-16-offset segments) consumed by TTS and the unified paginator; `TXTReflowableTextSource.swift` (§ above) is its TXT adapter.

## TextKit 2 spike conclusion

`vreader/Services/TextKit2Spike/SPIKE_RESULTS.md` (2026-03-16): decision "USE TextKit 2" — 14/14 tests passed including CJK boundary correctness (UAX #14 line breaking natively) and no-gaps/no-duplicates page coverage; 500 lines paginate in ~8 ms, 5000 CJK chars in ~22 ms (~2.7x slower than Latin). Known limitations recorded: paragraph-level fragment granularity, `@MainActor` requirement, memory (full attributed string held). `TextKit2Paginator.swift` (`paginate`/`paginateAttributed`, `TextKit2PageInfo` with UTF-16 `NSRange`) was promoted into the unified reflow engine (`vreader/ViewModels/UnifiedTextRendererViewModel.swift`, `vreader/Views/Reader/UnifiedPagedView.swift`), while the native TXT/MD paged path stayed on TextKit 1 to match the existing UITextView infrastructure.

## Encoding detection (CJK)

`decodeText` order: UTF-8 first; UTF-16 only with BOM; `NSString.stringEncoding(for:)` heuristic with a suggested-encodings list; manual fallbacks GBK (GB18030, covers GB2312), Big5, EUC-JP, Shift_JIS, EUC-KR, then Windows-1252 and ISO-8859-1 last (catch-alls that accept any bytes). `detectEncodingFromSample` analyzes the first `encodingSampleSize = 8192` bytes, walking back from the cut to avoid splitting multi-byte UTF-8/CJK sequences. `decodeForDisplayAndSearch` = sample hint then `decodeText` fallback; also used by `vreader/Services/Search/TXTTextExtractor.swift` so display and search offsets agree.

## Chapter detection and cache

GH #30 (Legado strategy): decode the full file once, run the selected rule's regex over the whole `NSString`, record exact UTF-16 match offsets as chapter starts. A synthetic "前言" preamble chapter is inserted when the first match isn't at offset 0 (not emitted as a tappable TOC entry). Fewer than 2 chapters → synthetic ~50,000-UTF-16 chapters split at `"\n\n"`. The index is cached (`TXTChapterIndexStore`), rejected when byte count/mtime mismatch, when the first chapter's `startByte != 0` (old streaming-format cache; only `chapters.first?.startByte` is checked, not every chapter, despite an adjacent source comment describing an all-chapters check), or when the cached `detectedEncoding` differs from the fresh detection (bug #99 Codex round-1 audit fix).

## Concurrency

`TXTService` is an actor with an `_isOpening` reentrancy guard (audit fix); all heavy I/O + decode runs in `Task.detached` with `Data(contentsOf:options:.mappedIfSafe)`. `TXTChapterContentLoader` and `TXTLazyTextProvider` are actors. `TXTChunkedLoader` is `@MainActor` (UI-driven loading). `SendableAttributedString` is an `@unchecked Sendable` wrapper for cross-isolation transfer of immutable `NSAttributedString`s.

## Edge cases and invariants

- Empty file → empty chapter index, encoding "UTF-8", no throw.
- BOM handling: UTF-8 3-byte / UTF-16 2-byte BOM detection in `TXTChapterIndexBuilder.detectBOMLength`.
- Surrogate pairs: `TXTOffsetMapper.snapToValidBoundary` snaps mid-pair offsets backward; the drop-cap decorator reconstructs supplementary-plane scalars from surrogate pairs and skips CJK initials.
- Chunk joins are lossless: `TXTTextChunker.split` output joined equals the input; `TXTChunkedLoader` carries partial trailing UTF-8 bytes into the next chunk.
- Chapter-start typography never mutates characters — offset-based subsystems (positions, highlights, search, TTS) are unaffected by construction.
- Justified alignment (feature #92) adjusts intra-line spacing only; line breaks and character offsets are unchanged.

## History

GH #30 (full-text chapter strategy replacing byte-offset streaming caches); bug #99 (display/search decode divergence — unified decode entry point); bug #286 (TOC vs reader chapter misalignment on non-UTF-8 files); bug #83 (enabled TOC rules broadened 8 → 14); bug #180 (continuous-scroll re-scope — `TXTContinuousChunkBuilder`, `TXTChapterOffsetIndex`); bug #153 (search-tap scroll headroom); bug #102 follow-up (`ensureLayout` for deep chapters); bug #217 relates to the transform layer (see [[Module — text mapping]]); feature #68 WI-2 (chapter-start typography); feature #92 (justified CJK margins); feature #56 WI-12/WI-12b (bilingual display seams in the container view, see [[Module — bilingual translation]]); bugs #15/#17, #44, #154/GH #443, #284 are container-view fixes noted in `TXTReaderContainerView.swift` comments. See [[Timeline — bug history and recurring classes]].

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
**Verified.** 2026-07-11 — checked against: vreader/Services/TXT/TXTService.swift, vreader/Services/TXT/TXTServiceProtocol.swift, vreader/Services/TXT/TXTTocRuleEngine.swift, vreader/Services/TXT/TXTTocRule.swift, vreader/Services/TXT/TXTChapterIndex.swift, vreader/Services/TXT/TXTChapterIndexBuilder.swift, vreader/Services/TXT/TXTChapterContentLoader.swift, vreader/Services/TXT/TXTChapterIndexStore.swift, vreader/Services/TXT/TXTFileLoader.swift, vreader/Services/TXT/TXTOffsetTranslator.swift, vreader/Services/TXT/TXTChapterOffsetIndex.swift, vreader/Services/TXT/TXTOffsetMapper.swift, vreader/Services/TXT/TXTTextChunker.swift, vreader/Services/TXT/TXTContinuousChunkBuilder.swift, vreader/Services/TXT/TXTChunkedLoader.swift, vreader/Services/TXT/TXTAttributedStringBuilder.swift, vreader/Services/TXT/TXTChapterStartDecorator.swift, vreader/Services/TXT/ChapterProgressCalculator.swift, vreader/Services/TXT/TXTLazyTextProvider.swift, vreader/Services/TXT/TXTReflowableTextSource.swift, vreader/Services/ReflowableTextSource.swift, vreader/Services/ChapterStartTypography.swift, vreader/Services/TextKit2Spike/SPIKE_RESULTS.md, vreader/Services/TextKit2Spike/TextKit2Paginator.swift, vreader/ViewModels/UnifiedTextRendererViewModel.swift, vreader/Services/Search/TXTTextExtractor.swift, vreader/Views/Reader/TXTReaderContainerView.swift, vreader/Views/Reader/TXTReaderContainerView+Paged.swift, vreader/Views/Reader/TXTReaderContainerView+Bilingual.swift, vreader/Views/Reader/TXTReaderContainerView+DebugBridgeHighlight.swift, vreader/Views/Reader/TXTBridgeShared.swift, vreader/Views/Reader/TXTBridgeShared+SelectionMapping.swift, vreader/Views/Reader/TXTTextViewBridgeCoordinator.swift, vreader/Views/Reader/TXTViewConfig.swift, vreader/Views/Reader/TXTChapterHighlightHelper.swift, vreader/Views/Reader/TXTChapterOverlayViews.swift, vreader/Views/Reader/TXTChunkedHighlightHelper.swift, vreader/Views/Reader/TXTChunkedScrollOffset.swift, vreader/Views/Reader/TXTPagedChapterAdvance.swift, vreader/Views/Reader/NativeTextPaginator.swift, vreader/Views/Reader/NativeTextPageNavigator.swift, vreader/Views/Reader/TXTChunkedReaderBridge.swift, vreader/Views/Reader/TXTTextViewBridge.swift, vreader/Views/Reader/UnifiedPagedView.swift, vreader/Views/Reader/ReaderContainerView.swift, vreader/Views/Reader/ReaderFormatHosts.swift, docs/bugs.md, docs/features.md, archive/bugs-history.md, dev-docs/plans/20260328-gh30-unified-chapter-system.md, dev-docs/plans/20260519-feature-56-bilingual-reading.md, canon/timeline/bug-history.md, canon/modules/locator.md, canon/architecture/reader-dispatch.md, canon/modules/text-mapping.md, canon/modules/bilingual-translation.md.
