// Purpose: Feature #42 Phase 1 WI-4 — tests for the Readium DebugBridge probe
// registry slot (`DebugReaderRegistry.setActiveReadiumNavigator(_:for:token:)`
// / `readiumNavigator(for:token:)`) and the JS-eval feasibility spike (Risk 5).
//
// The Readium EPUB host (WI-5) renders via `EPUBNavigatorViewController`, which
// owns its own (possibly multiple) internal WKWebView(s) — there is no single
// app-owned webview to register like `EPUBWebViewBridge`. The spike resolved
// that Readium 3.9 DOES expose a clean JS-eval surface:
// `EPUBNavigatorViewController.evaluateJavaScript(_:) async -> Result<Any,Error>`
// runs JS on the currently-visible spine HTML. So the probe stores a weak
// reference to a `ReadiumNavigatorEvaluating` seam (which `EPUBNavigatorViewController`
// conforms to in WI-5) and exposes the same keyed + per-reader-token guarding
// as the EPUB/Foliate webview slots (bug #126 / #142). Settle reuses the
// existing `markReaderSettled` / `awaitReaderSettled` machinery — WI-5's host
// signals settle from Readium's `navigator(_:locationDidChange:)` delegate.
//
// Mirrors DebugReaderRegistryTests (EPUB/Foliate slots) + the settle suites.
// DEBUG-only — the registry and its probe machinery are #if DEBUG.

#if DEBUG

import XCTest
import Foundation
#if canImport(WebKit)
import WebKit
#endif
@testable import vreader

@MainActor
final class ReadiumDebugProbeTests: XCTestCase {

    /// Stable token for tests that don't exercise the bug #142 reopen race.
    private let testToken = UUID()

    override func setUp() {
        super.setUp()
        DebugReaderRegistry.shared.reset()
    }

    override func tearDown() {
        DebugReaderRegistry.shared.reset()
        super.tearDown()
    }

    // MARK: - Registration + keyed lookup (bug #126 parity)

    func test_readiumNavigator_initiallyNil_forAnyKey() {
        XCTAssertNil(DebugReaderRegistry.shared.readiumNavigator(for: "any-key", token: testToken))
    }

    func test_setActiveReadiumNavigator_returnsForMatchingKeyAndToken() {
        let nav = FakeReadiumNavigator()
        DebugReaderRegistry.shared.setActiveReadiumNavigator(nav, for: "k1", token: testToken)
        XCTAssertTrue(DebugReaderRegistry.shared.readiumNavigator(for: "k1", token: testToken) === nav)
    }

    func test_setActiveReadiumNavigator_returnsNilForMismatchedKey() {
        // Stale-protection: a navigator registered for an outgoing book must
        // NOT be returned to a probe asking about a different book.
        let nav = FakeReadiumNavigator()
        DebugReaderRegistry.shared.setActiveReadiumNavigator(nav, for: "outgoing-book", token: testToken)
        XCTAssertNil(DebugReaderRegistry.shared.readiumNavigator(for: "incoming-book", token: testToken))
    }

    func test_setActiveReadiumNavigator_replacesPreviousBinding() {
        let navA = FakeReadiumNavigator()
        let navB = FakeReadiumNavigator()
        DebugReaderRegistry.shared.setActiveReadiumNavigator(navA, for: "k1", token: testToken)
        DebugReaderRegistry.shared.setActiveReadiumNavigator(navB, for: "k2", token: testToken)
        XCTAssertNil(DebugReaderRegistry.shared.readiumNavigator(for: "k1", token: testToken))
        XCTAssertTrue(DebugReaderRegistry.shared.readiumNavigator(for: "k2", token: testToken) === navB)
    }

    // MARK: - Per-reader token disambiguation (bug #142 same-book reopen race)

    func test_readiumNavigator_returnsNilForSameKeyDifferentToken() {
        // A late didFinish/relocate from the outgoing reader re-registers
        // under the same key but the old token; the new reader must NOT see it.
        let outgoing = FakeReadiumNavigator()
        let outgoingToken = UUID()
        let incomingToken = UUID()
        DebugReaderRegistry.shared.setActiveReadiumNavigator(outgoing, for: "k1", token: outgoingToken)
        XCTAssertNil(DebugReaderRegistry.shared.readiumNavigator(for: "k1", token: incomingToken))
    }

    func test_setActiveReadiumNavigator_lateStaleCallbackCannotClobberCurrentReader() {
        // Codex round-1 ordering test (bug #142): new reader mounts and sets
        // its expected token; a stale callback from the outgoing reader fires
        // AFTER and must be rejected, not clobber the current binding.
        let oldNav = FakeReadiumNavigator()
        let newNav = FakeReadiumNavigator()
        let oldToken = UUID()
        let newToken = UUID()

        DebugReaderRegistry.shared.setExpectedReaderToken(newToken)
        DebugReaderRegistry.shared.setActiveReadiumNavigator(newNav, for: "k1", token: newToken)
        // Stale callback (outgoing token) arrives late.
        DebugReaderRegistry.shared.setActiveReadiumNavigator(oldNav, for: "k1", token: oldToken)

        XCTAssertTrue(
            DebugReaderRegistry.shared.readiumNavigator(for: "k1", token: newToken) === newNav,
            "Stale callback (outgoing token) must not clobber the current Readium binding"
        )
    }

