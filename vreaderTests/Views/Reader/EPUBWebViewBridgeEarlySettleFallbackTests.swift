// Purpose: Tests for the EPUBWebViewBridge.Coordinator's "early settle
// fallback" machinery (bug #251 / GH #1086). When `webView(_:didFinish:)`
// does not fire within a bounded interval after `loadFileURL` is invoked,
// the bridge schedules a fallback that calls both `setActiveEPUBWebView`
// and `markReaderSettled` on the DebugReaderRegistry so the host-driven
// `vreader-debug://settle` URL does not hit its 30-second timeout when
// the WKWebView's load-complete callback is delayed or missing.
//
// Why these tests exist: round-2 verification of feature #64 (PR #1087)
// found that EPUB settle times out for `mini-epub3` with ZERO observable
// `markReaderSettled` / `setActiveEPUBWebView` side-effects in the
// `subsystem == "com.vreader.app"` log between `open: posted notification`
// and the 30-second timeout. Inference: didFinish never fired (the sole
// caller of both side-effects). The fallback ensures the harness can
// proceed even when WKWebView's callback is delayed past the verify
// budget. The fallback is idempotent against a late didFinish — registry
// `setActiveEPUBWebView` re-stores the same ref, and `markReaderSettled`
// inserts the same `(key, token)` SettleKey in a Set, so a subsequent
// didFinish callback is a no-op rather than a clobber.
//
// DEBUG-only — the registry, the bridge's DEBUG-gated fingerprintKey /
// readerToken fields, and the fallback machinery itself are all
// `#if DEBUG`.

#if canImport(UIKit) && DEBUG
import Testing
import Foundation
import UIKit
import WebKit
@testable import vreader

@Suite("EPUBWebViewBridge.Coordinator — early settle fallback (bug #251)")
@MainActor
struct EPUBWebViewBridgeEarlySettleFallbackTests {

    /// Builds a Coordinator with no-op callbacks. Tests assign
    /// fingerprintKey + readerToken directly because in the real flow
    /// `EPUBWebViewBridge.makeUIView` / `updateUIView` populate those
    /// from the SwiftUI binding before `loadFileURL` runs.
    private func makeCoordinator() -> EPUBWebViewBridge.Coordinator {
        EPUBWebViewBridge.Coordinator(
            onProgressChange: { _ in },
            onLoadError: { _ in }
        )
    }

    // MARK: - Case 1: fallback fires markReaderSettled + setActiveEPUBWebView

    /// When `scheduleEarlySettleFallback(webView:)` runs and the bounded
    /// delay elapses without `didFinish` cancelling it, the registry must
    /// observe both side-effects — the WebView slot is populated for the
    /// downstream highlight observer (Bug #1085 Stage-2 gate passes) AND
    /// the settle waiter is resumed via `markReaderSettled` (Stage-1
    /// gate passes). Without this, Bug #251's Stage-1 30s timeout
    /// reproduces.
    @Test func case1_fallbackFires_setActiveEPUBWebView_andMarkReaderSettled() async throws {
        let registry = DebugReaderRegistry.shared
        registry.reset()
        defer { registry.reset() }

        let coordinator = makeCoordinator()
        let key = "epub:fallback-case1:1024"
        let token = UUID()
        coordinator.fingerprintKey = key
        coordinator.readerToken = token
        // Token-keyed reads in the registry require the expected token to
        // be set first; production wires this from
        // `ReaderContainerView.onAppear` (line ~744).
        registry.setExpectedReaderToken(token)

        let webView = WKWebView()
        // Bound the fallback delay to a tiny interval so the test is fast.
        coordinator.earlySettleFallbackDelay = 0.05

        // Sanity: registry is empty before the fallback.
        #expect(registry.rawActiveEPUBWebViewKeyForTests == nil)
        #expect(registry.settledKeys.contains(
            DebugReaderRegistry.SettleKey(fingerprintKey: key, token: token)
        ) == false)

        coordinator.scheduleEarlySettleFallback(webView: webView)

        // Wait for the fallback to fire. 250ms is generous against a 50ms
        // delay, which keeps the test deterministic without flake.
        try await Task.sleep(nanoseconds: 250_000_000)

        // Registry must now observe both side-effects.
        #expect(registry.rawActiveEPUBWebViewKeyForTests == key,
                "Fallback must register the EPUB WebView slot under the bridge's fingerprintKey.")
        #expect(registry.rawActiveEPUBWebViewForTests === webView,
                "Fallback must store the same WKWebView reference the bridge owns.")
        #expect(registry.settledKeys.contains(
            DebugReaderRegistry.SettleKey(fingerprintKey: key, token: token)
        ),
        "Fallback must mark (key, token) as render-settled so the settle waiter unblocks.")
    }

    // MARK: - Case 2: didFinish-before-fallback cancels the fallback

    /// When `didFinish` fires before the fallback delay elapses, the
    /// coordinator must cancel the pending fallback so the same registry
    /// state isn't re-written twice. The visible state is idempotent
    /// either way — re-storing the same ref and re-inserting the same
    /// SettleKey are no-ops — but cancelling the timer keeps the timing
    /// model honest and avoids the fallback Task leaking past the
    /// happy-path completion.
    @Test func case2_didFinishCancelsTheFallback() async throws {
        let registry = DebugReaderRegistry.shared
        registry.reset()
        defer { registry.reset() }

        let coordinator = makeCoordinator()
        let key = "epub:fallback-case2:2048"
        let token = UUID()
        coordinator.fingerprintKey = key
        coordinator.readerToken = token
        registry.setExpectedReaderToken(token)

        let webView = WKWebView()
        coordinator.earlySettleFallbackDelay = 5.0  // long enough that
        // the test wouldn't have time to observe a fallback firing.

        coordinator.scheduleEarlySettleFallback(webView: webView)
        // Simulate didFinish having fired in the production flow.
        coordinator.cancelEarlySettleFallback()
        // Give the cancelled Task a beat to settle.
        try await Task.sleep(nanoseconds: 50_000_000)

        // The fallback Task must have been cancelled — no side-effects.
        #expect(registry.rawActiveEPUBWebViewKeyForTests == nil,
                "Cancelled fallback must NOT register the WebView.")
        #expect(registry.settledKeys.contains(
            DebugReaderRegistry.SettleKey(fingerprintKey: key, token: token)
        ) == false,
        "Cancelled fallback must NOT mark settled.")
    }

    // MARK: - Case 3: fallback no-op without fingerprintKey / readerToken

    /// If the coordinator's identity fields haven't been threaded yet
    /// (rare: SwiftUI re-render race), the fallback must silently no-op
    /// rather than writing a half-identity binding to the registry. This
    /// mirrors the existing `didFinish` guard at line 245-246 of
    /// `EPUBWebViewBridgeCoordinator.swift`.
    @Test func case3_fallbackNoOpsWhenIdentityNotThreaded() async throws {
        let registry = DebugReaderRegistry.shared
        registry.reset()
        defer { registry.reset() }

        let coordinator = makeCoordinator()
        // Intentionally leave fingerprintKey / readerToken nil.
        let webView = WKWebView()
        coordinator.earlySettleFallbackDelay = 0.05

        coordinator.scheduleEarlySettleFallback(webView: webView)
        try await Task.sleep(nanoseconds: 250_000_000)

        // Registry is untouched — the fallback can't bind without an
        // identity.
        #expect(registry.rawActiveEPUBWebViewKeyForTests == nil,
                "Fallback must NOT register a WebView when identity fields are nil.")
        #expect(registry.settledKeys.isEmpty,
                "Fallback must NOT mark settled when identity fields are nil.")
    }
}
#endif
