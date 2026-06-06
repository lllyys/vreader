// Purpose: Feature #91 WI-7 — pin the bounded agentic loop: a scripted
// ToolUseSending provider drives the driver through tool rounds + a final text;
// a real AIToolRegistry runs the tools. Proves: text-immediately (no tools),
// tool→result→re-send→text, the assistant turn re-appended losslessly + the
// tool_result fed back, a tool error continues the loop, multiple calls in one
// turn, the iteration cap, and provider-throw propagation.
//
// @coordinates-with: AgenticChatDriver.swift, AIToolRegistry.swift, AITool.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-7)

import Testing
import Foundation
@testable import vreader

private enum ScriptedProviderError: Error { case boom }

/// A test tool that echoes a fixed reply (and records nothing — the registry
/// rebinds the call id, which the driver tests assert on the fed-back result).
private struct ProbeTool: AITool {
    let toolName: String
    let reply: String
    let fail: Bool
    init(name: String, reply: String = "tool output", fail: Bool = false) {
        self.toolName = name; self.reply = reply; self.fail = fail
    }
    var definition: ToolDefinition {
        ToolDefinition(name: toolName, description: "probe \(toolName)", inputSchema: .object([:]))
    }
    func run(_ input: JSONValue) async -> ToolResult {
        ToolResult(toolUseID: "IGNORED", content: reply, isError: fail)
    }
}

/// Returns a scripted sequence of turns (looping the last one when `loopLast`),
/// records every request, and can throw on the Nth call.
private actor ScriptedProvider: ToolUseSending {
    private var queue: [AIToolTurn]
    private let loopLast: Bool
    private let throwOnCall: Int?
    private var last: AIToolTurn?
    private var callCount = 0
    private(set) var requests: [AIToolRequest] = []

    init(_ queue: [AIToolTurn], loopLast: Bool = false, throwOnCall: Int? = nil) {
        self.queue = queue
        self.loopLast = loopLast
        self.throwOnCall = throwOnCall
    }

    func sendToolRequest(_ request: AIToolRequest) async throws -> AIToolTurn {
        callCount += 1
        requests.append(request)
        if let t = throwOnCall, callCount == t { throw ScriptedProviderError.boom }
        if !queue.isEmpty {
            last = queue.removeFirst()
            return last!
        }
        if loopLast, let last { return last }
        return .text("(exhausted)")
    }
}

/// An actor that records run count and PARKS the first entrant until `release()` —
/// so a test can cancel the surrounding task while a tool is mid-execution.
private actor ToolGate {
    private(set) var runCount = 0
    private var parkCont: CheckedContinuation<Void, Never>?
    private var released = false
    func enterAndParkFirst() async {
        runCount += 1
        guard runCount == 1, !released else { return }   // only the first call parks
        await withCheckedContinuation { cont in parkCont = cont }
    }
    func release() {
        released = true
        parkCont?.resume(); parkCont = nil
    }
}

/// A tool whose FIRST `run` parks until released — lets a test cancel the driver
/// task mid-round and assert the driver stops before the NEXT in-round tool call.
private final class GatedProbeTool: AITool, @unchecked Sendable {
    let toolName: String
    private let gate = ToolGate()
    init(name: String) { self.toolName = name }
    var definition: ToolDefinition {
        ToolDefinition(name: toolName, description: "gated probe", inputSchema: .object([:]))
    }
    var runCount: Int { get async { await gate.runCount } }
    func release() async { await gate.release() }
    func run(_ input: JSONValue) async -> ToolResult {
        await gate.enterAndParkFirst()
        return ToolResult(toolUseID: "IGNORED", content: "ok", isError: false)
    }
}

@Suite("Feature #91 WI-7 — AgenticChatDriver")
struct AgenticChatDriverTests {

    private static func history(_ prompt: String) -> [ToolTurnMessage] {
        [ToolTurnMessage(role: .user, content: [.text(prompt)])]
    }

    private static func toolUseTurn(callID: String, name: String, text: String? = nil) -> AIToolTurn {
        var blocks: [ToolContentBlock] = []
        if let text { blocks.append(.text(text)) }
        blocks.append(.toolUse(ToolCall(id: callID, name: name, input: .object([:]))))
        return .toolUse(blocks: blocks)
    }

    private func run(
        _ provider: ScriptedProvider, _ registry: AIToolRegistry, maxIterations: Int = 6
    ) async throws -> AgenticResult {
        try await AgenticChatDriver(maxIterations: maxIterations).run(
            systemPrompt: "sys", history: Self.history("question"),
            registry: registry, provider: provider, maxTokens: 1024)
    }

