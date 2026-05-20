// Purpose: DEBUG-only wiring that creates an EPUB highlight from a
// `.debugBridgeHighlightCommand` notification (Bug #220 / GH #845 —
// verification harness highlight-creator for EPUB). Counterpart of the
// TXT/MD observers shipped in PR #1047 — the same URL grammar
// (`vreader-debug://highlight?start=<int>&end=<int>[&color=<name>]`) now
// routes through the EPUB host when an EPUB is the active reader.
//
// Why a separate file (and not a shared `DebugBridgeHighlightObserver`):
//   - The EPUB pipeline needs a WKWebView round-trip: JS walks visible
//     text nodes to map `[start, end)` UTF-16 offsets to a real DOM
//     `EPUBSerializedRange`. TXT/MD have the source text in Swift and
//     build a `Locator` via `LocatorFactory.txtRange` / `mdRange` with
//     no WebView involvement.
//   - The EPUB anchor (`AnnotationAnchor.epub(href:cfi:serializedRange:)`)
//     carries the canonical DOM range, not just UTF-16 offsets. So
//     `HighlightCoordinator.create(...)` is called with `anchor:` set,
//     matching the gesture path in `EPUBReaderContainerView+Highlights`.
//   - Format scoping: EPUB only — the modifier is attached only inside
//     the EPUB container's body, so a stray URL fired while TXT/MD/PDF/
//     AZW3 is active is a no-op for the EPUB observer (and vice versa).
//
// Design — JS resolves range, Swift persists, renderer paints:
//
//   Codex Gate-4 Round-1 (High): an earlier round had the JS paint with
//   a transient UUID and let `restoreAll` re-paint with the canonical
//   record ID. The EPUB restore pipeline is additive, not replace-all —
//   the transient paint would stay on the live page until chapter
//   reload. The current design: JS resolves the DOM range only;
//   `HighlightCoordinator.create(...)` persists; `EPUBHighlightRenderer.apply`
//   paints with the canonical record UUID through the existing
//   `onInjectJS` callback. Identical posture to the gesture path.
//
// Stale-state protection (Codex Gate-4 Round-1 Medium):
//
//   The `evaluateJavaScript` completion fires on an implementation-
//   defined queue, so the user can close the reader or navigate
//   chapters during the JS round-trip. Before persisting, the observer
//   re-validates that the same `(fingerprintKey, readerToken,
//   currentHref)` triple is still active. If anything changed, the
//   result is dropped — a stale range computed against the prior DOM
//   would otherwise persist against the new chapter.
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with EPUBReaderContainerView.swift,
//   EPUBDebugBridgeHighlightJS.swift, EPUBHighlightBridge.swift,
//   EPUBReaderContainerView+Highlights.swift, HighlightCoordinator.swift,
//   DebugBridgeNotifications.swift, DebugReaderRegistry.swift,
//   RealDebugBridgeContext.swift

import SwiftUI

#if !DEBUG
// Release stub: the body of EPUBReaderContainerView references
// `debugBridgeHighlightObserverModifier`; we provide an `EmptyModifier`
// here so Release builds compile without any DebugBridge symbols.
#if canImport(UIKit)
extension EPUBReaderContainerView {
    var debugBridgeHighlightObserverModifier: EmptyModifier {
        EmptyModifier()
    }
}
#endif
#endif

#if DEBUG
#if canImport(UIKit)

import OSLog
import WebKit

extension EPUBReaderContainerView {

    /// The `ViewModifier` that observes `.debugBridgeHighlightCommand`
    /// and dispatches into `handleDebugBridgeHighlightCommand`. The body
    /// reads this property unconditionally; the Release stub above
    /// supplies an `EmptyModifier` so DebugBridge symbols never leak
    /// into release builds.
    var debugBridgeHighlightObserverModifier: some ViewModifier {
        EPUBDebugBridgeHighlightObserver(
            onCommand: { startUTF16, endUTF16, color in
                handleDebugBridgeHighlightCommand(
                    startUTF16: startUTF16,
                    endUTF16: endUTF16,
                    color: color
                )
            }
        )
    }