    // MARK: - Lifecycle clearing (unregister / reset)

    func test_unregister_clearsReadiumNavigatorWhenKeyMatches() {
        let nav = FakeReadiumNavigator()
        let probe = ReadiumStubProbe(key: "k1", fmt: "epub")
        DebugReaderRegistry.shared.register(probe)
        DebugReaderRegistry.shared.setActiveReadiumNavigator(nav, for: "k1", token: testToken)
        DebugReaderRegistry.shared.unregister(probe)
        XCTAssertNil(DebugReaderRegistry.shared.readiumNavigator(for: "k1", token: testToken))
    }

    func test_reset_clearsReadiumNavigator() {
        let nav = FakeReadiumNavigator()
        DebugReaderRegistry.shared.setActiveReadiumNavigator(nav, for: "k1", token: testToken)
        DebugReaderRegistry.shared.reset()
        XCTAssertNil(DebugReaderRegistry.shared.readiumNavigator(for: "k1", token: testToken))
        XCTAssertNil(DebugReaderRegistry.shared.rawActiveReadiumNavigatorKeyForTests)
    }

    func test_readiumBinding_isIndependentOfEPUBAndFoliateSlots() {
        // Setting the Readium slot must not disturb the EPUB/Foliate slots
        // and vice-versa — three independent reader-engine slots.
        let nav = FakeReadiumNavigator()
        DebugReaderRegistry.shared.setActiveReadiumNavigator(nav, for: "k1", token: testToken)
        XCTAssertTrue(DebugReaderRegistry.shared.readiumNavigator(for: "k1", token: testToken) === nav)
        #if canImport(WebKit)
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "k1", token: testToken))
        XCTAssertNil(DebugReaderRegistry.shared.foliateWebView(for: "k1", token: testToken))
        #endif
    }

    // MARK: - Eval feasibility spike (Risk 5): JS runs through the navigator

    func test_evaluateJavaScript_throughRegisteredNavigator_returnsJSONBytes() async throws {
        let nav = FakeReadiumNavigator()
        nav.stubbedResultJSON = Data("42".utf8)
        DebugReaderRegistry.shared.setActiveReadiumNavigator(nav, for: "k1", token: testToken)

        let navigator = try XCTUnwrap(DebugReaderRegistry.shared.readiumNavigator(for: "k1", token: testToken))
        let result = try await navigator.evaluateJavaScriptValue("1 + 41")
        XCTAssertEqual(result, Data("42".utf8))
        XCTAssertEqual(nav.lastScript, "1 + 41")
    }

    func test_evaluateJavaScript_propagatesNavigatorError() async {
        let nav = FakeReadiumNavigator()
        nav.shouldThrow = true
        DebugReaderRegistry.shared.setActiveReadiumNavigator(nav, for: "k1", token: testToken)

        let navigator = DebugReaderRegistry.shared.readiumNavigator(for: "k1", token: testToken)
        XCTAssertNotNil(navigator)
        do {
            _ = try await navigator?.evaluateJavaScriptValue("boom")
            XCTFail("expected the navigator's eval error to propagate")
        } catch {
            // expected — eval errors surface to the caller, no crash.
        }
    }

    // MARK: - Settle reuse (markReaderSettled / awaitReaderSettled)
    //
    // WI-5's host signals settle from Readium's navigator(_:locationDidChange:)
    // delegate. The probe path reuses the existing keyed+token settle machinery,
    // so a Readium key participates exactly like an EPUB/Foliate key.

    func test_readiumSettle_markThenAwait_resolvesForMatchingKeyToken() async throws {
        let key = "epub:readium:1024"
        let token = UUID()
        DebugReaderRegistry.shared.markReaderSettled(for: key, token: token)
        // Fast path — already settled.
        try await DebugReaderRegistry.shared.awaitReaderSettled(for: key, token: token, timeout: 0.05)
    }

    func test_readiumSettle_awaitTimesOutWithoutMark() async {
        let key = "epub:readium:512"
        let token = UUID()
        do {
            try await DebugReaderRegistry.shared.awaitReaderSettled(for: key, token: token, timeout: 0.15)
            XCTFail("expected settleTimeout")
        } catch DebugReaderProbeError.settleTimeout {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Bug #277: Stage-2 WebView gate accepts the Readium navigator slot
    //
    // The settle Stage-2 gate (`awaitWebViewRegistered(for:format:)`, bug #250)
    // only knew the legacy EPUB/Foliate WebView slots. A Readium-rendered EPUB
    // fills the `activeReadiumNavigator` slot instead — so settle always wrote
    // `error=webview not registered` even though the reader rendered. The fix
    // teaches the gate to accept EITHER slot for `.epub`, under the same
    // key+token guard. Uses an isolated registry (bug #227/#228 pattern) so the
    // parallel Swift-Testing/XCTest run can't trip on shared-singleton state.

    func test_awaitWebViewRegistered_epub_resolvesWhenOnlyReadiumNavigatorRegistered() async throws {
        let registry = DebugReaderRegistry.makeIsolatedForTests()
        let nav = FakeReadiumNavigator()
        let key = "epub:readium:2048"
        let token = UUID()
        // Match the production lifecycle: expected token is set before the
        // navigator registers, exactly as ReaderContainerView.onAppear does.
        registry.setExpectedReaderToken(token)
        registry.setActiveReadiumNavigator(nav, for: key, token: token)
        // No EPUB WebView slot is ever populated by the Readium host. Pre-fix
        // this throws settleTimeout → settle reports `webview not registered`.
        try await registry.awaitWebViewRegistered(for: key, format: "epub", timeout: 1.0)
    }

    func test_hasActiveWebView_epub_trueForReadiumNavigatorSlot() {
        let registry = DebugReaderRegistry.makeIsolatedForTests()
        let nav = FakeReadiumNavigator()
        let token = UUID()
        registry.setExpectedReaderToken(token)
        registry.setActiveReadiumNavigator(nav, for: "k1", token: token)
        XCTAssertTrue(registry.hasActiveWebView(for: "k1", format: "epub"))
    }

    func test_hasActiveWebView_epub_falseForReadiumNavigatorWrongKey() {
        let registry = DebugReaderRegistry.makeIsolatedForTests()
        let nav = FakeReadiumNavigator()
        let token = UUID()
        registry.setExpectedReaderToken(token)
        registry.setActiveReadiumNavigator(nav, for: "k1", token: token)
        XCTAssertFalse(registry.hasActiveWebView(for: "other-key", format: "epub"))
    }

    func test_hasActiveWebView_epub_falseForReadiumNavigatorStaleToken() {
        // A late navigator binding under an outgoing token must not satisfy the
        // gate for the incoming reader: the slot's token != expectedReaderToken.
        let registry = DebugReaderRegistry.makeIsolatedForTests()
        let nav = FakeReadiumNavigator()
        let outgoingToken = UUID()
        let incomingToken = UUID()
        // Outgoing token registers the navigator (no expected token yet).
        registry.setActiveReadiumNavigator(nav, for: "k1", token: outgoingToken)
        // Incoming reader takes over and sets its expected token.
        registry.setExpectedReaderToken(incomingToken)
        XCTAssertFalse(
            registry.hasActiveWebView(for: "k1", format: "epub"),
            "Slot token (outgoing) must match expectedReaderToken (incoming) to satisfy the gate"
        )
    }

    func test_hasActiveWebView_epub_stillTrueForLegacyEPUBWebViewSlot() {
        // The legacy path must keep working: an EPUB WebView slot satisfies the
        // gate without any Readium navigator registered.
        #if canImport(WebKit)
        let registry = DebugReaderRegistry.makeIsolatedForTests()
        let webView = WKWebView()
        let token = UUID()
        registry.setExpectedReaderToken(token)
        registry.setActiveEPUBWebView(webView, for: "k1", token: token)
        XCTAssertTrue(registry.hasActiveWebView(for: "k1", format: "epub"))
        XCTAssertNil(registry.readiumNavigator(for: "k1", token: token))
        #endif
    }
}

// MARK: - Test doubles

/// Fake `ReadiumNavigatorEvaluating` standing in for `EPUBNavigatorViewController`.
/// The real navigator conforms via a thin WI-5 adapter; the registry only needs
/// the eval seam, so the slot is unit-testable without a live Readium publication.
@MainActor
private final class FakeReadiumNavigator: ReadiumNavigatorEvaluating {
    var stubbedResultJSON = Data("null".utf8)
    var shouldThrow = false
    private(set) var lastScript: String?

    func evaluateJavaScriptValue(_ script: String) async throws -> Data {
        lastScript = script
        if shouldThrow {
            throw DebugReaderProbeError.evalUnsupported(format: "epub")
        }
        return stubbedResultJSON
    }
}

@MainActor
private final class ReadiumStubProbe: DebugReaderProbe {
    let fingerprintKey: String
    let format: String
    var currentPositionString: String? = nil

    init(key: String, fmt: String) {
        self.fingerprintKey = key
        self.format = fmt
    }

    func awaitSettle(timeout: TimeInterval) async throws {}
    func evaluateJavaScript(_ script: String) async throws -> Data {
        throw DebugReaderProbeError.evalUnsupported(format: format)
    }
}

#endif
