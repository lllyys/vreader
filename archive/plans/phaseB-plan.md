# Phase B Implementation Plan (Retroactive + Forward)

**Date**: 2026-03-17
**Status**: 7/13 WIs DONE, 6 WIs remaining (FORWARD)
**Scope**: Reader core — dual-mode pagination, TTS, dictionary, TOC, animations

---

## RETROACTIVE (7 WIs Done)

### WI-B01: #23 TXT TOC Rules (Legado 25 Patterns)

**Files**: `vreader/Services/TXT/TXTTocRuleEngine.swift` (351 lines), `vreader/Services/TXT/TXTTocRule.swift` (model)
**Tests**: `vreaderTests/Services/TXT/TXTTocRuleEngineTests.swift` — 17 tests

**What was built**: 25 regex rules ported from Legado's txtTocRule.json. Auto-detection samples first 512KB UTF-16. Best rule = enabled rule with most matches (minimum 2). Extraction uses NSRegularExpression with `.anchorsMatchLines`. 8 rules enabled by default.

**Decisions**: UTF-16 offsets for TextKit compatibility. Rules ordered by serialNumber. CJK patterns first (primary audience).

### WI-B02: #33 Dictionary / Define / Translate-on-Select

**Files**: `vreader/Services/DictionaryLookup.swift` (57 lines)
**Tests**: `vreaderTests/Services/DictionaryLookupTests.swift` — 19 tests

**What was built**: System dictionary via `UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm:)`. Word extraction from selections. Menu title constants.

**Decisions**: First whitespace-delimited token extracted. Empty/whitespace-only returns nil. Enum namespace with static methods.

### WI-B03: #26 TTS Read Aloud (System AVSpeechSynthesizer)

**Files**: `vreader/Services/TTS/TTSService.swift` (173 lines), `vreader/Services/TTS/SpeechSynthesizing.swift` (protocol)
**Tests**: `vreaderTests/Services/TTSServiceTests.swift` — 35 tests

**What was built**: TTS service with idle/speaking/paused state machine. Position tracking via UTF-16 offsets. Rate clamped 0.0-1.0. SpeechSynthesizing protocol for test injection. Text extraction from ReflowableTextSource.

**Decisions**: @MainActor @Observable for SwiftUI binding. Empty/whitespace text is no-op. Negative offsets clamped to 0. Delegate pattern for position tracking.

### WI-B06: #21 Native EPUB Paged Layout (CSS Columns)

**Files**: `vreader/Views/Reader/EPUBPaginationHelper.swift` (166 lines)
**Tests**: `vreaderTests/Views/Reader/EPUBPaginationTests.swift` — 26 tests

**What was built**: CSS multi-column pagination helper. Generates CSS, JS for page navigation, page count computation, CSS injection/removal. Pure calculations for totalPages and pageFromScrollOffset.

**Decisions**: CSS column-width + column-gap + overflow:hidden. Navigation via scrollLeft. Integer pixel values. Zero/negative viewport returns safe fallbacks.

### WI-B08: #21 Native TXT/MD Paged Layout (TextKit)

**Files**: `vreader/Views/Reader/NativeTextPaginator.swift` (153 lines)
**Tests**: `vreaderTests/Views/Reader/NativeTextPaginatorTests.swift` — 23 tests

**What was built**: TextKit 1 paginator using NSLayoutManager + multiple NSTextContainers. Two entry points: plain text and attributed string. Page lookup by UTF-16 offset.

**Decisions**: @MainActor. TextKit 1 to match existing UITextView infra. Speculatively adds containers until all glyphs laid out. NSRange (UTF-16) for UIKit compatibility.

### WI-B09: #21 Native PDF Page Navigation

**Files**: `vreader/Views/Reader/PDFPageNavigator.swift` (37 lines)
**Tests**: `vreaderTests/Views/Reader/PDFPageNavigatorTests.swift` — 26 tests

**What was built**: PDF-specific BasePageNavigator subclass. `syncCurrentPage(_:)` method for PDFView notification sync. Does NOT hold PDFView reference — caller bridges navigation.

**Decisions**: Decoupled from PDFKit for testability. Two paths: user-initiated (nextPage/previousPage) and PDFView-reported (syncCurrentPage).

### WI-B12: #21 EPUB Complexity Classifier

**Files**: `vreader/Services/EPUB/EPUBComplexityClassifier.swift` (93 lines)
**Tests**: `vreaderTests/Services/EPUB/EPUBComplexityClassifierTests.swift` — 31 tests

