// Purpose: SwiftUI container for the TXT reader. Composes the TXTTextViewBridge
// (small files) or TXTChunkedReaderBridge (large files) with loading/error overlays.
// Supports chapter-based display when a TXTChapterIndex is available (WI-6).
//
// Key decisions:
// - Owns TXTReaderViewModel lifecycle (open on appear, close on disappear).
// - Delegates scroll/selection events from bridge to ViewModel.
// - Shows loading spinner during file open.
// - Shows error message on failure.
// - Passes theme config to bridge (font size, line spacing).
// - Builds NSAttributedString on a background thread to avoid blocking the main
//   thread for large files. The bridge receives the pre-built attributed string.
// - Files over `largeFileThreshold` UTF-16 code units use chunked rendering
//   (UITableView) to avoid TextKit 1 glyph storage blowup.
// - Chapter-based display: when currentChapterText is available, displays just
//   the current chapter via TXTTextViewBridge (fast — chapter is ~5-50KB).
//   Falls back to full-text path when no chapter index is available.
// - Book-level progress shown in bottom overlay using ChapterProgressCalculator.
//
// @coordinates-with: TXTReaderViewModel.swift, TXTTextViewBridge.swift,
//   TXTChunkedReaderBridge.swift, TXTTextChunker.swift, TXTAttributedStringBuilder.swift,
//   ChapterProgressCalculator.swift, TXTChapterIndex.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

/// Container view for the TXT reader screen.
struct TXTReaderContainerView: View {
    let fileURL: URL
    let viewModel: TXTReaderViewModel
    var settingsStore: ReaderSettingsStore?
    var modelContainer: ModelContainer?
    var ttsService: TTSService?
    /// TOC entries from regex detection — used for chapter progress in legacy mode (bug #31).
    var tocEntries: [TOCEntry] = []

    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors ReaderContainerView's chrome toggle so the bottom overlay hides with the nav bar.
    @State private var isChromeVisible = true

    /// Files with more UTF-16 code units than this use chunked rendering.
    static let largeFileThreshold = 500_000

    /// Pre-built attributed string for small files, constructed off the main thread.
    @State private var preparedAttrString: NSAttributedString?
    /// True while the attributed string is being built for the first time.
    /// Subsequent rebuilds (e.g., settings changes) keep old content visible.
    @State private var isBuildingInitialAttrString = false
    /// Pre-split chunks for large files.
    @State private var textChunks: [String]?
    /// Cumulative UTF-16 start offsets per chunk.
    @State private var chunkStartOffsets: [Int]?
    /// Captured scroll position for one-shot restore. Set once after file opens.
    /// Using @State breaks the observation cycle that caused bug #15/#17:
    /// reading viewModel.currentOffsetUTF16 in body created a feedback loop.
    @State private var initialRestoreOffset: Int?
    /// Navigation target from search results. Updated via notification.
    @State private var scrollToOffset: Int?
    // Bug #154 / GH #443: previously declared local @State `highlightRange` and
    // `highlightIsTemporary` were orphans — `ReaderNotificationModifier`'s
    // `.readerNavigateToLocator` handler writes `uiState.highlightRange` /
    // `uiState.highlightIsTemporary` (TextReaderUIState), so the bridge
    // wiring below reads from `uiState` directly. MDReaderContainerView was
    // already correctly wired; only TXT regressed.
    /// Pending annotation info for the "Add Note" flow (bug #44).
    @State private var pendingAnnotationInfo: TextSelectionInfo?
    /// Text input for the annotation note.
    @State private var annotationNoteText: String = ""

    /// Pre-built attributed string for chapter-based display (WI-6).
    @State private var chapterAttrString: NSAttributedString?
    @State private var chapterScrollFraction: Double = 0

    // MARK: - Shared UI State (Phase R3) + Highlight Coordination (Phase R4)
    @State var uiState = TextReaderUIState()
    @State var highlightRenderer: TextHighlightRenderer?
    @State var highlightCoordinator: HighlightCoordinator?
    @State var ttsHighlightCoordinator: TTSHighlightCoordinator?

    // MARK: - Feature #56 WI-12: bilingual reading state
    //
    // Owned here so SwiftUI's lifecycle frees the VM on container
    // teardown. The actual wiring (lazy init, setup-sheet, More-menu
    // observer) lives in `TXTReaderContainerView+Bilingual.swift`.
    @State var bilingualViewModel: BilingualReadingViewModel?
    @State var showBilingualSetupSheet: Bool = false
    @State var bilingualSetupState: BilingualSetupSheetState = .defaultValue

    /// Feature #56 WI-12b: the current chapter's bilingual display segment
    /// map. Identity when bilingual is off (the rendered string IS the
    /// source string); a non-identity interleaved map when bilingual is on
    /// and the current unit has cached translations. Every TXT display-
    /// offset touchpoint (highlight ranges, scroll-to-offset, selection)
    /// routes through this map via `BilingualOffsetRouter`. Defaults to
    /// identity-zero so an off-mode container still has a well-defined
    /// map for routing.
    @State var bilingualSegmentMap: BilingualDisplaySegmentMap =
        BilingualDisplaySegmentMap.identity(sourceLength: 0)

    /// Feature #56 WI-12b: holds the delegate adapter (when bilingual is
    /// on with a non-identity segment map) that maps display offsets the
    /// bridge reports back to source offsets before forwarding to the
    /// VM. Held here so its lifetime tracks the bridge's; recreated when
    /// `bilingualSegmentMap` changes. `nil` (and the VM is used
    /// directly) when bilingual is effectively off — preserves the
    /// byte-identical pass-through.
    @State var bilingualBridgeDelegate: BilingualTXTBridgeDelegateAdapter?

    /// Whether the loaded text exceeds the large file threshold.
    private var isLargeFile: Bool {
        viewModel.totalTextLengthUTF16 > Self.largeFileThreshold
    }

    /// Whether the ViewModel has chapter-based display data available.
    private var hasChapterDisplay: Bool {
        viewModel.chapterIndex != nil && viewModel.currentChapterText != nil
    }

    /// Whether the ViewModel is rendering chaptered TXT as one continuous
    /// scrollable surface (Bug #180 re-scoped fix). Drives the `body` branch.
    private var isContinuousChaptered: Bool {
        viewModel.isContinuousMode
            && viewModel.continuousChunks != nil
            && viewModel.continuousChunkStartOffsets != nil
    }

    /// Decides whether a chaptered TXT file opens as one continuous scroll
    /// surface (Bug #180) or the legacy single-chapter Paged path.
    /// Scroll layout (and the no-settings default) → continuous.
    static func shouldOpenContinuous(epubLayout: EPUBLayoutPreference?) -> Bool {
        epubLayout != .paged
    }

