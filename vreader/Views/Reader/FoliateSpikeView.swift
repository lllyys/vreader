// Purpose: Spike view for AZW3/MOBI rendering via Foliate-js.
// Uses loadHTMLString + inline IIFE bundle + base64 book handoff.
// This is the PROVEN approach that worked on device.

import SwiftUI
import SwiftData
import WebKit
import OSLog

struct FoliateSpikeView: View {
    let bookURL: URL
    /// Bug #141: book identity for the DebugBridge eval registry binding.
    /// Optional so existing call sites (previews, tests) stay
    /// source-compatible. Threaded into the spike's WKWebView coordinator
    /// so `webView(_:didFinish:)` can pair `(webView, fingerprintKey)` in
    /// `DebugReaderRegistry`.
    var fingerprintKey: String?
    /// Bug #142: per-reader instance token paired with fingerprintKey.
    var readerToken: UUID?
    /// Bug #189: source of `epubLayout` for the AZW3/MOBI reading-mode
    /// toggle (Scroll/Paged). Optional so legacy call sites (previews,
    /// tests) compile; nil resolves to scrolled via `FoliateLayoutFlowMapper`.
    var settingsStore: ReaderSettingsStore?
    /// Bug #199 / GH #733: optional inline-menu presenter for tap-on-
    /// highlight. When nil (preview / test harness), the menu skips —
    /// `.readerHighlightTapped` still fires from WI-5 so other observers
    /// (annotations panel, etc.) react.
    var highlightActionPresenter: (any HighlightActionPresenting)?

    @State private var isBookReady = false
    @State private var bookTitle = ""
    @State private var errorMessage: String?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            FoliateSpikeWebView(
                bookURL: bookURL,
                fingerprintKey: fingerprintKey,
                readerToken: readerToken,
                layoutFlow: FoliateLayoutFlowMapper.layoutFlow(for: settingsStore?.epubLayout),
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
        .foliateHighlightTapHandler(
            fingerprintKey: fingerprintKey,
            presenter: highlightActionPresenter
        )
        .foliateSelectionHandler(fingerprintKey: fingerprintKey)
        .onReceive(NotificationCenter.default.publisher(for: .readerBookmarkRequested)) { _ in
            guard let key = fingerprintKey,
                  let fp = DocumentFingerprint(canonicalKey: key) else { return }
            let locator = Locator(bookFingerprint: fp,
                                  href: nil, progression: nil, totalProgression: nil,
                                  cfi: nil, page: nil, charOffsetUTF16: nil,
                                  charRangeStartUTF16: nil, charRangeEndUTF16: nil,
                                  textQuote: nil, textContextBefore: nil, textContextAfter: nil)
            let persistence = PersistenceActor(modelContainer: modelContext.container)
            Task {
                do {
                    try await persistence.addBookmark(
                        locator: locator,
                        title: nil,
                        toBookWithKey: key
                    )
                    HapticFeedbackProvider().triggerLightImpact()
                } catch {}
            }
        }
    }
}

