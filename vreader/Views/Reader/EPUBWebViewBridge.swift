// Purpose: WKWebView bridge for rendering EPUB XHTML content.
// Loads spine item HTML files with resource access to the extracted EPUB directory.
//
// Key decisions:
// - Uses loadFileURL with allowingReadAccessTo for local CSS/image resources.
// - allowingReadAccessTo uses the extracted root (not opfDir) to cover all resources.
// - Injects JavaScript to report scroll progress back to Swift (throttled at 100ms).
// - Supports scroll-to-fraction via JS injection for intra-chapter seeking.
// - Injects selection tracking and highlight API JS for text highlighting (WI-007).
// - Supports paged layout via CSS multi-column pagination (WI-B06).
//   In paged mode, pagination CSS is injected and navigation uses scrollLeft.
// - Coordinator handles WKScriptMessageHandler for progress, tap, and selection callbacks.
// - Navigation delegate reports load errors to the container via onLoadError.
// - Only file:// URLs are allowed for all navigation types.
//
// @coordinates-with: EPUBWebViewBridgeJS.swift, EPUBWebViewBridgeCoordinator.swift,
//   EPUBReaderContainerView.swift, EPUBReaderViewModel.swift,
//   EPUBHighlightBridge.swift, EPUBPaginationHelper.swift

#if canImport(UIKit)
import SwiftUI
import WebKit

/// Weak proxy to break the retain cycle between WKUserContentController and Coordinator.
/// WKUserContentController.add(_:name:) retains the handler strongly; this proxy
/// holds the real handler weakly so the Coordinator can be deallocated.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