**What was built**: String-based HTML scanner for complex layout indicators (table, math, svg, iframe, canvas, video, audio, CSS grid/table/fixed/absolute, viewport meta). Per-chapter classification with book-level rollup. Pre-compiled regex patterns.

**Decisions**: Conservative — uncertain = complex. No DOM parsing needed. Case-insensitive matching.

---

## FORWARD (6 WIs Remaining)

### WI-B04: #21 Unified TXT Reflow Engine (Scroll + Pagination)

**Problem**: The TextKit2Paginator from F08 spike and UnifiedTextRendererViewModel exist but the engine needs hardening for production: font/theme changes, viewport resize, large files, CJK, progress persistence, mode switching.

**Files to create/modify**:
- Modify: `vreader/Services/TextKit2Spike/TextKit2Paginator.swift` — move to `vreader/Services/Unified/` and harden
- Modify: `vreader/ViewModels/UnifiedTextRendererViewModel.swift` — wire to ReaderLifecycleCoordinator
- Modify: `vreader/Views/Reader/UnifiedTextRenderer.swift` — integrate tap zones, progress bar
- Modify: `vreader/Views/Reader/UnifiedPagedView.swift` — polish page rendering
- Modify: `vreader/Views/Reader/UnifiedScrollView.swift` — scroll progress tracking
- Create: `vreader/Services/Unified/UnifiedTXTPageNavigator.swift` — BasePageNavigator subclass

**Tests FIRST**:
- `testPaginateEmpty_returnsZeroPages`
- `testPaginateSingleLine_returnsOnePage`
- `testPaginateMultiPage_correctPageCount`
- `testPaginate15MBCJK_completesUnder5Seconds`
- `testRepaginateOnFontChange_preservesApproximatePosition`
- `testRepaginateOnViewportResize_recalculatesPages`
- `testPageNavigator_nextPrev_clampsCorrectly`
- `testScrollProgress_tracksUTF16Offset`
- `testModeSwitch_scrollToPaged_preservesProgress`
- `testModeSwitch_pagedToScroll_preservesProgress`
- `testCurrentPageText_returnsCorrectSlice`
- `testEmptyText_noOp`

**Implementation approach**:
1. Move TextKit2Paginator out of spike directory into `Services/Unified/`
2. Create UnifiedTXTPageNavigator subclass of BasePageNavigator
3. Wire ViewModel to use PageNavigator protocol
4. Add tap zone support (observe .readerNextPage/.readerPreviousPage)
5. Add progress persistence via LocatorFactory
6. Add font/theme/viewport change re-pagination with position preservation

**Edge cases**: 15MB CJK files, emoji, mixed scripts, zero-height viewport, rapid font changes, empty files.

**Acceptance criteria**: TXT files render in both scroll and paged mode under Unified engine. Page turns work via tap zones and swipe. Progress persists. Font/theme changes re-paginate. 15MB CJK file paginates in <5s.

**Dependencies**: WI-F03 (ReflowableTextSource), WI-F07 (ReadingMode), WI-F08 (TextKit 2 spike), WI-F11 (PageNavigator) — all done.

**Effort**: L

---

### WI-B05: #21 Unified MD Reflow (Scroll + Pagination)

**Problem**: MD files need to flow through the same unified engine as TXT, but fed as attributed text (NSAttributedString from the existing MD renderer).

**Files to create/modify**:
- Create: `vreader/Services/Unified/UnifiedMDPageNavigator.swift`
- Modify: `vreader/ViewModels/UnifiedTextRendererViewModel.swift` — add attributed text path
- Modify: `vreader/Services/TextKit2Spike/TextKit2Paginator.swift` — add `paginateAttributed()` method
- Modify: `vreader/Views/Reader/MDReaderContainerView.swift` — dispatch to Unified when mode=unified

**Tests FIRST**:
- `testPaginateAttributedText_correctPageCount`
- `testMDHeadings_preserveFormatting_perPage`
- `testMDListItems_wrapCorrectly`
- `testMDCodeBlocks_dontSplitMidLine`
- `testEmptyMDFile_zeroPages`
- `testMDWithEmoji_correctPagination`
- `testProgressPersistence_MDUnified`

