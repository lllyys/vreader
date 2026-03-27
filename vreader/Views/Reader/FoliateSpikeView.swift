// Purpose: Spike view for AZW3/MOBI rendering via Foliate-js.
// Uses loadHTMLString + inline IIFE bundle + base64 book handoff.
// This is the PROVEN approach that worked on device.

import SwiftUI
import WebKit

struct FoliateSpikeView: View {
    let bookURL: URL

    @State private var isBookReady = false
    @State private var bookTitle = ""
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            FoliateSpikeWebView(
                bookURL: bookURL,
                onBookReady: { title in
                    isBookReady = true
                    bookTitle = title
                },
                onError: { msg in errorMessage = msg }
            )

            if !isBookReady && errorMessage == nil {
                ProgressView("Opening book\u{2026}")
            }

            if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }
}

private struct FoliateSpikeWebView: UIViewRepresentable {
    let bookURL: URL
    let onBookReady: @MainActor (String) -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBookReady: onBookReady, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let coordinator = context.coordinator
        for name in [
            "bridge-ready", "book-ready", "relocate", "selection",
            "tap", "annotation-show", "create-overlay", "section-load",
            "external-link", "tts-ssml", "search-result", "search-done",
            "search-progress", "error",
        ] {
            config.userContentController.add(WeakScriptMessageHandler(coordinator), name: name)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        webView.navigationDelegate = coordinator
        webView.scrollView.isScrollEnabled = false
        coordinator.webView = webView

        // Read book as base64
        if let bookData = try? Data(contentsOf: bookURL) {
            coordinator.bookBase64 = bookData.base64EncodedString()
            coordinator.bookExt = bookURL.pathExtension.lowercased()
            if coordinator.bookExt?.isEmpty == true { coordinator.bookExt = "azw3" }
        }

        // Build HTML with inline IIFE bundle
        guard let bundleURL = Bundle.main.url(forResource: "foliate-bundle", withExtension: "js"),
              let jsCode = try? String(contentsOf: bundleURL, encoding: .utf8) else {
            Task { @MainActor in onError("foliate-bundle.js not found") }
            return webView
        }

        let html = """
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
        if(!window.readerAPI){post('error',{message:'readerAPI not defined',type:'init'})}
        </script>
        </body></html>
        """

        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var bookBase64: String?
        var bookExt: String?
        let onBookReady: @MainActor (String) -> Void
        let onError: @MainActor (String) -> Void

        init(onBookReady: @escaping @MainActor (String) -> Void,
             onError: @escaping @MainActor (String) -> Void) {
            self.onBookReady = onBookReady
            self.onError = onError
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            let name = message.name
            let body = message.body

            Task { @MainActor in
                switch name {
                case "bridge-ready":
                    openBook()

                case "book-ready":
                    if let dict = body as? [String: Any] {
                        let title = dict["title"] as? String ?? "Unknown"
                        onBookReady(title)
                        _ = try? await webView?.evaluateJavaScript("readerAPI.init({})")
                    }

                case "error":
                    if let dict = body as? [String: Any] {
                        let msg = dict["message"] as? String ?? "Unknown error"
                        onError(msg)
                    }

                default:
                    break
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.scheme == "blob" || url.absoluteString == "about:blank" { return .allow }
            // Allow the initial loadHTMLString (about:blank origin)
            if url.absoluteString.hasPrefix("about:") { return .allow }
            return .cancel
        }

        private func openBook() {
            guard let bookBase64, let bookExt else {
                Task { @MainActor in onError("Book file could not be read") }
                return
            }
            let js = """
            (async () => {
                try {
                    const b64 = "\(bookBase64)";
                    const binary = atob(b64);
                    const bytes = new Uint8Array(binary.length);
                    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
                    const file = new File([bytes], "book.\(bookExt)");
                    await readerAPI.open(file);
                } catch(e) {
                    window.webkit?.messageHandlers?.error?.postMessage({
                        message: 'openBook: ' + (e.message || e), type: 'open'
                    });
                }
            })()
            """
            webView?.evaluateJavaScript(js) { _, error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.onError("JS eval: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?
    init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        delegate?.userContentController(c, didReceive: m)
    }
}
