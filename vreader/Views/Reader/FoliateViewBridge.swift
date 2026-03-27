// Purpose: UIViewRepresentable wrapping WKWebView for the Foliate-js reader.
// Loads the reader HTML via loadHTMLString with the JS bundle inlined, and passes
// book data as base64 to bypass WKWebView's custom scheme fetch() limitations.
//
// Key decisions:
// - Single WKWebView created once in makeUIView (no recreation on SwiftUI updates).
// - WeakScriptMessageHandler pattern breaks WKUserContentController retain cycle.
// - loadHTMLString with inlined IIFE bundle (not loadFileURL or scheme handler loading).
// - Book file read as base64 in Swift, passed to JS via evaluateJavaScript.
// - updateUIView detects themeCSS and layoutFlow changes, pushes via evaluateJavaScript.
// - All interpolated values are sanitized via FoliateJSEscaper.
//
// @coordinates-with: FoliateViewCoordinator.swift, FoliateTypes.swift,
//   FoliateMessageParser.swift, FoliateJSEscaper.swift

#if canImport(UIKit)
import SwiftUI
import WebKit

/// UIViewRepresentable bridge for Foliate-js book rendering via WKWebView.
struct FoliateViewBridge: UIViewRepresentable {

    // MARK: - Properties

    /// URL of the book file on disk (e.g., .azw3 in the app's Documents).
    let bookURL: URL

    /// Book file format extension (e.g., "azw3", "epub", "mobi").
    let bookFormat: String

    /// Optional saved CFI to restore reading position after book-ready.
    var lastLocationCFI: String?

    /// Optional CSS string to inject for theme customization.
    var themeCSS: String?

    /// Layout flow: "paginated" or "scrolled".
    var layoutFlow: String = "paginated"

    // MARK: - Callbacks

    /// Called when Foliate-js reports a position change.
    let onRelocate: @MainActor (FoliateRelocateEvent) -> Void

    /// Called when the user selects text.
    let onSelection: @MainActor (FoliateSelectionEvent) -> Void

    /// Called when the book is parsed and ready.
    let onBookReady: @MainActor (FoliateBookInfo) -> Void

    /// Called when a section's SVG overlay is created (ready for highlight restoration).
    let onCreateOverlay: @MainActor (Int) -> Void

    /// Called when an error occurs in the reader.
    let onError: @MainActor (String) -> Void

    /// Called when the user taps content (for toolbar toggle).
    let onTap: @MainActor () -> Void

    /// Called when a highlight annotation is tapped.
    let onAnnotationShow: @MainActor (String) -> Void

    /// Called when an external link is tapped.
    let onExternalLink: @MainActor (String) -> Void

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> FoliateViewCoordinator {
        FoliateViewCoordinator(
            bookFormat: bookFormat,
            onBookReady: onBookReady,
            onRelocate: onRelocate,
            onSelection: onSelection,
            onTap: onTap,
            onCreateOverlay: onCreateOverlay,
            onAnnotationShow: onAnnotationShow,
            onExternalLink: onExternalLink,
            onError: onError
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let coordinator = context.coordinator
        coordinator.lastLocationCFI = lastLocationCFI

        // Read book file as base64 for passing to JS (bypasses WKURLSchemeHandler fetch limitation).
        // If file can't be read, bookBase64 stays nil → coordinator shows error on bridge-ready.
        if let bookData = try? Data(contentsOf: bookURL, options: .mappedIfSafe), !bookData.isEmpty {
            coordinator.bookBase64 = bookData.base64EncodedString()
        }

        // Register message handlers using weak proxy to avoid retain cycle
        let weakHandler = WeakScriptMessageHandler(coordinator)
        for name in FoliateViewCoordinator.messageNames {
            config.userContentController.add(weakHandler, name: name)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.navigationDelegate = coordinator
        webView.scrollView.isScrollEnabled = false
        webView.accessibilityIdentifier = "foliateWebView"

        // Provide JS evaluator to coordinator
        coordinator.jsEvaluator = { [weak webView] js in
            webView?.evaluateJavaScript(js) { _, error in
                if let error {
                    print("[FoliateViewBridge] JS eval error: \(error.localizedDescription)")
                }
            }
        }

        // Load reader HTML with JS bundle inlined (proven approach from spike)
        if let html = Self.buildReaderHTML() {
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            coordinator.handleMessage(name: "error", body: [
                "message": "Failed to build reader HTML — foliate-bundle.js not found in app bundle",
                "type": "init"
            ] as [String: Any])
        }

        return webView
    }

    /// Builds the reader HTML with the IIFE JS bundle inlined.
    /// This bypasses WKWebView's file:// and custom scheme restrictions for ES modules.
    private static func buildReaderHTML() -> String? {
        guard let bundleURL = Bundle.main.url(forResource: "foliate-bundle", withExtension: "js"),
              let jsCode = try? String(contentsOf: bundleURL, encoding: .utf8) else {
            return nil
        }
        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
        html, body { margin:0; padding:0; width:100%; height:100%; overflow:hidden; }
        foliate-view { display:block; width:100%; height:100%; }
        </style>
        </head><body>
        <script>
        function post(n,d){try{window.webkit?.messageHandlers?.[n]?.postMessage(d||{})}catch(e){}}
        window.onerror=function(m,s,l){post('error',{message:'JS: '+m+' line:'+l,type:'onerror'})};
        window.addEventListener('unhandledrejection',function(e){post('error',{message:'Promise: '+(e.reason?.message||e.reason||'?'),type:'rejection'})});
        </script>
        <foliate-view id="view"></foliate-view>
        <script>\(jsCode)</script>
        <script>
        // The IIFE bundle already posts bridge-ready at the end.
        // Only post error if readerAPI failed to initialize.
        if(!window.readerAPI){post('error',{message:'readerAPI not defined after bundle load',type:'init'})}
        </script>
        </body></html>
        """
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.isReaderReady else { return }

        // Detect theme CSS changes
        if coordinator.currentThemeCSS != themeCSS {
            coordinator.currentThemeCSS = themeCSS
            if let css = themeCSS {
                let escaped = FoliateJSEscaper.escapeForJSString(css)
                let js = "readerAPI.setStyles('\(escaped)')"
                webView.evaluateJavaScript(js) { _, error in
                    if let error {
                        print("[FoliateViewBridge] setStyles error: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Detect layout flow changes
        let safeFlow = FoliateJSEscaper.sanitizeFlow(layoutFlow)
        if coordinator.currentLayoutFlow != safeFlow {
            coordinator.currentLayoutFlow = safeFlow
            let js = "readerAPI.setLayout({flow: '\(safeFlow)'})"
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    print("[FoliateViewBridge] setLayout error: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - WeakScriptMessageHandler

/// Weak proxy to break the retain cycle between WKUserContentController and Coordinator.
/// WKUserContentController.add(_:name:) retains the handler strongly; this proxy
/// holds the real handler weakly so the Coordinator can be deallocated.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(controller, didReceive: message)
    }
}
#endif
