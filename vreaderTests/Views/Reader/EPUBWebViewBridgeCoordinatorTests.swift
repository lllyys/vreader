// Purpose: Tests for EPUBWebViewBridge.Coordinator's deferred-eval state
// (bug #182). Verifies that the new `pendingHighlightJS` +
// `onPendingHighlightJSCompleted` stash fields are settable, mutually
// independent, and clear correctly. The full deferred-eval round-trip
// (URL change → didFinish runs JS → completion fires) requires a real
// WKWebView and isn't unit-testable in this style — same constraint as
// the existing `pendingScrollFraction` field which is verified only by
// device verification. The audit log calls out this gap explicitly.

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("EPUBWebViewBridge.Coordinator — pendingHighlightJS stash (bug #182)")
@MainActor
struct EPUBWebViewBridgeCoordinatorPendingHighlightJSTests {

    /// Builds a Coordinator with no-op callbacks so we can exercise state
    /// fields without standing up a SwiftUI/UIKit context.
    private func makeCoordinator() -> EPUBWebViewBridge.Coordinator {
        EPUBWebViewBridge.Coordinator(
            onProgressChange: { _ in },
            onLoadError: { _ in }
        )
    }

    @Test func pendingHighlightJS_isNilByDefault() {
        let coordinator = makeCoordinator()
        #expect(coordinator.pendingHighlightJS == nil)
        #expect(coordinator.onPendingHighlightJSCompleted == nil)
    }

    @Test func pendingHighlightJS_storesAndReadsBackAJSString() {
        let coordinator = makeCoordinator()
        let js = "window.find('Pierre', false, false, true, false, false, false);"
        coordinator.pendingHighlightJS = js
        #expect(coordinator.pendingHighlightJS == js)
    }

    @Test func pendingHighlightJS_clearsToNil() {
        let coordinator = makeCoordinator()
        coordinator.pendingHighlightJS = "some-js"
        coordinator.pendingHighlightJS = nil
        #expect(coordinator.pendingHighlightJS == nil)
    }

    @Test func onPendingHighlightJSCompleted_invokesWhenCalled() async {
        let coordinator = makeCoordinator()
        var fired = false
        coordinator.onPendingHighlightJSCompleted = {
            fired = true
        }
        coordinator.onPendingHighlightJSCompleted?()
        #expect(fired, "Stashed completion callback must invoke when called.")
    }

    @Test func onPendingHighlightJSCompleted_clearsToNil() {
        let coordinator = makeCoordinator()
        coordinator.onPendingHighlightJSCompleted = { /* no-op */ }
        #expect(coordinator.onPendingHighlightJSCompleted != nil)
        coordinator.onPendingHighlightJSCompleted = nil
        #expect(coordinator.onPendingHighlightJSCompleted == nil)
    }

    @Test func pendingHighlightJS_andPendingScrollFraction_areIndependent() {
        // Sanity check that the new stash field doesn't accidentally alias
        // the existing pendingScrollFraction field — both must be
        // independently settable + readable for the URL-change path to
        // queue BOTH a scroll target AND a highlight payload.
        let coordinator = makeCoordinator()
        coordinator.pendingScrollFraction = 0.42
        coordinator.pendingHighlightJS = "var x = 1;"

        #expect(coordinator.pendingScrollFraction == 0.42)
        #expect(coordinator.pendingHighlightJS == "var x = 1;")

        coordinator.pendingHighlightJS = nil
        #expect(coordinator.pendingScrollFraction == 0.42, "Clearing pendingHighlightJS must NOT clear pendingScrollFraction.")
    }
}
#endif
