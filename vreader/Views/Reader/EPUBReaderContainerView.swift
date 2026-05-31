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

    /// Feature #70 WI-3: the EPUB body font size the container injects into
    /// `epubOverrideCSS`, routed through the calibrator's `.epub` target so
    /// EPUB (CSS px in a WKWebView) renders at a size perceptually consistent
    /// with TXT (the calibration anchor) at the same slider value.
    ///
    /// Extracted as a pure static helper so the WI-3 routing seam is directly
    /// unit-testable — a regression to the raw `typography.fontSize` is caught
    /// here, not silently passed by a test that builds CSS directly.
    static func calibratedEPUBFontSize(for store: ReaderSettingsStore) -> CGFloat {
        store.calibrator.calibratedSize(
            forUnified: store.typography.fontSize, target: .epub)
    }

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
    /// Pending selection event for the note-input sheet. WI-7c5b:
    /// set when the SelectionPopover's Note action resolves; consumed
    /// by `noteInputSheet`.
    @State var pendingSelectionEvent: ReaderSelectionEvent?
    /// Feature #60 WI-7c5b: single-entry token→event cache. A
    /// long-press selection is stashed here under a `UUID`; the
    /// SelectionPopover action notification carries the token back so
    /// the DOM-path anchor (which `TextSelectionInfo` can't hold) is
    /// recovered from this cache.
    @State private var selectionTokenCache = EPUBSelectionTokenCache()
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
    /// Bug #165 / GH #489: armed by a backward chapter-wrap so the
    /// new chapter's `onPaginationReady` callback lands the user on the
    /// LAST page (design §2.2's "left-tap from first page → last page
    /// of N-1"). One-shot — consumed when pagination resolves.
    @State var chapterWrapPendingTarget = EPUBChapterWrapPendingTarget()
    /// Phase R4: highlight renderer and coordinator.
    @State var highlightRenderer = EPUBHighlightRenderer()
    @State var highlightCoordinator: HighlightCoordinator?
    /// Feature #60 WI-12 (#795): the Photo theme's user-picked background
    /// image, encoded as an inline `data:` URL for injection into the EPUB
    /// theme CSS. Recomputed by `refreshPhotoBackgroundImage()` on theme /
    /// custom-background changes — kept off the body hot path because it
    /// reads + base64-encodes a file. Nil for every theme but Photo (and
    /// for Photo with "Custom Background" off).
    @State private var photoBackgroundDataURL: URL?

    /// Feature #71 WI-6b-i: continuous cross-chapter scroll config — the window
    /// coordinator + late-binding evaluator handle, built ONCE per open (in the
    /// open `.task`) when `epubLayout == .scroll`. Nil in paged mode, before
    /// metadata loads, or for an empty spine. Passed into `EPUBWebViewBridge`;
    /// nil ⇒ the legacy one-chapter-per-`loadFileURL` path.
    // Feature #71 WI-7: `internal` (not `private`) so the
    // `+ContinuousBilingual` extension can route per-section bilingual
    // enumerate / inject JS through the live evaluator handle instead of the
    // single `pendingHighlightJS` slot (Gate-4 round-2 MEDIUM 1).
    @State var continuousScrollConfig: EPUBContinuousScrollConfig?

    // MARK: - Feature #56 WI-10: bilingual reading state

    /// The bilingual VM for the open book — created lazily once
    /// metadata has loaded so the spine list is available for the
    /// `EPUBChapterTextProvider` adapter. Nil before that point.
    @State var bilingualViewModel: BilingualReadingViewModel?

    /// Bilingual orchestrator — pure host-side coordinator that
    /// emits enumerate / inject / clear JS for the bridge. Always
    /// constructed; emits no-op JS for clear / inject when the VM
    /// is disabled.
    @State var bilingualOrchestrator = EPUBBilingualOrchestrator()

    /// Bilingual setup-sheet presentation flag mirrored from the VM's
    /// `needsSetupSheet`. SwiftUI's `.sheet(isPresented:)` needs a
    /// binding; the observer in `bilingualSurfaces` mirrors VM state
    /// into this `@State` and back.
    @State var showBilingualSetupSheet: Bool = false

    /// Mutable bilingual setup-sheet state (target language + granularity)
    /// — bound to the sheet's pickers. Confirm commits to the VM.
    @State var bilingualSetupState: BilingualSetupSheetState = .defaultValue

    /// Whether paged layout is active.
    private var isPaged: Bool {
        settingsStore?.epubLayout == .paged
    }

    var body: some View {
        ZStack {
            // Bug #214 / GH #834: scope `epubReaderContainer` to the
            // content subtree so the container identifier does not
            // propagate onto and clobber `ReaderBottomChrome`'s toolbar
            // button identifiers (`readerDisplayButton` / `readerNotesButton`).
            // Same root cause + fix as Bug #209 / GH #804 Cause B for
            // TXT/MDReaderContainerView. Scoped here it still propagates
            // onto the inner WebView — `Feature11EPUBHighlightVerificationTests`
            // looks the content view up by `epubReaderContainer` — without
            // reaching the bottom chrome, a separate ZStack sibling.
            Group {
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
            }
            .accessibilityIdentifier("epubReaderContainer")

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
                    // Feature #71 WI-6b-i: build the continuous-scroll config
                    // (window coordinator + evaluator handle) once, AFTER metadata
                    // + initial position are resolved. No-op in paged mode.
                    buildContinuousScrollConfig(resourceBase: base)
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
            // Bug #252 / GH #1089: only cancel the in-flight `openTask`
            // here — the `viewModel.close()` lifecycle moved to
            // `EPUBReaderHost.onDisappear` so a transient SwiftUI
            // re-mount of THIS container does not close the parser
            // out from under the new mount (the host's `@State`
            // viewModel + parser are shared across container instances).
            // Without this split, the disappearing instance's close
            // races the appearing instance's `parser.resourceBaseURL()`
            // and the appearing instance fails with `.notOpen`,
            // surfacing as "Failed to resolve book resources." with
            // zero EPUB log activity in the DebugBridge settle window.
            openTask?.cancel()
            openTask = nil
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
            handleSideTapNext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPreviousPage)) { _ in
            guard isPaged else { return }
            handleSideTapPrevious()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
            guard let locator = notification.object as? Locator,
                  let href = locator.href,
                  let meta = viewModel.metadata,
                  let base = resourceBase else { return }
            if let spineIndex = meta.spineItems.firstIndex(where: { $0.href == href }) {
                // WI-8: continuous scroll drives the coordinator (scroll within the
                // window, or rebuild the window around an out-of-window target)
                // instead of the single-chapter `loadFileURL` path, which the
                // bridge ignores in continuous mode. Without this, TOC / bookmark /
                // search-result jumps no-op (the WI-6b-i Critical that gated the
                // feature behind a flag). `progression` carries the intra-chapter
                // landing fraction; a search `textQuote` highlight in continuous
                // mode lands by fraction only (the find-in-section highlight is the
                // deferred GH #1200-adjacent work). The persisted position is
                // updated ONLY if the coordinator actually navigated (Gate-4
                // round-2): a jump dropped because the mutation lane was busy must
                // not move `currentPosition` while the DOM stays put.
                if let config = continuousScrollConfig {
                    let fraction = locator.progression ?? 0
                    Task {
                        if await config.coordinator.navigate(toSpineIndex: spineIndex, fraction: fraction) {
                            viewModel.navigateToSpine(index: spineIndex)
                        }
                    }
                    return
                }
                viewModel.navigateToSpine(index: spineIndex)
                webViewError = nil
                // Issue 6: Reset pagination on locator navigation (same as chapter nav).
                pageNavigator.reset()
                currentPaginationPage = nil
                // Bug #165 / GH #489 (audit round-1 finding [1] High):
                // a pending backward-chapter-wrap intent must NOT bleed
                // into an unrelated TOC / search / annotation navigation.
                // The dedicated entry point names the call-site intent.
                chapterWrapPendingTarget.cancelBecauseUnrelatedNavigationStarted()
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
        #if DEBUG
        // Bug #273: CU-free harness for WI-8 continuous-mode navigation. The
        // `navigate` DebugBridge command can't build a Locator itself (it has
        // no spine metadata / fingerprint), so it posts the spine index here;
        // we resolve index → href against the loaded metadata, build a Locator
        // with the active book's fingerprint, and re-post the SAME
        // `.readerNavigateToLocator` a real TOC/bookmark/search tap uses — so
        // the WI-8 handler above performs the jump (no parallel path).
        .onReceive(NotificationCenter.default.publisher(for: .debugBridgeNavigateCommand)) { notification in
            guard let spineIndex = notification.userInfo?["spineIndex"] as? Int,
                  let meta = viewModel.metadata,
                  spineIndex >= 0, spineIndex < meta.spineItems.count,
                  let fingerprint = DocumentFingerprint(canonicalKey: viewModel.bookFingerprintKey) else { return }
            let fraction = notification.userInfo?["fraction"] as? Double
            let href = meta.spineItems[spineIndex].href
            guard let locator = Locator.validated(
                bookFingerprint: fingerprint, href: href, progression: fraction
            ) else { return }
            NotificationCenter.default.post(name: .readerNavigateToLocator, object: locator)
        }
        #endif
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
        // Feature #60 WI-7c5b: long-press selection now surfaces
        // `SelectionPopoverView` (WI-7a) via the WI-7c1 presenter,
        // replacing the legacy Highlight / Add Note / Copy / Cancel
        // confirmationDialog. The producer (`onSelectionEvent`, in
        // `readerContent`) posts `.readerSelectionPopoverRequested`
        // with a `UUID` token; these handlers resolve the popover
        // action back to the cached `ReaderSelectionEvent`. Translate
        // routes through the parent `ReaderContainerView`'s
        // `.readerTranslateRequested` observer — no EPUB-specific
        // handler needed. Copy is intentionally dropped (plan v10:
        // consistent with TXT/MD losing the iOS-default Copy when
        // their empty `UIMenu` returned).
        .selectionPopoverPresenter(
            theme: settingsStore?.theme ?? .paper,
            // WI-7c5b: drop the cached selection when the popover
            // closes without an action — keeps the single-entry
            // cache from holding a stale `ReaderSelectionEvent`
            // until the next long-press. Idempotent on the dispatch
            // path (the action handler already consumed the entry).
            onDismiss: { selectionTokenCache.clear() }
        )
        .onReceive(NotificationCenter.default.publisher(for: .readerHighlightRequested)) { note in
            let token = note.userInfo?["selectionRequestToken"] as? UUID
            guard let event = selectionTokenCache.resolve(token: token),
                  let container = modelContainer else { return }
            handleHighlightAction(
                event: event,
                container: container,
                color: resolveHighlightColor(from: note)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerAnnotationRequested)) { note in
            let token = note.userInfo?["selectionRequestToken"] as? UUID
            guard let event = selectionTokenCache.resolve(token: token) else { return }
            pendingSelectionEvent = event
            noteText = ""
            showNoteSheet = true
        }
        .sheet(isPresented: $showNoteSheet) {
            noteInputSheet
        }
        // Feature #64 WI-8: a tap on a persisted EPUB highlight opens the
        // unified cross-format highlight-action popover (color / note / copy /
        // share / delete) — superseding feature #55's read-only note preview.
        // EPUB highlight taps arrive from the JS `highlightTapHandler`
        // channel; `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage`
        // posts `.readerHighlightTapped`, which `HighlightPopoverModifier`
        // (attached here) observes. `mutating` is the EPUB `HighlightCoordinator`
        // (over `EPUBHighlightRenderer`). Inert in SwiftUI previews / test
        // harnesses where `modelContainer` is nil.
        .unifiedHighlightPopoverPresenterIfAvailable(
            modelContainer: modelContainer,
            bookFingerprintKey: viewModel.bookFingerprintKey,
            mutating: highlightCoordinator,
            theme: settingsStore?.theme ?? .paper
        )
        // Feature #60 WI-12 (#795): keep the Photo background-image data
        // URL fresh. Driven by theme + custom-background changes — never
        // by scroll — so the file read + base64 encode stays off the
        // body hot path.
        .onAppear { refreshPhotoBackgroundImage() }
        .onChange(of: settingsStore?.theme) { _, _ in refreshPhotoBackgroundImage() }
        .onChange(of: settingsStore?.useCustomBackground) { _, _ in refreshPhotoBackgroundImage() }
        .onChange(of: settingsStore?.customBackgroundRevision) { _, _ in refreshPhotoBackgroundImage() }
        // Feature #71 WI-6b-i hard-block (Gate-4 round-2): live mode-switching is
        // not supported until WI-6b-iii (coordinator teardown + observer-script
        // swap + window rebuild). If the reader leaves `.scroll` after continuous
        // engaged, retire the config ONE-WAY this open: invalidate the coordinator
        // (cancels any in-flight materialization) and nil it so the bridge reverts
        // to the legacy single-chapter path. Re-entering `.scroll` this open lands
        // on legacy single-chapter scroll rather than a stale stitched document; a
        // fresh continuous session requires reopening the book. No-op when the
        // continuous flag is off (config was never built).
        .onChange(of: settingsStore?.epubLayout) { _, newLayout in
            if newLayout != .scroll, continuousScrollConfig != nil {
                continuousScrollConfig?.coordinator.invalidate()
                continuousScrollConfig = nil
            }
        }
        // Feature #56 WI-10: bilingual reading wiring lives in a
        // dedicated `ViewModifier` to keep this body under the
        // compiler's type-inference budget.
        .modifier(bilingualSurfacesModifier)
        // Bug #220 / GH #845 — DebugBridge highlight-driver observer.
        // DEBUG-only; attached inside the EPUB host (not the generic
        // `ReaderContainerView`) so the orchestration can JS-walk the
        // active WebView to map UTF-16 offsets to a real DOM
        // `EPUBSerializedRange`, then persist via the same
        // `HighlightCoordinator.create(...)` entry the gesture path
        // uses. Format scoping mirrors the TXT/MD observers in
        // PR #1047 — Release builds replace the modifier with an
        // `EmptyModifier` so no DebugBridge symbols leak.
        .modifier(debugBridgeHighlightObserverModifier)
        // Feature #71 WI-6b — DebugBridge scroll-boundary-driver observer.
        // DEBUG-only; lives in its own `ViewModifier` (like the highlight
        // observer above) so this body stays within the compiler's
        // type-inference budget. Release builds replace it with an
        // `EmptyModifier` so no DebugBridge symbols leak.
        .modifier(debugBridgeScrollBoundaryObserverModifier)
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

    /// Feature #60 WI-12 (#795): recomputes `photoBackgroundDataURL`, the
    /// data URL injected into the EPUB theme CSS for the Photo theme's
    /// background image. Only the Photo theme with "Custom Background"
    /// enabled carries an image; every other theme / toggle state resolves
    /// to nil so the EPUB CSS emits no `background-image` rule. Called from
    /// `.onAppear` and `.onChange` of theme + `useCustomBackground` so the
    /// file read + base64 encode never runs on a scroll-triggered body
    /// re-evaluation.
    private func refreshPhotoBackgroundImage() {
        guard let store = settingsStore,
              store.theme.usesBackgroundImage,
              store.useCustomBackground else {
            photoBackgroundDataURL = nil
            return
        }
        photoBackgroundDataURL = ThemeBackgroundStore.backgroundImageDataURL(
            for: store.theme.rawValue
        )
    }

    @ViewBuilder
    /// Feature #71 WI-6b-i: build the continuous-scroll config once per open when
    /// `epubLayout == .scroll`. Wires the WI-6a chapter provider (spine index →
    /// rewritten body) into the WI-4 window coordinator behind a fresh
    /// late-binding `EPUBWebViewEvaluatorHandle` the bridge binds to the live
    /// webView. Sets `continuousScrollConfig = nil` (legacy single-chapter path)
    /// for paged mode, an empty spine, or before metadata loads.
    @MainActor
    private func buildContinuousScrollConfig(resourceBase base: URL) {
        // Feature #71 continuous cross-chapter scroll. `FeatureFlags.epubContinuousScroll`
        // now defaults ON (terminal WI, 2026-05-28); the guard still honours an
        // explicit persisted `false` override (a user/QA who turned it off) and
        // restricts continuous mode to EPUB `.scroll` layout — paged mode keeps
        // the legacy single-chapter path. `nil` config before metadata loads or
        // when the flag/layout don't qualify.
        guard FeatureFlags.shared.epubContinuousScroll,
              settingsStore?.epubLayout == .scroll,
              let metadata = viewModel.metadata else {
            continuousScrollConfig = nil
            return
        }
        let spineItems = metadata.spineItems
        let spineCount = metadata.spineCount
        let anchorIndex: Int = {
            guard let href = viewModel.currentPosition?.href,
                  let idx = spineItems.firstIndex(where: { $0.href == href }) else {
                return 0
            }
            return idx
        }()
        guard let initialWindow = EPUBSpineWindow.initial(
            anchor: anchorIndex, spineCount: spineCount
        ) else {
            continuousScrollConfig = nil
            return
        }
        // Absolute `file://` prefix the rewriter rewrites relative resource refs
        // against (e.g. "file:///.../OEBPS/"). Ensure a trailing slash so the
        // rewriter's path join produces a valid URL.
        var prefix = base.absoluteString
        if !prefix.hasSuffix("/") { prefix += "/" }
        let provider = EPUBContinuousChapterProvider(
            spineItems: spineItems,
            parser: parser,
            resourceBaseAbsolutePrefix: prefix,
            linkedStylesheetLoader: { resolvedHref in
                // `resolvedHref` is already resource-root-relative: the rewriter
                // joins the bare `<link>` href onto the chapter's directory before
                // calling this (so a nested chapter's `../css/x.css` resolves
                // against the chapter, not the root — feature-#71 flag-flip Gate-4
                // fix). We just anchor it to the resource base and read it.
                let url = URL(fileURLWithPath: resolvedHref, relativeTo: base).standardized
                return try? String(contentsOf: url, encoding: .utf8)
            }
        )
        let handle = EPUBWebViewEvaluatorHandle()
        let coordinator = EPUBContinuousScrollCoordinator(
            initialWindow: initialWindow,
            chapterBodyProvider: provider.makeClosure(),
            evaluate: { [handle] js in try await handle.evaluate(js) },
            dividerTitle: { idx in
                guard idx >= 0, idx < spineItems.count else { return nil }
                return spineItems[idx].title
            },
            // WI-6b-iii: restore the saved intra-chapter position. `anchorIndex`
            // is the saved chapter's spine index, so the coordinator scrolls it
            // to this fraction once the initial window materializes.
            restoreFraction: viewModel.currentPosition?.progression,
            // Feature #71 WI-7 (Gate-4 round-2 MEDIUM 2): on eviction, post the
            // per-section evicted signal so the bilingual surfaces modifier
            // drops that section's stale block bucket. Captures only the book
            // key by value (no View / weak viewModel) so this long-lived
            // coordinator closure holds no View snapshot. No-op downstream when
            // bilingual is off.
            onSectionEvicted: { [bookKey = viewModel.bookFingerprintKey] spineIndex in
                NotificationCenter.default.post(
                    name: .readerBilingualSectionEvicted,
                    object: nil,
                    userInfo: ["fingerprintKey": bookKey, "spineIndex": spineIndex]
                )
            }
        )
        continuousScrollConfig = EPUBContinuousScrollConfig(
            coordinator: coordinator,
            totalSpineCount: spineCount,
            handle: handle,
            onWindowedPosition: { [weak viewModel] visibleSpineIndex, intraFraction in
                guard let viewModel,
                      visibleSpineIndex >= 0,
                      visibleSpineIndex < spineItems.count else { return }
                let href = spineItems[visibleSpineIndex].href
                let totalProg = EPUBProgressCalculator.progress(
                    spineIndex: visibleSpineIndex,
                    scrollFraction: intraFraction,
                    totalSpineItems: spineCount
                )
                let newPosition = EPUBPosition(
                    href: href,
                    progression: intraFraction,
                    totalProgression: totalProg,
                    cfi: nil
                )
                viewModel.updatePosition(newPosition)
                if let locator = viewModel.makeCurrentLocator() {
                    NotificationCenter.default.post(
                        name: .readerPositionDidChange, object: locator
                    )
                }
            },
            // WI-6b-ii: a chapter section was stitched in. Appended sections
            // never fire `didFinish`, so restore THIS section's highlights here,
            // re-rooted into the section via `__vreader_createHighlightInSection`.
            // Captures the book key + container by value (not the View / weak
            // viewModel) so the long-lived config closure holds no View snapshot.
            onSectionMaterialized: { [handle, container = modelContainer, bookKey = viewModel.bookFingerprintKey] spineIndex, href in
                // Feature #71 WI-7: post the per-section materialize signal so
                // the bilingual surfaces modifier (which has View context) can
                // drive a SECTION-SCOPED enumerate for THIS stitched chapter
                // without this long-lived config closure capturing the View.
                // The enumerate namespaces bids `s{N}b…` and tags each posted
                // block `sectionIndex: N`, so translations inject per section
                // with no cross-section bid bleed. No-op downstream when
                // bilingual is off.
                NotificationCenter.default.post(
                    name: .readerBilingualSectionMaterialized,
                    object: nil,
                    userInfo: ["fingerprintKey": bookKey, "spineIndex": spineIndex]
                )
                guard let container else { return }
                Task { @MainActor in
                    let persistence = PersistenceActor(modelContainer: container)
                    let highlights = (try? await persistence.fetchHighlights(
                        forBookWithKey: bookKey
                    )) ?? []
                    let js = EPUBHighlightActions.restoreHighlightsInSectionJS(
                        highlights: highlights, href: href, spineIndex: spineIndex
                    )
                    if !js.isEmpty { try? await handle.evaluate(js) }
                }
            }
        )
    }

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
                // Feature #60 WI-4/WI-11: route through ReaderThemeV2's
                // 5-token surface. WI-11 migrated `ReaderSettingsStore.theme`
                // to `ReaderThemeV2`, so `epubOverrideCSS` is read directly
                // off the stored theme — Paper / Sepia / Dark / OLED / Photo.
                themeCSS: settingsStore.map {
                    $0.theme.epubOverrideCSS(
                        // Feature #70 WI-3: route the EPUB body font size
                        // through the calibrator's `.epub` target (see
                        // `calibratedEPUBFontSize(for:)`) so EPUB (CSS px in
                        // a WKWebView) renders at a size perceptually
                        // consistent with TXT (the anchor) at the same
                        // slider value. Clamped to the 12...64 text band.
                        fontSize: Self.calibratedEPUBFontSize(for: $0),
                        lineHeight: $0.typography.lineSpacing,
                        letterSpacing: $0.typography.cjkSpacing ? $0.typography.fontSize * 0.05 / $0.typography.fontSize : 0,
                        fontFamily: $0.typography.fontFamily,
                        // Feature #60 WI-12 (#795): the Photo theme's
                        // background image. Cached in `@State` (see
                        // `refreshPhotoBackgroundImage`) — nil for every
                        // other theme, so `epubOverrideCSS` emits no
                        // background-image rule.
                        backgroundImageURL: photoBackgroundDataURL
                    )
                },
                themeBackgroundColor: settingsStore?.theme.backgroundColor,
                safeAreaTopInset: proxy.safeAreaInsets.top,
                scrollFraction: seekScrollFraction,
                currentHref: viewModel.currentPosition?.href,
                fingerprintKey: fingerprintKey,
                readerToken: readerToken,
            onProgressChange: { scrollFraction in
                // Feature #71 WI-6b-i: in continuous mode the bridge already
                // sends WHOLE-BOOK progress (the section-aware observer folds in
                // the spine offset), and the persisted position is updated via
                // `onWindowedPosition` (visibleSpineIndex + intraFraction). Drive
                // ONLY the scrubber here — re-deriving from `currentPosition.href`
                // would double-count the spine offset.
                if continuousScrollConfig != nil {
                    readingProgress = scrollFraction
                    return
                }
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
                // Feature #60 WI-7c5b: cache the EPUB selection under
                // a fresh token, then post `.readerSelectionPopoverRequested`.
                // The popover's action notification carries the token
                // back so the DOM-path anchor — which `TextSelectionInfo`
                // can't represent — is recovered from `selectionTokenCache`.
                // `startUTF16` / `endUTF16` are placeholder (the popover
                // only displays `selectedText`); the real anchor lives
                // in the cached `ReaderSelectionEvent`.
                let token = selectionTokenCache.store(event)
                let info = TextSelectionInfo(
                    selectedText: event.selectedText,
                    startUTF16: 0,
                    endUTF16: event.selectedText.utf16.count
                )
                SelectionPopoverRequest.post(selection: info, requestToken: token)
            },
            // Feature #56 WI-10: the bridge posts blocks parsed from
            // the JS `bilingualEnumerate` channel. The orchestrator
            // stores them; the VM prefetches translation for the
            // current unit; on `.readerBilingualDidChange` the
            // observer builds the inject JS and pushes it through
            // `pendingHighlightJS`.
            onBilingualEnumerate: { payload in
                handleBilingualEnumeratePayload(payload)
            },
            // Feature #64 WI-8: the EPUB highlight tap still posts
            // `.readerHighlightTapped` (from the JS `highlightTapHandler`
            // channel via `EPUBWebViewBridgeCoordinator.handleHighlightTapMessage`),
            // now observed by the unified highlight-action popover
            // (`HighlightPopoverModifier` on the container) — color / note /
            // copy / share / delete. There is no EPUB-specific action
            // presenter to wire: the web host never carried feature #53's
            // long-press inline menu, so the bridge takes no
            // `highlightActionPresenter` / `onHighlightTapAction`.
            onPageDidFinishLoad: { evaluateJS in
                restoreHighlightsOnLoad(evaluateJS: evaluateJS)
                // Feature #56 WI-10: re-enumerate translatable blocks
                // on every chapter load so the orchestrator's block
                // list matches the live DOM. Idempotent: re-stamping
                // an already-stamped block keeps the existing
                // `data-vreader-bid`.
                //
                // Codex Gate-4 round-3 finding [R3-1]: also gate on
                // `!showBilingualSetupSheet` so a chapter load that
                // happens WHILE the first-enable setup sheet is open
                // (rare but possible — a notification-driven nav,
                // or a re-render of the same chapter) does not
                // enumerate ahead of the user's confirm. The
                // confirm path pushes its own enumerate.
                //
                // Feature #71 WI-7 (Gate-4 round-3 HIGH 1): the GLOBAL
                // (paged) enumerate must NEVER run in continuous-scroll
                // mode. In continuous mode `didFinish` fires for the
                // bootstrap doc (empty body OR the whole stitched DOM);
                // a global enumerate posts an UNTAGGED payload that
                // routes through the paged `updateBlocks(_:)` and
                // clobbers the per-section buckets (or creates a flat
                // `-1` cache). Continuous enumerate is driven PER SECTION
                // off `.readerBilingualSectionMaterialized`
                // (`enumerateBilingualSection(spineIndex:)`), so gate the
                // global enumerate to paged mode only.
                // The continuous-mode test mirrors the bridge's own
                // `continuousScroll: isPaged ? nil : continuousScrollConfig`
                // gate exactly (a stale config under a paged layout is NOT
                // continuous), so the global enumerate runs iff the bridge is
                // actually rendering one-chapter-per-document.
                let isContinuous = (isPaged ? nil : continuousScrollConfig) != nil
                if bilingualViewModel?.isEnabled == true,
                   !showBilingualSetupSheet,
                   !isContinuous {
                    evaluateJS(bilingualOrchestrator.enumerateJS())
                }
            },
            pendingJS: pendingHighlightJS,
            onPendingJSCompleted: {
                pendingHighlightJS = nil
            },
            // Feature #71 WI-6b-i: non-nil only in continuous (scroll) mode —
            // the bridge then loads the bootstrap doc + stitches chapter
            // sections instead of one-chapter-per-loadFileURL. Guarded by
            // `!isPaged` so a stale config can't leak into paged mode.
            continuousScroll: isPaged ? nil : continuousScrollConfig,
            isPaged: isPaged,
            paginationPage: currentPaginationPage,
            onPaginationReady: { totalPages, resumePage in
                pageNavigator.totalPages = totalPages
                // Bug #165 / GH #489: a backward chapter-wrap armed
                // `chapterWrapPendingTarget`; now that the new chapter
                // has settled, land on its LAST page so the user
                // continues reading where the previous chapter left
                // off (design §2.2).
                if let landingPage = chapterWrapPendingTarget.consume(
                    totalPages: totalPages
                ) {
                    pageNavigator.jumpToPage(landingPage)
                    currentPaginationPage = landingPage
                    // Bug #281 / GH #1258: a backward chapter-wrap lands on the
                    // new chapter's LAST page; record that within-chapter
                    // position so progress reflects it (not page 0).
                    recordPagedProgress()
                } else if let resumePage, resumePage > 0 {
                    // Bug #293 / GH #1301: reopening to a persisted within-
                    // chapter position. Sync the Swift page state — setting
                    // `currentPaginationPage` drives the JS nav through
                    // `updateUIView`, and `pageNavigator.currentPage` stays
                    // correct so the next side-tap pages from `resumePage`,
                    // not page 0.
                    pageNavigator.jumpToPage(resumePage)
                    currentPaginationPage = resumePage
                    recordPagedProgress()
                }
            }
            )
            .ignoresSafeArea(edges: .bottom)
            .accessibilityIdentifier("epubReaderContent")
        }
    }

}
#endif