private struct FoliateSpikeWebView: UIViewRepresentable {
    let bookURL: URL
    /// Bug #141: threaded from FoliateSpikeView for DebugBridge registry
    /// binding. Set on the Coordinator so didFinish can register the
    /// live webview with `setActiveFoliateWebView(_:for:token:)`.
    let fingerprintKey: String?
    /// Bug #142: per-reader instance token paired with fingerprintKey.
    let readerToken: UUID?
    /// Bug #189: pre-mapped layoutFlow value ("paginated" or "scrolled").
    /// SwiftUI re-evaluates `body` when `settingsStore.epubLayout` changes
    /// (the store is `@Observable @MainActor`), so this value reaches
    /// `updateUIView` as soon as the user toggles reading mode.
    let layoutFlow: String
    let onBookReady: @MainActor (String) -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> FoliateSpikeView.Coordinator {
        let coord = FoliateSpikeView.Coordinator(
            initialLayoutFlow: layoutFlow,
            onBookReady: onBookReady,
            onError: onError
        )
        coord.fingerprintKey = fingerprintKey
        #if DEBUG
        coord.readerToken = readerToken
        #endif
        return coord
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
            // Bug #189: posted by the book-ready iife after `await
            // readerAPI.init({})` and the first `setLayout(...)` actually
            // resolve. We can't use the `evaluateJavaScript` completion
            // for this because it fires when the top-level expression
            // evaluates (the iife's Promise creation), not when the
            // awaited init resolves.
            "layout-ready",
        ] {
            config.userContentController.add(WeakScriptMessageHandler(coordinator), name: name)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        webView.navigationDelegate = coordinator
        // Bug #189: scrollView is the outer container the document renders into.
        // In paginated mode foliate-js consumes touches and paginates internally
        // (outer scroll must be off). In scrolled mode the document is one long
        // page and the outer scrollView IS the scroller. Mirrors EPUBWebViewBridge
        // line 226 (`webView.scrollView.isScrollEnabled = !isPaged`).
        webView.scrollView.isScrollEnabled = (layoutFlow == "scrolled")
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

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Bug #189: live-toggle reading mode. SwiftUI re-evaluates body when
        // `settingsStore.epubLayout` changes (@Observable). We compare against
        // the coordinator's last-applied value to avoid redundant JS calls.
        let coordinator = context.coordinator
        let safeFlow = FoliateJSEscaper.sanitizeFlow(layoutFlow)
        guard coordinator.currentLayoutFlow != safeFlow else { return }
        coordinator.currentLayoutFlow = safeFlow
        uiView.scrollView.isScrollEnabled = (safeFlow == "scrolled")
        // Always stash the latest preference into the JS-side global. The
        // book-ready iife reads this AFTER its `await readerAPI.init({})`
        // resolves, so a toggle that lands while init is still in flight
        // is captured (it queues behind init's outer call, runs at the
        // await yield, and is picked up when init resumes). Once
        // `isBookReady` is true we ALSO call setLayout directly so the
        // user sees the change immediately rather than waiting for the
        // next open.
        let stash = "window.__vreaderTargetFlow = '\(safeFlow)';"
        if coordinator.isBookReady {
            let js = "\(stash) readerAPI.setLayout({flow: '\(safeFlow)'});"
            uiView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            uiView.evaluateJavaScript(stash, completionHandler: nil)
        }
    }
}

extension FoliateSpikeView {
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var bookBase64: String?
        var bookExt: String?
        let onBookReady: @MainActor (String) -> Void
        let onError: @MainActor (String) -> Void
        /// Bug #189: layoutFlow string applied to readerAPI. Initialized from
        /// the SwiftUI value at coordinator construction; updated by both the
        /// `book-ready` handler (initial apply) and `updateUIView`
        /// (live-toggle). Sanitized via `FoliateJSEscaper.sanitizeFlow` at
        /// write time so JS interpolation is safe.
        var currentLayoutFlow: String
        /// True once `readerAPI.init({})` has been issued (book-ready handler).
        /// `updateUIView` checks this before pushing `setLayout` because the
        /// JS-side renderer isn't attached until after init.
        var isBookReady: Bool = false
        /// Bug #141 / Feature #53 WI-5: book identity needed by the
        /// DebugBridge eval registry (DEBUG only) AND by the production
        /// `annotation-show` handler that posts the resolver request with
        /// a per-reader filter. Set by `makeCoordinator()` from the
        /// SwiftUI binding regardless of build configuration.
        var fingerprintKey: String?
        #if DEBUG
        /// Bug #142: per-reader instance token paired with fingerprintKey.
        var readerToken: UUID?
        #endif