**Implementation approach**:
1. Add `paginateAttributed(attributedText:viewportSize:)` to TextKit2Paginator (mirroring NativeTextPaginator's dual entry point pattern)
2. MDReaderContainerView checks ReadingMode: if `.unified`, pass rendered NSAttributedString to UnifiedTextRenderer
3. UnifiedTextRendererViewModel accepts either plain text (TXT) or attributed text (MD)

**Edge cases**: MD with inline images (should fall back or skip), very long single paragraphs, code blocks with long lines.

**Acceptance criteria**: MD files render in Unified mode with correct formatting. TOC headings preserved. Pagination matches Native mode page count within +/-10%.

**Dependencies**: WI-B04 (Unified TXT engine must be working first).

**Effort**: M

---

### WI-B07: #21 Unified EPUB Simple Chapters

**Problem**: Simple EPUB chapters (no tables, SVG, math) should render in the Unified reflow engine by stripping HTML to attributed text.

**Files to create/modify**:
- Create: `vreader/Services/EPUB/EPUBTextExtractor.swift` — HTML to NSAttributedString converter
- Create: `vreaderTests/Services/EPUB/EPUBTextExtractorTests.swift`
- Modify: `vreader/Views/Reader/EPUBReaderContainerView.swift` — dispatch simple chapters to Unified
- Modify: `vreader/Services/EPUB/EPUBComplexityClassifier.swift` — per-chapter routing

**Tests FIRST**:
- `testExtractSimpleHTML_preservesParagraphs`
- `testExtractBoldItalic_preservesStyling`
- `testExtractHeadings_preservesLevels`
- `testExtractLinks_preservesText`
- `testExtractImages_insertsPlaceholder`
- `testComplexHTML_routesToNative`
- `testMixedBook_simpleChaptersUseUnified`
- `testEmptyChapter_producesEmptyText`
- `testCJKContent_correctExtraction`

**Implementation approach**:
1. Build EPUBTextExtractor using NSAttributedString(data:options:documentAttributes:) with `[.documentType: NSAttributedString.DocumentType.html]`
2. EPUBComplexityClassifier already provides per-chapter classification
3. EPUBReaderContainerView checks classifier: simple chapters route to UnifiedTextRenderer, complex stay in WKWebView
4. Chapter transitions handled by the existing PageNavigator protocol

**Edge cases**: Chapters with CSS class references but no complex layout (still simple), chapters mixing simple and complex elements, charset encoding issues.

**Acceptance criteria**: Simple EPUB chapters render identically in Unified and Native modes (text content, not layout). Complex chapters stay in WKWebView. User can switch engines mid-book.

**Dependencies**: WI-B04 (Unified engine), WI-B12 (classifier) — B12 done.

**Effort**: L

---

### WI-B10: #31 Auto Page Turning

**Problem**: Users want hands-free reading with timed automatic page advancement.

**Files to create/modify**:
- Create: `vreader/Services/AutoPageTurner.swift`
- Create: `vreaderTests/Services/AutoPageTurnerTests.swift`
- Modify: `vreader/Views/Reader/ReaderSettingsPanel.swift` — add auto-turn toggle + interval slider

**Tests FIRST**:
- `testAutoTurn_callsNextPage_afterInterval`
- `testAutoTurn_stopsAtLastPage`
- `testAutoTurn_pauseResume`
- `testAutoTurn_stopOnUserInteraction`
- `testAutoTurn_adjustInterval_immediateEffect`
- `testAutoTurn_doesNotStartWhenAtLastPage`
- `testAutoTurn_zeroInterval_clampedToMinimum`
- `testAutoTurn_negativeInterval_clampedToMinimum`
- `testAutoTurn_defaultInterval_5Seconds`
- `testAutoTurn_stateTransitions_idle_running_paused`

**Implementation approach**:
1. AutoPageTurner class with Timer-based page advancement
2. Accepts any PageNavigator via protocol — format-agnostic
3. State machine: idle -> running -> paused -> idle
4. Minimum interval 1 second, default 5 seconds
5. Pauses on user scroll/tap, resumes automatically or via button
6. Shows subtle indicator (progress ring) in status bar area

**Edge cases**: App backgrounding (pause), low battery mode, very short pages, user swipes during auto-turn, screen lock.

**Acceptance criteria**: Auto page turning works in all paged modes (Native and Unified). Interval adjustable 1-60 seconds. Stops at end of book. Pauses on user interaction.

**Dependencies**: WI-F11 (PageNavigator) — done.

**Effort**: S

---

### WI-B11: #21 Page Turn Animations

**Problem**: Paged reading needs visual page-turn feedback: none (instant), slide, cover (page peel).

**Files to create/modify**:
- Create: `vreader/Views/Reader/PageTurnAnimator.swift` — shared animation delegate
- Create: `vreaderTests/Views/Reader/PageTurnAnimatorTests.swift`
- Modify: `vreader/Views/Reader/UnifiedPagedView.swift` — apply animations
- Modify: `vreader/Views/Reader/ReaderSettingsPanel.swift` — animation picker

**Tests FIRST**:
- `testAnimationNone_immediateTransition`
- `testAnimationSlide_leftToRight_previousPage`
- `testAnimationSlide_rightToLeft_nextPage`
- `testAnimationCover_nextPage_coversFromRight`
- `testAnimationCover_previousPage_uncoversFromLeft`
- `testRapidPageTurns_cancelsPreviousAnimation`
- `testAnimationDuration_default300ms`
- `testAnimationDuration_respectsReduceMotion`
- `testAnimationType_codableRoundTrip`

**Implementation approach**:
1. `PageTurnAnimation` enum: `.none`, `.slide`, `.cover`
2. `PageTurnAnimator` renders transition between two page snapshots (UIView.transition or CAAnimation)
3. For `.slide`: translate X by viewport width
4. For `.cover`: 3D transform with shadow (like iBooks)
5. `.none`: instant swap
6. Respects UIAccessibility.isReduceMotionEnabled — forces `.none`
7. Stored in ReaderSettingsStore

**Edge cases**: Reduce motion accessibility, rapid multi-tap, animation during resize, concurrent font change.

**Acceptance criteria**: Three animation types work in Unified paged mode. Animations cancel cleanly on rapid taps. Reduce motion disables animations. No frame drops on iPhone 12+.

**Dependencies**: WI-B04 (Unified TXT paged), WI-B09 (PDF paged) — both done.

**Effort**: M

---

### WI-B13: #21 Pagination Cache Invalidation

**Problem**: Pagination results must be recomputed when font size, font family, theme, line spacing, or viewport dimensions change.

**Files to create/modify**:
- Create: `vreader/Services/Unified/PaginationCache.swift`
- Create: `vreaderTests/Services/Unified/PaginationCacheTests.swift`
- Modify: `vreader/ViewModels/UnifiedTextRendererViewModel.swift` — wire cache invalidation
- Modify: `vreader/Views/Reader/NativeTextPaginator.swift` — add cache key support

**Tests FIRST**:
- `testCacheKey_changeFont_invalidates`
- `testCacheKey_changeViewportWidth_invalidates`
- `testCacheKey_changeViewportHeight_invalidates`
- `testCacheKey_changeLineSpacing_invalidates`
- `testCacheKey_changeLetterSpacing_invalidates`
- `testCacheKey_changeTheme_doesNotInvalidate` (theme doesn't affect text layout)
- `testCacheKey_sameParams_hits`
- `testCacheKey_rotateDevice_invalidates`
- `testInvalidation_preservesApproximatePosition`
- `testInvalidation_emptiesOldPages_beforeRepagination`

**Implementation approach**:
1. PaginationCache stores pages keyed by `CacheKey(font, fontSize, lineSpacing, letterSpacing, viewportWidth, viewportHeight)`
2. On settings change, compute new key; if different, invalidate and re-paginate
3. During re-pagination, compute approximate position from old progress fraction
4. Cache is per-document (keyed additionally by document fingerprint)
5. Memory-only cache (no disk persistence needed — re-pagination is fast enough)

**Edge cases**: Rapid sequential font changes (debounce), device rotation during pagination, split-screen multitasking resize.

**Acceptance criteria**: Font/viewport changes trigger re-pagination within 500ms for normal files. Reading position preserved within +/-1 page. No stale page display.

**Dependencies**: WI-B04 (Unified TXT paginator), WI-B08 (Native TXT paginator) — both done.

**Effort**: M

---

## Sprint Plan

**Sprint B1** (parallel): B04 (Unified TXT engine) — L. Critical path.
**Sprint B2** (sequential after B1): B13 (cache invalidation) — M.
**Sprint B3** (parallel after B1): B05 (Unified MD) + B07 (Unified EPUB) — M + L.
**Sprint B4** (parallel, independent): B10 (auto page) + B11 (animations) — S + M.

## Checkpoint Criteria

- All 13 WIs complete (7 retroactive + 6 new)
- TXT/MD/simple EPUB support scroll + paged in both Native and Unified
- PDF paged via PDFKit tap zones
- TTS works for TXT/MD
- Dictionary lookup works
- EPUB classifier routes to correct engine
- Page turn animations (none/slide/cover) work
- Auto page turning with configurable interval
- All existing tests still pass

## Manual Testing

See `docs/manual-test-checklist.md` for phase-specific test items.