    // MARK: - No tools

    @Test("a text-only first turn returns immediately, usedTools == false, one send")
    func textImmediately() async throws {
        let provider = ScriptedProvider([.text("Hello.")])
        let result = try await run(provider, AIToolRegistry([]))
        #expect(result.finalText == "Hello.")
        #expect(result.usedTools == false)
        #expect(await provider.requests.count == 1)
    }

    // MARK: - One tool round

    @Test("tool turn → run → tool_result re-sent → final text; assistant turn is lossless")
    func runsToolThenText() async throws {
        let provider = ScriptedProvider([
            Self.toolUseTurn(callID: "c1", name: "search", text: "Let me search."),
            .text("The answer is 42."),
        ])
        let registry = AIToolRegistry([ProbeTool(name: "search", reply: "search result text")])

        let result = try await run(provider, registry)

        #expect(result.finalText == "The answer is 42.")
        #expect(result.usedTools == true)
        let requests = await provider.requests
        #expect(requests.count == 2)
        // The re-sent (2nd) request carries: user(q), assistant(the EXACT toolUse
        // blocks), user(tool_result).
        let msgs = requests[1].messages
        #expect(msgs.count == 3)
        #expect(msgs[1].role == .assistant)
        #expect(msgs[1].content == [.text("Let me search."), .toolUse(ToolCall(id: "c1", name: "search", input: .object([:])))])
        // The fed-back tool_result is bound to the call id (registry rebind) + carries the tool's output.
        guard case .toolResult(let fed) = msgs[2].content.first else {
            Issue.record("expected a tool_result block"); return
        }
        #expect(fed.toolUseID == "c1")
        #expect(fed.content == "search result text")
        #expect(fed.isError == false)
    }

    // MARK: - Tool error continues the loop

    @Test("a tool error is fed back as data; the loop continues to a final answer")
    func toolErrorContinues() async throws {
        // Empty registry → the call resolves to an unknown-tool isError result.
        let provider = ScriptedProvider([
            Self.toolUseTurn(callID: "c1", name: "missing"),
            .text("Recovered without that tool."),
        ])
        let result = try await run(provider, AIToolRegistry([]))
        #expect(result.finalText == "Recovered without that tool.")
        #expect(result.usedTools == true)
        let msgs = await provider.requests[1].messages
        guard case .toolResult(let fed) = msgs[2].content.first else {
            Issue.record("expected a tool_result block"); return
        }
        #expect(fed.isError == true)                 // the unknown-tool error was fed back
        #expect(fed.content.contains("Unknown tool 'missing'"))
    }

    // MARK: - Multiple calls in one turn

    @Test("multiple tool calls in one turn all run, in one tool_result user turn")
    func multipleCallsOneTurn() async throws {
        let blocks: [ToolContentBlock] = [
            .toolUse(ToolCall(id: "a", name: "search", input: .object([:]))),
            .toolUse(ToolCall(id: "b", name: "search", input: .object([:]))),
        ]
        let provider = ScriptedProvider([.toolUse(blocks: blocks), .text("done")])
        let result = try await run(provider, AIToolRegistry([ProbeTool(name: "search")]))
        #expect(result.finalText == "done")
        let userTurn = await provider.requests[1].messages[2]
        #expect(userTurn.role == .user)
        let resultIDs = userTurn.content.compactMap {
            if case .toolResult(let r) = $0 { return r.toolUseID } else { return nil }
        }
        #expect(resultIDs == ["a", "b"])             // both results, in order, one turn
    }

    // MARK: - Two completed tool rounds (multi-resend ordering + validator-safety)

    @Test("two tool rounds stay ordered + provider-invariant-valid before the final text")
    func twoToolRoundsThenText() async throws {
        let provider = ScriptedProvider([
            Self.toolUseTurn(callID: "a", name: "search"),
            Self.toolUseTurn(callID: "b", name: "search"),
            .text("done"),
        ])
        let result = try await run(provider, AIToolRegistry([ProbeTool(name: "search")]))
        #expect(result.finalText == "done")
        let requests = await provider.requests
        #expect(requests.count == 3)
        // The 3rd request carries BOTH completed rounds in order:
        // user(q), assistant(a), user(result a), assistant(b), user(result b).
        let msgs = requests[2].messages
        #expect(msgs.map(\.role) == [.user, .assistant, .user, .assistant, .user])
        // Each assistant tool_use turn is immediately followed by a tool_result-
        // leading user turn with every id answered — pin it with the real validator.
        try ToolHistoryValidator.validate(msgs)
    }

    // MARK: - Iteration cap

