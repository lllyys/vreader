// Purpose: Tests for DebugBridge orchestrator — wires URL parsing
// (DebugCommand) to per-command handlers (DebugBridgeContext) for
// feature #44. Verifies dispatch routing, error handling, and that
// handlers receive the parsed command faithfully.

#if DEBUG

import XCTest
@testable import vreader

final class DebugBridgeTests: XCTestCase {

    // MARK: - Routing

    @MainActor
    func test_handle_resetURL_callsResetHandler() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://reset")!)

        XCTAssertEqual(context.calls, [.reset])
    }

    @MainActor
    func test_handle_seedURL_callsSeedHandlerWithFixtureName() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://seed?fixture=alice")!)

        XCTAssertEqual(context.calls, [.seed(fixture: "alice")])
    }

    @MainActor
    func test_handle_searchURLWithQueryOnly_callsSearchHandlerWithNilIndex() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://search?query=alice")!)

        XCTAssertEqual(context.calls, [.search(query: "alice", index: nil)])
    }

    @MainActor
    func test_handle_searchURLWithQueryAndIndex_callsSearchHandler() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://search?query=alice&index=2")!)

        XCTAssertEqual(context.calls, [.search(query: "alice", index: 2)])
    }

    @MainActor
    func test_handle_highlightURLWithStartEnd_callsHighlightHandlerWithNilColor() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://highlight?start=10&end=42")!)

        XCTAssertEqual(context.calls, [.highlight(startUTF16: 10, endUTF16: 42, color: nil)])
    }

    @MainActor
    func test_handle_highlightURLWithColor_callsHighlightHandler() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://highlight?start=0&end=5&color=pink")!)

        XCTAssertEqual(context.calls, [.highlight(startUTF16: 0, endUTF16: 5, color: "pink")])
    }

    @MainActor
    func test_handle_unknownCommand_recordsParseErrorWithoutCallingHandlers() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://teleport")!)

        XCTAssertTrue(context.calls.isEmpty, "no handlers should be invoked")
        XCTAssertNotNil(bridge.lastError, "parse error should be recorded")
    }

    @MainActor
    func test_handle_wrongScheme_recordsErrorWithoutCallingHandlers() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "https://example.com")!)

        XCTAssertTrue(context.calls.isEmpty)
        XCTAssertNotNil(bridge.lastError)
    }

    @MainActor
    func test_handle_successClearsLastError() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        // First a failing call
        await bridge.handle(URL(string: "vreader-debug://teleport")!)
        XCTAssertNotNil(bridge.lastError)

        // Then a succeeding call
        await bridge.handle(URL(string: "vreader-debug://reset")!)
        XCTAssertNil(bridge.lastError, "lastError should clear after a successful dispatch")
    }

    @MainActor
    func test_handle_multipleCommands_areDispatchedInOrder() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://reset")!)
        await bridge.handle(URL(string: "vreader-debug://seed?fixture=alice")!)
        await bridge.handle(URL(string: "vreader-debug://reset")!)

        XCTAssertEqual(context.calls, [.reset, .seed(fixture: "alice"), .reset])
    }

    // MARK: - stableErrorMessage

    func test_stableErrorMessage_parseErrors_useParsePrefix() {
        XCTAssertEqual(
            DebugBridge.stableErrorMessage(for: DebugCommandError.invalidScheme),
            "parse.invalidScheme"
        )
        XCTAssertEqual(
            DebugBridge.stableErrorMessage(for: DebugCommandError.unknownCommand("teleport")),
            "parse.unknownCommand: teleport"
        )
        XCTAssertEqual(
            DebugBridge.stableErrorMessage(for: DebugCommandError.missingParam("fixture")),
            "parse.missingParam: fixture"
        )
    }

    func test_stableErrorMessage_bridgeContextErrors_useBridgePrefix() {
        XCTAssertEqual(
            DebugBridge.stableErrorMessage(for: DebugBridgeContextError.unknownFixture("foo")),
            "bridge.unknownFixture: foo"
        )
        XCTAssertEqual(
            DebugBridge.stableErrorMessage(for: DebugBridgeContextError.fixtureResourceMissing("foo.txt")),
            "bridge.fixtureResourceMissing: foo.txt"
        )
        XCTAssertEqual(
            DebugBridge.stableErrorMessage(for: DebugBridgeContextError.notImplemented(command: "open")),
            "bridge.notImplemented: open"
        )
    }

    func test_stableErrorMessage_unknownError_usesUnknownPrefix() {
        struct DummyError: Error {}
        let msg = DebugBridge.stableErrorMessage(for: DummyError())
        XCTAssertTrue(msg.hasPrefix("unknown:"), "got \(msg)")
    }

    // MARK: - Routing

    @MainActor
    func test_handle_concurrentCalls_doNotInterleave() async {
        // A slow context exposes interleaving. Without serialization, two
        // concurrent calls would produce events like [start A, start B, end A, end B].
        // Arrival order across `async let` is not guaranteed by Swift, so this
        // test asserts the load-bearing property: every start is immediately
        // followed by its matching end (no interleave).
        let context = SlowDebugBridgeContext(delayNs: 30_000_000) // 30 ms each
        let bridge = DebugBridge(context: context)

        async let a: () = bridge.handle(URL(string: "vreader-debug://reset")!)
        async let b: () = bridge.handle(URL(string: "vreader-debug://seed?fixture=alice")!)
        async let c: () = bridge.handle(URL(string: "vreader-debug://reset")!)
        _ = await (a, b, c)

        XCTAssertEqual(context.calls.count, 6, "3 commands → 3 start + 3 end events")

        var i = 0
        while i < context.calls.count {
            guard case .start(let startTag) = context.calls[i] else {
                XCTFail("expected start at index \(i), got \(context.calls[i])")
                return
            }
            guard i + 1 < context.calls.count,
                  case .end(let endTag) = context.calls[i + 1] else {
                XCTFail("expected end immediately after start at \(i)")
                return
            }
            XCTAssertEqual(startTag, endTag, "interleave detected: start \(startTag) was followed by end \(endTag)")
            i += 2
        }
    }
}

