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
    // Bug #237 (DEBUG): `internal` (was `private`) so the
    // `+DebugBridgeHighlight` extension can read the coordinator when
    // dispatching `vreader-debug://highlight`. Production gesture path
    // also reads it via `ReaderNotificationModifier` (same file).
    @State var highlightCoordinator: HighlightCoordinator?
    /// TTS sentence highlighting + auto-scroll coordinator (features #40, #41).
    @State private var ttsHighlightCoordinator: TTSHighlightCoordinator?

    // MARK: - Feature #56 WI-12: bilingual reading state
    //
    // Owned here so SwiftUI's lifecycle frees the VM on container
    // teardown. The wiring lives in `MDReaderContainerView+Bilingual.swift`.
    @State var bilingualViewModel: BilingualReadingViewModel?
    @State var showBilingualSetupSheet: Bool = false
    @State var bilingualSetupState: BilingualSetupSheetState = .defaultValue

    /// Whether paged mode is active.
    private var isPagedMode: Bool {
        settingsStore?.epubLayout == .paged
    }

    var body: some View {
        ZStack {
            // Bug #209 / GH #804: scope `mdReaderContainer` to the content
            // subtree so the container identifier does not propagate onto
            // and clobber `ReaderBottomChrome`'s toolbar button identifiers
            // (`readerDisplayButton` etc.). See TXTReaderContainerView.
            Group {
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
            }
            .accessibilityIdentifier("mdReaderContainer")

            // Bottom overlay for progress, scrubber, and session time (WI-004b)
            // Hidden when TTS is active to avoid overlap (bug #97)
            if viewModel.renderedText != nil && !viewModel.isLoading && isChromeVisible
                && (ttsService?.state ?? .idle) == .idle {
                // Feature #60 WI-6b: shared bottom chrome (scrubber +
                // labels + Contents/Notes/Display/AI toolbar) replaces
                // the legacy ReadingProgressBar + ReaderBottomOverlay.
                ReaderBottomChrome(
                    theme: settingsStore?.theme ?? .paper,
                    progress: $uiState.readingProgress,
                    onSeek: { seekValue in
                        let charOffset = ScrollProgressHelper.charOffsetFromProgress(
                            progress: seekValue,
                            totalLengthUTF16: viewModel.renderedTextLengthUTF16
                        )
                        uiState.scrollToOffset = charOffset
                    },
                    // Bug #215 / GH #837 — design §3.2: in paged mode the
                    // chrome's leading label is the single source of truth
                    // for the page count; the content-bottom indicator only
                    // appears when chrome is hidden. Scroll mode keeps the
                    // legacy percentage label (no page concept).
                    leadingLabel: pagedLeadingLabel(),
                    trailingLabel: viewModel.sessionTimeDisplay ?? ""
                )
            }
        }
        // Feature #60 WI-7c4: present `SelectionPopoverView` (WI-7a)
        // when a long-press selection finishes in MD. MD's SCROLL mode
        // renders via the shared `TXTTextViewBridge` whose coordinator's
        // `editMenuForTextIn` was swapped to post
        // `.readerSelectionPopoverRequested` in WI-7c2; this modifier
        // observes the notification and shows the sheet, mirroring the
        // TXT container's attachment from WI-7c2. Bug #218 scope facet on
        // Bug #215 (this file's row): MD's PAGED mode renders
        // `NativeTextPagedView` (a plain `UITextView`, no `TXTTextViewBridge`
        // and no editMenu swap), so the selection-popover producer is
        // currently absent in paged MD and the iOS system edit menu shows
        // instead. Tracked as the open paged-mode selection-popover facet
        // on Bug #215 — separate fix scope.
        .selectionPopoverPresenter(theme: settingsStore?.theme ?? .paper)
        // Feature #64 WI-6: a tap on a highlight opens the unified
        // highlight-action popover — superseding feature #55's note preview
        // and feature #53's long-press delete `UIMenu`. MD's SCROLL mode
        // routes through the shared `TXTTextViewBridge`'s tap recognizer,
        // which posts `.readerHighlightTapped`. MD's PAGED mode (Bug #215
        // wiring) routes the bridge-equivalent tap recognizer on
        // `NativePagedContainer` through `ReaderTapZoneRouter` (page-turn
        // / chrome-toggle, no highlight hit-test yet — same Bug #218 facet
        // as the selection-popover producer above).
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
        // attached inside the MD host so the helper can build MD-shaped
        // Locators via LocatorFactory.mdRange and re-paint atomically via
        // HighlightCoordinator.create — the gesture path's full posture.
        // Audit Round-1 High #1 / #2 fix.
        .modifier(debugBridgeHighlightObserverModifier)
        .task {
            // PERF: open already called by MDReaderHost
            if viewModel.renderedText == nil {
                // Bug #178 / GH #606: forward chineseConversion so the
                // MD render pipeline applies SimpTradTransform to the
                // source text before parsing. Live re-apply on toggle
                // requires close+reopen (out of scope for the silent-
                // noop fix; documented limitation).
                // Feature #68: forward the theme-aware mdRenderConfig so
                // the MD body colors AND the chapter-start drop-cap /
                // leading-heading restyle pick up the active theme. MD has
                // no live theme re-render path — these colors apply on the
                // next open of the file (see MDReaderViewModel.open).
                // Feature #54 WI-7: fetch the enabled content replacement
                // rules scoped to this book and forward them so the MD
                // render pipeline applies them to the source text before
                // parsing. Replaces the retired Unified-mode replacement-
                // rule path. Like Chinese conversion, a mid-book rule
                // change re-applies only on the next open.
                let rules = await MDReplacementRuleFetcher.rules(
                    container: modelContainer,
                    bookKey: viewModel.bookFingerprintKey
                )
                await viewModel.open(
                    url: fileURL,
                    renderConfig: settingsStore?.mdRenderConfig ?? .default,
                    chineseConversion: settingsStore?.chineseConversion ?? .none,
                    replacementRules: rules
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
        // Bug #215 / GH #837 — design: dev-docs/designs/vreader-fidelity-v1/
        // project/design-notes/reader-navigation.md §3.
        //
        // §3.1 chrome-aware content inset: the bottom-of-screen chrome
        // (`ReaderBottomChrome`) is an opaque overlay, not a sibling sized
        // to take real estate. Without an explicit bottom padding the paged
        // page renders UNDER the chrome and the last 1–2 lines + the page
        // indicator are occluded ("clipped mid-line" symptom). The padding
        // is chrome-aware: when chrome is visible we reserve roughly the
        // chrome's height + the design's 8pt breath above its hairline rule;
        // when chrome is hidden we leave only 56pt (the design's "no
        // duplicate indicator" baseline) so the page extends to the edge.
        //
        // §3.2 de-duplicated page indicator: when chrome is visible, the
        // chrome's leading label already surfaces the page count — hide the
        // content-bottom indicator to avoid duplicating it. When chrome is
        // hidden, show the indicator at the page edge in compact "X / Y"
        // form (the design's preferred chrome-hidden format).
        //
        // GeometryReader threads the measured `NativeTextPagedView` box
        // through `updatePagination` so pagination matches the renderer's
        // actual size (Cause 1 in the bug doc: `UIScreen.main.bounds.size`
        // packed too many glyphs per page; mis-sized pages truncated
        // mid-line).
        GeometryReader { proxy in
            VStack(spacing: 0) {
                NativeTextPagedView(
                    navigator: navigator,
                    fullText: attributedString.string,
                    fullAttributedText: attributedString,
                    config: settingsStore?.txtViewConfig ?? TXTViewConfig(),
                    currentPage: uiState.pagedCurrentPage,
                    pageTurnAnimation: settingsStore?.pageTurnAnimation ?? .none,
                    layout: settingsStore?.epubLayout
                )

                if navigator.totalPages > 0 && !isChromeVisible {
                    Text("\(uiState.pagedCurrentPage + 1) / \(navigator.totalPages)")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.bottom, 4)
                        .accessibilityIdentifier("mdPageIndicator")
                }
            }
            .padding(.bottom, Self.pagedBottomPadding(chromeVisible: isChromeVisible))
            .onAppear {
                updatePaginationIfNeeded(
                    viewportSize: Self.paginatorViewportSize(
                        proxy: proxy.size, chromeVisible: isChromeVisible
                    )
                )
            }
            .onChange(of: proxy.size) { _, newSize in
                updatePaginationIfNeeded(
                    viewportSize: Self.paginatorViewportSize(
                        proxy: newSize, chromeVisible: isChromeVisible
                    )
                )
            }
            // Codex audit Round-1 High #2: chrome toggle changes the
            // textView's usable height (the VStack's `.padding(.bottom, …)`
            // resolves to a different value, the indicator appears, etc.).
            // Re-paginate when chrome visibility flips so the page
            // boundaries stay in sync with what the renderer actually
            // displays.
            .onChange(of: isChromeVisible) { _, newValue in
                updatePaginationIfNeeded(
                    viewportSize: Self.paginatorViewportSize(
                        proxy: proxy.size, chromeVisible: newValue
                    )
                )
            }
        }
        .accessibilityIdentifier("mdReaderPagedContent")
    }

    /// Bug #215 / GH #837 — Codex audit Round-1 High #1: computes the
    /// EFFECTIVE per-page viewport for the paginator, accounting for the
    /// VStack's chrome-aware bottom padding, the page indicator's reserved
    /// height when chrome is hidden, and the paged textView's
    /// `textContainerInset` (16pt all sides). The paginator's
    /// `NSTextContainer` is sized to match the renderer's interior text
    /// box — pages computed at this size land exactly inside the rendered
    /// textView with no mid-line truncation.
    ///
    /// Extracted `static` so the formula is unit-testable and lockable.
    /// Width: `proxy.width - 2 × textInset` (horizontal inset is unchanged
    /// by chrome / indicator). Height: `proxy.height - bottomPadding -
    /// indicatorReserved - 2 × textInset`. `indicatorReserved` is 24pt
    /// when chrome is hidden (the indicator's font.caption text + 4pt
    /// bottom padding, ≈20pt total, rounded to 24 for safety) and 0pt
    /// when chrome is visible (the indicator is hidden by `if !isChromeVisible`).
    /// Clamped to a positive minimum so the paginator never receives a
    /// degenerate size.
    static func paginatorViewportSize(
        proxy: CGSize,
        chromeVisible: Bool
    ) -> CGSize {
        let bottomPad = pagedBottomPadding(chromeVisible: chromeVisible)
        let indicatorHeight: CGFloat = chromeVisible ? 0 : 24
        let inset = NativePagedContainer.textInset
        let width = max(proxy.width - 2 * inset, 1)
        let height = max(proxy.height - bottomPad - indicatorHeight - 2 * inset, 1)
        return CGSize(width: width, height: height)
    }

    /// Bug #215 / GH #837 — design §3.2: in paged mode the chrome's leading
    /// label is the single source of truth for the page count
    /// ("Page X of Y"); scroll mode keeps the legacy percentage label.
    /// Falls back to the percentage when paged mode is on but the navigator
    /// hasn't paginated yet (zero total pages) — the chrome stays
    /// informative across the first-render transition rather than showing
    /// a spurious "Page 1 of 0".
    private func pagedLeadingLabel() -> String {
        if isPagedMode, let nav = uiState.pageNavigator, nav.totalPages > 0 {
            return "Page \(uiState.pagedCurrentPage + 1) of \(nav.totalPages)"
        }
        return ScrollProgressHelper.percentageLabel(uiState.readingProgress)
    }

    /// Bug #215 design §3.1: chrome-aware content inset.
    /// - chrome visible → reserve `chromeHeight + 8` (the design's breath
    ///   above the chrome's hairline rule). `ReaderBottomChrome`'s actual
    ///   measured height varies per device safe-area; the bug doc reported
    ///   ≈128pt on iPhone 17 Pro Sim. We use 128 as a deterministic baseline
    ///   matching the design's measurement and add the 8pt breath. On home-
    ///   indicator devices the bottom safe-area inset already extends the
    ///   chrome higher; the same `+8` breath still applies, so the constant
    ///   stays correct across device classes.
    /// - chrome hidden → 56pt (the design's baseline) so the page extends
    ///   close to the edge with room for the compact page indicator.
    ///
    /// Extracted `static` so a unit test can lock the formula without
    /// touching the view hierarchy.
    static func pagedBottomPadding(chromeVisible: Bool) -> CGFloat {
        chromeVisible ? 128 + 8 : 56
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
                delegate: viewModel,
                // Bug #239 — gate side-tap → page-turn dispatch in the
                // bridge's tap recognizer on the current paged/scroll layout.
                // MD scroll mode collapses to chrome-toggle; MD paged mode
                // (when wired) produces `.readerNextPage` /
                // `.readerPreviousPage`.
                layout: settingsStore?.epubLayout
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

    /// Bug #215 / GH #837: optional `viewportSize` threads the measured
    /// `NativeTextPagedView` box from the `pagedReaderContent`'s
    /// `GeometryReader` into the paginator. Callers without a measured size
    /// (the `.task` block at first appearance, or the `.onChange(of:
    /// epubLayout / font)` handlers) fall through to the default
    /// `UIScreen.main.bounds.size` — a re-paginate fires from
    /// `pagedReaderContent`'s `.onAppear` / `.onChange(of: proxy.size)`
    /// the moment the GeometryReader measures, so the wrong-size paginate
    /// is corrected within the same render cycle.
    private func updatePaginationIfNeeded(viewportSize: CGSize? = nil) {
        if let viewportSize {
            uiState.updatePagination(
                isPagedMode: isPagedMode,
                attributedText: viewModel.renderedAttributedString,
                initialRestoreOffset: initialRestoreOffset,
                autoPageTurnEnabled: settingsStore?.autoPageTurn ?? false,
                autoPageTurnInterval: settingsStore?.autoPageTurnInterval ?? 5.0,
                viewportSize: viewportSize
            )
        } else {
            uiState.updatePagination(
                isPagedMode: isPagedMode,
                attributedText: viewModel.renderedAttributedString,
                initialRestoreOffset: initialRestoreOffset,
                autoPageTurnEnabled: settingsStore?.autoPageTurn ?? false,
                autoPageTurnInterval: settingsStore?.autoPageTurnInterval ?? 5.0
            )
        }
        if let offset = uiState.syncPagedState() {
            viewModel.updateScrollPosition(charOffsetUTF16: offset)
        }
    }

}
#endif
