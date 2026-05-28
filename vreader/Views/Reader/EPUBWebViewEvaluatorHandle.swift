// Purpose: Feature #71 WI-6a — the late-binding seam between the host-side
// continuous-scroll coordinator and the bridge's `WKWebView`. Resolves the
// design gap documented in the plan's "WI-6 evaluate-binding" section: the
// `EPUBContinuousScrollCoordinator.evaluate` closure is set at coordinator
// init, but the container creates the coordinator BEFORE the bridge's webview
// exists (`makeUIView` runs later). The container builds the coordinator with
// `evaluate: { [handle] js in try await handle.evaluate(js) }` and threads this
// handle to the bridge, which sets `handle.webView = webView` once it exists.
//
// The `webView` reference is `weak` (no retain cycle; released with the bridge),
// and `evaluate` THROWS `noWebView` when it's nil — so a boundary signal that
// arrives before the webview mounts (or after teardown) is a clean no-op via
// the coordinator's round-1 [H4] contract (the window does not advance on a
// failed eval), not a crash or a desynced window.
//
// NOTE (WI-6b freshness rule): `weak` alone is not the teardown contract — a
// live mode-switch / reopen can briefly leave a stale webview alive, so WI-6b
// uses a FRESH handle per bridge generation (see the plan's "WI-6b design
// requirements" #2). This type is the per-generation primitive.
//
// @coordinates-with: EPUBContinuousScrollCoordinator.swift (evaluate consumer),
//   EPUBWebViewBridge.swift (populates webView in makeUIView, WI-6b),
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-6a)

#if canImport(UIKit)
import Foundation
import WebKit

/// A late-bound handle for evaluating JS on the continuous-scroll bridge's
/// `WKWebView`. `@MainActor` to match the coordinator's evaluate isolation.
@MainActor
final class EPUBWebViewEvaluatorHandle {
    /// Weak so the handle never retains the webview — populated by the bridge's
    /// `makeUIView`, nilled automatically when the bridge tears down.
    weak var webView: WKWebView?

    enum EvaluatorError: Error, Equatable {
        /// `evaluate` was called while no webview is bound (pre-mount or torn
        /// down). The coordinator treats a thrown eval as "do not advance the
        /// window" — so this is a safe no-op, not a failure to surface.
        case noWebView
    }

    init() {}

    /// Evaluate `js` on the bound webview. Throws `noWebView` when none is
    /// bound; otherwise bridges `WKWebView.evaluateJavaScript`'s
    /// completion-handler form to async-throws so the coordinator observes a
    /// real eval failure (its [H4] window-safety contract).
    func evaluate(_ js: String) async throws {
        guard let webView else { throw EvaluatorError.noWebView }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
