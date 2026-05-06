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
    /// Called after a page finishes loading (for highlight restoration).
    /// The closure receives a JS evaluator that runs JavaScript on the WKWebView.
    var onPageDidFinishLoad: (@MainActor (@escaping (String) -> Void) -> Void)?
    /// JavaScript to evaluate on next updateUIView cycle.
    /// Container sets this to inject highlight JS after persist.
    /// Bridge evaluates it and the container should clear via onPendingJSCompleted.
    var pendingJS: String?
    /// Called after pendingJS has been evaluated so the container can clear state.
    var onPendingJSCompleted: (@MainActor () -> Void)?
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

        // Add scroll progress tracking script (throttled)
        let script = WKUserScript(
            source: Self.progressTrackingJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(script)
        let weakHandler = WeakScriptMessageHandler(context.coordinator)
        userContentController.add(weakHandler, name: "progressHandler")

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

        let highlightScript = WKUserScript(
            source: EPUBHighlightBridge.highlightAPIJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(highlightScript)

        config.userContentController = userContentController
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.themeCSS = themeCSS
        context.coordinator.allowedRoot = baseDirectory
        context.coordinator.currentHref = currentHref
        #if DEBUG
        context.coordinator.fingerprintKey = fingerprintKey
        context.coordinator.readerToken = readerToken
        #endif
        context.coordinator.onSelectionEvent = onSelectionEvent
        context.coordinator.onPageDidFinishLoad = onPageDidFinishLoad
        context.coordinator.isPaged = isPaged
        context.coordinator.previousIsPaged = isPaged
        context.coordinator.onPaginationReady = onPaginationReady
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
        context.coordinator.onPageDidFinishLoad = onPageDidFinishLoad
        context.coordinator.isPaged = isPaged
        context.coordinator.onPaginationReady = onPaginationReady

        // Update scroll enabled state when layout mode changes
        webView.scrollView.isScrollEnabled = !isPaged

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
        if context.coordinator.currentURL != contentURL {
            context.coordinator.currentURL = contentURL
            context.coordinator.themeCSS = themeCSS
            // Store scroll fraction to apply after the page finishes loading
            context.coordinator.pendingScrollFraction = scrollFraction
            context.coordinator.pendingPaginationPage = paginationPage
            webView.loadFileURL(contentURL, allowingReadAccessTo: baseDirectory)
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
            // Same URL but scroll fraction changed — scroll immediately via JS
            context.coordinator.pendingScrollFraction = fraction
            let js = Self.scrollToFractionJS(fraction)
            webView.evaluateJavaScript(js) { _, error in
                if let error { AppLogger.epub.error("scroll error: \(error)") }
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

        // Evaluate pending JS from container (e.g., highlight injection after persist)
        if let js = pendingJS {
            webView.evaluateJavaScript(js) { _, error in
                if let error { AppLogger.epub.error("pendingJS error: \(error)") }
            }
            Task { @MainActor in
                onPendingJSCompleted?()
            }
        }
    }

    // Static JS members are in EPUBWebViewBridgeJS.swift.
    // Coordinator is defined in EPUBWebViewBridgeCoordinator.swift.
}
#endif
