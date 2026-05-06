// Purpose: Tests for DebugReaderRegistry — the active-reader handle used
// by settle/eval/snapshot in feature #44 DebugBridge. Verifies register
// replaces previous, unregister no-ops on stale entries, and the registry
// holds a weak reference.

#if DEBUG

import XCTest
#if canImport(WebKit)
import WebKit
#endif
@testable import vreader

@MainActor
final class DebugReaderRegistryTests: XCTestCase {

    /// Stable token for tests that don't care about per-reader instance
    /// disambiguation (the bug #142 race seam). Tests that DO exercise
    /// the race generate their own UUIDs in the test body.
    private let testToken = UUID()

    override func setUp() {
        super.setUp()
        DebugReaderRegistry.shared.reset()
    }

    override func tearDown() {
        DebugReaderRegistry.shared.reset()
        super.tearDown()
    }

    func test_initiallyNoCurrentReader() {
        XCTAssertNil(DebugReaderRegistry.shared.current)
    }

    func test_register_setsCurrentReader() {
        let probe = StubProbe(key: "k1", fmt: "txt")
        DebugReaderRegistry.shared.register(probe)
        XCTAssertNotNil(DebugReaderRegistry.shared.current)
        XCTAssertEqual(DebugReaderRegistry.shared.current?.fingerprintKey, "k1")
    }

    func test_register_replacesPreviousReader() {
        let p1 = StubProbe(key: "k1", fmt: "txt")
        let p2 = StubProbe(key: "k2", fmt: "epub")
        DebugReaderRegistry.shared.register(p1)
        DebugReaderRegistry.shared.register(p2)
        XCTAssertEqual(DebugReaderRegistry.shared.current?.fingerprintKey, "k2")
    }

    func test_unregister_clearsCurrentIfMatches() {
        let probe = StubProbe(key: "k1", fmt: "txt")
        DebugReaderRegistry.shared.register(probe)
        DebugReaderRegistry.shared.unregister(probe)
        XCTAssertNil(DebugReaderRegistry.shared.current)
    }

    func test_unregister_isNoOpIfStaleProbe() {
        // Quick reader switch: probe1 disappears AFTER probe2 registered.
        // The stale unregister should not clear the new entry.
        let p1 = StubProbe(key: "k1", fmt: "txt")
        let p2 = StubProbe(key: "k2", fmt: "epub")
        DebugReaderRegistry.shared.register(p1)
        DebugReaderRegistry.shared.register(p2)
        DebugReaderRegistry.shared.unregister(p1)
        XCTAssertEqual(DebugReaderRegistry.shared.current?.fingerprintKey, "k2")
    }

    func test_registry_holdsWeakReference() {
        // Strong reference held only inside the closure. After it returns,
        // the registry's weak reference should drop to nil without an
        // explicit unregister call.
        autoreleasepool {
            let probe = StubProbe(key: "kw", fmt: "txt")
            DebugReaderRegistry.shared.register(probe)
            XCTAssertNotNil(DebugReaderRegistry.shared.current)
        }
        XCTAssertNil(DebugReaderRegistry.shared.current, "registry must hold weak; probe should be gone")
    }

    // MARK: - Bug #126: keyed activeEPUBWebView binding