    /// Composite key that triggers attributed string rebuild when text or config changes.
    /// Uses totalTextLengthUTF16 + totalWordCount (O(1)) instead of text.hashValue (O(n)).
    /// Includes theme colors so theme changes trigger rebuild (bug #29).
    /// Includes currentChapterIdx so chapter navigation triggers rebuild (WI-6).
    /// Includes chineseConversion so conversion changes trigger rebuild (feature #28 WI-A).
    /// Feature #56 WI-12b: includes bilingual on/off + the current unit's
    /// translation-count nonce so a bilingual toggle or fresh translation
    /// landing fires a rebuild of the chapter attrString.
    private var attrStringKey: String {
        let cfg = settingsStore?.txtViewConfig ?? TXTViewConfig()
        return Self.makeAttrStringKey(
            hasText: viewModel.textContent != nil,
            textLen: viewModel.totalTextLengthUTF16,
            wordCount: viewModel.totalWordCount,
            chIdx: viewModel.currentChapterIdx,
            chCount: viewModel.totalChapterCount,
            config: cfg,
            chineseConversion: settingsStore?.chineseConversion ?? .none,
            headingLineLength: viewModel.currentChapterHeadingLineLength,
            bilingualNonce: bilingualNonce
        )
    }

    /// Feature #56 WI-12b: a string that changes when bilingual on/off
    /// flips or the current unit's translation count changes. Drives the
    /// `attrStringKey` rebuild so the chapter attrString re-renders the
    /// moment a prefetch lands.
    private var bilingualNonce: String {
        guard let vm = bilingualViewModel, vm.isEnabled else { return "off" }
        // Look up the unit by current chapter index — matches the TXT
        // adapter's identity.
        let unitValue = String(viewModel.currentChapterIdx)
        let unit = TranslationUnitID(kind: .txtChapterIndex, value: unitValue)
        let count = vm.translations(for: unit)?.count ?? 0
        return "on-\(unitValue)-\(count)"
    }

    /// Extracted for testability (feature #28 WI-A). Internal so
    /// `TXTReaderContainerViewChineseConversionTests` can call directly.
    ///
    /// Feature #68: `config.accentColor` / `config.chapterHeadingColor`
    /// are hashed in so a theme switch that changes only those re-fires
    /// the `.task(id:)` and rebuilds the chapter (live theme switching).
    /// `headingLineLength` is included so two chapters that share an
    /// index value across a re-open still rebuild.
    internal static func makeAttrStringKey(
        hasText: Bool,
        textLen: Int,
        wordCount: Int,
        chIdx: Int,
        chCount: Int,
        config: TXTViewConfig,
        chineseConversion: ChineseConversionDirection,
        headingLineLength: Int = 0,
        bilingualNonce: String = "off"
    ) -> String {
        let textColorHash = config.textColor.hash
        let bgColorHash = config.backgroundColor.hash
        let accentColorHash = config.accentColor.hash
        let headingColorHash = config.chapterHeadingColor.hash
        return "\(hasText)-\(textLen)-\(wordCount)-ch\(chIdx)/\(chCount)-\(config.fontSize)-\(config.fontName ?? "sys")-\(config.lineSpacing)-\(config.letterSpacing)-\(textColorHash)-\(bgColorHash)-\(accentColorHash)-\(headingColorHash)-hl\(headingLineLength)-\(chineseConversion.rawValue)-bi\(bilingualNonce)"
    }

