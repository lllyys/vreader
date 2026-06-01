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
    func test_handle_txtContentURL_callsTxtContentHandler() async {
        // Bug #1218: txt-content?dest routes to the txtContent handler
        // (mirrors the snapshot routing). The handler reads the active TXT
        // reader's rendered text for CU-free conversion verification.
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://txt-content?dest=txt.json")!)

        XCTAssertEqual(context.calls, [.txtContent(dest: "txt.json")])
    }

    @MainActor
    func test_handle_seekURL_callsSeekFractionHandler() async {
        // Bug #267: seek?fraction routes to the seekFraction handler.
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://seek?fraction=0.5")!)

        XCTAssertEqual(context.calls, [.seekFraction(fraction: 0.5)])
    }

    @MainActor
    func test_handle_scrollSheetURL_callsScrollSheetHandler() async {
        // Bug #271: scroll-sheet?to routes to the scrollSheet handler.
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://scroll-sheet?to=bottom")!)

        XCTAssertEqual(context.calls, [.scrollSheet(target: .bottom)])
    }

    @MainActor
    func test_handle_navigateURL_withFraction_callsNavigateHandler() async {
        // Bug #273: navigate?spine&fraction routes to the navigate handler.
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://navigate?spine=2&fraction=0.5")!)

        XCTAssertEqual(context.calls, [.navigate(spineIndex: 2, fraction: 0.5)])
    }

    @MainActor
    func test_handle_navigateURL_withoutFraction_callsNavigateHandlerWithNil() async {
        // Bug #273: fraction is optional — absent ⇒ chapter start (nil).
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://navigate?spine=0")!)

        XCTAssertEqual(context.calls, [.navigate(spineIndex: 0, fraction: nil)])
    }

    @MainActor
    func test_handle_scrollBoundaryURL_callsHandler() async {
        // Feature #71 WI-6b: scroll-boundary?spine&near routes to the
        // scrollBoundary handler.
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://scroll-boundary?spine=2&near=bottom")!)

        XCTAssertEqual(context.calls, [.scrollBoundary(spineIndex: 2, near: .bottom)])
    }

    @MainActor
    func test_handle_pdfHighlightURL_callsPDFHighlightHandlerWithNilColor() async {
        // Feature #17: pdf-highlight?page&rect routes to the pdfHighlight handler.
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://pdf-highlight?page=0&rect=0.1,0.2,0.3,0.4")!)

        XCTAssertEqual(
            context.calls,
            [.pdfHighlight(
                page: 0,
                rect: NormalizedRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4),
                color: nil
            )]
        )
    }

    @MainActor
    func test_handle_pdfHighlightURLWithColor_callsPDFHighlightHandler() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://pdf-highlight?page=2&rect=0,0,1,1&color=green")!)

        XCTAssertEqual(
            context.calls,
            [.pdfHighlight(
                page: 2,
                rect: NormalizedRect(x: 0, y: 0, w: 1, h: 1),
                color: "green"
            )]
        )
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
    func test_handle_providerAddURL_callsProviderHandlerWithAddAction() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        let endpoint = "https://openrouter.ai/api/v1".addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        )!
        await bridge.handle(URL(string:
            "vreader-debug://provider?action=add&name=OR&kind=openAICompatible&endpoint=\(endpoint)&apiKey=k&active=true"
        )!)

        XCTAssertEqual(
            context.calls,
            [.provider(action: .add(
                name: "OR",
                kind: .openAICompatible,
                endpoint: URL(string: "https://openrouter.ai/api/v1")!,
                apiKey: "k",
                model: nil,
                active: true
            ))]
        )
    }

    @MainActor
    func test_handle_providerRemoveURL_callsProviderHandlerWithRemoveAction() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://provider?action=remove&name=OR")!)

        XCTAssertEqual(context.calls, [.provider(action: .remove(name: "OR"))])
    }

    @MainActor
    func test_handle_providerClearURL_callsProviderHandlerWithClearAction() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://provider?action=clear")!)

        XCTAssertEqual(context.calls, [.provider(action: .clear)])
    }

    @MainActor
    func test_handle_seedSessionsURL_callsSeedReadingSessionsHandler() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://seed-sessions?book=txt:abc:1&seconds=300")!)

        XCTAssertEqual(
            context.calls,
            [.seedReadingSessions(bookFingerprintKey: "txt:abc:1", secondsPerSession: 300)]
        )
    }

    @MainActor
    func test_handle_presentSheetURL_callsPresentHandlerWithSheetOnly() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://present?sheet=toc")!)

        XCTAssertEqual(context.calls, [.present(sheet: .toc, tab: nil, detent: nil)])
    }

    @MainActor
    func test_handle_presentSheetWithTabURL_callsPresentHandlerWithTab() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://present?sheet=ai&tab=summarize")!)

        XCTAssertEqual(context.calls, [.present(sheet: .ai, tab: "summarize", detent: nil)])
    }

    @MainActor
    func test_handle_presentAIDetentLargeURL_callsPresentHandlerWithDetent() async {
        // Bug #256 — the `detent` param threads through the dispatch into the
        // handler so the AI sheet's larger detent is reachable CU-free.
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://present?sheet=ai&tab=translate&detent=large")!)

        XCTAssertEqual(context.calls, [.present(sheet: .ai, tab: "translate", detent: .large)])
    }

    @MainActor
    func test_handle_aiSummarizeURL_callsAIActionHandler() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://ai?action=summarize&scope=chapter")!)

        XCTAssertEqual(context.calls, [.aiAction(action: .summarize, scope: .chapter, text: nil)])
    }

    @MainActor
    func test_handle_aiChatURL_callsAIActionHandlerWithText() async {
        let context = RecordingDebugBridgeContext()
        let bridge = DebugBridge(context: context)

        await bridge.handle(URL(string: "vreader-debug://ai?action=chat&text=hello")!)

        XCTAssertEqual(context.calls, [.aiAction(action: .chat, scope: nil, text: "hello")])
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
    func txtContent(dest: String) async throws { await record("txt-content:\(dest)") }
    func eval(bridge: String, js: String) async throws { await record("eval:\(bridge)") }
    func tts(action: String) async throws { await record("tts:\(action)") }
    func search(query: String, index: Int?) async throws {
        await record("search:\(query):\(index.map(String.init) ?? "nil")")
    }
    func highlight(startUTF16: Int, endUTF16: Int, color: String?) async throws {
        await record("highlight:\(startUTF16):\(endUTF16):\(color ?? "nil")")
    }
    func provider(action: DebugCommand.ProviderAction) async throws {
        await record("provider:\(actionTag(action))")
    }
    func present(sheet: DebugCommand.SheetKind, tab: String?, detent: DebugCommand.SheetDetent?) async throws {
        await record("present:\(sheet.rawValue):\(tab ?? "nil"):\(detent?.rawValue ?? "nil")")
    }
    func aiAction(action: DebugCommand.AIActionKind, scope: SummaryScope?, text: String?) async throws {
        await record("ai:\(action.rawValue):\(scope?.rawValue ?? "nil"):\(text ?? "nil")")
    }
    func seedReadingSessions(bookFingerprintKey: String, secondsPerSession: Int) async throws {
        await record("seed-sessions:\(bookFingerprintKey):\(secondsPerSession)")
    }
    func seekFraction(fraction: Double) async throws {
        await record("seek:\(fraction)")
    }
    func scrollSheet(target: DebugCommand.ScrollTarget) async throws {
        await record("scroll-sheet:\(target.rawValue)")
    }
    func navigate(spineIndex: Int, fraction: Double?) async throws {
        await record("navigate:\(spineIndex):\(fraction.map { String($0) } ?? "nil")")
    }
    func scrollBoundary(spineIndex: Int, near: DebugCommand.ScrollBoundaryEdge) async throws {
        await record("scroll-boundary:\(spineIndex):\(near.rawValue)")
    }
    func pdfHighlight(page: Int, rect: NormalizedRect, color: String?) async throws {
        await record("pdf-highlight:\(page):\(rect.x),\(rect.y),\(rect.w),\(rect.h):\(color ?? "nil")")
    }
    func setLayout(layout: DebugCommand.LayoutMode) async throws {
        await record("set-layout:\(layout.rawValue)")
    }
    func page(direction: DebugCommand.PageDirection) async throws {
        await record("page:\(direction.rawValue)")
    }

    private func actionTag(_ action: DebugCommand.ProviderAction) -> String {
        switch action {
        case .add(let name, _, _, _, _, _): return "add:\(name)"
        case .remove(let name): return "remove:\(name)"
        case .clear: return "clear"
        }
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
        case txtContent(dest: String)
        case eval(bridge: String, js: String)
        case tts(action: String)
        case search(query: String, index: Int?)
        case highlight(startUTF16: Int, endUTF16: Int, color: String?)
        case provider(action: DebugCommand.ProviderAction)
        case present(sheet: DebugCommand.SheetKind, tab: String?, detent: DebugCommand.SheetDetent?)
        case aiAction(action: DebugCommand.AIActionKind, scope: SummaryScope?, text: String?)
        case seedReadingSessions(bookFingerprintKey: String, secondsPerSession: Int)
        case seekFraction(fraction: Double)
        case scrollSheet(target: DebugCommand.ScrollTarget)
        case navigate(spineIndex: Int, fraction: Double?)
        case scrollBoundary(spineIndex: Int, near: DebugCommand.ScrollBoundaryEdge)
        case pdfHighlight(page: Int, rect: NormalizedRect, color: String?)
        case setLayout(layout: DebugCommand.LayoutMode)
        case page(direction: DebugCommand.PageDirection)
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
    func txtContent(dest: String) async throws {
        calls.append(.txtContent(dest: dest))
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
    func provider(action: DebugCommand.ProviderAction) async throws {
        calls.append(.provider(action: action))
    }
    func present(sheet: DebugCommand.SheetKind, tab: String?, detent: DebugCommand.SheetDetent?) async throws {
        calls.append(.present(sheet: sheet, tab: tab, detent: detent))
    }
    func aiAction(action: DebugCommand.AIActionKind, scope: SummaryScope?, text: String?) async throws {
        calls.append(.aiAction(action: action, scope: scope, text: text))
    }
    func seedReadingSessions(bookFingerprintKey: String, secondsPerSession: Int) async throws {
        calls.append(.seedReadingSessions(bookFingerprintKey: bookFingerprintKey, secondsPerSession: secondsPerSession))
    }
    func seekFraction(fraction: Double) async throws {
        calls.append(.seekFraction(fraction: fraction))
    }
    func scrollSheet(target: DebugCommand.ScrollTarget) async throws {
        calls.append(.scrollSheet(target: target))
    }
    func navigate(spineIndex: Int, fraction: Double?) async throws {
        calls.append(.navigate(spineIndex: spineIndex, fraction: fraction))
    }
    func scrollBoundary(spineIndex: Int, near: DebugCommand.ScrollBoundaryEdge) async throws {
        calls.append(.scrollBoundary(spineIndex: spineIndex, near: near))
    }
    func pdfHighlight(page: Int, rect: NormalizedRect, color: String?) async throws {
        calls.append(.pdfHighlight(page: page, rect: rect, color: color))
    }
    func setLayout(layout: DebugCommand.LayoutMode) async throws {
        calls.append(.setLayout(layout: layout))
    }
    func page(direction: DebugCommand.PageDirection) async throws {
        calls.append(.page(direction: direction))
    }
}

#endif
