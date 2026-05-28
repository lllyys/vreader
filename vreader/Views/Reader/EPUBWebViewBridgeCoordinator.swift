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
        /// Bug #251 / GH #1086: bounded fallback delay after `loadFileURL`
        /// is invoked. If `webView(_:didFinish:)` has not fired by the
        /// time this elapses, the coordinator marks the reader settled
        /// and registers the WebView with `DebugReaderRegistry` so the
        /// host-driven `vreader-debug://settle` URL does NOT hit its 30s
        /// timeout when WKWebView's load-complete callback is delayed or
        /// missing. The fallback is idempotent against a late didFinish
        /// — both registry writes safely re-state the same identity.
        /// 2.0 seconds is conservative against the few-hundred-ms typical
        /// load time of a single EPUB chapter on iOS Simulator while
        /// still leaving 28s of harness budget after the fallback fires.
        var earlySettleFallbackDelay: TimeInterval = 2.0
        /// Bug #251 / GH #1086: handle on the in-flight fallback Task,
        /// kept here so a later `didFinish` callback (the happy path)
        /// can cancel the pending fallback before it has a chance to run.
        /// Cancellation is idempotent: a `nil` task is a no-op, and a
        /// completed task is also a no-op.
        var earlySettleFallbackTask: Task<Void, Never>?
        #endif
        /// Callback for text selection events.
        var onSelectionEvent: (@MainActor (ReaderSelectionEvent) -> Void)?
        /// Feature #56 WI-10: receives the `EPUBBilingualEnumeratePayload`
        /// parsed from the JS `bilingualEnumerate` channel after a chapter
        /// loads. `nil` for non-bilingual call sites; the message handler
        /// short-circuits there. Feature #71 WI-7 (Gate-4 round-3 MEDIUM 1):
        /// carries the requested-section identity so an empty scoped enumerate
        /// clears only that section.
        var onBilingualEnumerate: (@MainActor (EPUBBilingualEnumeratePayload) -> Void)?
        /// Callback to restore highlights after page loads.
        /// Provides a JS evaluator so the container can inject restore scripts.
        var onPageDidFinishLoad: (@MainActor (@escaping (String) -> Void) -> Void)?
        /// Whether paged layout mode is active.
        var isPaged = false
        /// Tracks the previous value of isPaged for change detection in updateUIView.
        var previousIsPaged = false
        /// Called when pagination is ready with total page count.
        var onPaginationReady: (@MainActor (Int) -> Void)?
        /// Feature #71 WI-5: non-nil in continuous-scroll mode. The
        /// `continuousScrollHandler` channel routes each boundary signal to
        /// `config.coordinator` (window transitions) and feeds the windowed
        /// whole-book progress to `onProgressChange`. Nil ⇒ legacy single-doc
        /// `progressHandler` path.
        var continuousScroll: EPUBContinuousScrollConfig?
        /// Feature #71 WI-6b-i: set once the bootstrap document has been requested
        /// so `updateUIView` loads it exactly once (a reload would wipe the
        /// stitched multi-chapter DOM).
        var didLoadContinuousBootstrap = false
        private let onProgressChange: @MainActor (Double) -> Void
        private let onLoadError: @MainActor (String) -> Void

        init(
            onProgressChange: @escaping @MainActor (Double) -> Void,
            onLoadError: @escaping @MainActor (String) -> Void
        ) {
            self.onProgressChange = onProgressChange
            self.onLoadError = onLoadError
        }

        #if DEBUG
        deinit {
            // Bug #251 / GH #1086 (Codex round-1 Low): when the Coordinator
            // is dismantled before the early-settle fallback fires (the
            // reader was dismissed within the 2s budget), the in-flight
            // Task must be cancelled — otherwise it can still run after
            // `DebugReaderRegistry.unregister` cleared `expectedReaderToken`
            // to nil, and the stale-write guard (which only rejects
            // mismatched NON-nil expected tokens) would let the fallback
            // re-populate the registry slot for a now-dead reader. The
            // weak-WebView capture in the Task body already short-circuits
            // when the WebView is deallocated, but the WebView may briefly
            // outlive the Coordinator's deinit (UIKit dismantle order), so
            // belt + suspenders.
            //
            // `Task.cancel()` is nonisolated and safe to call from deinit
            // regardless of the Coordinator's actor isolation.
            earlySettleFallbackTask?.cancel()
            earlySettleFallbackTask = nil
        }
        #endif

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "contentTapHandler" {
                // Bug #239 — the JS `contentTapTrackingJS` now sends either a
                // bare `'tap'` (synthetic clicks without coordinates) or a
                // `{x, w}` dict carrying the click's viewport-x and the
                // viewport width. In paged layout, side-tap zones route to
                // `.readerNextPage` / `.readerPreviousPage` via
                // `ReaderTapZoneRouter`; in scroll layout (or when only the
                // bare `'tap'` is available), the router collapses to
                // `.readerContentTapped` — the legacy chrome-toggle.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let dict = message.body as? [String: Any],
                       let x = (dict["x"] as? NSNumber)?.doubleValue,
                       let w = (dict["w"] as? NSNumber)?.doubleValue,
                       w > 0 {
                        ReaderTapZoneRouter.dispatch(
                            x: CGFloat(x),
                            totalWidth: CGFloat(w),
                            layout: self.isPaged ? .paged : .scroll
                        )
                    } else {
                        NotificationCenter.default.post(
                            name: .readerContentTapped, object: nil
                        )
                    }
                }
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
            if message.name == EPUBBilingualJS.enumerateMessageHandlerName {
                handleBilingualEnumerateMessage(message.body)
                return
            }
            if message.name == "continuousScrollHandler" {
                handleContinuousScrollMessage(message.body)
                return
            }
            if message.name == "sectionMaterialized" {
                handleSectionMaterializedMessage(message.body)
                return
            }
            guard message.name == "progressHandler",
                  let progress = message.body as? Double else { return }
            Task { @MainActor in
                onProgressChange(progress)
            }
        }

        /// Feature #71 WI-5: parse a `continuousScrollHandler` boundary signal,
        /// forward it to the window-transition coordinator (WI-4 — materialize /
        /// evict adjacent chapters), and feed the windowed whole-book progress
        /// (`(visibleSpineIndex + intraFraction)/spineCount`) to the existing
        /// `onProgressChange` contract. No-op when the config is absent (the
        /// channel is only registered in continuous mode, but the guard keeps a
        /// stray message safe).
        private func handleContinuousScrollMessage(_ body: Any) {
            guard let config = continuousScroll,
                  let signal = EPUBScrollBoundarySignal.parse(body) else { return }
            let progress = config.windowedProgress(for: signal)
            // WI-6b-i (re-audit finding 1): hand the container the windowed
            // {visibleSpineIndex, intraFraction} so it can persist the chapter
            // the reader scrolled into — `onProgressChange` only carries the
            // whole-book Double, which can't say which section is on screen.
            // Fired synchronously (no Task hop) so the position update isn't
            // reordered behind the window-transition await below.
            config.onWindowedPosition(signal.visibleSpineIndex, signal.intraFraction)
            Task { @MainActor in
                onProgressChange(progress)
                await config.coordinator.handleBoundarySignal(signal)
            }
        }

        /// Feature #71 WI-6b-ii: a chapter section was stitched into the DOM.
        /// Appended/prepended sections never fire `webView(_:didFinish:)` (only
        /// the bootstrap doc does), so this is the per-section lifecycle hook the
        /// container uses to restore that section's highlights (re-rooted into
        /// the section). No-op when the config is absent.
        private func handleSectionMaterializedMessage(_ body: Any) {
            guard let config = continuousScroll,
                  let signal = EPUBSectionMaterialized.parse(body) else { return }
            config.onSectionMaterialized(signal.spineIndex, signal.href)
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

        /// Feature #56 WI-10: parse the `[{bid, text}]` payload posted
        /// by `EPUBBilingualJS.bilingualEnumerateJS` and forward the
        /// `[BilingualBlock]` array to the bilingual VM via the
        /// container's callback. Short-circuits if `onBilingualEnumerate`
        /// is `nil` — the message handler is registered unconditionally
        /// for every EPUB reader, so an active reader that never
        /// invokes the enumerate JS will still receive (and drop) any
        /// stray payload.
        private func handleBilingualEnumerateMessage(_ body: Any) {
            // Feature #71 WI-7 (Gate-4 round-3 MEDIUM 1): parse the FULL payload
            // (blocks + requested section). The continuous-scroll scoped
            // enumerate posts `{sectionIndex, blocks}`; the paged path posts the
            // bare array. Forwarding the requested section lets the container
            // clear ONLY an emptied section's bucket.
            let payload = EPUBBilingualPipeline.parseEnumeratePayload(body)
            guard let callback = onBilingualEnumerate else { return }
            Task { @MainActor in
                callback(payload)
            }
        }

        private func handleSelectionMessage(_ body: Any) {
            guard let parsed = EPUBHighlightBridge.parseSelectionMessage(body) else { return }
            // Feature #71 WI-5: in continuous-scroll mode the selection JS reports
            // the section's href (`closest('[data-vreader-href]')`); attribute the
            // anchor to THAT section, not the global current chapter. Legacy
            // single-chapter mode reports no section href → falls back to
            // `currentHref` (unchanged behaviour).
            let href = parsed.sectionHref ?? currentHref ?? ""
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
            // Bug #251 / GH #1086: directly observable navigation failure.
            // Without this log, the verify cron can only INFER that didFinish
            // didn't fire (by absence of side-effects); this lets it observe
            // that the load actually aborted via the provisional path.
            AppLogger.epub.error(
                "didFailProvisionalNavigation: \(error.localizedDescription, privacy: .public)"
            )
            #if DEBUG
            // Bug #251 / GH #1086 (Codex round-1 High): the early-settle
            // fallback was always armed right after `loadFileURL`; if a
            // chapter genuinely fails to load via the provisional path,
            // we must NOT let the fallback subsequently report settled
            // to the harness — that would mask a real load error as a
            // ready sentinel and unblock downstream debug actions against
            // a broken/empty render. Cancel the pending fallback Task
            // here so the harness sees the timeout (or the explicit
            // `onLoadError` path that surfaces `webViewError` in the
            // container) instead of a false-positive success.
            cancelEarlySettleFallback()
            #endif
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
            // Bug #251 / GH #1086: directly observable navigation failure
            // on the committed path. Same rationale as the provisional log
            // above — make absence-of-didFinish distinguishable from a
            // silent failure mode.
            AppLogger.epub.error(
                "didFail: \(error.localizedDescription, privacy: .public)"
            )
            #if DEBUG
            // Bug #251 / GH #1086 (Codex round-1 High): same as
            // `didFailProvisionalNavigation` above — cancel the
            // early-settle fallback so a committed-but-failed navigation
            // doesn't get false-positive-settled by the timer.
            cancelEarlySettleFallback()
            #endif
            let message = "Chapter loading error: \(error.localizedDescription)"
            Task { @MainActor in
                onLoadError(message)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Bug #251 / GH #1086: directly observable entry log for the
            // EPUB chapter-load completion callback. Round-2 verification
            // could only infer `didFinish` ran from absence of side-effects;
            // this gives future verify cron runs a real anchor point in
            // the log when the side-effects ARE observed. The same info
            // also records the chapter URL so a load against the wrong
            // file is obvious.
            #if DEBUG
            AppLogger.epub.info(
                "didFinish: url=\(webView.url?.lastPathComponent ?? "<nil>", privacy: .public)"
            )
            // Bug #251 / GH #1086: cancel the pending early-settle
            // fallback Task now that the genuine render-complete signal
            // has arrived. Idempotent — `cancelEarlySettleFallback` is a
            // no-op if the task is nil or already finished. Required so
            // the fallback doesn't subsequently re-write registry state
            // that didFinish is about to write below (and to keep the
            // background Task tree clean).
            cancelEarlySettleFallback()
            #endif
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
            } else {
                AppLogger.epub.error(
                    "didFinish: identity not threaded (fingerprintKey or readerToken nil) — registry binding skipped"
                )
            }
            #endif

            // Inject theme CSS after page finishes loading
            if let css = themeCSS {
                let js = EPUBWebViewBridge.injectThemeCSSJS(css)
                webView.evaluateJavaScript(js) { _, error in
                    if let error { AppLogger.epub.error("didFinish theme inject error: \(error)") }
                }
            }

            if let cs = continuousScroll {
                // Feature #71 WI-6b-i: the bootstrap document finished loading.
                // Materialize the initial window (anchor chapter ±1) by stitching
                // sections through the coordinator's evaluator. No single-chapter
                // scroll-fraction / chapter-top offset restore here — section
                // seeking against the inner scroll root is WI-6b-iii's job.
                Task { @MainActor in
                    await cs.coordinator.materializeInitialWindow()
                }
            } else if isPaged {
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

        // MARK: - Early settle fallback (bug #251 / GH #1086)

        #if DEBUG
        /// Bug #251 / GH #1086: schedule a bounded fallback that marks
        /// the reader settled and registers the WebView with
        /// `DebugReaderRegistry` if `webView(_:didFinish:)` has not yet
        /// fired by the time `earlySettleFallbackDelay` elapses. Called
        /// from `EPUBWebViewBridge.updateUIView` immediately after the
        /// `loadFileURL(...)` invocation.
        ///
        /// Why this exists: round-2 verification of feature #64 (PR #1087)
        /// observed `vreader-debug://settle?token=...` writing
        /// `error: "settle timeout"` 30 seconds after the open URL
        /// against `mini-epub3`, with ZERO `markReaderSettled` /
        /// `setActiveEPUBWebView` log activity between the open
        /// notification and the timeout. The most parsimonious
        /// explanation is that `didFinish` did not fire (it is the sole
        /// caller of both side-effects), but the round-2 instrumentation
        /// could not directly confirm — only infer from absence. This
        /// fallback ensures the harness can proceed even when WKWebView's
        /// load-complete callback is delayed past the verify budget,
        /// surfacing the genuine "WebView is rendered enough to accept
        /// a JS highlight call" point in the lifecycle without requiring
        /// the chapter-load callback to win the race.
        ///
        /// Idempotency: a subsequent `didFinish` that arrives AFTER the
        /// fallback has already fired safely re-states the same registry
        /// identity — `setActiveEPUBWebView` re-stores the same ref under
        /// the same key/token; `markReaderSettled` inserts the same
        /// `(key, token)` SettleKey into a Set. The `cancelEarlySettleFallback`
        /// call at the start of `webView(_:didFinish:)` avoids the
        /// duplicate write in the happy path; this idempotency property
        /// covers the race where didFinish fires before cancel observes.
        ///
        /// Guard: when `fingerprintKey` or `readerToken` has not been
        /// threaded yet (rare SwiftUI re-render order race), the
        /// fallback no-ops rather than writing a half-identity binding
        /// to the registry — mirrors the existing `didFinish` guard.
        func scheduleEarlySettleFallback(webView: WKWebView) {
            // Replace any previously-scheduled fallback so a rapid
            // re-load (chapter navigation before the prior load finished)
            // doesn't leave two timers racing.
            earlySettleFallbackTask?.cancel()
            let delay = earlySettleFallbackDelay
            earlySettleFallbackTask = Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                guard let self, let webView else { return }
                guard let key = self.fingerprintKey, let token = self.readerToken else {
                    AppLogger.epub.error(
                        "earlySettleFallback: identity not threaded — skipping registry binding"
                    )
                    return
                }
                AppLogger.epub.info(
                    "earlySettleFallback: didFinish did not fire within \(delay, privacy: .public)s — marking settled + registering WebView for \(key, privacy: .public)"
                )
                DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: key, token: token)
                DebugReaderRegistry.shared.markReaderSettled(for: key, token: token)
            }
        }

        /// Bug #251 / GH #1086: cancel the pending early-settle fallback,
        /// called from the happy-path `webView(_:didFinish:)` callback so
        /// the fallback Task is dropped once the genuine render-complete
        /// signal has arrived. Idempotent — safe to call when no fallback
        /// is pending.
        func cancelEarlySettleFallback() {
            earlySettleFallbackTask?.cancel()
            earlySettleFallbackTask = nil
        }
        #endif
    }
}
#endif
