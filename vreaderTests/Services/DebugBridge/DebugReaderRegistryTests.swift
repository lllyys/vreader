// Purpose: Tests for DebugReaderRegistry — the active-reader handle used
// by settle/eval/snapshot in feature #44 DebugBridge. Verifies register
// replaces previous, unregister no-ops on stale entries, and the registry
// holds a weak reference.

#if DEBUG

import XCTest
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
