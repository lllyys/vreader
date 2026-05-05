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
    /// Match highlight range for search navigation (bug #43).
    @State private var highlightRange: NSRange?
    /// Whether the current highlight is temporary (search nav) or persistent (user-created).
    /// Temporary highlights auto-clear after 3s; persistent ones survive cell reuse (bug #54).
    @State private var highlightIsTemporary: Bool = true
    /// Pending annotation info for the "Add Note" flow (bug #44).
    @State private var pendingAnnotationInfo: TextSelectionInfo?
    /// Text input for the annotation note.
    @State private var annotationNoteText: String = ""
    /// Persisted highlight ranges loaded from DB on file open (bug #55).
    @State private var persistedHighlightRanges: [NSRange] = []

    /// Pre-built attributed string for chapter-based display (WI-6).
    @State private var chapterAttrString: NSAttributedString?
    @State private var chapterScrollFraction: Double = 0

    // MARK: - Shared UI State (Phase R3) + Highlight Coordination (Phase R4)
    @State var uiState = TextReaderUIState()
    @State var highlightRenderer: TextHighlightRenderer?
    @State var highlightCoordinator: HighlightCoordinator?
    @State var ttsHighlightCoordinator: TTSHighlightCoordinator?

    /// Whether the loaded text exceeds the large file threshold.
    private var isLargeFile: Bool {
        viewModel.totalTextLengthUTF16 > Self.largeFileThreshold
    }

    /// Whether the ViewModel has chapter-based display data available.
    private var hasChapterDisplay: Bool {
        viewModel.chapterIndex != nil && viewModel.currentChapterText != nil
    }

    /// Composite key that triggers attributed string rebuild when text or config changes.
    /// Uses totalTextLengthUTF16 + totalWordCount (O(1)) instead of text.hashValue (O(n)).
    /// Includes theme colors so theme changes trigger rebuild (bug #29).
    /// Includes currentChapterIdx so chapter navigation triggers rebuild (WI-6).
    private var attrStringKey: String {
        let hasText = viewModel.textContent != nil
        let len = viewModel.totalTextLengthUTF16
        let words = viewModel.totalWordCount
        let chIdx = viewModel.currentChapterIdx
        let chCount = viewModel.totalChapterCount
        let cfg = settingsStore?.txtViewConfig ?? TXTViewConfig()
        let textColorHash = cfg.textColor.hash
        let bgColorHash = cfg.backgroundColor.hash
        return "\(hasText)-\(len)-\(words)-ch\(chIdx)/\(chCount)-\(cfg.fontSize)-\(cfg.fontName ?? "sys")-\(cfg.lineSpacing)-\(cfg.letterSpacing)-\(textColorHash)-\(bgColorHash)"
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading || isBuildingInitialAttrString {
                loadingView
            } else if let errorMessage = viewModel.errorMessage,
                      viewModel.textContent == nil && viewModel.currentChapterText == nil {
                errorView(message: errorMessage)
            } else if let chapterText = viewModel.currentChapterText,
                      let attrStr = chapterAttrString {
                // Chapter-based display (WI-6) — fast path for files with detected chapters
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
                VStack(spacing: 0) {
                    Spacer()
                    if hasChapterDisplay {
                        ReadingProgressBar(
                            progress: $chapterScrollFraction,
                            onSeek: { seekValue in
                                let chLen = viewModel.currentChapterText?.utf16.count ?? 0
                                let charOffset = Int(seekValue * Double(chLen))
                                uiState.scrollToOffset = charOffset
                            },
                            isVisible: (viewModel.currentChapterText?.utf16.count ?? 0) > 0,
                            label: ScrollProgressHelper.percentageLabel(chapterScrollFraction),
                            settingsStore: settingsStore
                        )
                        ChapterBottomOverlay(
                            viewModel: viewModel,
                            bookProgress: chapterScrollFraction,
                            settingsStore: settingsStore,
                            onNavigate: { chapterAttrString = nil }
                        )
                    } else {
                        ReadingProgressBar(
                            progress: $chapterScrollFraction,
                            onSeek: { seekValue in
                                // If TOC entries exist, seek within current chapter
                                if let cp = tocChapterProgress {
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
                            isVisible: viewModel.totalTextLengthUTF16 > 0,
                            label: ScrollProgressHelper.percentageLabel(chapterScrollFraction),
                            settingsStore: settingsStore
                        )
                        ReaderBottomOverlay(
                            progress: chapterScrollFraction,
                            sessionTime: viewModel.sessionTimeDisplay,
                            settingsStore: settingsStore,
                            accessibilityPrefix: "txt"
                        )
                    }
                }
            }
        }
        .task {
            // PERF: open already called by TXTReaderHost — skip if content loaded
            if viewModel.textContent == nil && viewModel.currentChapterText == nil {
                await viewModel.openChapterBased(url: fileURL)
            }
            // GH #30: In chapter mode, capture LOCAL offset for within-chapter restore.
            if viewModel.isChapterMode {
                initialRestoreOffset = viewModel.currentChapterLocalUTF16
            } else {
                initialRestoreOffset = viewModel.currentOffsetUTF16
            }
            // Load persisted highlights from DB for visual rendering (bug #55)
            if let container = modelContainer {
                let persistence = PersistenceActor(modelContainer: container)
                if let records = try? await persistence.fetchHighlights(
                    forBookWithKey: viewModel.bookFingerprintKey
                ) {
                    persistedHighlightRanges = records.compactMap { record in
                        guard let start = record.locator.charRangeStartUTF16,
                              let end = record.locator.charRangeEndUTF16,
                              end > start else { return nil }
                        return NSRange(location: start, length: end - start)
                    }
                }
            }
            // Bug #132: instantiate TTS highlight coordinator (was missing
            // entirely — feature #40/#41 weren't wired in TXT). Mirror
            // MDReaderContainerView's onAppear pattern.
            if let tts = ttsService, ttsHighlightCoordinator == nil {
                ttsHighlightCoordinator = TTSHighlightCoordinator(ttsService: tts, uiState: uiState)
            }
        }
        .task(id: attrStringKey) {
            let config = settingsStore?.txtViewConfig ?? TXTViewConfig()

            // Chapter-based path (WI-6): build attributed string for current chapter only.
            // Much smaller text → typically <50ms, often synchronous for small chapters.
            if let chapterText = viewModel.currentChapterText {
                let isInitial = chapterAttrString == nil
                if isInitial { isBuildingInitialAttrString = true }
                defer { if isInitial { isBuildingInitialAttrString = false } }

                if chapterText.utf16.count < 10_000 {
                    // Small chapter (<10KB UTF-16): build synchronously
                    chapterAttrString = TXTAttributedStringBuilder.build(
                        text: chapterText, config: config
                    )
                } else {
                    let wrapped = await Task.detached(priority: .userInitiated) {
                        TXTAttributedStringBuilder.buildSendable(
                            text: chapterText, config: config
                        )
                    }.value
                    guard !Task.isCancelled else { return }
                    chapterAttrString = wrapped.value
                }
                return
            }

            // Legacy full-text path (no chapter index)
            guard let text = viewModel.textContent else { return }

            if text.utf16.count > Self.largeFileThreshold {
                // Large file: split into chunks (fast, no attributed string needed here)
                let isInitial = textChunks == nil
                if isInitial { isBuildingInitialAttrString = true }
                defer { if isInitial { isBuildingInitialAttrString = false } }

                let splitResult = await Task.detached(priority: .userInitiated) {
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
            } else {
                // Small file: build full attributed string
                let isInitial = preparedAttrString == nil
                if isInitial { isBuildingInitialAttrString = true }
                defer { if isInitial { isBuildingInitialAttrString = false } }

                let wrapped = await Task.detached(priority: .userInitiated) {
                    TXTAttributedStringBuilder.buildSendable(text: text, config: config)
                }.value
                guard !Task.isCancelled else { return }
                preparedAttrString = wrapped.value
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
        .accessibilityIdentifier("txtReaderContainer")
        .accessibilityValue(initialRestoreOffset.map { "restoredOffset:\($0)" } ?? "restoredOffset:none")
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
            locatorFactory: { fp, start, end, text in
                LocatorFactory.txtRange(fingerprint: fp, charRangeStartUTF16: start, charRangeEndUTF16: end, sourceText: text)
            },
            sourceText: { [viewModel] in viewModel.textContent },
            makeCurrentLocator: { [viewModel] in viewModel.makeLocator() },
            onNavigate: { [viewModel, tocEntries] offset in
                if viewModel.chapterIndex != nil {
                    // GH #30: TOC and chapters now use the same full-text decode,
                    // so title matching is reliable. Fall back to offset for bookmarks/search.
                    if let title = tocEntries.first(where: { $0.locator.charOffsetUTF16 == offset })?.title {
                        Task {
                            let matched = await viewModel.navigateToChapterByTitle(title)
                            if !matched {
                                await viewModel.navigateToGlobalOffset(offset)
                            }
                        }
                    } else {
                        Task { await viewModel.navigateToGlobalOffset(offset) }
                    }
                } else {
                    viewModel.updateScrollPosition(charOffsetUTF16: offset)
                }
            }
        )
    }

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
        TXTTextViewBridge(
            text: text,
            attributedText: attributedText,
            config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
            restoreOffset: initialRestoreOffset,
            scrollToOffset: uiState.scrollToOffset ?? scrollToOffset,
            highlightRange: highlightRange,
            highlightIsTemporary: highlightIsTemporary,
            persistedHighlights: persistedHighlightRanges,
            delegate: viewModel
        )
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
        TXTTextViewBridge(
            text: text,
            attributedText: attributedText,
            config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
            restoreOffset: initialRestoreOffset, // GH #30: chapter-local offset for scroll restore
            scrollToOffset: uiState.scrollToOffset, // Scrubber seek within chapter
            highlightRange: nil, // Highlight offset translation is WI-7
            highlightIsTemporary: true,
            persistedHighlights: [], // Highlight mapping is WI-7
            delegate: viewModel
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderChapterContent")
    }

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

        TXTChunkedReaderBridge(
            chunks: chunks,
            config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
            restoreChunkIndex: chunkIdx,
            restoreIntraChunkOffset: intraFraction,
            delegate: viewModel,
            chunkStartOffsets: offsets,
            scrollToOffset: uiState.scrollToOffset ?? scrollToOffset,
            highlightRange: highlightRange,
            highlightIsTemporary: highlightIsTemporary,
            persistedHighlights: persistedHighlightRanges
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("txtReaderChunkedContent")
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