/// Records when each command starts and finishes. Inserts an artificial
/// delay between start and end so any concurrent dispatch would surface as
/// overlapping start/end events.
@MainActor
final class SlowDebugBridgeContext: DebugBridgeContext {
    enum Event: Equatable {
        case start(String)
        case end(String)
    }

    private(set) var calls: [Event] = []
    let delayNs: UInt64

    init(delayNs: UInt64) { self.delayNs = delayNs }

    private func record(_ tag: String) async {
        calls.append(.start(tag))
        try? await Task.sleep(nanoseconds: delayNs)
        calls.append(.end(tag))
    }

    func reset() async throws { await record("reset") }
    func seed(fixture: String) async throws { await record("seed:\(fixture)") }
    func open(bookId: String, position: String?) async throws { await record("open:\(bookId)") }
    func theme(mode: DebugCommand.ThemeMode, fontSize: Int?) async throws { await record("theme:\(mode.rawValue)") }
    func settle(token: String) async throws { await record("settle:\(token)") }
    func snapshot(dest: String, lastErrorMessage: String?) async throws { await record("snapshot:\(dest)") }
    func eval(bridge: String, js: String) async throws { await record("eval:\(bridge)") }
    func tts(action: String) async throws { await record("tts:\(action)") }
    func search(query: String, index: Int?) async throws {
        await record("search:\(query):\(index.map(String.init) ?? "nil")")
    }
    func highlight(startUTF16: Int, endUTF16: Int, color: String?) async throws {
        await record("highlight:\(startUTF16):\(endUTF16):\(color ?? "nil")")
    }
}

// MARK: - Recorder

/// Records every command the bridge dispatches, in order. Each method is a
/// no-op except for the recording. Used to verify routing without coupling
/// tests to real app state.
@MainActor
final class RecordingDebugBridgeContext: DebugBridgeContext {
    enum Call: Equatable {
        case reset
        case seed(fixture: String)
        case open(bookId: String, position: String?)
        case theme(mode: DebugCommand.ThemeMode, fontSize: Int?)
        case settle(token: String)
        case snapshot(dest: String, lastErrorMessage: String?)
        case eval(bridge: String, js: String)
        case tts(action: String)
        case search(query: String, index: Int?)
        case highlight(startUTF16: Int, endUTF16: Int, color: String?)
    }

    private(set) var calls: [Call] = []

    func reset() async throws { calls.append(.reset) }
    func seed(fixture: String) async throws { calls.append(.seed(fixture: fixture)) }
    func open(bookId: String, position: String?) async throws {
        calls.append(.open(bookId: bookId, position: position))
    }
    func theme(mode: DebugCommand.ThemeMode, fontSize: Int?) async throws {
        calls.append(.theme(mode: mode, fontSize: fontSize))
    }
    func settle(token: String) async throws { calls.append(.settle(token: token)) }
    func snapshot(dest: String, lastErrorMessage: String?) async throws {
        calls.append(.snapshot(dest: dest, lastErrorMessage: lastErrorMessage))
    }
    func eval(bridge: String, js: String) async throws {
        calls.append(.eval(bridge: bridge, js: js))
    }
    func tts(action: String) async throws { calls.append(.tts(action: action)) }
    func search(query: String, index: Int?) async throws {
        calls.append(.search(query: query, index: index))
    }
    func highlight(startUTF16: Int, endUTF16: Int, color: String?) async throws {
        calls.append(.highlight(startUTF16: startUTF16, endUTF16: endUTF16, color: color))
    }
}

#endif
