// Purpose: SwiftUI container for the Markdown reader. Composes the TXTTextViewBridge
// (with NSAttributedString) with loading/error overlays and reading session chrome.
// When layout is .paged, uses NativeTextPagedView for page-at-a-time rendering.
//
// Key decisions:
// - Owns MDReaderViewModel lifecycle (open on appear, close on disappear).
// - Delegates scroll/selection events from bridge to ViewModel for position persistence.
// - Shows loading spinner during file open.
// - Shows error message on failure.
// - Passes rendered NSAttributedString to bridge for rich display.
// - Paged mode (B08): uses NativeTextPageNavigator + NativeTextPagedView.
// - AutoPageTurner (B10): wired when autoPageTurn is enabled + paged layout.
// - PageTurnAnimator (B11): animation style from settingsStore.pageTurnAnimation.
// - Phase R3: shared UI state (highlights, pagination, progress) lives in TextReaderUIState.
//
// @coordinates-with: MDReaderViewModel.swift, TXTTextViewBridge.swift,
//   ReadingProgressBar.swift, ScrollProgressHelper.swift,
//   NativeTextPageNavigator.swift, NativeTextPagedView.swift,
//   AutoPageTurner.swift, PageTurnAnimator.swift, TextReaderUIState.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

/// Container view for the Markdown reader screen.
struct MDReaderContainerView: View {
    let fileURL: URL
    let viewModel: MDReaderViewModel
    var settingsStore: ReaderSettingsStore?
    var modelContainer: ModelContainer?
    var ttsService: TTSService?

    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors ReaderContainerView's chrome toggle so the bottom overlay hides with the nav bar.
    @State private var isChromeVisible = true

    /// Captured scroll position for one-shot restore. Set once after file opens.
    @State private var initialRestoreOffset: Int?

    // MARK: - Shared UI State (Phase R3) + Highlight Coordination (Phase R4)

    @State private var uiState = TextReaderUIState()
    @State private var highlightRenderer: TextHighlightRenderer?
    @State private var highlightCoordinator: HighlightCoordinator?
    /// TTS sentence highlighting + auto-scroll coordinator (features #40, #41).
    @State private var ttsHighlightCoordinator: TTSHighlightCoordinator?

