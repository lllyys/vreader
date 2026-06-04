// Purpose: Feature #91 WI-3 — pin the Anthropic tool-use request assembly +
// response parsing. `buildToolURLRequest` is synchronous (no network) so the body
// shape is asserted by decoding its `httpBody`; `parseToolTurn` is a pure function
// over the response `content` blocks. Mirrors `AnthropicProviderTests`' body/parse
// pins without needing the URLSession stub.
//
// @coordinates-with: AnthropicProvider+ToolUse.swift, AITool.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-3)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #91 WI-3 — Anthropic tool-use")
struct AnthropicProviderToolUseTests {

    private func makeProvider() -> AnthropicProvider {
        AnthropicProvider(
            providerName: "Anthropic",
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "k", model: "claude-x", maxTokens: 2048, session: .shared)
    }

    private static let toolDef = ToolDefinition(
        name: "search_current_book",
        description: "Full-text search the open book.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object(["query": .object(["type": .string("string")])]),
            "required": .array([.string("query")]),
        ]))

    private func decodeBody(_ req: URLRequest) throws -> [String: Any] {
        try #require(req.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
    }

    // MARK: - Capability

    @Test("AnthropicProvider supports tool use")
    func supportsToolUse() {
        #expect(makeProvider().supportsToolUse == true)
    }

    // MARK: - Request assembly

    @Test("the tool-use body carries the tools array (name/description/input_schema)")
    func bodyCarriesTools() throws {
        let req = AIToolRequest(
            systemPrompt: "sys",
            messages: [ToolTurnMessage(role: .user, content: [.text("find darcy")])],
            tools: [Self.toolDef], maxTokens: 1024)
        let body = try decodeBody(try makeProvider().buildToolURLRequest(req))
        #expect(body["model"] as? String == "claude-x")
        #expect(body["max_tokens"] as? Int == 1024)
        #expect(body["system"] as? String == "sys")
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["name"] as? String == "search_current_book")
        #expect(tools[0]["description"] as? String == "Full-text search the open book.")
        #expect(tools[0]["input_schema"] is [String: Any])  // JSON-Schema object survives
    }

    @Test("an empty tools list omits the tools key entirely")
    func emptyToolsOmitsKey() throws {
        let req = AIToolRequest(
            systemPrompt: "s", messages: [ToolTurnMessage(role: .user, content: [.text("hi")])],
            tools: [], maxTokens: 512)
        let body = try decodeBody(try makeProvider().buildToolURLRequest(req))
        #expect(body["tools"] == nil)
    }

    @Test("multi-turn messages serialize text / tool_use / tool_result content blocks")
    func messagesSerializeContentBlocks() throws {
        let call = ToolCall(id: "tu_1", name: "search", input: .object(["q": .string("x")]))
        let req = AIToolRequest(
            systemPrompt: "s",
            messages: [
                ToolTurnMessage(role: .user, content: [.text("find x")]),
                ToolTurnMessage(role: .assistant, content: [.text("searching"), .toolUse(call)]),
                ToolTurnMessage(role: .user, content: [
                    .toolResult(ToolResult(toolUseID: "tu_1", content: "3 hits", isError: false)),
                ]),
            ], tools: [Self.toolDef], maxTokens: 1024)
        let body = try decodeBody(try makeProvider().buildToolURLRequest(req))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
        // assistant turn: a text block + a tool_use block (id/name/input).
        let asst = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(asst[0]["type"] as? String == "text")
        #expect(asst[1]["type"] as? String == "tool_use")
        #expect(asst[1]["id"] as? String == "tu_1")
        #expect(asst[1]["name"] as? String == "search")
        #expect(asst[1]["input"] is [String: Any])
        // tool_result turn keys.
        let toolMsg = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(toolMsg[0]["type"] as? String == "tool_result")
        #expect(toolMsg[0]["tool_use_id"] as? String == "tu_1")
        #expect(toolMsg[0]["content"] as? String == "3 hits")
        #expect(toolMsg[0]["is_error"] as? Bool == false)
    }

    @Test("the request carries the Anthropic auth + version headers")
    func headers() throws {
        let req = AIToolRequest(systemPrompt: "s",
            messages: [ToolTurnMessage(role: .user, content: [.text("hi")])],
            tools: [], maxTokens: 256)
        let urlReq = try makeProvider().buildToolURLRequest(req)
        #expect(urlReq.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(urlReq.value(forHTTPHeaderField: "anthropic-version") == AnthropicProvider.anthropicVersionHeader)
        #expect(urlReq.url?.absoluteString.hasSuffix("/v1/messages") == true)
    }

    // MARK: - Response parsing

    @Test("a tool_use response parses to a .toolUse turn preserving ordered blocks")
    func parseToolUseResponse() {
        let blocks: [[String: Any]] = [
            ["type": "text", "text": "I'll search."],
            ["type": "tool_use", "id": "toolu_9", "name": "search_current_book",
             "input": ["query": "darcy"]],
        ]
        let turn = AnthropicProvider.parseToolTurn(contentBlocks: blocks)
        #expect(turn.toolCalls == [ToolCall(id: "toolu_9", name: "search_current_book",
                                            input: .object(["query": .string("darcy")]))])
        #expect(turn.assistantText == "I'll search.")
    }

    @Test("a text-only response parses to a concatenated .text turn")
    func parseTextResponse() {
        let turn = AnthropicProvider.parseToolTurn(contentBlocks: [
            ["type": "text", "text": "Final "],
            ["type": "text", "text": "answer."],
        ])
        #expect(turn == .text("Final answer."))
        #expect(turn.toolCalls.isEmpty)
    }

    @Test("a malformed tool_use (missing id) is skipped, not crashed")
    func parseMalformedToolUseSkipped() {
        let turn = AnthropicProvider.parseToolTurn(contentBlocks: [
            ["type": "tool_use", "name": "x"],           // no id → skipped
            ["type": "text", "text": "ok"],
            ["type": "future_block_kind", "data": 1],    // unknown type → ignored
        ])
        // No valid tool_use survived → falls back to text.
        #expect(turn == .text("ok"))
    }

    @Test("a tool_use with no input defaults to an empty object")
    func parseToolUseNoInput() {
        let turn = AnthropicProvider.parseToolTurn(contentBlocks: [
            ["type": "tool_use", "id": "t", "name": "noargs"],
        ])
        #expect(turn.toolCalls == [ToolCall(id: "t", name: "noargs", input: .object([:]))])
    }

    // MARK: - Gate-4 High: stop_reason

    @Test("a max_tokens-truncated response is rejected (not silently downgraded)")
    func truncatedResponseThrows() {
        let json: [String: Any] = [
            "content": [["type": "text", "text": "partial"]],
            "stop_reason": "max_tokens",
        ]
        #expect(throws: AIError.self) { _ = try AnthropicProvider.parseToolResponse(json) }
    }

    @Test("a normal stop_reason parses through to the turn")
    func normalStopReasonParses() throws {
        let toolJSON: [String: Any] = [
            "content": [["type": "tool_use", "id": "t", "name": "search", "input": ["q": "x"]]],
            "stop_reason": "tool_use",
        ]
        let turn = try AnthropicProvider.parseToolResponse(toolJSON)
        #expect(turn.toolCalls.first?.name == "search")
        let textJSON: [String: Any] = [
            "content": [["type": "text", "text": "done"]], "stop_reason": "end_turn"]
        #expect(try AnthropicProvider.parseToolResponse(textJSON) == .text("done"))
    }

    @Test("an empty / missing content response throws invalidResponse")
    func emptyContentThrows() {
        #expect(throws: AIError.self) { _ = try AnthropicProvider.parseToolResponse(["content": []]) }
        #expect(throws: AIError.self) { _ = try AnthropicProvider.parseToolResponse([:]) }
    }

    // MARK: - Gate-4 Medium: history validation

    @Test("a valid tool-use history passes validation")
    func validHistoryPasses() throws {
        let call = ToolCall(id: "t1", name: "s", input: .null)
        try AnthropicProvider.validateToolHistory([
            ToolTurnMessage(role: .user, content: [.text("q")]),
            ToolTurnMessage(role: .assistant, content: [.text("ok"), .toolUse(call)]),
            ToolTurnMessage(role: .user, content: [
                .toolResult(ToolResult(toolUseID: "t1", content: "r")),
            ]),
        ])
    }

    @Test("an assistant tool_use turn NOT followed by a user tool_result throws")
    func toolUseNotFollowedThrows() {
        let call = ToolCall(id: "t1", name: "s", input: .null)
        #expect(throws: AIError.self) {
            try AnthropicProvider.validateToolHistory([
                ToolTurnMessage(role: .assistant, content: [.toolUse(call)]),
                // no following user tool_result turn
            ])
        }
        #expect(throws: AIError.self) {
            try AnthropicProvider.validateToolHistory([
                ToolTurnMessage(role: .assistant, content: [.toolUse(call)]),
                ToolTurnMessage(role: .user, content: [.text("not a tool_result first")]),
            ])
        }
    }

    @Test("an assistant tool_use whose id has no matching tool_result throws")
    func missingToolResultIDThrows() {
        let c1 = ToolCall(id: "t1", name: "s", input: .null)
        let c2 = ToolCall(id: "t2", name: "f", input: .null)
        #expect(throws: AIError.self) {
            try AnthropicProvider.validateToolHistory([
                ToolTurnMessage(role: .assistant, content: [.toolUse(c1), .toolUse(c2)]),
                // only t1 answered — t2's tool_use id is missing a result → 400
                ToolTurnMessage(role: .user, content: [
                    .toolResult(ToolResult(toolUseID: "t1", content: "r")),
                ]),
            ])
        }
        // both answered → passes
        #expect(throws: Never.self) {
            try AnthropicProvider.validateToolHistory([
                ToolTurnMessage(role: .assistant, content: [.toolUse(c1), .toolUse(c2)]),
                ToolTurnMessage(role: .user, content: [
                    .toolResult(ToolResult(toolUseID: "t1", content: "r1")),
                    .toolResult(ToolResult(toolUseID: "t2", content: "r2")),
                ]),
            ])
        }
    }

    @Test("a user message with a non-tool_result block before a tool_result throws")
    func toolResultNotFirstThrows() {
        #expect(throws: AIError.self) {
            try AnthropicProvider.validateToolHistory([
                ToolTurnMessage(role: .user, content: [
                    .text("preamble"),
                    .toolResult(ToolResult(toolUseID: "t1", content: "r")),
                ]),
            ])
        }
    }

    // MARK: - Gate-4 Low: effective per-request max_tokens validation

    @Test("a per-request max_tokens override is validated (not the bad profile value)")
    func effectiveMaxTokensValidated() throws {
        // Profile maxTokens=0 (bad) but the request carries a valid 1024 — must
        // NOT throw, and the body emits 1024.
        let provider = AnthropicProvider(
            providerName: "Anthropic", baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "k", model: "m", maxTokens: 0, session: .shared)
        let req = AIToolRequest(systemPrompt: "s",
            messages: [ToolTurnMessage(role: .user, content: [.text("hi")])],
            tools: [], maxTokens: 1024)
        let body = try decodeBody(try provider.buildToolURLRequest(req))
        #expect(body["max_tokens"] as? Int == 1024)
    }
}
