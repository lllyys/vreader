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
        /// Bug #167: themed background color for the WKWebView's scroll
        /// view. Tracked here so `updateUIView` can detect a theme change
        /// and restyle the rubber-band overscroll area without reloading
        /// the page.
        var themeBackgroundColor: UIColor?
        /// Bug #163: last applied safe-area top inset. Tracked so
        /// `updateUIView` can detect changes (e.g. rotation, multi-window
        /// resize) and re-apply the inset without reloading the page.
        var safeAreaTopInset: CGFloat = 0
        /// Bug #163 round-2 audit fix [1]: last-known paged-mode webview
        /// bounds. Tracked so pure size changes (iPad split-screen / Stage
        /// Manager / multitasking resize) — which keep `safeAreaTopInset`
        /// constant but change `bounds.width`/`bounds.height` — re-trigger
        /// `setupPagination(...)`. Without this, paged geometry stays
        /// stale on resize.
        var lastPagedBounds: CGRect = .zero
        /// Scroll fraction to apply after the next page load completes.
        var pendingScrollFraction: Double?
        /// Page index to navigate to after pagination setup (paged mode).
        var pendingPaginationPage: Int?
        /// Bug #182: highlight JS deferred from a URL-change update so it
        /// runs against the NEW chapter DOM, not the old/loading one. Set
        /// in `EPUBWebViewBridge.updateUIView` when `pendingJS` arrives in
        /// the same SwiftUI state update as a `contentURL` change;
        /// consumed in `webView(_:didFinish:)`.
        var pendingHighlightJS: String?
        /// Bug #182: completion callback paired with `pendingHighlightJS`.
        /// Stashed alongside the JS so the container's @State
        /// `pendingHighlightJS = nil` clear-back fires once the deferred
        /// eval actually completes (mirrors the synchronous flow's
        /// `onPendingJSCompleted` semantics).
        var onPendingHighlightJSCompleted: (@MainActor () -> Void)?
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
        /// Bug #142: per-reader instance token paired with fingerprintKey.
        /// See registry's `setActiveEPUBWebView(_:for:token:)`.
        var readerToken: UUID?
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
            if message.name == "highlightTapHandler" {
                handleHighlightTapMessage(message.body)
                return
            }
            guard message.name == "progressHandler",
                  let progress = message.body as? Double else { return }
            Task { @MainActor in
                onProgressChange(progress)
            }
        }

        /// Parses a `{id, rect}` payload from the JS `highlightTapHandler`
        /// channel and posts the cross-format `.readerHighlightTapped`
        /// notification.
        ///
        /// Feature #64 WI-8: a tap on an annotated EPUB highlight opens the
        /// unified highlight-action popover (`HighlightPopoverModifier`,
        /// attached on `EPUBReaderContainerView`, observes
        /// `.readerHighlightTapped`) — color / note / copy / share / delete.
        /// EPUB has no native long-press recognizer for a highlight, so
        /// unlike the native TXT/MD/PDF bridges there was never a feature-#53
        /// long-press `UIMenu` here to remove.
        private func handleHighlightTapMessage(_ body: Any) {
            guard let event = EPUBHighlightBridge.parseHighlightTapMessage(body)
            else { return }
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .readerHighlightTapped, object: event
                )
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
            // Bug #126: register the webview with DebugReaderRegistry
            // paired with the book's fingerprintKey + per-reader token
            // (bug #142) so eval can verify both book identity AND that
            // this is the active reader instance, not an outgoing same-
            // book webview firing didFinish late. Skip when either has
            // not been threaded yet — silently dropping is preferable
            // to binding to a half-identity.
            if let key = fingerprintKey, let token = readerToken {
                DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: key, token: token)
                // Bug #141: `didFinish` is the EPUB render-complete signal
                // (the chapter HTML has loaded and laid out). Mark the
                // reader settled so `vreader-debug://settle` unblocks on
                // real render-complete instead of the 100ms placeholder.
                // Same key/token guard as the binding above — the registry
                // drops the mark if it's a stale callback from an outgoing
                // reader.
                DebugReaderRegistry.shared.markReaderSettled(for: key, token: token)
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
                    // URL-guard: no-op if a new chapter loaded before the 0.15s
                    // delay fires (same stale-load hazard as the chapter-top branch).
                    let expectedURL = currentURL
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak webView] in
                        guard self != nil, let webView else { return }
                        guard self?.currentURL == expectedURL else { return }
                        webView.evaluateJavaScript(scrollJS) { _, error in
                            if let error { AppLogger.epub.error("scroll error: \(error)") }
                        }
                    }
                } else {
                    // Bug #163 (reopen): WKWebView resets contentOffset to .zero after
                    // every loadFileURL. With contentInset.top = safeAreaTopInset, the
                    // correct chapter-top offset is -safeAreaTopInset so document y=0
                    // sits just below the Dynamic Island, not clipped behind it.
                    // URL-guard: capture the URL at didFinish time and no-op if a
                    // subsequent load has already changed currentURL before the 0.05s
                    // delay fires (prevents stale resets on rapid chapter navigation).
                    pendingScrollFraction = nil
                    let inset = safeAreaTopInset
                    let expectedURL = currentURL
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak webView] in
                        guard let self, let scrollView = webView?.scrollView else { return }
                        guard self.currentURL == expectedURL else { return }
                        EPUBWebViewBridge.applyInitialContentOffset(to: scrollView, topInset: inset)
                    }
                }
            }

            // Bug #182: evaluate any highlight JS that was deferred from a
            // URL-change update. Runs AFTER theme + pagination/scroll setup
            // (so the DOM is laid out and CSS is applied) and BEFORE the
            // persisted-highlights restore Task below (so search highlight
            // is the first highlight painted on the new chapter — avoids
            // a visual flash where persisted highlights appear, then
            // search highlight overlays them). Synchronous eval — no
            // delay — because `didFinish` already guarantees the DOM
            // tree is ready for `window.find()` / CFI lookup.
            if let highlightJS = pendingHighlightJS {
                pendingHighlightJS = nil
                let completion = onPendingHighlightJSCompleted
                onPendingHighlightJSCompleted = nil
                webView.evaluateJavaScript(highlightJS) { _, error in
                    if let error { AppLogger.epub.error("deferred pendingHighlightJS error: \(error)") }
                }
                Task { @MainActor in
                    completion?()
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
        ///
        /// Bug #163: subtracts the safe-area top inset from viewport height
        /// so paged columns aren't taller than the visible area below the
        /// notch. Without this, applying `contentInset.top = safeAreaTop`
        /// would push each column DOWN by `safeAreaTop` pt, clipping the
        /// bottom of the column off-screen. Reading the inset from the
        /// coordinator's tracked field (set by `EPUBWebViewBridge`'s
        /// makeUIView/updateUIView) avoids changing the function's
        /// signature for every caller.
        func setupPagination(webView: WKWebView) {
            let viewportWidth = webView.bounds.width
            let viewportHeight = max(webView.bounds.height - safeAreaTopInset, 0)
            guard viewportWidth > 0, viewportHeight > 0 else { return }
            // Round-2 audit fix [1]: snapshot the bounds we paginated for so
            // updateUIView can detect pure size changes that didn't go
            // through the safe-area branch.
            lastPagedBounds = webView.bounds

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