    @Test("the loop stops at maxIterations; with no model text the result is the fallback")
    func capStopsAtMaxFallback() async throws {
        let provider = ScriptedProvider(
            [Self.toolUseTurn(callID: "c", name: "search")], loopLast: true)   // no text
        let result = try await run(provider, AIToolRegistry([ProbeTool(name: "search")]), maxIterations: 3)
        #expect(await provider.requests.count == 3)   // capped — not unbounded
        #expect(result.usedTools == true)
        #expect(result.finalText == "I wasn't able to finish answering within the tool-call limit.")
    }

    @Test("on the cap, the model's last assistant text is returned when present")
    func capReturnsLastText() async throws {
        let provider = ScriptedProvider(
            [Self.toolUseTurn(callID: "c", name: "search", text: "Still digging…")], loopLast: true)
        let result = try await run(provider, AIToolRegistry([ProbeTool(name: "search")]), maxIterations: 2)
        #expect(result.finalText == "Still digging…")
    }

    @Test("maxIterations is floored to 1 — a 0 cap still makes exactly one send")
    func maxIterationsFloor() async throws {
        let provider = ScriptedProvider(
            [Self.toolUseTurn(callID: "c", name: "search")], loopLast: true)
        _ = try await run(provider, AIToolRegistry([ProbeTool(name: "search")]), maxIterations: 0)
        #expect(await provider.requests.count == 1)
    }

    // MARK: - Provider error propagates

    @Test("a provider error propagates (the driver throws), unlike a tool error")
    func providerThrows() async {
        let provider = ScriptedProvider([.text("never reached")], throwOnCall: 1)
        await #expect(throws: ScriptedProviderError.self) {
            try await run(provider, AIToolRegistry([]))
        }
    }

    // MARK: - Cancellation (Bug #323: a Stop must break a runaway tool loop)

    @Test("a cancelled task breaks the loop promptly instead of running to the cap")
    func cancellationBreaksLoop() async {
        // A provider that ALWAYS asks for another tool → absent a cancellation
        // check the loop would run to the (large) iteration cap, keeping the chat's
        // `isLoading` true the whole time (the Bug #323 'tool call cannot freeze the
        // chat' clause). A Stop cancels the streaming task; the driver must observe
        // it and abort.
        let provider = ScriptedProvider(
            [Self.toolUseTurn(callID: "c", name: "search")], loopLast: true)
        let registry = AIToolRegistry([ProbeTool(name: "search")])
        let driver = AgenticChatDriver(maxIterations: 200)

        let task = Task {
            try await driver.run(
                systemPrompt: "sys", history: Self.history("question"),
                registry: registry, provider: provider, maxTokens: 1024)
        }
        task.cancel()

        let result = await task.result
        switch result {
        case .failure(let error):
            #expect(error is CancellationError, "a cancelled agentic loop throws CancellationError")
        case .success:
            Issue.record("BUG #323: a cancelled agentic loop must stop, not run to the cap")
        }
        // It must NOT have run anywhere near the 200-iteration cap.
        #expect(await provider.requests.count < 5, "cancellation bounded the loop, not the cap")
    }

    @Test("a Stop during a multi-tool round aborts before the NEXT in-round tool call")
    func cancellationBreaksInRound() async {
        // One round with TWO tool calls; the first tool parks. We cancel while it's
        // parked, then release — the driver's inner cancellation check must fire
        // BEFORE the second `registry.run`, so the second tool never runs.
        let blocks: [ToolContentBlock] = [
            .toolUse(ToolCall(id: "a", name: "search", input: .object([:]))),
            .toolUse(ToolCall(id: "b", name: "search", input: .object([:]))),
        ]
        let provider = ScriptedProvider([.toolUse(blocks: blocks), .text("done")])
        let tool = GatedProbeTool(name: "search")
        let registry = AIToolRegistry([tool])
        let driver = AgenticChatDriver(maxIterations: 6)

        let task = Task {
            try await driver.run(
                systemPrompt: "sys", history: Self.history("question"),
                registry: registry, provider: provider, maxTokens: 1024)
        }

        // Wait (bounded) until the first tool call has started + parked.
        var spins = 0
        while await tool.runCount < 1, spins < 1000 {
            spins += 1
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(await tool.runCount == 1, "the first tool call started")
        task.cancel()
        await tool.release()

        let result = await task.result
        switch result {
        case .failure(let error):
            #expect(error is CancellationError, "a cancelled mid-round loop throws CancellationError")
        case .success:
            Issue.record("BUG #323: a cancelled multi-tool round must abort before the next tool call")
        }
        #expect(await tool.runCount == 1, "the second in-round tool call must NOT run after cancellation")
    }
}
