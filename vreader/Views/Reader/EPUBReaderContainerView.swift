// Purpose: SwiftUI container for the EPUB reader. Composes the EPUBWebViewBridge
// with loading/error overlays, chapter navigation, reading progress, and highlights.
//
// @coordinates-with: EPUBReaderViewModel.swift, EPUBWebViewBridge.swift,
//   EPUBReaderContainerView+Navigation.swift, EPUBReaderContainerView+Highlights.swift,
//   EPUBHighlightBridge.swift, HighlightCoordinator.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

/// Container view for the EPUB reader screen.
struct EPUBReaderContainerView: View {
    let fileURL: URL
    let viewModel: EPUBReaderViewModel
    let parser: any EPUBParserProtocol
    var settingsStore: ReaderSettingsStore?
    var modelContainer: ModelContainer?
    var ttsService: TTSService?
    /// Bug #126: book identity threaded into `EPUBWebViewBridge` so the
    /// DebugBridge eval registry can pair `(webView, fingerprintKey)` and
    /// reject stale-webview matches. Optional so existing call sites
    /// (tests, previews) remain source-compatible.
    var fingerprintKey: String?
    /// Bug #142: per-reader instance token paired with fingerprintKey.
    var readerToken: UUID?

    /// OPF directory — spine hrefs are resolved relative to this.
    @State var resourceBase: URL?
    /// Extracted root directory — passed to WKWebView for file access.
    @State private var extractedRoot: URL?
    @State var contentURL: URL?
    @State var webViewError: String?
    @State private var openTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Mirrors ReaderContainerView's chrome toggle so the bottom overlay hides with the nav bar.
    @State private var isChromeVisible = true
    /// Overall reading progress (0.0-1.0) computed from spine index + scroll fraction.
    @State var readingProgress: Double = 0
    /// Scroll fraction to pass to EPUBWebViewBridge for intra-chapter seeking.
    @State var seekScrollFraction: Double?
    /// Pending text selection event for the highlight action dialog.
    @State var pendingSelectionEvent: ReaderSelectionEvent?
    /// Whether the highlight action sheet is visible.
    @State private var showHighlightSheet = false
    /// JavaScript to inject into WKWebView (e.g., highlight CSS after persist).
    @State var pendingHighlightJS: String?
    /// Whether the note input sheet is visible.
    @State var showNoteSheet = false
    /// Text input for the note being added.
    @State var noteText = ""
    /// Page navigator for paged layout (WI-B06).
    @State var pageNavigator = BasePageNavigator()
    /// Current page in paged mode (drives bridge navigation).
    @State var currentPaginationPage: Int?
    /// Phase R4: highlight renderer and coordinator.
    @State var highlightRenderer = EPUBHighlightRenderer()
    @State var highlightCoordinator: HighlightCoordinator?

