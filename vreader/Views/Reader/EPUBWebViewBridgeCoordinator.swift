// Purpose: Coordinator for EPUBWebViewBridge — handles WKScriptMessageHandler
// callbacks (progress, tap, selection), WKNavigationDelegate for security
// (file:// scope enforcement), theme CSS injection, and pagination setup.
//
// @coordinates-with EPUBWebViewBridge.swift, EPUBWebViewBridgeJS.swift,
//   EPUBHighlightBridge.swift, EPUBPaginationHelper.swift

#if canImport(UIKit)
import WebKit

extension EPUBWebViewBridge {
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var currentURL: URL?
        var themeCSS: String?
        /// Scroll fraction to apply after the next page load completes.
        var pendingScrollFraction: Double?
        /// Page index to navigate to after pagination setup (paged mode).
        var pendingPaginationPage: Int?
        /// Allowed root directory for file:// navigation (scoped to extracted EPUB).
        var allowedRoot: URL?
        /// Current chapter href for anchor construction.
        var currentHref: String?
        #if DEBUG
        /// Bug #126: book identity used to bind the live `WKWebView` to a
        /// fingerprintKey in `DebugReaderRegistry` from
        /// `webView(_:didFinish:)`. Set by `EPUBWebViewBridge.updateUIView`
        /// from the SwiftUI binding. DEBUG-only.
        var fingerprintKey: String?
        #endif
        /// Callback for text selection events.
        var onSelectionEvent: (@MainActor (ReaderSelectionEvent) -> Void)?
        /// Callback to restore highlights after page loads.
        /// Provides a JS evaluator so the container can inject restore scripts.
        var onPageDidFinishLoad: (@MainActor (@escaping (String) -> Void) -> Void)?
        /// Whether paged layout mode is active.
        var isPaged = false
        /// Tracks the previous value of isPaged for change detection in updateUIView.
        var previousIsPaged = false
        /// Called when pagination is ready with total page count.
        var onPaginationReady: (@MainActor (Int) -> Void)?
        private let onProgressChange: @MainActor (Double) -> Void
        private let onLoadError: @MainActor (String) -> Void

        init(
            onProgressChange: @escaping @MainActor (Double) -> Void,
            onLoadError: @escaping @MainActor (String) -> Void
        ) {
            self.onProgressChange = onProgressChange
            self.onLoadError = onLoadError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "contentTapHandler" {
                NotificationCenter.default.post(name: .readerContentTapped, object: nil)
                return
            }
            if message.name == "selectionChanged" {
                handleSelectionMessage(message.body)
                return
            }
            if message.name == "footnoteHandler" {
                handleFootnoteMessage(message.body)
                return
            }
            guard message.name == "progressHandler",
                  let progress = message.body as? Double else { return }
            Task { @MainActor in
                onProgressChange(progress)
            }
        }

        private func handleSelectionMessage(_ body: Any) {
            guard let parsed = EPUBHighlightBridge.parseSelectionMessage(body) else { return }
            let href = currentHref ?? ""
            let event = EPUBHighlightBridge.makeSelectionEvent(
                selectedText: parsed.selectedText,
                href: href,
                cfi: "",
                range: parsed.range,
                sourceRect: parsed.sourceRect
            )
            Task { @MainActor in
                onSelectionEvent?(event)
            }
        }

