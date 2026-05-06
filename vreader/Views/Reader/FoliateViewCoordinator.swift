// Purpose: WKScriptMessageHandler + WKNavigationDelegate for the Foliate-js reader bridge.
// Receives raw JS messages, parses them via FoliateMessageParser, and routes to typed callbacks.
//
// Key decisions:
// - Separate from UIViewRepresentable (testable without WKWebView instantiation).
// - jsEvaluator closure decouples JS execution from WKWebView (enables unit testing).
// - Pure shouldAllowNavigation(to:) method extracted for testability.
// - openBookJS/initJS are static for isolated testing of JS string generation.
// - All user/file values are escaped via FoliateJSEscaper before JS interpolation.
//
// @coordinates-with: FoliateViewBridge.swift, FoliateMessageParser.swift,
//   FoliateTypes.swift, FoliateURLSchemeHandler.swift, FoliateJSEscaper.swift

#if canImport(UIKit)
import WebKit

/// Coordinator that routes Foliate-js WKScriptMessage events to typed Swift callbacks.
/// Also serves as WKNavigationDelegate, restricting navigation to the custom scheme.
@MainActor
final class FoliateViewCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    // MARK: - Configuration

    /// Book file extension (e.g., "azw3", "epub", "mobi").
    let bookFormat: String

    /// Base64-encoded book file data. Set by FoliateViewBridge before loading.
    var bookBase64: String?

    /// Optional saved CFI to restore position on book-ready.
    var lastLocationCFI: String?

    /// Closure to evaluate JavaScript on the WKWebView.
    /// Set by FoliateViewBridge after creating the web view.
    var jsEvaluator: ((String) -> Void)?

    // MARK: - State Tracking (for updateUIView change detection)

    /// Last theme CSS applied, used by FoliateViewBridge to detect changes.
    var currentThemeCSS: String?

    /// Last layout flow applied, used by FoliateViewBridge to detect changes.
    var currentLayoutFlow: String?

    /// Whether the reader is ready (book-ready received). Guards JS calls in updateUIView.
    var isReaderReady = false

    #if DEBUG
    /// Bug #141: book identity used to bind the live `WKWebView` to a
    /// fingerprintKey in `DebugReaderRegistry` from the navigation
    /// delegate's `webView(_:didFinish:)`. Set by `FoliateViewBridge`
    /// from the SwiftUI binding in both `makeUIView` and `updateUIView`.
    /// DEBUG-only.
    var fingerprintKey: String?
    /// Bug #142: per-reader instance token paired with fingerprintKey.
    var readerToken: UUID?
    #endif

    // MARK: - Callbacks

    private let onBookReady: @MainActor (FoliateBookInfo) -> Void
    private let onRelocate: @MainActor (FoliateRelocateEvent) -> Void
    private let onSelection: @MainActor (FoliateSelectionEvent) -> Void
    private let onTap: @MainActor () -> Void
    private let onCreateOverlay: @MainActor (Int) -> Void
    private let onAnnotationShow: @MainActor (String) -> Void
    private let onExternalLink: @MainActor (String) -> Void
    private let onError: @MainActor (String) -> Void

    // MARK: - Init

    init(
        bookFormat: String,
        onBookReady: @escaping @MainActor (FoliateBookInfo) -> Void,
        onRelocate: @escaping @MainActor (FoliateRelocateEvent) -> Void,
        onSelection: @escaping @MainActor (FoliateSelectionEvent) -> Void,
        onTap: @escaping @MainActor () -> Void,
        onCreateOverlay: @escaping @MainActor (Int) -> Void,
        onAnnotationShow: @escaping @MainActor (String) -> Void,
        onExternalLink: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        self.bookFormat = bookFormat
        self.onBookReady = onBookReady
        self.onRelocate = onRelocate
        self.onSelection = onSelection
        self.onTap = onTap
        self.onCreateOverlay = onCreateOverlay
        self.onAnnotationShow = onAnnotationShow
        self.onExternalLink = onExternalLink
        self.onError = onError
        super.init()
    }

    // MARK: - Message Names

    /// All message handler names registered with WKUserContentController.
    static let messageNames: [String] = [
        "bridge-ready", "book-ready", "relocate", "selection",
        "tap", "annotation-show", "create-overlay", "section-load",
        "external-link", "tts-ssml", "search-result", "search-done",
        "search-progress", "error",
    ]

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let name = message.name
        let body = message.body
        Task { @MainActor in
            self.handleMessage(name: name, body: body)
        }
    }

    // MARK: - Message Routing (testable)

    /// Routes a message to the appropriate callback. Called from WKScriptMessageHandler
    /// and directly from tests.
    func handleMessage(name: String, body: Any) {
        switch name {
        case "bridge-ready":
            // Book is opened directly in the HTML (embedded as base64 in the page).
            // bridge-ready just confirms the JS bridge loaded. No action needed here.
            break

        case "book-ready":
            guard let info = FoliateMessageParser.parseBookReady(body) else { return }
            isReaderReady = true
            onBookReady(info)
            let js = Self.initJS(cfi: lastLocationCFI)
            jsEvaluator?(js)

        case "relocate":
            guard let event = FoliateMessageParser.parseRelocate(body) else { return }
            onRelocate(event)

        case "selection":
            guard let event = FoliateMessageParser.parseSelection(body) else { return }
            onSelection(event)

        case "tap":
            onTap()

        case "error":
            if let parsed = FoliateMessageParser.parseError(body) {
                onError("\(parsed.type): \(parsed.message)")
            } else {
                onError("Unknown error from reader")
            }

        case "create-overlay":
            if let dict = body as? [String: Any], let index = dict["index"] as? Int {
                onCreateOverlay(index)
            }

        case "annotation-show":
            if let dict = body as? [String: Any], let value = dict["value"] as? String {
                onAnnotationShow(value)
            }

        case "external-link":
            if let dict = body as? [String: Any], let href = dict["href"] as? String {
                onExternalLink(href)
            }

        case "section-load", "tts-ssml", "search-result", "search-done", "search-progress":
            // Handled by future WI features (TTS, Search). No-op for now.
            break

        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        return Self.shouldAllowNavigation(to: url) ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Bug #141: register the live WKWebView with DebugReaderRegistry,
        // paired with the book's fingerprintKey so eval can verify book
        // identity at call-time. Skip when the fingerprintKey hasn't been
        // threaded yet — silently dropping is preferable to binding to
        // no key. Mirrors the bug #126 EPUB pattern.
        #if DEBUG
        if let key = fingerprintKey, let token = readerToken {
            DebugReaderRegistry.shared.setActiveFoliateWebView(webView, for: key, token: token)
        }
        #endif
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        let msg = error.localizedDescription
        Task { @MainActor in
            self.onError("Navigation failed: \(msg)")
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        let msg = error.localizedDescription
        Task { @MainActor in
            self.onError("Navigation error: \(msg)")
        }
    }

    // MARK: - Navigation Policy (testable)

    /// Pure decision function: should this URL be allowed for navigation?
    /// Allows vreader-resource://, blob://, and about:blank only.
    static func shouldAllowNavigation(to url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == FoliateURLSchemeHandler.scheme { return true }
        if scheme == "blob" { return true }
        if url.absoluteString == "about:blank" { return true }
        return false
    }

    // MARK: - JS Generation (static, testable)

    /// Generates JavaScript to fetch the book file from the scheme handler and open it.
    /// Note: fetch() from custom URL schemes may fail on device. Prefer openBookBase64JS.
    static func openBookJS(format: String) -> String {
        let bookURL = "\(FoliateURLSchemeHandler.scheme)://localhost/book/file"
        let safeFormat = FoliateJSEscaper.escapeForJSString(format)
        return """
        (async () => {
            try {
                const res = await fetch('\(bookURL)');
                if (!res.ok) throw new Error('fetch failed: ' + res.status);
                const blob = await res.blob();
                const file = new File([blob], "book.\(safeFormat)");
                await readerAPI.open(file);
            } catch(e) {
                window.webkit?.messageHandlers?.error?.postMessage({
                    message: 'openBook: ' + (e.message || e), type: 'open'
                });
            }
        })()
        """
    }

    /// Generates JavaScript to open a book from base64-encoded data.
    /// This approach bypasses the WKURLSchemeHandler fetch() limitation on device.
    static func openBookBase64JS(base64: String, format: String) -> String {
        let safeFormat = FoliateJSEscaper.escapeForJSString(format)
        return """
        (async () => {
            try {
                const b64 = "\(base64)";
                const binary = atob(b64);
                const bytes = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
                const file = new File([bytes], "book.\(safeFormat)");
                await readerAPI.open(file);
            } catch(e) {
                window.webkit?.messageHandlers?.error?.postMessage({
                    message: 'openBook: ' + (e.message || e), type: 'open'
                });
            }
        })()
        """
    }

    /// Generates JavaScript to initialize the reader, optionally restoring a saved CFI.
    static func initJS(cfi: String?) -> String {
        if let cfi {
            let escaped = FoliateJSEscaper.escapeForJSString(cfi)
            return "readerAPI.init({cfi: '\(escaped)'})"
        } else {
            return "readerAPI.init({})"
        }
    }
}
#endif