        /// Bug #199 / GH #733: observer token for
        /// `.foliateRequestAnnotationJSDelete`. The outer view posts this
        /// after persistence delete fires; the Coordinator picks it up
        /// (its `webView` is in scope) and evaluates
        /// `readerAPI.deleteAnnotation` so the rendered annotation
        /// disappears from the Foliate-js overlay without waiting for
        /// the next book reopen. `nonisolated(unsafe)` mirrors the
        /// TXT coordinator pattern — the Coordinator is effectively
        /// `@MainActor`-isolated at use time but the deinit is
        /// nonisolated, so the property cannot be MainActor-isolated.
        nonisolated(unsafe) private var foliateJSDeleteToken: NSObjectProtocol?

        /// Bug #201 / GH #739: sibling of `foliateJSDeleteToken` for
        /// the create path. The outer view posts
        /// `.foliateRequestAnnotationJSCreate` after persistence add
        /// fires; this observer evaluates
        /// `FoliateHighlightRenderer.addAnnotationJS` on the live
        /// WebView so the rendered annotation appears immediately.
        nonisolated(unsafe) private var foliateJSCreateToken: NSObjectProtocol?

        init(initialLayoutFlow: String,
             onBookReady: @escaping @MainActor (String) -> Void,
             onError: @escaping @MainActor (String) -> Void) {
            self.currentLayoutFlow = FoliateJSEscaper.sanitizeFlow(initialLayoutFlow)
            self.onBookReady = onBookReady
            self.onError = onError
            super.init()
            self.foliateJSDeleteToken = NotificationCenter.default.addObserver(
                forName: .foliateRequestAnnotationJSDelete,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self,
                      let info = notification.userInfo,
                      let cfi = info["cfi"] as? String, !cfi.isEmpty,
                      let key = info["fingerprintKey"] as? String,
                      key == self.fingerprintKey else { return }
                // Reuse the canonical Foliate JS builder so the escape
                // semantics stay aligned with the renderer's
                // `addAnnotationJS` / `restoreAllJS` paths.
                let js = FoliateHighlightRenderer.removeAnnotationJS(cfi: cfi)
                // The observer's queue is `.main`, so this closure runs on
                // the main thread; the WKWebView API is safe to call from
                // here. `assumeIsolated` documents the contract for the
                // type-checker.
                MainActor.assumeIsolated {
                    self.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
            self.foliateJSCreateToken = NotificationCenter.default.addObserver(
                forName: .foliateRequestAnnotationJSCreate,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self,
                      let info = notification.userInfo,
                      let cfi = info["cfi"] as? String, !cfi.isEmpty,
                      let color = info["color"] as? String, !color.isEmpty,
                      let key = info["fingerprintKey"] as? String,
                      key == self.fingerprintKey else { return }
                let js = FoliateHighlightRenderer.addAnnotationJS(cfi: cfi, color: color)
                MainActor.assumeIsolated {
                    self.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }

        deinit {
            if let token = foliateJSDeleteToken {
                NotificationCenter.default.removeObserver(token)
            }
            if let token = foliateJSCreateToken {
                NotificationCenter.default.removeObserver(token)
            }
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            let name = message.name
            let body = message.body
            Task { @MainActor in
                await self.handleMessage(name: name, body: body)
            }
        }

        /// MainActor-isolated message router. Extracted so unit tests
        /// can exercise specific cases (bug #108) without constructing
        /// a real `WKScriptMessage` (whose initializer is internal to
        /// WebKit).
        @MainActor
        func handleMessage(name: String, body: Any) async {
            switch name {
            case "bridge-ready":
                openBook()

            case "book-ready":
                if let dict = body as? [String: Any] {
                    let title = dict["title"] as? String ?? "Unknown"
                    onBookReady(title)
                    // Bug #189: init the renderer, then apply the freshest
                    // reading-mode preference, then post `layout-ready` so
                    // native flips `isBookReady` only AFTER the renderer
                    // truly exists.
                    //
                    // Why a message post instead of the evaluateJavaScript
                    // completion: WKWebView's completion fires when the
                    // top-level expression evaluates — for an async iife,
                    // that's when the Promise is created, NOT when its
                    // awaited init resolves. Using the completion would
                    // flip `isBookReady` early and let `updateUIView`
                    // push `setLayout(...)` while `view.renderer` is still
                    // nil (foliate-host.js:234 returns early).
                    //
                    // Why the JS-side global: any `updateUIView` that fires
                    // during the awaited init yields at the `await`, queued
                    // stash JS updates `window.__vreaderTargetFlow`, and
                    // the iife reads the freshest value when init resumes.
                    let initialFlow = currentLayoutFlow
                    let js = """
                    (async () => {
                        if (typeof window.__vreaderTargetFlow !== 'string') {
                            window.__vreaderTargetFlow = '\(initialFlow)';
                        }
                        await readerAPI.init({});
                        readerAPI.setLayout({flow: window.__vreaderTargetFlow});
                        post('layout-ready', {});
                    })();
                    """
                    webView?.evaluateJavaScript(js, completionHandler: nil)
                }

            case "layout-ready":
                // Bug #189: posted by the book-ready iife after init +
                // initial setLayout actually resolve. Flipping here (and
                // only here) closes the Codex round-3 race where
                // `updateUIView` could push `setLayout` against a not-yet
                // attached renderer.
                isBookReady = true

            case "tap":
                // Bug #108: forward center-tap to the chrome-toggle
                // observer in `ReaderContainerView`. Without this case
                // the toolbar stayed visible because the JS bundle's
                // `tap` message hit the default branch and silently
                // no-oped.
                NotificationCenter.default.post(name: .readerContentTapped, object: nil)

            case "selection":
                // Bug #201 / GH #739: user finished a long-press selection
                // in AZW3/MOBI. Parse via FoliateMessageParser (rejects
                // collapsed selections, validates the rect dict), then
                // hand the payload to the outer view via
                // `.foliateSelectionDetected` so the action sheet
                // (Highlight / Cancel) can present from `modelContext`
                // scope. Without this case the registered "selection"
                // handler at line 129 silently no-ops and the user gets
                // iOS's default WKWebView menu (Copy / Look Up / …) with
                // no Highlight option.
                if let parsed = FoliateMessageParser.parseSelection(body),
                   let info = FoliateSelectionDispatcher.notificationUserInfo(
                    event: parsed,
                    fingerprintKey: self.fingerprintKey
                   ) {
                    NotificationCenter.default.post(
                        name: .foliateSelectionDetected,
                        object: nil,
                        userInfo: info
                    )
                }

            case "annotation-show":
                // Feature #53 WI-5: user tapped an existing highlight in the
                // Foliate-rendered (AZW3/MOBI) reader. The bridge forwards
                // `e.detail.value` (the CFI) as `value`. Forward to the
                // outer view (which has `modelContext` in scope) so the
                // CFI can be resolved to the persisted highlight's UUID
                // and `.readerHighlightTapped` posted. Filtered by
                // `fingerprintKey` so concurrent Foliate readers don't
                // cross-fire.
                if let dict = body as? [String: Any],
                   let value = dict["value"] as? String,
                   let key = self.fingerprintKey {
                    NotificationCenter.default.post(
                        name: .foliateAnnotationTapRequested,
                        object: nil,
                        userInfo: ["cfi": value, "fingerprintKey": key]
                    )
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Bug #141: register the live spike WKWebView with
            // DebugReaderRegistry, paired with the book's fingerprintKey
            // so eval can verify identity at call-time. Mirrors the bug
            // #126 EPUB pattern. Skip when key not yet threaded.
            #if DEBUG
            if let key = fingerprintKey, let token = readerToken {
                DebugReaderRegistry.shared.setActiveFoliateWebView(webView, for: key, token: token)
            }
            #endif
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
            })(); void 0;
            """
            webView?.evaluateJavaScript(js) { _, _ in }
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