    /// Whether paged layout is active.
    private var isPaged: Bool {
        settingsStore?.epubLayout == .paged
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.metadata == nil {
                errorView(message: errorMessage)
            } else if let webViewError {
                errorView(message: webViewError)
            } else if let contentURL, let extractedRoot {
                readerContent(contentURL: contentURL, accessRoot: extractedRoot)
            } else if viewModel.metadata != nil {
                // Metadata loaded but content URL not yet resolved
                loadingView
            } else {
                Color.clear
            }

            // Bottom navigation overlay (Issue 9: spacing: 0 to match PDF/TXT containers)
            // Hidden when TTS is active to avoid overlap (bug #97)
            if viewModel.metadata != nil, !viewModel.isLoading, isChromeVisible,
               (ttsService?.state ?? .idle) == .idle {
                VStack(spacing: 0) {
                    Spacer()
                    bottomOverlay
                }
            }
        }
        .task {
            // Phase R4: set up highlight renderer + coordinator
            highlightRenderer.onInjectJS = { [self] js in
                pendingHighlightJS = js
            }
            if let container = modelContainer {
                let persistence = PersistenceActor(modelContainer: container)
                highlightCoordinator = HighlightCoordinator(
                    renderer: highlightRenderer,
                    persistence: persistence,
                    bookFingerprintKey: viewModel.bookFingerprintKey
                )
            }

            let task = Task {
                await viewModel.open(url: fileURL)
                guard !Task.isCancelled else { return }
                // Resolve base directories and initial content URL
                guard viewModel.metadata != nil,
                      let firstItem = viewModel.currentPosition else { return }
                do {
                    let base = try await parser.resourceBaseURL()
                    let root = try await parser.extractedRootURL()
                    guard !Task.isCancelled else { return }
                    resourceBase = base
                    extractedRoot = root
                    // Restore intra-chapter scroll position (bug #58).
                    // The restored position includes progression (0.0-1.0)
                    // which must be passed to EPUBWebViewBridge as seekScrollFraction
                    // so the bridge scrolls to the saved offset after loading.
                    if firstItem.progression > 0 {
                        seekScrollFraction = firstItem.progression
                    }
                    // Ensure chapter file exists before WKWebView loads it (bug #102)
                    await ensureChapterExtracted(href: firstItem.href)
                    contentURL = base.appendingPathComponent(firstItem.href)
                } catch {
                    if !Task.isCancelled {
                        webViewError = "Failed to resolve book resources."
                    }
                }
            }
            openTask = task
            await task.value
        }
        .onDisappear {
            openTask?.cancel()
            openTask = nil
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
        .onReceive(NotificationCenter.default.publisher(for: .readerBookmarkRequested)) { _ in
            guard let container = modelContainer,
                  let locator = viewModel.makeCurrentLocator() else { return }
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                do {
                    try await persistence.addBookmark(
                        locator: locator,
                        title: nil,
                        toBookWithKey: viewModel.bookFingerprintKey
                    )
                    HapticFeedbackProvider().triggerLightImpact()
                } catch {}
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            isChromeVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNextPage)) { _ in
            guard isPaged else { return }
            pageNavigator.nextPage()
            currentPaginationPage = pageNavigator.currentPage
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPreviousPage)) { _ in
            guard isPaged else { return }
            pageNavigator.previousPage()
            currentPaginationPage = pageNavigator.currentPage
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
            guard let locator = notification.object as? Locator,
                  let href = locator.href,
                  let meta = viewModel.metadata,
                  let base = resourceBase else { return }
            if let spineIndex = meta.spineItems.firstIndex(where: { $0.href == href }) {
                viewModel.navigateToSpine(index: spineIndex)
                webViewError = nil
                // Issue 6: Reset pagination on locator navigation (same as chapter nav).
                pageNavigator.reset()
                currentPaginationPage = nil
                // Issue 3: Use locator.progression to scroll within the chapter.
                // This reuses the existing WI-004d scroll-to-fraction mechanism so
                // the WebView lands at the correct position, not chapter top.
                if let progression = locator.progression, progression > 0 {
                    seekScrollFraction = progression
                } else {
                    seekScrollFraction = nil
                }
                // Ensure chapter extracted before WKWebView loads it (bug #102)
                Task { await ensureChapterExtracted(href: href) }
                contentURL = base.appendingPathComponent(href)
                // Inject search highlight JS after page loads (bug #43)
                // Issue 4: Pass progression so JS scrolls before find()
                if let textQuote = locator.textQuote {
                    let js = EPUBHighlightBridge.searchHighlightJS(
                        textQuote: textQuote,
                        progression: locator.progression
                    )
                    if !js.isEmpty {
                        pendingHighlightJS = js
                    }
                }
            }
        }
        // Bug #88: re-render highlights after annotation import
        .onReceive(NotificationCenter.default.publisher(for: .readerHighlightsDidImport)) { _ in
            if let coordinator = highlightCoordinator {
                Task { await coordinator.restoreAll() }
            }
        }
        // Remove highlight visual when deleted from annotations panel (bug #78)
        // Phase R4b: delegate to coordinator (renderer generates remove JS)
        .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRemoved)) { notification in
            guard let idString = notification.object as? String,
                  let highlightId = UUID(uuidString: idString) else { return }
            if let coordinator = highlightCoordinator {
                Task { await coordinator.handleRemoval(highlightId: highlightId) }
            } else {
                // Fallback: direct JS injection if coordinator not ready
                pendingHighlightJS = EPUBHighlightBridge.removeHighlightJS(id: idString)
            }
        }
        .confirmationDialog(
            "Text Selection",
            isPresented: $showHighlightSheet,
            titleVisibility: .visible
        ) {
            Button("Highlight") {
                guard let event = pendingSelectionEvent,
                      let container = modelContainer else { return }
                handleHighlightAction(event: event, container: container)
            }
            Button("Add Note") {
                noteText = ""
                showNoteSheet = true
            }
            Button("Copy") {
                guard let event = pendingSelectionEvent else { return }
                UIPasteboard.general.string = event.selectedText
                pendingSelectionEvent = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSelectionEvent = nil
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            noteInputSheet
        }
        .accessibilityIdentifier("epubReaderContainer")
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
        .accessibilityIdentifier("epubReaderLoading")
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
        .accessibilityIdentifier("epubReaderError")
    }

    /// Ensures the chapter file is extracted from the ZIP before WKWebView tries to load it.
    /// The selective extraction parser only pre-extracts the first chapter + CSS/fonts. (bug #102)
    func ensureChapterExtracted(href: String) async {
        _ = try? await parser.contentForSpineItem(href: href)
    }

    @ViewBuilder
    private func readerContent(contentURL: URL, accessRoot: URL) -> some View {
        // Bug #163: GeometryReader gives us the SwiftUI safe-area top
        // (Dynamic Island + status-bar). Threaded into the bridge so the
        // WKWebView's scroll view positions chapter content below the
        // notch instead of clipping behind it. GeometryReader fills the
        // ZStack slot the bridge already occupies — no extra layout cost.
        GeometryReader { proxy in
            EPUBWebViewBridge(
                contentURL: contentURL,
                baseDirectory: accessRoot,
                themeCSS: settingsStore.map {
                    $0.theme.epubOverrideCSS(
                        fontSize: $0.typography.fontSize,
                        lineHeight: $0.typography.lineSpacing,
                        letterSpacing: $0.typography.cjkSpacing ? $0.typography.fontSize * 0.05 / $0.typography.fontSize : 0,
                        fontFamily: $0.typography.fontFamily
                    )
                },
                themeBackgroundColor: settingsStore?.theme.backgroundColor,
                safeAreaTopInset: proxy.safeAreaInsets.top,
                scrollFraction: seekScrollFraction,
                currentHref: viewModel.currentPosition?.href,
                fingerprintKey: fingerprintKey,
                readerToken: readerToken,
            onProgressChange: { scrollFraction in
                guard let position = viewModel.currentPosition,
                      let metadata = viewModel.metadata else { return }
                let spineIndex = metadata.spineItems.firstIndex(
                    where: { $0.href == position.href }
                ) ?? 0
                let totalProg = EPUBProgressCalculator.progress(
                    spineIndex: spineIndex,
                    scrollFraction: scrollFraction,
                    totalSpineItems: metadata.spineCount
                )
                readingProgress = totalProg
                let newPosition = EPUBPosition(
                    href: position.href,
                    progression: scrollFraction,
                    totalProgression: totalProg,
                    cfi: nil
                )
                viewModel.updatePosition(newPosition)
                // Notify ReaderContainerView of the live position for AI panel.
                if let locator = viewModel.makeCurrentLocator() {
                    NotificationCenter.default.post(
                        name: .readerPositionDidChange, object: locator
                    )
                }
            },
            onLoadError: { error in
                webViewError = error
            },
            onSelectionEvent: { event in
                pendingSelectionEvent = event
                showHighlightSheet = true
            },
            highlightActionPresenter: UIKitHighlightActionPresenter(),
            onHighlightTapAction: { [highlightCoordinator] action, id in
                await highlightCoordinator?.handleTapAction(action, highlightID: id)
            },
            onPageDidFinishLoad: { evaluateJS in
                restoreHighlightsOnLoad(evaluateJS: evaluateJS)
            },
            pendingJS: pendingHighlightJS,
            onPendingJSCompleted: {
                pendingHighlightJS = nil
            },
            isPaged: isPaged,
            paginationPage: currentPaginationPage,
            onPaginationReady: { totalPages in
                pageNavigator.totalPages = totalPages
            }
            )
            .ignoresSafeArea(edges: .bottom)
            .accessibilityIdentifier("epubReaderContent")
        }
    }

}
#endif