    #if canImport(WebKit)
    func test_epubWebView_initiallyNil_forAnyKey() {
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "any-key", token: testToken))
    }

    func test_setActiveEPUBWebView_returnsForMatchingKey() {
        let webView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: "k1", token: testToken)
        XCTAssertTrue(DebugReaderRegistry.shared.epubWebView(for: "k1", token: testToken) === webView)
    }

    func test_setActiveEPUBWebView_returnsNilForMismatchedKey() {
        // Bug #126 stale-protection: a webview registered for an outgoing
        // book must NOT be returned to a probe that asks about a different
        // book. Codex audit (2026-05-06) flagged this as the High finding
        // on the initial fix.
        let webView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: "outgoing-book", token: testToken)
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "incoming-book", token: testToken))
    }

    func test_setActiveEPUBWebView_replacesPreviousBinding() {
        let webViewA = WKWebView(frame: .zero)
        let webViewB = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webViewA, for: "k1", token: testToken)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webViewB, for: "k2", token: testToken)
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "k1", token: testToken))
        XCTAssertTrue(DebugReaderRegistry.shared.epubWebView(for: "k2", token: testToken) === webViewB)
    }

    func test_unregister_clearsEPUBWebViewWhenKeyMatches() {
        let webView = WKWebView(frame: .zero)
        let probe = StubProbe(key: "k1", fmt: "epub")
        DebugReaderRegistry.shared.register(probe)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: "k1", token: testToken)
        DebugReaderRegistry.shared.unregister(probe)
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "k1", token: testToken))
    }

    func test_reset_clearsEPUBWebView() {
        let webView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: "k1", token: testToken)
        DebugReaderRegistry.shared.reset()
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "k1", token: testToken))
        XCTAssertNil(DebugReaderRegistry.shared.rawActiveEPUBWebViewKeyForTests)
    }

    // Note: the underlying ref (`activeEPUBWebViewRef`) is declared `weak`
    // in source. A behavioral weak-drop test is flaky here — UIKit-class
    // instances often outlive an `autoreleasepool` block during test
    // runs. The compile-time declaration is the contract; the runtime
    // weak-drop is covered by on-device verification (bug #126 evidence).

    // MARK: - Bug #141: keyed activeFoliateWebView binding (AZW3/MOBI)
    //
    // Symmetric with the EPUB binding above. Same lifecycle, same
    // stale-protection contract, separate slot.

    func test_foliateWebView_initiallyNil_forAnyKey() {
        XCTAssertNil(DebugReaderRegistry.shared.foliateWebView(for: "any-key", token: testToken))
    }

    func test_setActiveFoliateWebView_returnsForMatchingKey() {
        let webView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveFoliateWebView(webView, for: "k1", token: testToken)
        XCTAssertTrue(DebugReaderRegistry.shared.foliateWebView(for: "k1", token: testToken) === webView)
    }

    func test_setActiveFoliateWebView_returnsNilForMismatchedKey() {
        // Same stale-protection regression seam as the EPUB pair.
        let webView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveFoliateWebView(webView, for: "outgoing-book", token: testToken)
        XCTAssertNil(DebugReaderRegistry.shared.foliateWebView(for: "incoming-book", token: testToken))
    }

    func test_setActiveFoliateWebView_replacesPreviousBinding() {
        let webViewA = WKWebView(frame: .zero)
        let webViewB = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveFoliateWebView(webViewA, for: "k1", token: testToken)
        DebugReaderRegistry.shared.setActiveFoliateWebView(webViewB, for: "k2", token: testToken)
        XCTAssertNil(DebugReaderRegistry.shared.foliateWebView(for: "k1", token: testToken))
        XCTAssertTrue(DebugReaderRegistry.shared.foliateWebView(for: "k2", token: testToken) === webViewB)
    }

    func test_unregister_clearsFoliateWebViewWhenKeyMatches() {
        let webView = WKWebView(frame: .zero)
        let probe = StubProbe(key: "k1", fmt: "azw3")
        DebugReaderRegistry.shared.register(probe)
        DebugReaderRegistry.shared.setActiveFoliateWebView(webView, for: "k1", token: testToken)
        DebugReaderRegistry.shared.unregister(probe)
        XCTAssertNil(DebugReaderRegistry.shared.foliateWebView(for: "k1", token: testToken))
    }

    func test_reset_clearsFoliateWebView() {
        let webView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveFoliateWebView(webView, for: "k1", token: testToken)
        DebugReaderRegistry.shared.reset()
        XCTAssertNil(DebugReaderRegistry.shared.foliateWebView(for: "k1", token: testToken))
        XCTAssertNil(DebugReaderRegistry.shared.rawActiveFoliateWebViewKeyForTests)
    }

    func test_epubAndFoliateBindings_areIndependent() {
        // Setting one binding must not clear the other; setting the same
        // key on both is a normal multi-host scenario (e.g., quick
        // format-switching between books) and both slots should retain.
        let epubWebView = WKWebView(frame: .zero)
        let foliateWebView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveEPUBWebView(epubWebView, for: "k1", token: testToken)
        DebugReaderRegistry.shared.setActiveFoliateWebView(foliateWebView, for: "k1", token: testToken)
        XCTAssertTrue(DebugReaderRegistry.shared.epubWebView(for: "k1", token: testToken) === epubWebView)
        XCTAssertTrue(DebugReaderRegistry.shared.foliateWebView(for: "k1", token: testToken) === foliateWebView)
    }

    // MARK: - Bug #142: per-reader instance token disambiguates same-book reopens

    func test_epubWebView_returnsNilForSameKeyDifferentToken() {
        // Bug #142 regression seam: two readers with the same fingerprintKey
        // (the same book closed and reopened) get distinct tokens. A late
        // didFinish from the outgoing reader's webview re-registers under
        // the same key but the outgoing reader's old token. The new
        // reader's eval must NOT see that webview.
        let outgoingWebView = WKWebView(frame: .zero)
        let outgoingToken = UUID()
        let incomingToken = UUID()

        // Outgoing reader registers, then a late didFinish hits same key.
        DebugReaderRegistry.shared.setActiveEPUBWebView(outgoingWebView, for: "k1", token: outgoingToken)
        // Incoming reader (same book, same key, different token) asks.
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "k1", token: incomingToken))
    }

    func test_foliateWebView_returnsNilForSameKeyDifferentToken() {
        // Same-book reopen race for the Foliate (AZW3/MOBI) binding.
        let outgoingWebView = WKWebView(frame: .zero)
        let outgoingToken = UUID()
        let incomingToken = UUID()

        DebugReaderRegistry.shared.setActiveFoliateWebView(outgoingWebView, for: "k1", token: outgoingToken)
        XCTAssertNil(DebugReaderRegistry.shared.foliateWebView(for: "k1", token: incomingToken))
    }

    func test_setActiveEPUBWebView_replacesBindingForSameKeyNewToken() {
        // The "newer wins" policy must hold across token changes too —
        // the incoming reader's didFinish overwrites the outgoing slot.
        // Note: with `setExpectedReaderToken` set, only matching tokens
        // can write. This test exercises the unset (test-default) path.
        let outgoingWebView = WKWebView(frame: .zero)
        let incomingWebView = WKWebView(frame: .zero)
        let outgoingToken = UUID()
        let incomingToken = UUID()

        DebugReaderRegistry.shared.setActiveEPUBWebView(outgoingWebView, for: "k1", token: outgoingToken)
        DebugReaderRegistry.shared.setActiveEPUBWebView(incomingWebView, for: "k1", token: incomingToken)
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "k1", token: outgoingToken))
        XCTAssertTrue(DebugReaderRegistry.shared.epubWebView(for: "k1", token: incomingToken) === incomingWebView)
    }

    // MARK: - Bug #142: stale-write protection (Codex round-1 ordering test)

    func test_epubWebView_lateStaleDidFinishCannotClobberCurrentReader() {
        // Codex round-1 ordering test: register newer reader (T2),
        // then simulate a stale didFinish from outgoing reader (T1)
        // arriving AFTER. The current reader's eval lookup must still
        // return the new webview, NOT nil and NOT the old webview.
        let oldWebView = WKWebView(frame: .zero)
        let newWebView = WKWebView(frame: .zero)
        let oldToken = UUID()
        let newToken = UUID()

        // New reader mounts: registry expects newToken first.
        DebugReaderRegistry.shared.setExpectedReaderToken(newToken)
        DebugReaderRegistry.shared.setActiveEPUBWebView(newWebView, for: "k1", token: newToken)

        // Stale didFinish from outgoing reader fires AFTER the new reader
        // already established its binding. Registry must reject the
        // stale write — not clobber the (newWebView, k1, newToken) slot.
        DebugReaderRegistry.shared.setActiveEPUBWebView(oldWebView, for: "k1", token: oldToken)

        // Current reader's eval looks up with newToken. Must return new.
        XCTAssertTrue(
            DebugReaderRegistry.shared.epubWebView(for: "k1", token: newToken) === newWebView,
            "Stale didFinish (outgoing token) must not clobber current reader's binding"
        )
    }

    func test_foliateWebView_lateStaleDidFinishCannotClobberCurrentReader() {
        // Same ordering test for the Foliate slot.
        let oldWebView = WKWebView(frame: .zero)
        let newWebView = WKWebView(frame: .zero)
        let oldToken = UUID()
        let newToken = UUID()

        DebugReaderRegistry.shared.setExpectedReaderToken(newToken)
        DebugReaderRegistry.shared.setActiveFoliateWebView(newWebView, for: "k1", token: newToken)
        DebugReaderRegistry.shared.setActiveFoliateWebView(oldWebView, for: "k1", token: oldToken)

        XCTAssertTrue(
            DebugReaderRegistry.shared.foliateWebView(for: "k1", token: newToken) === newWebView,
            "Stale didFinish (outgoing token) must not clobber current Foliate binding"
        )
    }
    #endif
}

@MainActor
private final class StubProbe: DebugReaderProbe {
    let fingerprintKey: String
    let format: String
    var currentPositionString: String? = nil

    init(key: String, fmt: String) {
        fingerprintKey = key
        format = fmt
    }

    func awaitSettle(timeout: TimeInterval) async throws {}

    func evaluateJavaScript(_ script: String) async throws -> Data {
        return Data("\"stub\"".utf8)
    }
}

#endif
