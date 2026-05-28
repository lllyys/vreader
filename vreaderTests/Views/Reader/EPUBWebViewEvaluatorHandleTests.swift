// Purpose: Feature #71 WI-6a — tests for EPUBWebViewEvaluatorHandle, the
// late-binding seam that lets the host-side continuous-scroll coordinator
// evaluate JS on a WKWebView created later by the bridge. The key unit-testable
// contract is the `webView == nil` path: it throws `noWebView` (rather than
// silently no-op'ing), so the coordinator's round-1 [H4] guarantee — the window
// does NOT advance on a failed eval — keeps a pre-mount boundary signal safe.
// The live-eval path needs a real WKWebView and is exercised at WI-6b's slice
// verification, not here.
//
// @coordinates-with: EPUBWebViewEvaluatorHandle.swift,
//   EPUBContinuousScrollCoordinator.swift (the evaluate consumer)

#if canImport(UIKit)
import Testing
import Foundation
import WebKit
@testable import vreader

@MainActor
@Suite("EPUBWebViewEvaluatorHandle (Feature #71 WI-6a)")
struct EPUBWebViewEvaluatorHandleTests {

    @Test("evaluate throws noWebView when the webView is nil (pre-mount / torn down)")
    func evaluateThrowsWhenNoWebView() async {
        let handle = EPUBWebViewEvaluatorHandle()
        #expect(handle.webView == nil)
        await #expect(throws: EPUBWebViewEvaluatorHandle.EvaluatorError.noWebView) {
            try await handle.evaluate("document.body;")
        }
    }

    @Test("unbinding the webView (set to nil) makes evaluate throw noWebView again")
    func unbindWebViewThrows() async {
        // The bridge teardown / WI-6b freshness rule nils the binding; after
        // that a stale eval must throw rather than hit a stale DOM. (Asserting
        // weak-dealloc *timing* is unreliable for WKWebView — its dealloc is
        // deferred by the web-content process pool — so the contract is checked
        // via an explicit unbind, which is what teardown does.)
        let handle = EPUBWebViewEvaluatorHandle()
        let webView = WKWebView(frame: .zero)
        handle.webView = webView
        #expect(handle.webView != nil)

        handle.webView = nil
        await #expect(throws: EPUBWebViewEvaluatorHandle.EvaluatorError.noWebView) {
            try await handle.evaluate("0;")
        }
    }
}
#endif