    /// Whether paged mode is active.
    private var isPagedMode: Bool {
        settingsStore?.epubLayout == .paged
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.renderedText == nil {
                errorView(message: errorMessage)
            } else if let attrStr = viewModel.renderedAttributedString {
                if isPagedMode, let nav = uiState.pageNavigator {
                    pagedReaderContent(attributedString: attrStr, navigator: nav)
                } else {
                    readerContent(attributedString: attrStr)
                }
            } else {
                // Not yet opened
                Color.clear
            }

            // Bottom overlay for progress, scrubber, and session time (WI-004b)
            // Hidden when TTS is active to avoid overlap (bug #97)
            if viewModel.renderedText != nil && !viewModel.isLoading && isChromeVisible
                && (ttsService?.state ?? .idle) == .idle {
                VStack(spacing: 0) {
                    Spacer()
                    ReadingProgressBar(
                        progress: $uiState.readingProgress,
                        onSeek: { seekValue in
                            let charOffset = ScrollProgressHelper.charOffsetFromProgress(
                                progress: seekValue,
                                totalLengthUTF16: viewModel.renderedTextLengthUTF16
                            )
                            uiState.scrollToOffset = charOffset
                        },
                        isVisible: viewModel.renderedTextLengthUTF16 > 0,
                        label: ScrollProgressHelper.percentageLabel(uiState.readingProgress),
                        settingsStore: settingsStore
                    )
                    ReaderBottomOverlay(
                        progress: viewModel.totalProgression,
                        sessionTime: viewModel.sessionTimeDisplay,
                        settingsStore: settingsStore,
                        accessibilityPrefix: "md"
                    )
                }
            }
        }
        .task {
            // PERF: open already called by MDReaderHost
            if viewModel.renderedText == nil {
                // Bug #178 / GH #606: forward chineseConversion so the
                // MD render pipeline applies SimpTradTransform to the
                // source text before parsing. Live re-apply on toggle
                // requires close+reopen (out of scope for the silent-
                // noop fix; documented limitation).
                await viewModel.open(
                    url: fileURL,
                    chineseConversion: settingsStore?.chineseConversion ?? .none
                )
            }
            initialRestoreOffset = viewModel.currentOffsetUTF16
            if isPagedMode {
                updatePaginationIfNeeded()
            }
            // PERF: Create renderer immediately, defer DB restore
            let renderer = TextHighlightRenderer(uiState: uiState)
            highlightRenderer = renderer
            if let tts = ttsService {
                ttsHighlightCoordinator = TTSHighlightCoordinator(ttsService: tts, uiState: uiState)
            }
            // Defer highlight restore — don't block content display
            Task {
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
        .onChange(of: viewModel.totalProgression) { _, newValue in
            uiState.readingProgress = newValue ?? 0
            // Notify ReaderContainerView of the live position for AI panel.
            let locator = viewModel.makeLocator()
            NotificationCenter.default.post(
                name: .readerPositionDidChange, object: locator
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            isChromeVisible.toggle()
            uiState.autoPageTurner?.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNextPage)) { _ in
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
        .onChange(of: settingsStore?.epubLayout) { _, _ in
            updatePaginationIfNeeded()
        }
        .onChange(of: settingsStore?.typography.fontSize) { _, _ in
            updatePaginationIfNeeded()
        }
        .onChange(of: settingsStore?.autoPageTurn) { _, newValue in
            uiState.updateAutoPageTurner(
                enabled: newValue ?? false,
                isPagedMode: isPagedMode,
                interval: settingsStore?.autoPageTurnInterval ?? 5.0
            )
        }
        .onChange(of: settingsStore?.autoPageTurnInterval) { _, _ in
            // Bug #137: live-apply interval changes for an already-running
            // turner. Mirror of the TXT handler added in bug #131 fix.
            guard settingsStore?.autoPageTurn == true else { return }
            uiState.updateAutoPageTurner(
                enabled: true,
                isPagedMode: isPagedMode,
                interval: settingsStore?.autoPageTurnInterval ?? 5.0
            )
        }
        // Bug #132: wire TTS sentence highlight + auto-scroll. The
        // coordinator is instantiated in onAppear but its updateHighlight
        // entry point was never invoked — the observation was missing.
        .onChange(of: ttsService?.currentOffsetUTF16) { _, newOffset in
            guard let newOffset, let coordinator = ttsHighlightCoordinator else { return }
            if let text = viewModel.renderedText {
                coordinator.ensureConfigured(text: text)
            }
            coordinator.updateHighlight(offset: newOffset)
        }
        .onChange(of: ttsService?.state) { _, newState in
            // Clear highlight when TTS stops; updateHighlight handles
            // the .speaking and .paused transitions.
            if newState == .idle {
                ttsHighlightCoordinator?.clearHighlight()
            }
        }
        .readerNotificationHandlers(
            deps: makeNotificationDeps(),
            uiState: uiState,
            highlightCoordinator: highlightCoordinator ?? makeNoOpCoordinator()
        )
        .accessibilityIdentifier("mdReaderContainer")
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
                LocatorFactory.mdRange(fingerprint: fp, charRangeStartUTF16: start, charRangeEndUTF16: end, sourceText: text)
            },
            sourceText: { [viewModel] in viewModel.renderedText },
            makeCurrentLocator: { [viewModel] in viewModel.makeLocator() },
            onNavigate: { [viewModel] offset in viewModel.updateScrollPosition(charOffsetUTF16: offset) },
            hapticFeedback: HapticFeedbackProvider()
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
        .accessibilityIdentifier("mdReaderLoading")
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
        .accessibilityIdentifier("mdReaderError")
    }

    @ViewBuilder
    private func pagedReaderContent(
        attributedString: NSAttributedString,
        navigator: NativeTextPageNavigator
    ) -> some View {
        VStack(spacing: 0) {
            NativeTextPagedView(
                navigator: navigator,
                fullText: attributedString.string,
                fullAttributedText: attributedString,
                config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                currentPage: uiState.pagedCurrentPage,
                pageTurnAnimation: settingsStore?.pageTurnAnimation ?? .none
            )

            if navigator.totalPages > 0 {
                Text("Page \(uiState.pagedCurrentPage + 1) of \(navigator.totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("mdPageIndicator")
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("mdReaderPagedContent")
    }

    @ViewBuilder
    private func readerContent(attributedString: NSAttributedString) -> some View {
        // Bug #179: wire the safe-area top into the bridge so MD scroll-mode
        // renders below the Dynamic Island. Same pattern as the TXT reader
        // (this bridge is shared) and the EPUB fix for #163. The
        // `ReaderSafeAreaResolver.topInsetWithFallback` hop survives the
        // GeometryReader-vs-makeUIView race that left chapter-nav and
        // saved-position restore behind the notch (REOPENED scenarios A/B).
        GeometryReader { proxy in
            TXTTextViewBridge(
                text: attributedString.string,
                attributedText: attributedString,
                config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                restoreOffset: initialRestoreOffset,
                scrollToOffset: uiState.scrollToOffset,
                highlightRange: uiState.highlightRange,
                highlightIsTemporary: uiState.highlightIsTemporary,
                persistedHighlights: uiState.persistedHighlightRanges,
                persistedHighlightLookup: uiState.persistedHighlightLookup,
                safeAreaTopInset: ReaderSafeAreaResolver.topInsetWithFallback(proxy.safeAreaInsets.top),
                delegate: viewModel
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("mdReaderContent")
    }

    // MARK: - Highlight Coordinator (Phase R4)

    private func makeNoOpCoordinator() -> HighlightCoordinator {
        let renderer = highlightRenderer ?? TextHighlightRenderer(uiState: uiState)
        return HighlightCoordinator(
            renderer: renderer,
            persistence: NoOpHighlightStore(),
            bookFingerprintKey: viewModel.bookFingerprintKey
        )
    }

    // MARK: - Paged Mode Helpers (B08, B10)

    private func updatePaginationIfNeeded() {
        uiState.updatePagination(
            isPagedMode: isPagedMode,
            attributedText: viewModel.renderedAttributedString,
            initialRestoreOffset: initialRestoreOffset,
            autoPageTurnEnabled: settingsStore?.autoPageTurn ?? false,
            autoPageTurnInterval: settingsStore?.autoPageTurnInterval ?? 5.0
        )
        if let offset = uiState.syncPagedState() {
            viewModel.updateScrollPosition(charOffsetUTF16: offset)
        }
    }
}
#endif
