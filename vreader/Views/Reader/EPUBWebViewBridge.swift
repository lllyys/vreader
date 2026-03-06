// Purpose: WKWebView bridge for rendering EPUB XHTML content.
// Loads spine item HTML files with resource access to the extracted EPUB directory.
//
// Key decisions:
// - Uses loadFileURL with allowingReadAccessTo for local CSS/image resources.
// - allowingReadAccessTo uses the extracted root (not opfDir) to cover all resources.
// - Injects JavaScript to report scroll progress back to Swift (throttled at 100ms).
// - Coordinator handles WKScriptMessageHandler for progress callbacks.
// - Navigation delegate reports load errors to the container via onLoadError.
// - Only file:// URLs are allowed for all navigation types.
//
// @coordinates-with: EPUBReaderContainerView.swift, EPUBReaderViewModel.swift

#if canImport(UIKit)
import SwiftUI
import WebKit

/// UIViewRepresentable bridge for EPUB content rendering via WKWebView.
struct EPUBWebViewBridge: UIViewRepresentable {
    /// URL of the XHTML file to load.
    let contentURL: URL
    /// Base directory for resolving relative resources (CSS, images).
    /// Should be the extracted EPUB root directory for widest access.
    let baseDirectory: URL
    /// Called when scroll progress changes (0.0...1.0).
    let onProgressChange: @MainActor (Double) -> Void
    /// Called when WKWebView fails to load content.
    let onLoadError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgressChange: onProgressChange, onLoadError: onLoadError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Add scroll progress tracking script (throttled)
        let script = WKUserScript(
            source: Self.progressTrackingJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(script)
        userContentController.add(context.coordinator, name: "progressHandler")

        config.userContentController = userContentController
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.accessibilityIdentifier = "epubWebView"

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if the URL changed
        if context.coordinator.currentURL != contentURL {
            context.coordinator.currentURL = contentURL
            webView.loadFileURL(contentURL, allowingReadAccessTo: baseDirectory)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "progressHandler"
        )
    }

    // MARK: - JavaScript

    /// Scroll progress tracking with 100ms throttle to reduce callback churn.
    private static let progressTrackingJS = """
    (function() {
        var lastReport = 0;
        function reportProgress() {
            var now = Date.now();
            if (now - lastReport < 100) return;
            lastReport = now;
            var scrollTop = document.documentElement.scrollTop || document.body.scrollTop || 0;
            var scrollHeight = Math.max(
                document.documentElement.scrollHeight || 0,
                document.body.scrollHeight || 0
            );
            var clientHeight = document.documentElement.clientHeight || window.innerHeight || 0;
            var maxScroll = scrollHeight - clientHeight;
            var progress = maxScroll > 0 ? Math.min(Math.max(scrollTop / maxScroll, 0), 1) : 0;
            window.webkit.messageHandlers.progressHandler.postMessage(progress);
        }
        window.addEventListener('scroll', reportProgress, { passive: true });
        // Report initial progress after layout
        setTimeout(reportProgress, 100);
    })();
    """

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var currentURL: URL?
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
            guard message.name == "progressHandler",
                  let progress = message.body as? Double else { return }
            Task { @MainActor in
                onProgressChange(progress)
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            // Only allow file:// URLs for all navigation types
            guard let url = navigationAction.request.url else { return .cancel }
            return url.isFileURL ? .allow : .cancel
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
    }
}
#endif