        private func handleFootnoteMessage(_ body: Any) {
            guard let dict = body as? [String: Any],
                  let href = dict["href"] as? String,
                  let text = dict["text"] as? String else { return }
            // Post notification for the container to show a footnote popover
            let info: [String: String] = ["href": href, "text": text]
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .epubFootnoteDetected,
                    object: info
                )
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            // Only allow file:// URLs scoped to the extracted EPUB directory
            guard let url = navigationAction.request.url, url.isFileURL else {
                return .cancel
            }
            // Scope-check: resolved path must be within the allowed root directory
            if let root = allowedRoot {
                let resolvedPath = url.standardizedFileURL.path()
                // Ensure rootPath ends with "/" for strict directory boundary matching
                var rootPath = root.standardizedFileURL.path()
                if !rootPath.hasSuffix("/") { rootPath += "/" }
                guard resolvedPath.hasPrefix(rootPath)
                    || resolvedPath == root.standardizedFileURL.path() else {
                    return .cancel
                }
            }
            return .allow
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            let message = "Failed to load chapter: \(error.localizedDescription)"
            Task { @MainActor in
                onLoadError(message)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            let message = "Chapter loading error: \(error.localizedDescription)"
            Task { @MainActor in
                onLoadError(message)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Bug #126: register the webview with DebugReaderRegistry so
            // `vreader-debug://eval?bridge=foliate` can reach it. This
            // fires on every page load, so reuses across book opens
            // refresh the registry's weak ref correctly. Safe to set
            // unconditionally; weak ref + `===` check on dismantle.
            #if DEBUG
            // Bug #126: register the webview with DebugReaderRegistry,
            // paired with the book's fingerprintKey so eval can verify
            // identity at call-time. Skip the registration when the
            // fingerprintKey hasn't been threaded yet — silently dropping
            // is preferable to binding the webview to no key.
            if let key = fingerprintKey {
                DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: key)
            }
            #endif

            // Inject theme CSS after page finishes loading
            if let css = themeCSS {
                let js = EPUBWebViewBridge.injectThemeCSSJS(css)
                webView.evaluateJavaScript(js) { _, error in
                    if let error { AppLogger.epub.error("didFinish theme inject error: \(error)") }
                }
            }

            if isPaged {
                // Paged mode: inject pagination CSS, then query total pages
                setupPagination(webView: webView)
            } else {
                // Scroll mode: scroll to pending fraction after page layout
                if let fraction = pendingScrollFraction, fraction > 0 {
                    pendingScrollFraction = nil
                    let scrollJS = EPUBWebViewBridge.scrollToFractionJS(fraction)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        webView.evaluateJavaScript(scrollJS) { _, error in
                            if let error { AppLogger.epub.error("scroll error: \(error)") }
                        }
                    }
                }
            }

            // Notify container that the page finished loading (for highlight restoration).
            // Provide a JS evaluator so the container can inject restore scripts.
            Task { @MainActor in
                onPageDidFinishLoad?({ js in
                    webView.evaluateJavaScript(js) { _, error in
                        if let error { AppLogger.epub.error("restore error: \(error)") }
                    }
                })
            }
        }

        /// Injects pagination CSS and queries total page count after layout settles.
        func setupPagination(webView: WKWebView) {
            let viewportWidth = webView.bounds.width
            let viewportHeight = webView.bounds.height
            guard viewportWidth > 0, viewportHeight > 0 else { return }

            let injectJS = EPUBPaginationHelper.injectPaginationCSSJS(
                viewportWidth: viewportWidth, viewportHeight: viewportHeight
            )
            webView.evaluateJavaScript(injectJS) { [weak self] _, error in
                if let error {
                    AppLogger.epub.error("pagination CSS error: \(error)")
                    return
                }
                // Delay to allow column layout to settle before querying page count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard let self else { return }
                    let totalPagesJS = EPUBPaginationHelper.totalPagesJS(
                        viewportWidth: viewportWidth
                    )
                    webView.evaluateJavaScript(totalPagesJS) { [weak self] result, error in
                        guard let self else { return }
                        if let error {
                            AppLogger.epub.error("totalPages query error: \(error)")
                            return
                        }
                        let totalPages = (result as? Int) ?? 1
                        Task { @MainActor in
                            self.onPaginationReady?(totalPages)
                        }
                        // Navigate to pending page if set
                        if let page = self.pendingPaginationPage, page > 0 {
                            self.pendingPaginationPage = nil
                            let navJS = EPUBPaginationHelper.navigateToPageJS(
                                page: page, viewportWidth: viewportWidth
                            )
                            webView.evaluateJavaScript(navJS) { _, error in
                                if let error {
                                    AppLogger.epub.error("page nav error: \(error)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