    /// Handle a `.debugBridgeHighlightCommand` notification by creating
    /// an EPUB highlight over `[startUTF16, endUTF16)` UTF-16 offsets in
    /// the visible chapter's concatenated text. Goes through:
    ///
    ///   1. Resolve the active EPUB WKWebView from `DebugReaderRegistry`
    ///      using `(fingerprintKey, readerToken)`. If absent (the
    ///      registry is the truth-of-binding for which WebView "right
    ///      now" represents this reader), log + bail.
    ///   2. Snapshot `(currentHref, locator, webView)` BEFORE the JS
    ///      round-trip so the post-completion validation has a stable
    ///      reference point (Codex Gate-4 Round-1 Medium fix).
    ///   3. Evaluate `EPUBDebugBridgeHighlightJS.buildResolveRangeJS` in
    ///      the WebView. The JS resolves the DOM range and returns
    ///      `{ startPath, startOffset, endPath, endOffset,
    ///      selectedText }` — NO paint happens in the JS (Codex
    ///      Gate-4 Round-1 High fix).
    ///   4. Re-validate state: the registry's `(webView, fingerprintKey,
    ///      token)` binding must still match AND the viewModel's
    ///      `currentPosition?.href` must equal the captured `href`. If
    ///      either has changed, the result is dropped — a stale range
    ///      computed against the prior DOM cannot persist against the
    ///      new chapter.
    ///   5. Parse the result via `EPUBDebugBridgeHighlightJS.parseResult`.
    ///   6. Build the `AnnotationAnchor.epub(...)` + call
    ///      `HighlightCoordinator.create(...)`. The coordinator persists,
    ///      then `EPUBHighlightRenderer.apply(record:)` paints with the
    ///      canonical record UUID through the existing `onInjectJS` →
    ///      `pendingHighlightJS` pipeline. Same path as the gesture in
    ///      `EPUBReaderContainerView+Highlights.handleHighlightAction`.
    ///
    /// Format scoping: this observer is only attached inside the EPUB
    /// host's body. TXT / MD / PDF / AZW3 do not see this code path.
    @MainActor
    func handleDebugBridgeHighlightCommand(
        startUTF16: Int,
        endUTF16: Int,
        color: String?
    ) {
        let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")
        let resolvedColor = color ?? "yellow"
        let fingerprintKeyForLog = viewModel.bookFingerprintKey

        log.info(
            "epub highlight observer: start=\(startUTF16) end=\(endUTF16) color=\(resolvedColor, privacy: .public) fingerprint=\(fingerprintKeyForLog, privacy: .public)"
        )

        // Resolve the active EPUB WebView via the registry. The registry
        // is keyed by `(fingerprintKey, token)` so a late didFinish from
        // an outgoing reader cannot match an incoming key (bug #126 +
        // #142). Both must be threaded from the container parameters.
        guard let fingerprintKey = fingerprintKey,
              let readerToken = readerToken else {
            log.error("epub highlight observer: fingerprintKey / readerToken not threaded — observer is a no-op")
            return
        }
        guard let webView = DebugReaderRegistry.shared.epubWebView(
            for: fingerprintKey, token: readerToken
        ) else {
            log.error("epub highlight observer: no active EPUB WebView registered for \(fingerprintKey, privacy: .public)")
            return
        }

        // Snapshot pre-evaluation state for the post-completion stale
        // check. `locator` carries the active chapter's href + progression
        // + (later) cfi — the same locator the gesture path takes for
        // `handleHighlightAction` (`viewModel.makeCurrentLocator()`).
        guard let locator = viewModel.makeCurrentLocator(),
              let href = locator.href else {
            log.error("epub highlight observer: no current locator / href — chapter not loaded yet")
            return
        }
        guard let coordinator = highlightCoordinator else {
            log.error("epub highlight observer: highlightCoordinator not yet initialized")
            return
        }

        let js = EPUBDebugBridgeHighlightJS.buildResolveRangeJS(
            startUTF16: startUTF16,
            endUTF16: endUTF16
        )

        // Capture for stale-state re-validation. `expectedKey` /
        // `expectedToken` / `expectedHref` / `expectedWebView` form the
        // identity we'll re-check at completion time. Captures by value;
        // `webView` is captured as a weak reference indirectly through
        // the registry re-lookup so we never persist against a defunct
        // webview.
        let expectedKey = fingerprintKey
        let expectedToken = readerToken
        let expectedHref = href
        weak var expectedWebView = webView

        webView.evaluateJavaScript(js) { [self] rawResult, jsError in
            // Hop to MainActor for persistence + notification posting —
            // evaluateJavaScript's completion fires on an
            // implementation-defined queue.
            Task { @MainActor in
                if let jsError {
                    log.error(
                        "epub highlight observer: evaluateJavaScript error \(String(describing: jsError), privacy: .public)"
                    )
                    return
                }

                // Codex Gate-4 Round-1 Medium fix: re-validate that the
                // same reader instance + chapter is still active. The
                // user may have closed the reader, navigated chapters,
                // or reopened a different book between the JS dispatch
                // and the completion callback.
                guard let liveWebView = DebugReaderRegistry.shared.epubWebView(
                    for: expectedKey, token: expectedToken
                ), liveWebView === expectedWebView else {
                    log.info(
                        "epub highlight observer: stale completion — reader changed during JS round-trip, dropping result"
                    )
                    return
                }
                guard viewModel.currentPosition?.href == expectedHref else {
                    log.info(
                        "epub highlight observer: stale completion — chapter changed from \(expectedHref, privacy: .public) to \(self.viewModel.currentPosition?.href ?? "nil", privacy: .public), dropping result"
                    )
                    return
                }

                guard let parsed = EPUBDebugBridgeHighlightJS.parseResult(rawResult) else {
                    // null result: JS rejected the range (out of bounds,
                    // empty doc, whitespace-only selection, etc.).
                    log.error(
                        "epub highlight observer: JS returned null / unparseable for start=\(startUTF16) end=\(endUTF16)"
                    )
                    return
                }

                // Build the EPUB anchor in the same shape the gesture
                // path emits via `EPUBHighlightBridge.makeAnchor` — the
                // `cfi` field is empty (we don't synthesize a CFI from
                // the DOM range; the production gesture path also
                // accepts an empty CFI when the JS selection-tracking
                // didn't surface one).
                let anchor = EPUBHighlightBridge.makeAnchor(
                    href: expectedHref, cfi: "", range: parsed.range
                )

                // Persist via the coordinator — same path as the gesture
                // in `handleHighlightAction`. The coordinator's
                // `create(...)` calls `renderer.apply(record:)` which
                // paints with the canonical persisted UUID through
                // `EPUBHighlightActions.createHighlightJS(for:)` →
                // `__vreader_createHighlight`. No transient ID can leak
                // onto the live page (Codex Gate-4 Round-1 High fix).
                _ = await coordinator.create(
                    locator: locator,
                    anchor: anchor,
                    selectedText: parsed.selectedText,
                    color: resolvedColor
                )
                log.info(
                    "epub highlight observer: created highlight start=\(startUTF16) end=\(endUTF16) text=\(parsed.selectedText, privacy: .public) color=\(resolvedColor, privacy: .public)"
                )
            }
        }
    }
}

/// Local `ViewModifier` mirroring the TXT/MD `DebugBridgeHighlightObserver`
/// shape. Kept local to the EPUB file because the shared observer struct
/// is closely paired with TXT/MD's `extractSelectedText` helper that the
/// EPUB path doesn't use (the selected-text extraction happens in JS).
/// Cohabiting in the shared file would entangle two unrelated extraction
/// strategies.
private struct EPUBDebugBridgeHighlightObserver: ViewModifier {
    let onCommand: (_ startUTF16: Int, _ endUTF16: Int, _ color: String?) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeHighlightCommand)
        ) { notification in
            guard let start = notification.userInfo?["start"] as? Int,
                  let end = notification.userInfo?["end"] as? Int else { return }
            let color = notification.userInfo?["color"] as? String
            onCommand(start, end, color)
        }
    }
}

#endif
#endif