    var body: some View {
        ZStack {
            // Bug #209 / GH #804: scope the `txtReaderContainer`
            // identifier to the content subtree. A container
            // `.accessibilityIdentifier` propagates onto every descendant
            // accessibility element; applied to the whole `body` ZStack it
            // also clobbered `ReaderBottomChrome`'s toolbar buttons
            // (`readerDisplayButton` / `readerNotesButton`) so XCUITest
            // could not resolve them. Scoped here it still propagates onto
            // the inner UITextView — the TXT highlight/position tests look
            // the content view up by `txtReaderContainer` — without
            // reaching the bottom chrome, a separate ZStack sibling.
            Group {
                if viewModel.isLoading || isBuildingInitialAttrString {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage,
                          viewModel.textContent == nil && viewModel.currentChapterText == nil {
                    errorView(message: errorMessage)
                } else if isContinuousChaptered,
                          let chunks = viewModel.continuousChunks,
                          let offsets = viewModel.continuousChunkStartOffsets {
                    // Bug #180: chaptered TXT in Scroll layout renders as one
                    // continuous scrollable surface (the chunked UITableView
                    // fed the whole book). Chapter awareness is layered via
                    // TXTChapterOffsetIndex; chapter boundaries are invisible
                    // in the scroll flow.
                    continuousChapteredReaderContent(chunks: chunks, offsets: offsets)
                } else if let chapterText = viewModel.currentChapterText,
                          let attrStr = chapterAttrString {
                    // Chapter-based display (WI-6) — Paged single-chapter path.
                    chapterReaderContent(text: chapterText, attributedText: attrStr)
                } else if viewModel.currentChapterText != nil {
                    // Chapter text available but attributed string still building
                    loadingView
                } else if viewModel.textContent != nil && isLargeFile {
                    // Legacy: large file → chunked renderer (fallback when no chapter index)
                    if let chunks = textChunks, let offsets = chunkStartOffsets {
                        chunkedReaderContent(chunks: chunks, offsets: offsets)
                    } else {
                        loadingView
                    }
                } else if let text = viewModel.textContent, let attrStr = preparedAttrString {
                    // Legacy: small file → single UITextView (fallback when no chapter index)
                    readerContent(text: text, attributedText: attrStr)
                } else if viewModel.textContent != nil {
                    loadingView
                } else {
                    Color.clear
                }
            }
            .accessibilityIdentifier("txtReaderContainer")
            .accessibilityValue(readerAccessibilityValue)

            // Top overlay: chapter title (WI-6)
            if hasChapterDisplay && isChromeVisible,
               let title = viewModel.currentChapterTitle, !title.isEmpty {
                VStack {
                    ChapterTitleOverlay(title: title, settingsStore: settingsStore)
                    Spacer()
                }
            }

            // Bottom overlay for session time, progress, and scrubber (bug #33, WI-004b)
            // Show when either full text or chapter text is loaded.
            // Hidden when TTS is active to avoid overlap (bug #97)
            if (viewModel.textContent != nil || viewModel.currentChapterText != nil)
                && !viewModel.isLoading && isChromeVisible
                && (ttsService?.state ?? .idle) == .idle {
                // Feature #60 WI-6b: shared bottom chrome (scrubber +
                // labels + Contents/Notes/Display/AI toolbar) replaces
                // the legacy ReadingProgressBar + ChapterBottomOverlay /
                // ReaderBottomOverlay. Chapter prev/next relocates to
                // the Contents (TOC) toolbar button per the v2 design;
                // chapter position is surfaced in the leading label.
                if hasChapterDisplay {
                    ReaderBottomChrome(
                        theme: settingsStore?.theme ?? .paper,
                        progress: $chapterScrollFraction,
                        onSeek: { seekValue in
                            guard let chapters = viewModel.chapterIndex?.chapters,
                                  viewModel.currentChapterIdx < chapters.count else { return }
                            let chapter = chapters[viewModel.currentChapterIdx]
                            uiState.scrollToOffset = Self.chapterScrubberGlobalOffset(
                                seekValue: seekValue, chapter: chapter
                            )
                        },
                        leadingLabel: "Chapter \(viewModel.currentChapterIdx + 1)"
                            + " of \(viewModel.totalChapterCount)",
                        trailingLabel: viewModel.sessionTimeDisplay ?? ""
                    )
                } else {
                    ReaderBottomChrome(
                        theme: settingsStore?.theme ?? .paper,
                        progress: $chapterScrollFraction,
                        onSeek: { seekValue in
                            // If TOC entries exist, seek within current chapter
                            if tocChapterProgress != nil {
                                let chapterLen = tocChapterLength
                                let localTarget = Int(seekValue * Double(chapterLen))
                                let globalTarget = tocChapterStartOffset + localTarget
                                uiState.scrollToOffset = globalTarget
                            } else {
                                let charOffset = ScrollProgressHelper.charOffsetFromProgress(
                                    progress: seekValue,
                                    totalLengthUTF16: viewModel.totalTextLengthUTF16
                                )
                                uiState.scrollToOffset = charOffset
                            }
                        },
                        leadingLabel: ScrollProgressHelper.percentageLabel(chapterScrollFraction),
                        trailingLabel: viewModel.sessionTimeDisplay ?? ""
                    )
                }
            }
        }
        // Feature #60 WI-7c2: present `SelectionPopoverView` (WI-7a)
        // when a long-press selection finishes. The TXT non-chunked
        // bridge (TXTTextViewBridgeCoordinator) posts
        // `.readerSelectionPopoverRequested` from
        // `editMenuForTextIn`; this modifier observes the
        // notification and shows the sheet. Theme is the store's
        // `ReaderThemeV2` (WI-11 migrated the type); falls back to
        // `.paper` when no settings store is wired (preview / tests).
        // WI-7c3..7c5 attach the same modifier to the chunked TXT /
        // MD / EPUB containers.
        .selectionPopoverPresenter(theme: settingsStore?.theme ?? .paper)
        // Feature #64 WI-6: a tap on a highlight opens the unified
        // highlight-action popover (color / note / copy / share / delete) —
        // superseding feature #55's note preview and feature #53's long-press
        // delete `UIMenu`. `mutating` is the TXT `HighlightCoordinator`.
        .unifiedHighlightPopoverPresenterIfAvailable(
            modelContainer: modelContainer,
            bookFingerprintKey: viewModel.bookFingerprintKey,
            mutating: highlightCoordinator,
            theme: settingsStore?.theme ?? .paper
        )
        // Feature #56 WI-12: bilingual reading wiring lives in a
        // separate extension to keep this file under the file-size
        // budget (rule 50 §9).
        .modifier(bilingualSurfacesModifier)
        // Bug #237 — DebugBridge highlight-driver observer. DEBUG-only;
        // attached inside the TXT host (not the generic ReaderContainerView)
        // so the helper can build TXT-shaped Locators via LocatorFactory
        // and re-paint atomically via HighlightCoordinator.create — the
        // gesture path's full posture. Audit Round-1 High #1 / #2 fix.
        .modifier(debugBridgeHighlightObserverModifier)
        .task {
            // Bug #258 / GH #1125: install the auto-page-turn position-persist
            // side-effect before pagination creates the turner, mirroring
            // MDReaderContainerView. (TXT shares `NativeTextPagedView` with MD;
            // `FormatCapabilities.autoPageTurn` is MD-only today, but wiring is
            // symmetric so a future TXT re-enable inherits a working sync.)
            uiState.onAutoAdvancePersist = { [weak viewModel] offset in
                guard let offset, let viewModel else { return }
                viewModel.updateScrollPosition(charOffsetUTF16: offset)
            }
            // PERF: open already called by TXTReaderHost — skip if content loaded
            if viewModel.textContent == nil && viewModel.currentChapterText == nil {
                // Bug #180: chaptered TXT in Scroll layout opens as one
                // continuous scrollable surface. Paged layout keeps the
                // legacy single-chapter open path.
                if Self.shouldOpenContinuous(epubLayout: settingsStore?.epubLayout) {
                    await viewModel.openContinuous(url: fileURL)
                } else {
                    await viewModel.openChapterBased(url: fileURL)
                }
            }
            // Bug #180: continuous mode restores via a document-global offset.
            // GH #30: chapter (Paged) mode captures LOCAL offset.
            if viewModel.isContinuousMode {
                initialRestoreOffset = viewModel.currentOffsetUTF16
            } else if viewModel.isChapterMode {
                initialRestoreOffset = viewModel.currentChapterLocalUTF16
            } else {
                initialRestoreOffset = viewModel.currentOffsetUTF16
            }
            // Bug #160: instantiate the renderer + HighlightCoordinator so
            // gesture-driven highlights actually reach the real PersistenceActor.
            // Mirrors MDReaderContainerView's pattern. Without this, the
            // .readerNotificationHandlers fallback (makeNoOpCoordinator with
            // NoOpHighlightStore) silently dropped every Highlight UIAction.
            let renderer = TextHighlightRenderer(uiState: uiState)
            highlightRenderer = renderer
            if let tts = ttsService, ttsHighlightCoordinator == nil {
                ttsHighlightCoordinator = TTSHighlightCoordinator(ttsService: tts, uiState: uiState)
            }
            // Wire coordinator + restore persisted highlights into uiState
            // (the renderer writes there; the bridge reads from there).
            if let container = modelContainer {
                let persistence = PersistenceActor(modelContainer: container)
                let coordinator = HighlightCoordinator(
                    renderer: renderer,
                    persistence: persistence,
                    bookFingerprintKey: viewModel.bookFingerprintKey
                )
                highlightCoordinator = coordinator
                await coordinator.restoreAll()
            }
        }
        .task(id: attrStringKey) {
            // Bug #180: in continuous mode the chunked UITableView builds
            // per-cell attributed strings lazily; no whole-document or
            // per-chapter NSAttributedString is built here.
            if viewModel.isContinuousMode {
                // Bug #1218: this IS the surface the bug targets (scroll-layout
                // chunked TXT). Surface the rendered chunk text to the
                // DebugBridge probe so CU-free XCUITest can read it. `joined()`
                // reconstructs exactly what the chunked UITableView renders.
                // Bug #1230 / GH #1230: Simp→Trad now IS applied in scroll mode
                // (per-chunk in the bridge), so post the CONVERTED joined text
                // — this is what the UITableView actually renders, and it
                // verifies Feature #28. The `attrStringKey` includes
                // `chineseConversion`, so this re-fires when conversion changes.
                #if DEBUG
                // Codex Gate-4 (Low): convert PER-CHUNK via the same helper the
                // bridge uses, so the probe matches the rendered cells exactly
                // (a single joined-then-converted string could differ from
                // per-chunk conversion at chunk boundaries) and the conversion
                // logic isn't duplicated.
                let conv = settingsStore?.chineseConversion ?? .none
                let rendered = (viewModel.continuousChunks ?? [])
                    .map { TXTChunkedReaderBridge.renderedChunkText($0, conversion: conv) }
                    .joined()
                postRenderedTextForDebug(rendered)
                #endif
                return
            }

            let config = settingsStore?.txtViewConfig ?? TXTViewConfig()
            let conversion = settingsStore?.chineseConversion ?? .none

            // Chapter-based path (WI-6): build attributed string for current chapter only.
            // Much smaller text → typically <50ms, often synchronous for small chapters.
            if let chapterText = viewModel.currentChapterText {
                let isInitial = chapterAttrString == nil
                if isInitial { isBuildingInitialAttrString = true }
                defer { if isInitial { isBuildingInitialAttrString = false } }

                // Feature #68: chapter-based rendering applies the design's
                // chapter-start typography (drop-cap + heading restyle).
                // `buildChapterStart` only adds attributes — the string is
                // byte-identical, so offsets stay valid. `headingLineLength`
                // is 0 for synthetic / "前言" chapters (drop-cap only).
                let headingLineLength = viewModel.currentChapterHeadingLineLength
                let typographedAttrString: NSAttributedString
                if chapterText.utf16.count < 10_000 {
                    // Small chapter (<10KB UTF-16): build synchronously.
                    // SimpTradTransform is 1:1 UTF-16 for BMP CJK chars; offsetMap discarded —
                    // reading positions and highlights in source-text coordinates remain valid.
                    let displayText = conversion != .none
                        ? TextMapper.apply(transforms: [SimpTradTransform(direction: conversion)], to: chapterText).text
                        : chapterText
                    typographedAttrString = TXTAttributedStringBuilder.buildChapterStart(
                        text: displayText, config: config,
                        headingLineLength: headingLineLength
                    )
                    #if DEBUG
                    postRenderedTextForDebug(displayText)
                    #endif
                } else {
                    // The detached closure returns the converted display text
                    // alongside the typography result so the bug #1218 debug
                    // post can run on the main actor after the cancel check
                    // (the post reads no detached state).
                    let result = await Task.detached(priority: .userInitiated) { () -> (wrapped: SendableAttributedString, displayText: String) in
                        let displayText = conversion != .none
                            ? TextMapper.apply(transforms: [SimpTradTransform(direction: conversion)], to: chapterText).text
                            : chapterText
                        let wrapped = TXTAttributedStringBuilder.buildChapterStartSendable(
                            text: displayText, config: config,
                            headingLineLength: headingLineLength
                        )
                        return (wrapped, displayText)
                    }.value
                    guard !Task.isCancelled else { return }
                    typographedAttrString = result.wrapped.value
                    #if DEBUG
                    postRenderedTextForDebug(result.displayText)
                    #endif
                }

                // Feature #56 WI-12b: when bilingual is on for this
                // chapter (the VM has cached translations for the unit),
                // interleave synthetic translation runs into the
                // typographed attrString. The composer preserves the
                // source-paragraph typography on each run; the resulting
                // segment map routes every TXT display-offset touchpoint
                // back to source via `BilingualOffsetRouter`. Off-mode is
                // a byte-identical identity pass-through (the renderer +
                // composer both short-circuit), so this branch is
                // transparent when bilingual is off.
                let unit = TranslationUnitID(
                    kind: .txtChapterIndex,
                    value: String(viewModel.currentChapterIdx)
                )
                let composed = BilingualDisplayPipeline.compose(
                    sourceAttributed: typographedAttrString,
                    unit: unit,
                    viewModel: bilingualViewModel
                )
                chapterAttrString = composed.attributedString
                bilingualSegmentMap = composed.segmentMap
                bilingualBridgeDelegate = Self.makeBilingualDelegateIfNeeded(
                    map: composed.segmentMap, wrapping: viewModel
                )
                return
            }

            // Legacy full-text path (no chapter index)
            guard let rawText = viewModel.textContent else { return }

            if rawText.utf16.count > Self.largeFileThreshold {
                // Large file: split into chunks (fast, no attributed string needed here)
                let isInitial = textChunks == nil
                if isInitial { isBuildingInitialAttrString = true }
                defer { if isInitial { isBuildingInitialAttrString = false } }

                let splitResult = await Task.detached(priority: .userInitiated) {
                    let text = conversion != .none
                        ? TextMapper.apply(transforms: [SimpTradTransform(direction: conversion)], to: rawText).text
                        : rawText
                    let chunks = TXTTextChunker.split(text: text, targetChunkSize: 16384)
                    var offsets: [Int] = []
                    offsets.reserveCapacity(chunks.count)
                    var cumulative = 0
                    for chunk in chunks {
                        offsets.append(cumulative)
                        cumulative += chunk.utf16.count
                    }
                    return (chunks, offsets)
                }.value
                guard !Task.isCancelled else { return }
                textChunks = splitResult.0
                chunkStartOffsets = splitResult.1
                // Bug #1218: legacy large-file chunked path (same flattened
                // UITableView surface). The chunks are already converted
                // (SimpTrad applied above), so joining them is the rendered text.
                #if DEBUG
                postRenderedTextForDebug(splitResult.0.joined())
                #endif
            } else {
                // Small file: build full attributed string
                let isInitial = preparedAttrString == nil
                if isInitial { isBuildingInitialAttrString = true }
                defer { if isInitial { isBuildingInitialAttrString = false } }

                let built = await Task.detached(priority: .userInitiated) { () -> (wrapped: SendableAttributedString, text: String) in
                    let text = conversion != .none
                        ? TextMapper.apply(transforms: [SimpTradTransform(direction: conversion)], to: rawText).text
                        : rawText
                    return (TXTAttributedStringBuilder.buildSendable(text: text, config: config), text)
                }.value
                guard !Task.isCancelled else { return }
                let wrapped = built.wrapped
                // Bug #1218: legacy small-file path (single UITextView). Post the
                // converted source text (before bilingual interleave) so the
                // txt-content probe surfaces the rendered content here too.
                #if DEBUG
                postRenderedTextForDebug(built.text)
                #endif
                // Feature #56 WI-12b: legacy small-file path. The
                // current-chapter unit is derived from the TXT VM's
                // chapter index; an absent index yields a nil unit and
                // the pipeline returns the identity pass-through.
                let unit: TranslationUnitID? = {
                    guard viewModel.chapterIndex != nil else { return nil }
                    return TranslationUnitID(
                        kind: .txtChapterIndex,
                        value: String(viewModel.currentChapterIdx)
                    )
                }()
                let composed = BilingualDisplayPipeline.compose(
                    sourceAttributed: wrapped.value,
                    unit: unit,
                    viewModel: bilingualViewModel
                )
                preparedAttrString = composed.attributedString
                bilingualSegmentMap = composed.segmentMap
                bilingualBridgeDelegate = Self.makeBilingualDelegateIfNeeded(
                    map: composed.segmentMap, wrapping: viewModel
                )
            }
        }
        .onDisappear {
            let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            Task {
                await viewModel.close()
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
        // Wire scroll progress to the ReadingProgressBar scrubber (bug #31).
        .onChange(of: viewModel.currentOffsetUTF16) { _, _ in
            updateChapterScrollFraction()
        }
        .onChange(of: viewModel.currentChapterIdx) { _, _ in
            updateChapterScrollFraction()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                Task {
                    await viewModel.onBackground()
                    if bgTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                    }
                }
            case .active:
                viewModel.onForeground()
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            // Bug #131: pause auto-page-turner on tap so the user has time
            // to read the chrome they just summoned, mirroring MDReaderContainerView.
            isChromeVisible.toggle()
            uiState.autoPageTurner?.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNextPage)) { _ in
            // Bug #131: manual page-turn pauses auto-turner so the user
            // doesn't get a second auto-turn one beat after their swipe.
            guard isPagedMode else { return }
            uiState.pageNavigator?.nextPage()
            if let offset = uiState.syncPagedState() {
                viewModel.updateScrollPosition(charOffsetUTF16: offset)
            }
            uiState.autoPageTurner?.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPreviousPage)) { _ in
            guard isPagedMode else { return }
            uiState.pageNavigator?.previousPage()
            if let offset = uiState.syncPagedState() {
                viewModel.updateScrollPosition(charOffsetUTF16: offset)
            }
            uiState.autoPageTurner?.pause()
        }
        .onChange(of: settingsStore?.autoPageTurn) { _, newValue in
            // Bug #131: live-apply the autoPageTurn toggle without requiring
            // the user to close + reopen the book.
            uiState.updateAutoPageTurner(
                enabled: newValue ?? false,
                isPagedMode: isPagedMode,
                interval: settingsStore?.autoPageTurnInterval ?? 5.0
            )
        }
        .onChange(of: settingsStore?.autoPageTurnInterval) { _, _ in
            // Bug #131: re-apply interval changes for an already-running turner.
            guard settingsStore?.autoPageTurn == true else { return }
            uiState.updateAutoPageTurner(
                enabled: true,
                isPagedMode: isPagedMode,
                interval: settingsStore?.autoPageTurnInterval ?? 5.0
            )
        }
        // Bug #132: wire TTS sentence highlight + auto-scroll. Coordinator
        // is instantiated in `.task` above; this observation drives its
        // entry point.
        .onChange(of: ttsService?.currentOffsetUTF16) { _, newOffset in
            guard let newOffset, let coordinator = ttsHighlightCoordinator else { return }
            if let text = viewModel.textContent {
                coordinator.ensureConfigured(text: text)
            }
            coordinator.updateHighlight(offset: newOffset)
        }
        .onChange(of: ttsService?.state) { _, newState in
            if newState == .idle {
                ttsHighlightCoordinator?.clearHighlight()
            }
        }
        .readerNotificationHandlers(
            deps: makeNotificationDeps(),
            uiState: uiState,
            highlightCoordinator: highlightCoordinator ?? makeNoOpCoordinator()
        )
    }

