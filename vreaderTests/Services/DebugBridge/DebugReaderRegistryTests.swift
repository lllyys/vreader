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
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "any-key"))
    }

    func test_setActiveEPUBWebView_returnsForMatchingKey() {
        let webView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: "k1")
        XCTAssertTrue(DebugReaderRegistry.shared.epubWebView(for: "k1") === webView)
    }

    func test_setActiveEPUBWebView_returnsNilForMismatchedKey() {
        // Bug #126 stale-protection: a webview registered for an outgoing
        // book must NOT be returned to a probe that asks about a different
        // book. Codex audit (2026-05-06) flagged this as the High finding
        // on the initial fix.
        let webView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: "outgoing-book")
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "incoming-book"))
    }

    func test_setActiveEPUBWebView_replacesPreviousBinding() {
        let webViewA = WKWebView(frame: .zero)
        let webViewB = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webViewA, for: "k1")
        DebugReaderRegistry.shared.setActiveEPUBWebView(webViewB, for: "k2")
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "k1"))
        XCTAssertTrue(DebugReaderRegistry.shared.epubWebView(for: "k2") === webViewB)
    }

    func test_unregister_clearsEPUBWebViewWhenKeyMatches() {
        let webView = WKWebView(frame: .zero)
        let probe = StubProbe(key: "k1", fmt: "epub")
        DebugReaderRegistry.shared.register(probe)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: "k1")
        DebugReaderRegistry.shared.unregister(probe)
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "k1"))
    }

    func test_reset_clearsEPUBWebView() {
        let webView = WKWebView(frame: .zero)
        DebugReaderRegistry.shared.setActiveEPUBWebView(webView, for: "k1")
        DebugReaderRegistry.shared.reset()
        XCTAssertNil(DebugReaderRegistry.shared.epubWebView(for: "k1"))
        XCTAssertNil(DebugReaderRegistry.shared.rawActiveEPUBWebViewKeyForTests)
    }

    // Note: the underlying ref (`activeEPUBWebViewRef`) is declared `weak`
    // in source. A behavioral weak-drop test is flaky here — UIKit-class
    // instances often outlive an `autoreleasepool` block during test
    // runs. The compile-time declaration is the contract; the runtime
    // weak-drop is covered by on-device verification (bug #126 evidence).
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
