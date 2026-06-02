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
    /// Feature #57: set in `makeCoordinator()` so the parent
    /// (`ReaderContainerView`) can request whole-book TTS text
    /// extraction once the book is ready. Optional → preview/test call
    /// sites stay source-compatible (same pattern as `fingerprintKey`,
    /// `readerToken`, `settingsStore`).
    var coordinatorBox: FoliateCoordinatorBox?

    @State private var isBookReady = false
    @State private var bookTitle = ""
    @State private var errorMessage: String?
    /// Feature #64 WI-9: the Foliate `HighlightMutating` boundary for the
    /// unified highlight-action popover. Built in `.task` (the model container
    /// + fingerprintKey are available then). Foliate has no `HighlightRenderer`,
    /// so this is `FoliateHighlightMutator` (persistence + JS bridge), not a
    /// `HighlightCoordinator`. The attach helper is inert until it is non-nil.
    @State private var highlightMutator: FoliateHighlightMutator?
    @Environment(\.modelContext) private var modelContext

    /// Feature #70 WI-4: the default unified font size used when no
    /// `settingsStore` is available (previews / tests). Matches
    /// `TypographySettings`'s default.
    static let defaultUnifiedFontSize: CGFloat = 18

    /// Feature #70 WI-4: builds the Foliate-js `setStyles` CSS for AZW3/MOBI
    /// — first-time font-size wiring for the live spike path. The body font
    /// size routes through the calibrator's `.foliate` target (rounded +
    /// clamped to `8...72` by `calibratedFoliateSize`) so AZW3/MOBI renders
    /// at a size perceptually consistent with TXT (the calibration anchor) at
    /// the same slider value; the line height rides with it.
    ///
    /// Theme colors / font-family are deliberately NOT wired here — the spike
    /// never themed those and AZW3/MOBI theme-color parity is a separate gap
    /// (see the feature #70 plan's "files OUT of scope"). The CSS sets
    /// `font-size` + `line-height` only.
    ///
    /// A `nil` store falls back to the documented default unified size (18)
    /// so previews / tests never crash. Extracted as a pure static helper so
    /// the WI-4 CSS-construction seam is directly unit-testable.
    static func themeCSS(for store: ReaderSettingsStore?) -> String? {
        let unified = store?.typography.fontSize ?? defaultUnifiedFontSize
        let lineHeight = Double(store?.typography.lineSpacing ?? 1.4)
        let calibrator = store?.calibrator ?? FontSizeCalibrator()
        let base = FoliateStyleMapper.themeCSS(
            fontSize: calibrator.calibratedFoliateSize(forUnified: unified),
            lineHeight: lineHeight,
            fontFamily: nil,
            textColor: nil,
            backgroundColor: nil
        )
        // Bug #304: append the `.vreader-bilingual` interlinear rule so the
        // bilingual blocks the Foliate bilingual JS injects get the designed
        // style (AZW3/MOBI render via Foliate `setStyles`, which never threaded
        // `epubOverrideCSS`). Harmless when no bilingual content exists.
        let parts = [base, store?.theme.bilingualBlockCSSRule()].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    var body: some View {
        ZStack {
            FoliateSpikeWebView(
                bookURL: bookURL,
                fingerprintKey: fingerprintKey,
                readerToken: readerToken,
                layoutFlow: FoliateLayoutFlowMapper.layoutFlow(for: settingsStore?.epubLayout),
                themeCSS: Self.themeCSS(for: settingsStore),
                coordinatorBox: coordinatorBox,
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
        .foliateHighlightTapHandler(fingerprintKey: fingerprintKey)
        .foliateSelectionHandler(fingerprintKey: fingerprintKey)
        .foliateHighlightRestoreHandler(fingerprintKey: fingerprintKey)
        // Feature #64 WI-9: a tap on a persisted AZW3/MOBI highlight opens the
        // unified cross-format highlight-action popover (color / note / copy /
        // share / delete) — superseding feature #55's read-only note preview.
        // `foliateHighlightTapHandler` posts `.readerHighlightTapped` when the
        // user taps a highlight; `HighlightPopoverModifier` (attached here)
        // observes it. The Foliate event carries `sourceRect == .zero`, so the
        // popover resolves to the bottom-sheet form. `mutating` is the
        // `FoliateHighlightMutator` (Foliate has no `HighlightRenderer`, so it
        // composes persistence + the JS-overlay bridge). Inert in previews /
        // test harnesses where the mutator is nil.
        .unifiedHighlightPopoverPresenterIfAvailable(
            modelContainer: modelContext.container,
            bookFingerprintKey: fingerprintKey ?? "",
            mutating: highlightMutator,
            theme: settingsStore?.theme ?? .paper
        )
        .task {
            // Build the Foliate highlight-mutation boundary once. The
            // `@State` flip makes SwiftUI recompute `body` and install the
            // live popover modifier (the helper is inert while it is nil) —
            // the same late-assignment pattern the native containers use.
            guard highlightMutator == nil, let key = fingerprintKey else { return }
            highlightMutator = FoliateHighlightMutator(
                persistence: PersistenceActor(modelContainer: modelContext.container),
                bookFingerprintKey: key
            )
        }
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
    /// Feature #70 WI-4: the calibrated Foliate `setStyles` CSS
    /// (`font-size` + `line-height`). SwiftUI re-evaluates `body` when
    /// `settingsStore.typography` changes (@Observable), so a font-size
    /// slider change reaches `updateUIView` and `updateUIView`'s themeCSS
    /// branch pushes it via `readerAPI.setStyles`. `nil` only when the spike
    /// has no `settingsStore` (previews / tests).
    let themeCSS: String?
    /// Feature #57: parent-owned handle; `makeCoordinator()` assigns the
    /// live Coordinator into it so the TTS path can call
    /// `extractPlainText()`.
    let coordinatorBox: FoliateCoordinatorBox?
    let onBookReady: @MainActor (String) -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> FoliateSpikeView.Coordinator {
        let coord = FoliateSpikeView.Coordinator(
            initialLayoutFlow: layoutFlow,
            initialThemeCSS: themeCSS,
            onBookReady: onBookReady,
            onError: onError
        )
        coord.fingerprintKey = fingerprintKey
        #if DEBUG
        coord.readerToken = readerToken
        #endif
        // Feature #57: hand the live Coordinator to the parent so
        // `ReaderContainerView`'s TTS path can request whole-book text
        // extraction once the book has rendered.
        coordinatorBox?.coordinator = coord
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
            // Feature #56 WI-11: AZW3/MOBI bilingual enumerate
            // channel. `readerAPI.bilingualEnumerate()` posts an
            // ordered `[{bid, text}]` array after stamping each
            // translatable block in the current section's rendered
            // DOM. Handled in the Coordinator's `handleMessage`
            // switch and forwarded to the SwiftUI layer via
            // `.foliateBilingualBlocksEnumerated`.
            "bilingualEnumerate",
        ] {
            config.userContentController.add(WeakScriptMessageHandler(coordinator), name: name)
        }

        // Feature #76 WI-5 verification harness: with no real vertical-rl AZW3
        // fixture, the DEBUG `--force-foliate-vertical-rl` launch flag makes the
        // paginator's section `afterLoad` inject `writing-mode: vertical-rl` BEFORE
        // `getDirection` runs — so a real (horizontal) AZW3 exercises the vertical
        // windowed-scroll axis path on-device. The flag is only honored in DEBUG;
        // in Release the value is hard-`false`. Gate-4 Medium: define the global
        // NON-WRITABLE / NON-CONFIGURABLE in EVERY build (at document start) so a
        // scripted book's iframe cannot set `parent.__vreaderForceVerticalRL` to
        // force the debug path — only this launch flag can.
        let forceVerticalRL: Bool = {
            #if DEBUG
            return ProcessInfo.processInfo.arguments.contains("--force-foliate-vertical-rl")
            #else
            return false
            #endif
        }()
        config.userContentController.addUserScript(WKUserScript(
            source: "Object.defineProperty(window,'__vreaderForceVerticalRL',"
                + "{value:\(forceVerticalRL),writable:false,configurable:false});",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))

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
        #if DEBUG
        webView.scrollView.delegate = coordinator  // Feature #73 WI-0 spike (throwaway)
        #endif

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
        // SwiftUI re-evaluates `body` when `settingsStore` changes
        // (@Observable) — `epubLayout` for reading mode (bug #189),
        // `typography` for font size (feature #70 WI-4). Both reach here.
        //
        // Feature #70 WI-4 — control flow MUST diff layout and theme
        // INDEPENDENTLY, with NO early return. A font-size-only slider change
        // leaves `layoutFlow` unchanged; a `guard currentLayoutFlow !=
        // safeFlow else { return }` (the pre-WI-4 shape) would dead-code the
        // `themeCSS` branch and the slider would still be a no-op. Mirrors
        // `FoliateViewBridge.updateUIView`'s two-if-branch shape.
        let coordinator = context.coordinator
        let safeFlow = FoliateJSEscaper.sanitizeFlow(layoutFlow)

        // --- Layout-flow branch (bug #189 live-toggle reading mode) ---
        if coordinator.currentLayoutFlow != safeFlow {
            coordinator.currentLayoutFlow = safeFlow
            uiView.scrollView.isScrollEnabled = (safeFlow == "scrolled")
            // Always stash the latest preference into the JS-side global. The
            // book-ready iife reads this AFTER its `await readerAPI.init({})`
            // resolves, so a toggle that lands while init is still in flight
            // is captured. Once `isBookReady` is true we ALSO call setLayout
            // directly so the user sees the change immediately.
            let stash = "window.__vreaderTargetFlow = '\(safeFlow)';"
            if coordinator.isBookReady {
                let js = "\(stash) readerAPI.setLayout({flow: '\(safeFlow)'});"
                uiView.evaluateJavaScript(js, completionHandler: nil)
            } else {
                uiView.evaluateJavaScript(stash, completionHandler: nil)
            }
        }

        // --- Theme-CSS branch (feature #70 WI-4 font-size wiring) ---
        // Diffed independently of layout so a font-size-only change fires.
        if coordinator.currentThemeCSS != themeCSS {
            coordinator.currentThemeCSS = themeCSS
            // ALWAYS stash the latest calibrated CSS into a JS-side global,
            // exactly like the layout branch stashes `window.__vreaderTargetFlow`.
            //
            // Why the global (Gate-4 audit Medium fix): `setStyles` is a no-op
            // before `readerAPI.init({})` resolves, so the pre-ready push must
            // be deferred to the `book-ready` iife. But that iife snapshots
            // its JS *before* `await readerAPI.init({})`; a font-size change
            // landing during the init window would otherwise be lost — the
            // iife would apply the stale snapshot, and no later `updateUIView`
            // diff fires because `currentThemeCSS` already equals the newest
            // value. Stashing into a JS-side global the iife reads AFTER its
            // `await` closes that race: a mid-init change updates the global,
            // and the resuming iife picks up the freshest value.
            if let css = themeCSS {
                let escaped = FoliateJSEscaper.escapeForJSString(css)
                let stash = "window.__vreaderTargetThemeCSS = '\(escaped)';"
                if coordinator.isBookReady {
                    // Ready → stash AND apply immediately.
                    let js = "\(stash) \(Coordinator.setStylesJS(forCSS: css))"
                    uiView.evaluateJavaScript(js, completionHandler: nil)
                } else {
                    // Pre-ready → stash only; the `book-ready` iife applies it
                    // post-init, reading the freshest stashed value.
                    uiView.evaluateJavaScript(stash, completionHandler: nil)
                }
            }
        }
    }
}

extension FoliateSpikeView {
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, UIScrollViewDelegate {
        weak var webView: WKWebView?
        #if DEBUG
        // Feature #73 WI-0 spike: instrument the OUTER WKWebView scrollView to
        // measure whether it is the actual scroller in scrolled mode, or whether
        // the inner shadow-DOM #container (overflow:auto) scrolls instead.
        // Throwaway spike instrumentation; reverted before WI-0 ships.
        private let wi0Log = Logger(subsystem: "com.vreader.app", category: "Feat73WI0")
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            wi0Log.info("OUTER scrollView.contentOffset.y=\(scrollView.contentOffset.y, privacy: .public) contentSize.h=\(scrollView.contentSize.height, privacy: .public) bounds.h=\(scrollView.bounds.height, privacy: .public)")
        }
        #endif
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
        /// Feature #70 WI-4: the last Foliate `setStyles` CSS applied to
        /// `readerAPI`. `updateUIView` diffs the incoming `themeCSS` against
        /// this and pushes `setStyles` only on a change — mirrors
        /// `currentLayoutFlow`. The `book-ready` handler also seeds the
        /// initial value (pre-ready belt-and-braces) so the first calibrated
        /// size lands even if no slider change ever fires.
        var currentThemeCSS: String?
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
        /// `.foliateRequestAnnotationJSDelete`. When a `.foliateRequestAnnotationJSDelete`
        /// notification (carrying a `cfi`) is posted, the Coordinator picks
        /// it up (its `webView` is in scope) and evaluates
        /// `readerAPI.deleteAnnotation` so the rendered annotation
        /// disappears from the Foliate-js overlay without waiting for the
        /// next book reopen.
        ///
        /// Feature #55 WI-7 removed the only former producer of this
        /// notification (`FoliateHighlightTapHandlerModifier.performDelete`,
        /// the now-dropped tap-time #53 delete). This observer is therefore
        /// currently a **dormant hook**: it is kept — rather than removed —
        /// because the panel-delete → AZW3/MOBI overlay-strip follow-up
        /// (which needs a CFI plumbed through from `HighlightListViewModel`)
        /// will re-use exactly this notification + observer. See the
        /// separately-tracked bug for the overlay-strip gap.
        ///
        /// `nonisolated(unsafe)` mirrors the TXT coordinator pattern — the
        /// Coordinator is effectively `@MainActor`-isolated at use time but
        /// the deinit is nonisolated, so the property cannot be
        /// MainActor-isolated.
        nonisolated(unsafe) private var foliateJSDeleteToken: NSObjectProtocol?

        /// Bug #201 / GH #739: sibling of `foliateJSDeleteToken` for
        /// the create path. The outer view posts
        /// `.foliateRequestAnnotationJSCreate` after persistence add
        /// fires; this observer evaluates
        /// `FoliateHighlightRenderer.addAnnotationJS` on the live
        /// WebView so the rendered annotation appears immediately.
        nonisolated(unsafe) private var foliateJSCreateToken: NSObjectProtocol?

        /// Feature #56 WI-11: observer for
        /// `.foliateRequestBilingualEvalJS`. The bilingual container
        /// posts arbitrary JS payloads (enumerate / inject / clear)
        /// scoped by fingerprintKey; this observer evaluates them
        /// against the live `WKWebView`. Same lifecycle / queue
        /// pattern as the highlight observers above.
        nonisolated(unsafe) private var foliateBilingualEvalToken: NSObjectProtocol?

        /// Bug #239 — observer for `.readerNextPage`. Side-tap in paged
        /// AZW3/MOBI: `ReaderTapZoneRouter.dispatch(...)` (driven by the
        /// foliate-host.js content-tap handler's `{x, w}` payload) posts
        /// this notification; the observer evaluates `readerAPI.next()`
        /// against the live `WKWebView`. The notification is global, so
        /// the observer cannot be filtered by `fingerprintKey` — Foliate
        /// spikes deinit when their reader unmounts, so a stale observer
        /// from an outgoing reader can't fire after dismissal.
        nonisolated(unsafe) private var foliateNextPageToken: NSObjectProtocol?

        /// Bug #239 — observer for `.readerPreviousPage`. Sibling of
        /// `foliateNextPageToken`; evaluates `readerAPI.prev()`.
        nonisolated(unsafe) private var foliatePrevPageToken: NSObjectProtocol?

        /// Bug #260 — observer for `.foliateRequestSeekFraction`. The
        /// AZW3/MOBI bottom-chrome scrubber posts a target `fraction`
        /// (filtered by `fingerprintKey`); this observer evaluates
        /// `readerAPI.goToFraction(<clamped>)` against the live
        /// `WKWebView`. The JS is built by `FoliateBottomChromeSeek`
        /// (clamp + finite-literal guard). Same `.main` queue +
        /// `MainActor.assumeIsolated` lifecycle as the sibling
        /// page-turn / annotation observers; released in `deinit`.
        nonisolated(unsafe) private var foliateSeekFractionToken: NSObjectProtocol?

        /// Bug #262 — observer for `.foliateRequestSeekTarget`. A shared
        /// TOC / Notes / Highlight row tap (relayed by
        /// `FoliateBilingualContainerView`) posts a navigation `target`
        /// (CFI or href, filtered by `fingerprintKey`); this observer
        /// evaluates `readerAPI.goTo('<escaped>')` against the live
        /// `WKWebView`. JS is built by `FoliateNavSeek.goToTargetJS`
        /// (escape + empty guard). Same `.main` queue + `MainActor.assumeIsolated`
        /// lifecycle as the sibling seek-fraction observer; released in `deinit`.
        nonisolated(unsafe) private var foliateSeekTargetToken: NSObjectProtocol?

        init(initialLayoutFlow: String,
             initialThemeCSS: String? = nil,
             onBookReady: @escaping @MainActor (String) -> Void,
             onError: @escaping @MainActor (String) -> Void) {
            self.currentLayoutFlow = FoliateJSEscaper.sanitizeFlow(initialLayoutFlow)
            // Feature #70 WI-4: seed the theme CSS so the `book-ready` handler
            // can apply the initial calibrated font size post-`init` even if
            // no slider change ever fires (pre-ready belt-and-braces).
            self.currentThemeCSS = initialThemeCSS
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
            // Feature #56 WI-11: the bilingual container posts arbitrary
            // JS payloads (enumerate / inject / clear) here. Same queue
            // (`.main`) + `MainActor.assumeIsolated` pattern as the
            // sibling create/delete observers.
            self.foliateBilingualEvalToken = NotificationCenter.default.addObserver(
                forName: .foliateRequestBilingualEvalJS,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self,
                      let info = notification.userInfo,
                      let js = info["js"] as? String, !js.isEmpty,
                      let key = info["fingerprintKey"] as? String,
                      key == self.fingerprintKey else { return }
                MainActor.assumeIsolated {
                    self.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
            // Bug #239 — paged-mode side-tap → page-turn observers. The
            // content-tap handler (foliate-host.js → spike's `tap` case →
            // `ReaderTapZoneRouter.dispatch`) posts `.readerNextPage` /
            // `.readerPreviousPage`; these observers call into the
            // Foliate-js engine via `readerAPI.next()` / `prev()`. The
            // notification is global (no fingerprintKey filter) — the
            // observer is removed in `deinit` when the reader unmounts,
            // so a stale post from a previous reader cannot reach this
            // coordinator.
            self.foliateNextPageToken = NotificationCenter.default.addObserver(
                forName: .readerNextPage,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                MainActor.assumeIsolated {
                    self.webView?.evaluateJavaScript("readerAPI.next();", completionHandler: nil)
                }
            }
            self.foliatePrevPageToken = NotificationCenter.default.addObserver(
                forName: .readerPreviousPage,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                MainActor.assumeIsolated {
                    self.webView?.evaluateJavaScript("readerAPI.prev();", completionHandler: nil)
                }
            }
            // Bug #260 — bottom-chrome scrubber seek. Filtered by
            // `fingerprintKey` (unlike the global page-turn observers)
            // because a stale seek from an outgoing reader could
            // otherwise jump a freshly-opened second reader. The JS
            // builder clamps the fraction to a finite 0...1 literal.
            self.foliateSeekFractionToken = NotificationCenter.default.addObserver(
                forName: .foliateRequestSeekFraction,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self,
                      let info = notification.userInfo,
                      let fraction = info["fraction"] as? Double,
                      let key = info["fingerprintKey"] as? String,
                      key == self.fingerprintKey else { return }
                let js = FoliateBottomChromeSeek.goToFractionJS(fraction)
                MainActor.assumeIsolated {
                    self.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
            // Bug #262 — TOC / Notes / Highlight row-tap navigation. The
            // bilingual container relays `.readerNavigateToLocator` here as a
            // resolved `target` (CFI or href). Filtered by `fingerprintKey`
            // (like the seek-fraction observer) so a stale navigation from an
            // outgoing reader cannot jump a freshly-opened second reader. The
            // JS builder escapes the target and no-ops on an empty target.
            self.foliateSeekTargetToken = NotificationCenter.default.addObserver(
                forName: .foliateRequestSeekTarget,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self,
                      let info = notification.userInfo,
                      let target = info["target"] as? String,
                      let key = info["fingerprintKey"] as? String,
                      key == self.fingerprintKey,
                      let js = FoliateNavSeek.goToTargetJS(target) else { return }
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
            if let token = foliateBilingualEvalToken {
                NotificationCenter.default.removeObserver(token)
            }
            // Bug #239 — release the side-tap → page-turn observers so a
            // future notification posted after this coordinator has
            // deinited cannot fire `readerAPI.next/prev` against an
            // already-released `WKWebView` (UIKit dismantle ordering can
            // briefly outlive the coordinator's deinit on iOS).
            if let token = foliateNextPageToken {
                NotificationCenter.default.removeObserver(token)
            }
            if let token = foliatePrevPageToken {
                NotificationCenter.default.removeObserver(token)
            }
            // Bug #260 — release the scrubber-seek observer so a seek
            // posted after this coordinator deinits cannot evaluate
            // `goToFraction` against an already-released `WKWebView`.
            if let token = foliateSeekFractionToken {
                NotificationCenter.default.removeObserver(token)
            }
            // Bug #262 — release the row-tap navigation observer so a
            // `goTo` posted after this coordinator deinits cannot evaluate
            // against an already-released `WKWebView`.
            if let token = foliateSeekTargetToken {
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
                    // Bug #262 / GH #1136: forward the parsed Foliate-js TOC
                    // so the live container (`FoliateBilingualContainerView`)
                    // can build the bottom-chrome Contents list. Pre-fix the
                    // handler dropped everything but `title` (the
                    // `onBookReady: (String) -> Void` boundary), leaving the
                    // AZW3/MOBI Contents sheet permanently empty even when the
                    // book ships a TOC. `parseBookReady` already parses the
                    // `toc` tree; we post it on a dedicated, fingerprintKey-
                    // scoped channel. Empty TOCs are NOT posted so a sparse
                    // book keeps `TOCSheet`'s genuine "no contents" state.
                    if let key = self.fingerprintKey,
                       let info = FoliateMessageParser.parseBookReady(body),
                       !info.toc.isEmpty {
                        NotificationCenter.default.post(
                            name: .foliateBookReadyTOC,
                            object: nil,
                            userInfo: [
                                "toc": info.toc,
                                "fingerprintKey": key,
                            ]
                        )
                    }
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
                    //
                    // Feature #70 WI-4: the iife ALSO applies the calibrated
                    // `setStyles` CSS after init resolves, reading the SAME
                    // kind of JS-side global (`window.__vreaderTargetThemeCSS`).
                    // `setStyles` is a no-op before `readerAPI.init({})` — so
                    // `updateUIView`'s pre-ready themeCSS branch only stashes
                    // into that global; this post-init apply reads it. Reading
                    // the global AFTER the `await` (not snapshotting Swift's
                    // `currentThemeCSS` before) closes the Gate-4-audit race:
                    // a font-size change landing mid-init updates the global
                    // and the resuming iife picks up the freshest value. The
                    // CSS is `FoliateJSEscaper.escapeForJSString`-escaped
                    // (rule 50 bridge safety).
                    let initialFlow = currentLayoutFlow
                    let initialThemeCSSSeed: String
                    if let css = currentThemeCSS {
                        let escaped = FoliateJSEscaper.escapeForJSString(css)
                        initialThemeCSSSeed = """
                        if (typeof window.__vreaderTargetThemeCSS !== 'string') {
                            window.__vreaderTargetThemeCSS = '\(escaped)';
                        }
                        """
                    } else {
                        initialThemeCSSSeed = ""
                    }
                    let js = """
                    (async () => {
                        if (typeof window.__vreaderTargetFlow !== 'string') {
                            window.__vreaderTargetFlow = '\(initialFlow)';
                        }
                        \(initialThemeCSSSeed)
                        await readerAPI.init({});
                        readerAPI.setLayout({flow: window.__vreaderTargetFlow});
                        if (typeof window.__vreaderTargetThemeCSS === 'string') {
                            readerAPI.setStyles(window.__vreaderTargetThemeCSS);
                        }
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
                // Feature #70 WI-4 (Gate-4 round-2 audit fix): reconcile the
                // theme CSS exactly at the ready transition. The book-ready
                // iife reads `window.__vreaderTargetThemeCSS` right after its
                // `await readerAPI.init({})`; a font-size change landing in
                // the narrow window between that read and this `isBookReady`
                // flip would otherwise be lost — `updateUIView` still took
                // the pre-ready (stash-only) branch, and no later SwiftUI
                // diff is guaranteed because `currentThemeCSS` already holds
                // the newest value. Force one `setStyles` of the freshest
                // `currentThemeCSS` here so the latest calibrated size always
                // lands. `setStyles` is idempotent, so a re-apply of the same
                // CSS the iife already pushed is harmless.
                if let css = currentThemeCSS {
                    webView?.evaluateJavaScript(
                        Coordinator.setStylesJS(forCSS: css), completionHandler: nil)
                }

            case "tap":
                // Bug #108: forward the chrome-toggle observer in
                // `ReaderContainerView`. Bug #239: the JS now carries
                // `{x, w}` for non-synthetic clicks; in paginated layout,
                // side zones route to `.readerNextPage` /
                // `.readerPreviousPage` via `ReaderTapZoneRouter`, restoring
                // the producer feature #54 WI-3 deleted. In scrolled layout
                // (Foliate-js owns swipe/scroll internally), every tap
                // collapses to `.readerContentTapped`.
                if let dict = body as? [String: Any],
                   let x = (dict["x"] as? NSNumber)?.doubleValue,
                   let w = (dict["w"] as? NSNumber)?.doubleValue,
                   w > 0 {
                    let layout: EPUBLayoutPreference =
                        (currentLayoutFlow == "paginated") ? .paged : .scroll
                    ReaderTapZoneRouter.dispatch(
                        x: CGFloat(x),
                        totalWidth: CGFloat(w),
                        layout: layout
                    )
                } else {
                    NotificationCenter.default.post(name: .readerContentTapped, object: nil)
                }

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

            case "create-overlay":
                // Bug #207 / GH #765: Foliate-js fires `create-overlay`
                // when a section's SVG overlay is freshly attached and
                // ready to accept `readerAPI.addAnnotation` calls. The
                // body shape is `{index: Int}` (foliate-host.js:48-52).
                // Without this case the message dropped silently and
                // saved AZW3/MOBI highlights never re-painted on book
                // reopen (the create-on-tap path from Bug #201 worked
                // because it ran inside an already-open overlay; the
                // restore-on-load path was never wired).
                //
                // We post `.foliateOverlayReadyForSection` to the outer
                // view (which holds `modelContext`); `FoliateSpikeView+
                // Restore` queries persistence and fans the saved
                // highlights out as per-CFI
                // `.foliateRequestAnnotationJSCreate` events the
                // existing observer at line 301 already evaluates.
                //
                // `addAnnotation` is idempotent on the JS side
                // (view.js:387 `overlayer.remove(value)` precedes add),
                // so refiring on every section's create-overlay is
                // safe — and necessary, because highlights targeting
                // later-loaded sections can't paint until their own
                // overlay exists. Without a `fingerprintKey`, the
                // restore can't route, so drop silently rather than
                // emit a notification the modifier can't filter.
                if let index = FoliateMessageParser.parseCreateOverlay(body),
                   let key = self.fingerprintKey {
                    NotificationCenter.default.post(
                        name: .foliateOverlayReadyForSection,
                        object: nil,
                        userInfo: [
                            "sectionIndex": index,
                            "fingerprintKey": key,
                        ]
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

            case "relocate":
                // Bug #141: `relocate` is the AZW3/MOBI render-complete
                // signal. foliate-js fires it only after the book is
                // paginated and the current location is rendered — the
                // navigation delegate's `didFinish` is just the HTML
                // shell. `FoliateSpikeView` is the live AZW3/MOBI host
                // (ReaderContainerView routes `.azw3` here), so settle
                // must key on `relocate` from THIS coordinator. Mark the
                // reader settled so `vreader-debug://settle` unblocks on
                // real render-complete instead of the 100ms placeholder.
                // DEBUG-only; the registry drops the mark if it's a stale
                // callback from an outgoing reader (key/token guard).
                #if DEBUG
                if let key = fingerprintKey, let token = readerToken {
                    DebugReaderRegistry.shared.markReaderSettled(for: key, token: token)
                }
                #endif
                // Feature #56 WI-11 (Gate-4 audit H1): forward
                // relocate to the bilingual container so a page turn
                // *within* an already-loaded section (no
                // section-load fires) still updates the current-unit
                // tracking. Without this forward, prefetch / inject
                // could target a stale section after the user
                // page-turned into a new section that was already
                // pre-loaded in paginated mode.
                if let key = self.fingerprintKey,
                   let parsed = FoliateMessageParser.parseRelocate(body) {
                    var userInfo: [AnyHashable: Any] = [
                        "sectionIndex": parsed.sectionIndex,
                        "fingerprintKey": key,
                        // Bug #260: the reading-progress fraction (0...1)
                        // drives the bottom-chrome scrubber for AZW3/MOBI.
                        // foliate-host.js always emits `fraction` on
                        // relocate; forwarding it here is what gives the
                        // (previously-missing) bottom bar a live progress
                        // source. `sectionTotal` rides along for the
                        // chapter-position label.
                        "fraction": parsed.fraction,
                        "sectionTotal": parsed.sectionTotal,
                    ]
                    if let href = parsed.tocHref {
                        userInfo["tocHref"] = href
                    }
                    // Bug #260: the current TOC entry label feeds the
                    // bottom-chrome leading label (e.g. the chapter
                    // title). Optional — sparse AZW3/MOBI TOCs omit it.
                    if let label = parsed.tocLabel {
                        userInfo["tocLabel"] = label
                    }
                    NotificationCenter.default.post(
                        name: .foliateRelocated,
                        object: nil,
                        userInfo: userInfo
                    )
                    // Bug #262 / GH #1136: also publish the live reading
                    // position on the shared `.readerPositionDidChange`
                    // channel so the AI panel + DebugBridge probe track where
                    // the AZW3/MOBI reader actually is (parity with the four
                    // native containers, which all post this on a page turn).
                    // Pre-fix this was only produced by the DEAD
                    // `FoliateReaderContainerView`, so the live path never
                    // updated `ReaderContainerView.currentLocator`. The
                    // section href (`tocHref`) + `cfi` anchor the locator.
                    if let locator = FoliateNavSeek.positionLocator(
                        fingerprintKey: key,
                        href: parsed.tocHref,
                        cfi: parsed.cfi,
                        fraction: parsed.fraction
                    ) {
                        NotificationCenter.default.post(
                            name: .readerPositionDidChange,
                            object: locator
                        )
                    }
                }

            case "bilingualEnumerate":
                // Feature #56 WI-11: forward the parsed payload to
                // the SwiftUI host via
                // `.foliateBilingualBlocksEnumerated`. Filtered by
                // `fingerprintKey` so concurrent Foliate readers do
                // not cross-fire (same pattern as `annotation-show`
                // / `create-overlay`).
                //
                // Gate-4 round-3 audit fix: the
                // payload now carries `requestedSectionIndex` so the
                // container can call `clearBlocks(forSection:)` when
                // a previously-populated section re-enumerates empty.
                if let key = self.fingerprintKey {
                    let payload = FoliateBilingualPipeline.parseEnumeratePayload(body)
                    var userInfo: [AnyHashable: Any] = [
                        "blocks": payload.blocks,
                        "fingerprintKey": key,
                    ]
                    if let req = payload.requestedSectionIndex {
                        userInfo["requestedSectionIndex"] = req
                    }
                    NotificationCenter.default.post(
                        name: .foliateBilingualBlocksEnumerated,
                        object: nil,
                        userInfo: userInfo
                    )
                }

            case "section-load":
                // Feature #56 WI-11: forward to the SwiftUI host so
                // the bilingual container can refresh its enumerate
                // payload against the freshly-loaded section. The
                // outer view filters by fingerprintKey and posts an
                // enumerate JS payload back via
                // `.foliateRequestBilingualEvalJS`. Pre-WI-11 this
                // case dropped silently.
                if let key = self.fingerprintKey,
                   let dict = body as? [String: Any],
                   let index = dict["index"] as? Int {
                    NotificationCenter.default.post(
                        name: .foliateSectionLoaded,
                        object: nil,
                        userInfo: [
                            "sectionIndex": index,
                            "fingerprintKey": key,
                        ]
                    )
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

        // MARK: - Feature #70 WI-4: setStyles JS

        /// Feature #70 WI-4: builds the `readerAPI.setStyles('<css>')` JS
        /// call, with the CSS escaped via `FoliateJSEscaper.escapeForJSString`
        /// (rule 50 bridge safety — the CSS could in principle contain a
        /// single-quote or backslash that would break out of the JS string
        /// literal). Pure + static so a unit test can assert the escaping
        /// without a live WKWebView.
        static func setStylesJS(forCSS css: String) -> String {
            let escaped = FoliateJSEscaper.escapeForJSString(css)
            return "readerAPI.setStyles('\(escaped)');"
        }

        // MARK: - Feature #57: TTS text extraction

        /// Feature #57: the async-function body run by
        /// `extractPlainText()`. A fixed string literal — no
        /// interpolation, no injection surface. `callAsyncJavaScript`
        /// treats this as an async function body and awaits the
        /// returned value, so a bare `return await …` resolves the
        /// `readerAPI.extractPlainText()` Promise before the call
        /// completes. Held as a constant so a unit test can assert it
        /// without a live WKWebView.
        static let extractPlainTextScript = "return await readerAPI.extractPlainText();"

        /// Feature #57: upper bound on a single `extractPlainText()`
        /// call. A malformed Foliate section or a wedged WebKit render
        /// could leave the JS extraction hung; `callAsyncJavaScript`
        /// would then suspend forever. The timeout races the JS call
        /// and returns `nil` on expiry so a TTS caller can never wedge.
        static let extractPlainTextTimeout: Duration = .seconds(12)

        /// Feature #57: extract the rendered book's whole-book plain
        /// text for TTS by calling the `foliate-host.js`
        /// `readerAPI.extractPlainText()` helper (a section-walk over
        /// `view.book.sections[].createDocument()`). Returns `nil` if
        /// the webView is gone, the book has not finished rendering,
        /// the JS errored, or the call exceeds `extractPlainTextTimeout`.
        ///
        /// `@MainActor` — `WKWebView.callAsyncJavaScript` requires the
        /// main actor. The Coordinator is used on the main actor in
        /// practice (`handleMessage` is `@MainActor`; the notification
        /// observers hop via `MainActor.assumeIsolated`), but `webView`
        /// is not statically isolated, so this method carries its own
        /// explicit `@MainActor` and is the single main-actor entry for
        /// the production text touch.
        ///
        /// `callAsyncJavaScript` (not `evaluateJavaScript`) is used
        /// deliberately: `evaluateJavaScript`'s completion fires when an
        /// async expression *creates* its Promise, not when the Promise
        /// resolves (see the `book-ready` handler's comment above).
        /// `callAsyncJavaScript` runs the body as an async function and
        /// awaits its return value, so the resolved whole-book `String`
        /// is delivered. The `as? String` coercion maps a JS error /
        /// `NSNull` / any non-String result to `nil`.
        ///
        /// The JS call is wrapped in a `@MainActor` child `Task` raced
        /// against a timeout `Task`; whichever finishes first wins and
        /// the loser is cancelled. A cancelled `callAsyncJavaScript`
        /// throws, which the `try?` maps to `nil` — so a wedged
        /// extraction frees the caller after `extractPlainTextTimeout`.
        @MainActor
        func extractPlainText() async -> String? {
            guard isBookReady, let webView else { return nil }
            let jsTask = Task { @MainActor [webView] () -> String? in
                let raw = try? await webView.callAsyncJavaScript(
                    Coordinator.extractPlainTextScript,
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
                return raw as? String
            }
            let timeoutTask = Task {
                try? await Task.sleep(for: Coordinator.extractPlainTextTimeout)
                return true
            }
            // Race: await the JS result, but if the timeout fires
            // first, cancel the JS task (its `callAsyncJavaScript`
            // throws → `try?` → nil) and return nil.
            return await withTaskGroup(of: String?.self) { group in
                group.addTask { await jsTask.value }
                group.addTask {
                    _ = await timeoutTask.value
                    jsTask.cancel()
                    return nil
                }
                let result = await group.next() ?? nil
                timeoutTask.cancel()
                jsTask.cancel()
                group.cancelAll()
                return result
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