    // MARK: - Notification Dependencies

    private func makeNotificationDeps() -> ReaderNotificationDeps {
        let container = modelContainer
        return ReaderNotificationDeps(
            bookFingerprintKey: viewModel.bookFingerprintKey,
            bookFingerprint: viewModel.bookFingerprint,
            bookmarkPersistence: container.map { PersistenceActor(modelContainer: $0) } ?? NoOpBookmarkStore(),
            highlightPersistence: container.map { PersistenceActor(modelContainer: $0) } ?? NoOpHighlightStore(),
            annotationPersistence: container.map { PersistenceActor(modelContainer: $0) } ?? NoOpAnnotationStore(),
            locatorFactory: { [viewModel] fp, start, end, _ in
                // Bug #180 WI-7: in continuous mode the bridge reports
                // document-global selection offsets, so the locator is built
                // with the global `txtRange` branch — no chapter-local hop.
                if viewModel.isContinuousMode {
                    return LocatorFactory.txtRange(
                        fingerprint: fp,
                        charRangeStartUTF16: start,
                        charRangeEndUTF16: end,
                        sourceText: viewModel.textContent
                    )
                }
                let chapters = viewModel.chapterIndex?.chapters ?? []
                let idx = viewModel.currentChapterIdx
                let chapter = idx >= 0 && idx < chapters.count ? chapters[idx] : nil
                return Self.makeLocatorForTXT(
                    fingerprint: fp,
                    localStart: start,
                    localEnd: end,
                    chapterText: viewModel.currentChapterText,
                    chapterGlobalStart: chapter?.globalStartUTF16 ?? 0,
                    isChapterMode: viewModel.isChapterMode
                )
            },
            sourceText: { [viewModel] in viewModel.textContent },
            makeCurrentLocator: { [viewModel] in viewModel.makeLocator() },
            onNavigate: { [viewModel] offset in
                // Bug #180 WI-6: in continuous mode every navigation target is
                // a document-global offset — TOC tap, bookmark, search hit all
                // resolve to a scroll offset. The chapter is derived afterward
                // from where the scroll lands; no text swap.
                if viewModel.isContinuousMode {
                    uiState.scrollToOffset = offset
                } else {
                    // Bug #234: a Paged-mode TOC tap resolves to its chapter by
                    // the tapped entry's unique document-global offset, never by
                    // a chapter-title string match — duplicate / empty TXT
                    // chapter titles made the old title match land on the wrong
                    // chapter.
                    Task { await viewModel.navigateToTOCTap(globalOffsetUTF16: offset) }
                }
            },
            hapticFeedback: HapticFeedbackProvider()
        )
    }