/// UIViewRepresentable bridge for EPUB content rendering via WKWebView.
struct EPUBWebViewBridge: UIViewRepresentable {
    /// URL of the XHTML file to load.
    let contentURL: URL
    /// Base directory for resolving relative resources (CSS, images).
    /// Should be the extracted EPUB root directory for widest access.
    let baseDirectory: URL
    /// Optional CSS `<style>` tag to inject for theme overrides.
    var themeCSS: String?
    /// Bug #167: opaque background color for the WKWebView's scroll view, so
    /// the rubber-band overscroll area paints in the current theme color
    /// instead of falling through to the host UIView (white by default).
    /// `nil` preserves the prior `.clear` behaviour for any caller that
    /// hasn't yet been threaded through.
    var themeBackgroundColor: UIColor?
    /// Bug #163: top safe-area inset (typically the Dynamic Island /
    /// status-bar safe area). Threaded in from the SwiftUI container so
    /// the WKWebView's scroll view positions chapter content below the
    /// notch. Default 0 preserves prior (broken) behaviour for any caller
    /// that hasn't been wired through. Negative values clamp to 0 inside
    /// the seam.
    var safeAreaTopInset: CGFloat = 0
    /// Scroll fraction (0.0-1.0) to scroll to after the chapter loads.
    /// Set by the container view when seeking within a chapter.
    var scrollFraction: Double?
    /// Current chapter href for anchor construction in selection events.
    var currentHref: String?
    /// Bug #126: book identity for the DebugBridge eval registry binding.
    /// Threaded through to the Coordinator so `webView(_:didFinish:)` can
    /// register `(webView, fingerprintKey)` together — preventing a late
    /// didFinish from an outgoing book from being matched against an
    /// incoming reader's eval call.
    var fingerprintKey: String?
    /// Bug #142: per-reader instance token. Generated once in
    /// `ReaderContainerView.onAppear` and threaded alongside
    /// `fingerprintKey`. Required to disambiguate the same-book reopen
    /// race where a late `didFinish` from an outgoing webview can
    /// re-register itself under the same key after the new reader
    /// already registered. The registry's `epubWebView(for:token:)`
    /// requires both to match.
    var readerToken: UUID?
    /// Called when scroll progress changes (0.0...1.0).
    let onProgressChange: @MainActor (Double) -> Void
    /// Called when WKWebView fails to load content.
    let onLoadError: @MainActor (String) -> Void
    /// Called when the user selects text in the EPUB content.
    var onSelectionEvent: (@MainActor (ReaderSelectionEvent) -> Void)?
    /// Feature #56 WI-10: receives the `[{bid, text}]` payload posted
    /// by `EPUBBilingualJS.bilingualEnumerateJS` after a chapter
    /// loads. Optional — call sites that don't enable bilingual mode
    /// simply leave it `nil` and the handler short-circuits inside
    /// the coordinator.
    var onBilingualEnumerate: (@MainActor ([BilingualBlock]) -> Void)?
    /// Called after a page finishes loading (for highlight restoration).
    /// The closure receives a JS evaluator that runs JavaScript on the WKWebView.
    var onPageDidFinishLoad: (@MainActor (@escaping (String) -> Void) -> Void)?
    /// JavaScript to evaluate on next updateUIView cycle.
    /// Container sets this to inject highlight JS after persist.
    /// Bridge evaluates it and the container should clear via onPendingJSCompleted.
    var pendingJS: String?
    /// Called after pendingJS has been evaluated so the container can clear state.
    var onPendingJSCompleted: (@MainActor () -> Void)?
    /// Feature #71 WI-5: continuous cross-chapter scroll config. `nil` ⇒ the
    /// legacy one-chapter-per-`loadFileURL` path (paged + the existing
    /// single-chapter scroll behaviour), unchanged. When non-nil, `makeUIView`
    /// injects the section-aware observer (in place of `progressTrackingJS`),
    /// registers the `continuousScrollHandler` channel, and the coordinator
    /// routes each boundary signal to `config.coordinator` (window transitions)
    /// while feeding the windowed spine-index + fraction to `onProgressChange`.
    var continuousScroll: EPUBContinuousScrollConfig?
    /// Whether paged layout is enabled (CSS multi-column pagination).
    var isPaged: Bool = false
    /// Page index to navigate to in paged mode (0-based).
    var paginationPage: Int?
    /// Called when pagination is set up with total page count (paged mode only).
    var onPaginationReady: (@MainActor (Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgressChange: onProgressChange, onLoadError: onLoadError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Inject foliate-js bridge (CFI, overlayer, TTS, footnotes)
        if let bridgeURL = Bundle.main.url(forResource: "foliate-bridge", withExtension: "js", subdirectory: nil)
            ?? Bundle.main.url(forResource: "foliate-bridge", withExtension: "js"),
           let bridgeSource = try? String(contentsOf: bridgeURL) {
            let bridgeScript = WKUserScript(
                source: bridgeSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            userContentController.addUserScript(bridgeScript)
        }

        // Inject CSS preprocessing (foliate-js pattern)
        let preprocessScript = WKUserScript(
            source: Self.cssPreprocessJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(preprocessScript)

        let weakHandler = WeakScriptMessageHandler(context.coordinator)
        // Feature #71 WI-5: mode-branched scroll observer. In continuous-scroll
        // mode the section-aware observer (reporting {visibleSpineIndex,
        // intraFraction, nearTop/BottomBoundary}) REPLACES the single-document
        // `progressTrackingJS` so the two don't both fire on the stitched
        // bootstrap doc and race the windowed progress (Gate-2 round-1 [H3]).
        // The nil-config (legacy paged + single-chapter scroll) path is byte-
        // identical to before.
        if continuousScroll != nil {
            let observerScript = WKUserScript(
                source: EPUBContinuousScrollJS.continuousScrollObserverJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            userContentController.addUserScript(observerScript)
            userContentController.add(weakHandler, name: "continuousScrollHandler")
        } else {
            // Add scroll progress tracking script (throttled)
            let script = WKUserScript(
                source: Self.progressTrackingJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            userContentController.addUserScript(script)
            userContentController.add(weakHandler, name: "progressHandler")
        }

        // Add content tap tracking for toolbar toggle
        let tapScript = WKUserScript(
            source: Self.contentTapTrackingJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(tapScript)
        userContentController.add(weakHandler, name: "contentTapHandler")

        // Add selection tracking and highlight API JS (WI-007)
        let selectionScript = WKUserScript(
            source: EPUBHighlightBridge.selectionTrackingJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(selectionScript)
        userContentController.add(weakHandler, name: "selectionChanged")
        // Footnote detection handler (foliate-js)
        userContentController.add(weakHandler, name: "footnoteHandler")
        // Feature #53 WI-4: tap-on-highlight handler. Receives
        // `{id, rect}` payloads when the user taps an existing
        // highlight in the EPUB WKWebView.
        userContentController.add(weakHandler, name: "highlightTapHandler")

        let highlightScript = WKUserScript(
            source: EPUBHighlightBridge.highlightAPIJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(highlightScript)

        // Feature #56 WI-10: register the `bilingualEnumerate`
        // channel so the chapter-load enumerate JS can post its
        // `[{bid, text}]` payload back to Swift. Idempotent for
        // call sites that never run the enumerate JS — an unused
        // handler costs only the message-handler registration.
        userContentController.add(
            weakHandler,
            name: EPUBBilingualJS.enumerateMessageHandlerName
        )

        config.userContentController = userContentController
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        // Bug #167 wiring: keep this call. The seam itself is unit-tested in
        // EPUBWebViewBridgeTests; deleting this line would silently re-introduce
        // the white-bleed regression because the call-site wiring is not
        // covered by tests (representable-context plumbing is too deep to mock).
        Self.applyScrollViewBackground(to: webView.scrollView, color: themeBackgroundColor)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Bug #163 wiring: keep this call. The seam is unit-tested in
        // EPUBWebViewBridgeSafeAreaInsetTests; deleting this line would
        // silently re-introduce content clipped behind the Dynamic Island
        // because representable-context plumbing isn't covered by tests.
        Self.applySafeAreaTopInset(to: webView.scrollView, top: safeAreaTopInset)
        context.coordinator.safeAreaTopInset = safeAreaTopInset
        context.coordinator.themeCSS = themeCSS
        context.coordinator.themeBackgroundColor = themeBackgroundColor
        context.coordinator.allowedRoot = baseDirectory
        context.coordinator.currentHref = currentHref
        #if DEBUG
        context.coordinator.fingerprintKey = fingerprintKey
        context.coordinator.readerToken = readerToken
        #endif
        context.coordinator.onSelectionEvent = onSelectionEvent
        context.coordinator.onBilingualEnumerate = onBilingualEnumerate
        context.coordinator.onPageDidFinishLoad = onPageDidFinishLoad
        context.coordinator.isPaged = isPaged
        context.coordinator.previousIsPaged = isPaged
        context.coordinator.onPaginationReady = onPaginationReady
        context.coordinator.continuousScroll = continuousScroll
        // Feature #71 WI-6b-i: bind the late-binding evaluator handle to this
        // freshly-created webView so the coordinator's `evaluate` closure (which
        // captured the same handle) can stitch chapter sections into it. The
        // bootstrap load in `updateUIView` happens after this, and the bootstrap's
        // `didFinish` triggers the coordinator's initial materialize — by then the
        // handle's `webView` is bound.
        continuousScroll?.handle.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.accessibilityIdentifier = "epubWebView"

        // Disable vertical scrolling in paged mode
        if isPaged {
            webView.scrollView.isScrollEnabled = false
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Keep coordinator in sync with current props
        context.coordinator.currentHref = currentHref
        #if DEBUG
        context.coordinator.fingerprintKey = fingerprintKey
        context.coordinator.readerToken = readerToken
        #endif
        context.coordinator.onSelectionEvent = onSelectionEvent
        context.coordinator.onBilingualEnumerate = onBilingualEnumerate
        context.coordinator.onPageDidFinishLoad = onPageDidFinishLoad
        context.coordinator.isPaged = isPaged
        context.coordinator.onPaginationReady = onPaginationReady
        context.coordinator.continuousScroll = continuousScroll

        // Update scroll enabled state when layout mode changes
        webView.scrollView.isScrollEnabled = !isPaged

        // Feature #71 WI-6b-i: continuous mode loads ONE bootstrap document and
        // then stitches chapter sections into it via the coordinator's evaluator
        // (driven from the bootstrap's `didFinish`). The single-chapter
        // `loadFileURL` path below never runs in this mode. Load the bootstrap
        // exactly once — re-loading would wipe the stitched DOM. (Live theme
        // re-inject + mode-switch teardown are WI-6b-iii.)
        if continuousScroll != nil {
            if !context.coordinator.didLoadContinuousBootstrap {
                context.coordinator.didLoadContinuousBootstrap = true
                loadContinuousBootstrap(into: webView)
            }
            // Deliberately do NOT record `currentURL` here. Leaving it unchanged
            // means a later switch OUT of continuous mode (→ paged) sees
            // `currentURL != contentURL`, so the legacy path force-reloads the
            // real chapter and wipes the stitched bootstrap. (Full mode-switch
            // teardown — coordinator generation bump + observer-script swap — is
            // WI-6b-iii; this only guarantees the DOM is replaced on switch.)
            return
        }

        // Issue 5: When isPaged toggles without a URL change, inject/remove pagination CSS live.
        let isPagedChanged = context.coordinator.previousIsPaged != isPaged
        context.coordinator.previousIsPaged = isPaged
        if isPagedChanged, context.coordinator.currentURL == contentURL {
            if isPaged {
                context.coordinator.setupPagination(webView: webView)
            } else {
                webView.evaluateJavaScript(EPUBPaginationHelper.removePaginationCSSJS) { _, error in
                    if let error { AppLogger.epub.error("remove pagination CSS error: \(error)") }
                }
            }
        }

        // Only reload if the URL changed
        let urlIsChanging = context.coordinator.currentURL != contentURL
        if urlIsChanging {
            context.coordinator.currentURL = contentURL
            context.coordinator.themeCSS = themeCSS
            // Store scroll fraction to apply after the page finishes loading
            context.coordinator.pendingScrollFraction = scrollFraction
            context.coordinator.pendingPaginationPage = paginationPage
            // Bug #182: when the container sets `pendingJS` in the SAME
            // SwiftUI state update that flips contentURL (cross-chapter
            // search-result tap), we must defer the JS eval until the
            // NEW chapter DOM is ready. Running `window.find()` on the
            // old/loading page silently fails, producing the
            // "navigates but no yellow highlight" symptom. Stash the JS
            // (and the completion callback that clears the container's
            // `@State pendingHighlightJS`) onto the coordinator; the
            // didFinish handler will eval and complete.
            if let js = pendingJS {
                context.coordinator.pendingHighlightJS = js
                context.coordinator.onPendingHighlightJSCompleted = onPendingJSCompleted
            }
            // Bug #251 / GH #1086: directly observable load-request entry
            // log. Round-2 verification could only infer the absence of
            // didFinish; this log lets future verify runs confirm that
            // `loadFileURL` was actually invoked. Combined with the
            // didFinish entry log (in the coordinator), the verify cron
            // can distinguish "load never requested" from "load requested
            // but didFinish never fired".
            AppLogger.epub.info(
                "loadFileURL: \(contentURL.lastPathComponent, privacy: .public)"
            )
            webView.loadFileURL(contentURL, allowingReadAccessTo: baseDirectory)
            #if DEBUG
            // Bug #251 / GH #1086: schedule the bounded fallback that
            // marks the reader settled + registers the WebView if
            // `webView(_:didFinish:)` does not fire within the
            // coordinator's `earlySettleFallbackDelay` window. The
            // happy-path `didFinish` cancels the fallback immediately;
            // the fallback only fires when didFinish is delayed past
            // the verify budget (typical observed delay: <500ms; this
            // window is 2s).
            context.coordinator.scheduleEarlySettleFallback(webView: webView)
            #endif
        } else if isPaged, let page = paginationPage,
                  page != context.coordinator.pendingPaginationPage {
            // Paged mode: navigate to specific page
            context.coordinator.pendingPaginationPage = page
            let viewportWidth = webView.bounds.width
            let js = EPUBPaginationHelper.navigateToPageJS(
                page: page, viewportWidth: viewportWidth
            )
            webView.evaluateJavaScript(js) { _, error in
                if let error { AppLogger.epub.error("page nav error: \(error)") }
            }
        } else if let fraction = scrollFraction,
                  fraction != context.coordinator.pendingScrollFraction {
            // Same URL but scroll fraction changed — scroll immediately via JS.
            // Bug #163 (reopen): fraction ≤ 0 means "chapter top" — use native
            // contentOffset instead of JS scrollTo(0,0) so the safe-area inset
            // is respected. JS window.scrollTo(0,0) sets document scrollTop=0,
            // which maps to UIScrollView contentOffset.y=0 (not -safeAreaTopInset),
            // undoing the chapter-top safe-area positioning.
            context.coordinator.pendingScrollFraction = fraction
            if fraction <= 0 {
                Self.applyInitialContentOffset(
                    to: webView.scrollView,
                    topInset: context.coordinator.safeAreaTopInset
                )
            } else {
                let js = Self.scrollToFractionJS(fraction)
                webView.evaluateJavaScript(js) { _, error in
                    if let error { AppLogger.epub.error("scroll error: \(error)") }
                }
            }
        } else if context.coordinator.themeCSS != themeCSS {
            // Theme changed without URL change — inject or remove CSS live
            context.coordinator.themeCSS = themeCSS
            if let css = themeCSS {
                let js = Self.injectThemeCSSJS(css)
                webView.evaluateJavaScript(js) { _, error in
                    if let error { AppLogger.epub.error("theme inject error: \(error)") }
                }
            } else {
                // Theme cleared — remove previously injected style element
                webView.evaluateJavaScript(Self.removeThemeCSSJS) { _, error in
                    if let error { AppLogger.epub.error("theme remove error: \(error)") }
                }
            }
        }

        // Bug #167 wiring: keep the rubber-band overscroll area in sync
        // with the current reader theme so it doesn't flash white.
        // Compared separately from `themeCSS` so a theme change still
        // restyles the scroll view even if the cascade above didn't run
        // (e.g. URL also changed in the same update). As above, the seam
        // is unit-tested but this call site is not — deleting it would
        // silently re-introduce the regression on live theme switches.
        if context.coordinator.themeBackgroundColor != themeBackgroundColor {
            context.coordinator.themeBackgroundColor = themeBackgroundColor
            Self.applyScrollViewBackground(to: webView.scrollView, color: themeBackgroundColor)
        }

        // Bug #163 wiring: live-update the safe-area top inset on rotation
        // / multi-window resize. Same coverage-gap caveat as the
        // background path: the seam is unit-tested but this call site is
        // not — deleting the call would silently re-introduce DI clipping
        // when the user rotates the device mid-read.
        let safeAreaChanged = context.coordinator.safeAreaTopInset != safeAreaTopInset
        if safeAreaChanged {
            context.coordinator.safeAreaTopInset = safeAreaTopInset
            Self.applySafeAreaTopInset(to: webView.scrollView, top: safeAreaTopInset)
        }

        // Bug #163 paged-mode rebuild: pagination CSS pins column height
        // to (bounds.height - safeAreaTopInset) and column width to
        // bounds.width. Re-inject pagination CSS whenever EITHER the
        // safe-area inset OR the webview bounds change while in paged
        // mode (round-2 audit fix [1]). Pure bounds changes (iPad
        // split-screen / Stage Manager / multitasking resize) also need
        // a rebuild even if the safe-area inset stays constant.
        if isPaged, context.coordinator.currentURL == contentURL {
            let boundsChanged = context.coordinator.lastPagedBounds != webView.bounds
            if safeAreaChanged || boundsChanged {
                context.coordinator.setupPagination(webView: webView)
            }
        }

        // Evaluate pending JS from container (e.g., highlight injection
        // after persist on the CURRENTLY-loaded chapter). Two guards keep
        // this from racing the URL-change path (bug #182):
        //
        //   1. `!urlIsChanging` — when this call also flips contentURL,
        //      the JS has already been stashed onto the coordinator for
        //      deferred eval in didFinish. Skip the immediate path.
        //   2. `pendingHighlightJS == nil` on the coordinator — if a prior
        //      URL-change update stashed JS that hasn't been evaluated
        //      yet (page still loading), a subsequent unrelated
        //      updateUIView (binding refresh, theme change, etc.) must
        //      NOT also try to eval the same JS against the loading DOM.
        //      The stashed value being non-nil is the in-flight sentinel.
        if !urlIsChanging,
           context.coordinator.pendingHighlightJS == nil,
           let js = pendingJS {
            webView.evaluateJavaScript(js) { _, error in
                if let error { AppLogger.epub.error("pendingJS error: \(error)") }
            }
            Task { @MainActor in
                onPendingJSCompleted?()
            }
        }
    }

    /// Feature #71 WI-6b-i: load the continuous-scroll bootstrap document.
    ///
    /// Re-audit finding 3: WKWebView's navigation policy cancels non-`file://`
    /// navigations and `loadHTMLString(_:baseURL:)` sandboxes `file://`
    /// subresource access, so a string-loaded bootstrap can't read the rewriter's
    /// absolute `file://` image / stylesheet refs. We therefore write a
    /// file-backed bootstrap under the extracted root and `loadFileURL` it with
    /// `allowingReadAccessTo: baseDirectory`, which grants the document read
    /// access to the whole extracted tree (chapters + resources). The theme CSS
    /// is baked into the bootstrap at construction (`bootstrapDocumentHTML`).
    private func loadContinuousBootstrap(into webView: WKWebView) {
        let html = EPUBContinuousScrollJS.bootstrapDocumentHTML(themeCSS: themeCSS ?? "")
        let bootstrapURL = baseDirectory.appendingPathComponent("__vreader_continuous_bootstrap.html")
        guard let data = html.data(using: .utf8) else {
            AppLogger.epub.error("continuous bootstrap: failed to encode HTML")
            onLoadError("Failed to prepare continuous scroll document")
            return
        }
        do {
            try data.write(to: bootstrapURL)
            AppLogger.epub.info(
                "loadContinuousBootstrap: \(bootstrapURL.lastPathComponent, privacy: .public)"
            )
            webView.loadFileURL(bootstrapURL, allowingReadAccessTo: baseDirectory)
        } catch {
            AppLogger.epub.error(
                "continuous bootstrap write failed: \(String(describing: error), privacy: .public)"
            )
            onLoadError("Failed to prepare continuous scroll document")
        }
    }

    // Static JS members are in EPUBWebViewBridgeJS.swift.
    // Coordinator is defined in EPUBWebViewBridgeCoordinator.swift.
}
#endif