    #if DEBUG
    /// Bug #1218: post the current chapter's rendered (post-Simp→Trad) text on
    /// `.debugBridgeRenderedTextChanged` so the DebugBridge probe can surface
    /// it via the `txt-content` command. iOS 26 SwiftUI flattens the chunked
    /// TXT reader's inner cells into the container, whose accessibility VALUE
    /// is the load-bearing `restoredOffset:…` state probe, so CU-free XCUITest
    /// cannot read the rendered content directly — which blocks Feature #28's
    /// conversion verification. `ReaderContainerView`'s observer writes the
    /// text onto the active probe when the `fingerprintKey` matches. The key is
    /// the VM's `bookFingerprintKey` (== `DocumentFingerprint.canonicalKey`),
    /// matching `book.fingerprintKey` in `ReaderContainerView`.
    private func postRenderedTextForDebug(_ displayText: String) {
        NotificationCenter.default.post(
            name: .debugBridgeRenderedTextChanged,
            object: nil,
            userInfo: [
                "fingerprintKey": viewModel.bookFingerprintKey,
                "text": displayText
            ]
        )
    }
    #endif

    // MARK: - Subviews

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("txtReaderLoading")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("txtReaderError")
    }

    @ViewBuilder
    private func readerContent(text: String, attributedText: NSAttributedString) -> some View {
        // Feature #56 WI-12b: route source-domain offsets through the
        // bilingual segment map for the legacy small-file path. Identity
        // map (bilingual off) is a byte-identical pass-through.
        let bilingualScroll: Int? = {
            guard let raw = uiState.scrollToOffset ?? scrollToOffset else { return nil }
            return BilingualOffsetRouter.displayOffset(forSourceOffset: raw, map: bilingualSegmentMap)
        }()
        // Codex Gate-4 H1: restore-offset is a source-domain position —
        // route through the segment map so a reopen lands on the
        // display position of the saved source paragraph rather than
        // jumping to the same numeric offset (which lands wrong when a
        // synthetic translation block precedes the saved position).
        let bilingualRestore: Int? = initialRestoreOffset.map {
            BilingualOffsetRouter.displayOffset(forSourceOffset: $0, map: bilingualSegmentMap)
        }
        let bilingualTemp = Self.routeNSRange(uiState.highlightRange, map: bilingualSegmentMap)
        let bilingualPersisted = Self.routePersisted(uiState.persistedHighlightRanges, map: bilingualSegmentMap)
        let bilingualLookup = Self.routeLookup(uiState.persistedHighlightLookup, map: bilingualSegmentMap)
        // Bug #179: the bridge sums a top safe-area inset into
        // `textContainerInset.top` so the first line clears the Dynamic Island
        // / status bar. The parent `ReaderContainerView` applies
        // `.ignoresSafeArea(edges: .top)` for chrome-overlay layout, so
        // `proxy.safeAreaInsets.top` from a GeometryReader nested here is
        // unreliable — it returns 0 momentarily on first render before
        // layout measures (REOPENED scenario A) and stays 0 across the
        // chapter-nav rebuild (REOPENED scenario B) until SwiftUI has
        // measured the new view identity. `ReaderSafeAreaResolver` reads
        // the device-level truth from `UIWindow.safeAreaInsets.top` and
        // takes the larger of the two — bridging the GeometryReader race
        // without over-insetting when the device actually has a 0 top
        // safe area (landscape, non-DI device).
        GeometryReader { proxy in
            TXTTextViewBridge(
                text: text,
                attributedText: attributedText,
                config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                restoreOffset: bilingualRestore,
                scrollToOffset: bilingualScroll,
                highlightRange: bilingualTemp,
                highlightIsTemporary: uiState.highlightIsTemporary,
                highlightNonce: uiState.highlightNonce,
                persistedHighlights: bilingualPersisted,
                persistedHighlightLookup: bilingualLookup,
                onTemporaryHighlightCleared: { [uiState] in
                    // Bug #154 / GH #443 (Codex audit): the bridge expired the
                    // temporary search highlight — drop it from the model too
                    // so a later font/theme re-render can't re-paint it.
                    uiState.highlightRange = nil
                },
                safeAreaTopInset: ReaderSafeAreaResolver.topInsetWithFallback(proxy.safeAreaInsets.top),
                // Feature #56 WI-12b: when bilingual is on, route the
                // bridge's display-domain delegate calls through the
                // adapter back to source domain so the VM persists
                // positions in document source coordinates. Off-mode
                // returns nil and the VM is used directly.
                delegate: bilingualBridgeDelegate ?? viewModel,
                // Codex Gate-4 H2: selection-action notifications
                // (Highlight / Note / Define / Translate) need
                // routing from display-domain to source-domain. The
                // bridge threads this map into TXTBridgeShared so
                // every posted `TextSelectionInfo` carries source-
                // domain offsets even with bilingual on.
                bilingualSegmentMap: bilingualSegmentMap,
                // Bug #239 — gate side-tap → page-turn dispatch in the
                // bridge's tap recognizer on the current layout. Paged
                // surfaces produce `.readerNextPage` / `.readerPreviousPage`
                // for left/right zones; scroll surfaces collapse every tap
                // to the legacy `.readerContentTapped` chrome toggle.
                layout: settingsStore?.epubLayout
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderContent")
    }

    // MARK: - Chapter-Based Content (WI-6)

    /// Renders the current chapter text via TXTTextViewBridge.
    /// Same bridge as full-text mode — just receives chapter text instead of full file.
    @ViewBuilder
    private func chapterReaderContent(
        text: String,
        attributedText: NSAttributedString
    ) -> some View {
        let highlights = Self.chapterLocalHighlightRanges(
            persistedGlobalRanges: uiState.persistedHighlightRanges,
            tempGlobalRange: uiState.highlightRange,
            chapterIndex: viewModel.currentChapterIdx,
            chapters: viewModel.chapterIndex?.chapters ?? []
        )
        // Bug #202: chapter mode also needs the UUID-keyed lookup, translated
        // to chapter-local offsets. Without this the bridge's
        // `handleContentTap` hit-test always returns nil and the tap falls
        // through to chrome-toggle instead of opening the inline edit/delete
        // menu (Feature #53 acceptance criterion (a) for TXT).
        let chapterLookup = TXTChapterHighlightHelper.lookupForChapter(
            chapterIndex: viewModel.currentChapterIdx,
            chapters: viewModel.chapterIndex?.chapters ?? [],
            globalLookup: uiState.persistedHighlightLookup
        )
        let chapters = viewModel.chapterIndex?.chapters ?? []
        let localScrollOffset = Self.chapterLocalScrollOffset(
            globalOffset: uiState.scrollToOffset,
            chapterIndex: viewModel.currentChapterIdx,
            chapters: chapters
        )
        // Feature #56 WI-12b: route every source-domain offset through
        // `BilingualOffsetRouter` so the bridge receives display-domain
        // offsets when bilingual is on. Identity-map mode (bilingual off)
        // is a byte-identical pass-through.
        let bilingualScroll = localScrollOffset.map {
            BilingualOffsetRouter.displayOffset(forSourceOffset: $0, map: bilingualSegmentMap)
        }
        // Codex Gate-4 H1: restore-offset is also a source-domain
        // position — route it through the segment map so reopen lands
        // on the right paragraph in display coordinates.
        let bilingualRestore: Int? = initialRestoreOffset.map {
            BilingualOffsetRouter.displayOffset(forSourceOffset: $0, map: bilingualSegmentMap)
        }
        let bilingualTemp = Self.routeNSRange(highlights.temp, map: bilingualSegmentMap)
        let bilingualPersisted = Self.routePersisted(highlights.persisted, map: bilingualSegmentMap)
        let bilingualLookup = Self.routeLookup(chapterLookup, map: bilingualSegmentMap)
        // Bug #179: see readerContent above. The chapter-nav rebuild path
        // (REOPENED scenario B) was a primary repro for this — when
        // `chapterAttrString = nil` swaps to `loadingView` then back to the
        // bridge, SwiftUI creates a fresh `TXTTextViewBridge` whose first
        // `makeUIView` call runs before the GeometryReader has measured.
        // `ReaderSafeAreaResolver.topInsetWithFallback` keeps the inset
        // correct across that race.
        GeometryReader { proxy in
            TXTTextViewBridge(
                text: text,
                attributedText: attributedText,
                config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                restoreOffset: bilingualRestore,
                scrollToOffset: bilingualScroll,
                highlightRange: bilingualTemp,
                highlightIsTemporary: uiState.highlightIsTemporary,
                highlightNonce: uiState.highlightNonce,
                persistedHighlights: bilingualPersisted,
                persistedHighlightLookup: bilingualLookup,
                onTemporaryHighlightCleared: { [uiState] in
                    // Bug #154 / GH #443 (Codex audit): the bridge expired the
                    // temporary search highlight — drop it from the model too
                    // so a later font/theme re-render can't re-paint it.
                    uiState.highlightRange = nil
                },
                safeAreaTopInset: ReaderSafeAreaResolver.topInsetWithFallback(proxy.safeAreaInsets.top),
                // Feature #56 WI-12b: see readerContent — route the
                // bridge's display-domain delegate calls through the
                // adapter when bilingual is on.
                delegate: bilingualBridgeDelegate ?? viewModel,
                bilingualSegmentMap: bilingualSegmentMap,
                // Bug #239 — see readerContent: gate side-tap → page-turn
                // dispatch on the current paged/scroll layout.
                layout: settingsStore?.epubLayout
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderChapterContent")
    }

    // MARK: - Bilingual offset routing helpers (Feature #56 WI-12b)
    //
    // The router/adapter/delegate helpers live in
    // `TXTReaderContainerView+Bilingual.swift` to keep this file under
    // the file-size budget (rule 50 §9). See that file for the routing
    // functions called by the bridge-config sites above.

    // MARK: - Legacy Subviews

    @ViewBuilder
    private func chunkedReaderContent(chunks: [String], offsets: [Int]) -> some View {
        let chunkIdx = Self.chunkIndex(for: initialRestoreOffset ?? 0, in: offsets)
        let intraFraction: CGFloat? = {
            guard let idx = chunkIdx, let offset = initialRestoreOffset else { return nil }
            let chunkStart = offsets[idx]
            let nextStart = idx + 1 < offsets.count ? offsets[idx + 1] : viewModel.totalTextLengthUTF16
            let chunkLen = nextStart - chunkStart
            guard chunkLen > 0 else { return nil }
            return CGFloat(offset - chunkStart) / CGFloat(chunkLen)
        }()

        // Bug #179: lift the first chunk below the Dynamic Island. See
        // readerContent above — same fallback applies to the chunked bridge
        // (large-file path) for the same GeometryReader-vs-makeUIView race.
        GeometryReader { proxy in
            TXTChunkedReaderBridge(
                chunks: chunks,
                config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                restoreChunkIndex: chunkIdx,
                restoreIntraChunkOffset: intraFraction,
                delegate: viewModel,
                chunkStartOffsets: offsets,
                scrollToOffset: uiState.scrollToOffset ?? scrollToOffset,
                highlightRange: uiState.highlightRange,
                highlightIsTemporary: uiState.highlightIsTemporary,
                highlightNonce: uiState.highlightNonce,
                persistedHighlights: uiState.persistedHighlightRanges,
                persistedHighlightLookup: uiState.persistedHighlightLookup,
                onTemporaryHighlightCleared: { [uiState] in
                    // Bug #154 / GH #443 (Codex audit): the bridge expired the
                    // temporary search highlight — drop it from the model too
                    // so a later font/theme re-render can't re-paint it.
                    uiState.highlightRange = nil
                },
                safeAreaTopInset: ReaderSafeAreaResolver.topInsetWithFallback(proxy.safeAreaInsets.top),
                // Bug #239 — gate side-tap → page-turn dispatch in the
                // chunked bridge's tap recognizer on the current layout.
                layout: settingsStore?.epubLayout
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderChunkedContent")
    }

    // MARK: - Continuous Chaptered Content (Bug #180)

    /// Renders chaptered TXT in Scroll layout as one continuous scrollable
    /// surface — the chunked `UITableView` fed the whole book, with the
    /// chapter-offset index layered for progress + chapter derivation.
    ///
    /// WI-7: highlights stay document-global end-to-end. The chunked bridge's
    /// `chunkStartOffsets` ARE document-global, so persisted highlights /
    /// lookup pass straight through with NO chapter-local translation — the
    /// bridge's existing chunk-offset math handles cross-chunk (and therefore
    /// cross-chapter) ranges.
    @ViewBuilder
    private func continuousChapteredReaderContent(
        chunks: [String], offsets: [Int]
    ) -> some View {
        GeometryReader { proxy in
            TXTChunkedReaderBridge(
                chunks: chunks,
                config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                // Bug #1230 / GH #1230: the scroll-layout / continuous chaptered
                // path is the DEFAULT reading experience — convert the rendered
                // text here so Simplified→Traditional applies (Feature #28).
                chineseConversion: settingsStore?.chineseConversion ?? .none,
                delegate: viewModel,
                chunkStartOffsets: offsets,
                scrollToOffset: uiState.scrollToOffset ?? scrollToOffset,
                highlightRange: uiState.highlightRange,
                highlightIsTemporary: uiState.highlightIsTemporary,
                highlightNonce: uiState.highlightNonce,
                persistedHighlights: uiState.persistedHighlightRanges,
                persistedHighlightLookup: uiState.persistedHighlightLookup,
                onTemporaryHighlightCleared: { [uiState] in
                    // Bug #154 / GH #443 (Codex audit): the bridge expired the
                    // temporary search highlight — drop it from the model too
                    // so a later font/theme re-render can't re-paint it.
                    uiState.highlightRange = nil
                },
                safeAreaTopInset: ReaderSafeAreaResolver.topInsetWithFallback(proxy.safeAreaInsets.top),
                chapterOffsetIndex: viewModel.chapterOffsetIndex,
                restoreGlobalOffset: viewModel.continuousRestoreGlobalOffset,
                // Bug #239 — gate side-tap → page-turn dispatch on the
                // current paged/scroll layout (continuous chaptered TXT
                // ships in scroll mode, so this collapses to chrome-toggle,
                // but plumb it through for completeness).
                layout: settingsStore?.epubLayout
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderContinuousContent")
    }

    /// WI-1: Translates global highlight ranges to chapter-local for TXTTextViewBridge rendering.
    /// Persisted ranges are filtered and clipped to the chapter; the temp range is treated the
    /// same way (wrapped + clipped, unwrapped to a single NSRange or nil).
    /// Returns ([], nil) when chapterIndex is out of bounds — acts as the nil-chapterIndex guard
    /// (chapterReaderContent is only called when chapterIndex != nil, but defensively handled).
    ///
    /// Bug #175: the temp-range path used `tempGlobalRange.flatMap { ... .first }` which
    /// triggered a Swift Testing test-harness hang when this @MainActor-isolated static func
    /// was invoked from a `@Suite struct` test with non-nil `tempGlobalRange`. Rewritten as
    /// an explicit `if let` to bypass the introspection path that triggered the hang.
    /// Behavior is identical (see `TXTChapterHighlightRenderingTests` for the proof).
    static func chapterLocalHighlightRanges(
        persistedGlobalRanges: [PaintedHighlight],
        tempGlobalRange: NSRange?,
        chapterIndex: Int,
        chapters: [TXTChapter]
    ) -> (persisted: [PaintedHighlight], temp: NSRange?) {
        let persisted = TXTChapterHighlightHelper.highlightsForChapter(
            chapterIndex: chapterIndex,
            chapters: chapters,
            persistedGlobalRanges: persistedGlobalRanges
        )
        let temp: NSRange?
        if let tempRange = tempGlobalRange {
            // The temp range is the search/nav highlight — the bridge
            // paints it as its `active` highlight, so the colorName on
            // this throwaway wrapper is never read; only the clipped
            // range is taken. Reuse `highlightsForChapter`'s clip math.
            temp = TXTChapterHighlightHelper.highlightsForChapter(
                chapterIndex: chapterIndex,
                chapters: chapters,
                persistedGlobalRanges: [PaintedHighlight(range: tempRange, colorName: "yellow")]
            ).first?.range
        } else {
            temp = nil
        }
        return (persisted, temp)
    }

    /// WI-2 Part 2a: Computes the global scroll target for the chapter-mode scrubber.
    /// Extracted as a static seam so the pure arithmetic is unit-testable.
    /// Clamped to [globalStart, globalStart + length - 1] so seekValue=1.0 stays inside
    /// the half-open chapter interval used by chapterLocalScrollOffset.
    static func chapterScrubberGlobalOffset(seekValue: Double, chapter: TXTChapter) -> Int {
        let length = chapter.textLengthUTF16
        guard length > 0 else { return chapter.globalStartUTF16 }
        return chapter.globalStartUTF16 + min(Int(seekValue * Double(length)), length - 1)
    }

    /// WI-2 Part 2b: Translates a global scroll offset to chapter-local for bridge delivery.
    /// Returns nil when globalOffset is nil, when chapters is empty, or when the global
    /// offset falls outside the current chapter's range (cross-chapter targets are handled
    /// by the navigation path; the new render cycle handles the post-swap scroll).
    static func chapterLocalScrollOffset(
        globalOffset: Int?,
        chapterIndex: Int,
        chapters: [TXTChapter]
    ) -> Int? {
        guard let global = globalOffset,
              chapterIndex >= 0, chapterIndex < chapters.count else { return nil }
        let chapter = chapters[chapterIndex]
        guard chapter.globalStartUTF16 >= 0, chapter.textLengthUTF16 >= 0 else { return nil }
        let chapterEnd = chapter.globalStartUTF16 + chapter.textLengthUTF16
        guard global >= chapter.globalStartUTF16, global < chapterEnd else { return nil }
        return TXTChapterHighlightHelper.toChapterLocalOffset(
            globalUTF16: global,
            chapterIndex: chapterIndex,
            chapters: chapters
        )
    }

    /// WI-3: Builds a Locator from a selection notification.
    /// In chapter mode, translates chapter-local offsets to global via txtChapterRange.
    /// In continuous mode, delegates directly to txtRange.
    /// Extracted as a static seam for unit testability (mirrors WI-2's chapterScrubberGlobalOffset pattern).
    static func makeLocatorForTXT(
        fingerprint: DocumentFingerprint,
        localStart: Int,
        localEnd: Int,
        chapterText: String?,
        chapterGlobalStart: Int,
        isChapterMode: Bool
    ) -> Locator? {
        if isChapterMode {
            guard let text = chapterText else { return nil }
            return LocatorFactory.txtChapterRange(
                fingerprint: fingerprint,
                chapterLocalStart: localStart,
                chapterLocalEnd: localEnd,
                chapterText: text,
                chapterGlobalStart: chapterGlobalStart
            )
        } else {
            return LocatorFactory.txtRange(
                fingerprint: fingerprint,
                charRangeStartUTF16: localStart,
                charRangeEndUTF16: localEnd
            )
        }
    }

    /// Finds the chunk index containing the given character offset.
    static func chunkIndex(for charOffset: Int, in offsets: [Int]) -> Int? {
        guard charOffset > 0, !offsets.isEmpty else { return nil }
        var lo = 0, hi = offsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if offsets[mid] <= charOffset {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    // MARK: - Helpers

    /// Accessibility value for the txtReaderContainer element.
    /// Encodes restore offset and chapter mode so UITests can detect reader state
    /// without relying on inner view identifiers (which are flattened in iOS 26 SwiftUI).
    private var readerAccessibilityValue: String {
        let base = initialRestoreOffset.map { "restoredOffset:\($0)" } ?? "restoredOffset:none"
        guard viewModel.isChapterMode else { return base }
        return "\(base) chapterMode:true chapters:\(viewModel.totalChapterCount)"
    }

    func makeNoOpCoordinator() -> HighlightCoordinator {
        let renderer = highlightRenderer ?? TextHighlightRenderer(uiState: uiState)
        return HighlightCoordinator(
            renderer: renderer,
            persistence: NoOpHighlightStore(),
            bookFingerprintKey: viewModel.bookFingerprintKey
        )
    }

    func updatePaginationIfNeeded() {
        uiState.updatePagination(
            isPagedMode: isPagedMode,
            attributedText: preparedAttrString,
            initialRestoreOffset: initialRestoreOffset,
            autoPageTurnEnabled: settingsStore?.autoPageTurn ?? false,
            autoPageTurnInterval: settingsStore?.autoPageTurnInterval ?? 5.0
        )
        if let offset = uiState.syncPagedState() {
            viewModel.updateScrollPosition(charOffsetUTF16: offset)
        }
    }

    var isPagedMode: Bool {
        settingsStore?.epubLayout == .paged && !isLargeFile
    }

    // MARK: - Chapter Progress (Bug #31)

    /// Current TOC-based chapter progress (nil if no TOC entries).
    private var tocChapterProgress: TOCChapterProgressResult? {
        TOCChapterProgress.progress(
            currentOffsetUTF16: viewModel.currentOffsetUTF16,
            tocEntries: tocEntries,
            totalTextLengthUTF16: viewModel.totalTextLengthUTF16
        )
    }

    /// Start offset of the current TOC chapter.
    private var tocChapterStartOffset: Int {
        guard let cp = tocChapterProgress, cp.chapterIndex < tocEntries.count else { return 0 }
        return tocEntries[cp.chapterIndex].locator.charOffsetUTF16 ?? 0
    }

    /// Length of the current TOC chapter in UTF-16 units.
    private var tocChapterLength: Int {
        guard let cp = tocChapterProgress, cp.chapterIndex < tocEntries.count else {
            return viewModel.totalTextLengthUTF16
        }
        let start = tocEntries[cp.chapterIndex].locator.charOffsetUTF16 ?? 0
        let end = cp.chapterIndex + 1 < tocEntries.count
            ? (tocEntries[cp.chapterIndex + 1].locator.charOffsetUTF16 ?? viewModel.totalTextLengthUTF16)
            : viewModel.totalTextLengthUTF16
        return max(end - start, 1)
    }

    /// Updates chapterScrollFraction from the appropriate source.
    private func updateChapterScrollFraction() {
        if hasChapterDisplay {
            // Chapter-based mode: use ViewModel's local offset
            chapterScrollFraction = viewModel.chapterScrollFraction
        } else if let cp = tocChapterProgress {
            // Legacy mode with TOC entries: use TOC-based chapter progress
            chapterScrollFraction = cp.fraction
        } else {
            // No chapters at all: fall back to book progress
            chapterScrollFraction = viewModel.totalProgression ?? 0
        }
    }
}
#endif
