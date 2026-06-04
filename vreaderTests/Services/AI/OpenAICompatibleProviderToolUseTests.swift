// Purpose: Feature #91 WI-4 — pin the OpenAI-style function-calling request
// assembly + response parsing for OpenAICompatibleProvider. `buildToolURLRequest`
// is synchronous so the body is asserted by decoding its `httpBody`;
// `parseToolResponse` / `encodeArguments` / `decodeArguments` / `encodeMessage`
// are pure. Mirrors the Anthropic WI-3 tests for the (different) OpenAI wire shape.
//
// @coordinates-with: OpenAICompatibleProvider+ToolUse.swift, AITool.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-4)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #91 WI-4 — OpenAI function-calling")
struct OpenAICompatibleProviderToolUseTests {

    private func makeProvider() -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            providerName: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "k", model: "gpt-x", session: .shared)
    }

    private static let toolDef = ToolDefinition(
        name: "search_current_book",
        description: "Full-text search the open book.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object(["query": .object(["type": .string("string")])]),
        ]))

    private func decodeBody(_ req: URLRequest) throws -> [String: Any] {
        try #require(req.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
    }

    // MARK: - Capability

    @Test("OpenAICompatibleProvider supports tool use")
    func supportsToolUse() {
        #expect(makeProvider().supportsToolUse == true)
    }

    // MARK: - Request assembly

    @Test("tools serialize as OpenAI function objects (type/function.name/description/parameters)")
    func toolsAsFunctionObjects() throws {
        let req = AIToolRequest(systemPrompt: "sys",
            messages: [ToolTurnMessage(role: .user, content: [.text("find darcy")])],
            tools: [Self.toolDef], maxTokens: 1024)
        let body = try decodeBody(try makeProvider().buildToolURLRequest(req))
        #expect(body["model"] as? String == "gpt-x")
        #expect(body["max_tokens"] as? Int == 1024)
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools[0]["type"] as? String == "function")
        let fn = try #require(tools[0]["function"] as? [String: Any])
        #expect(fn["name"] as? String == "search_current_book")
        #expect(fn["description"] as? String == "Full-text search the open book.")
        #expect(fn["parameters"] is [String: Any])
        // system message is first.
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "sys")
    }

    @Test("an assistant tool_use maps to tool_calls with arguments as a JSON STRING")
    func assistantToolCallsArgumentsAreString() throws {
        let call = ToolCall(id: "call_1", name: "search",
                            input: .object(["q": .string("darcy")]))
        let req = AIToolRequest(systemPrompt: "s",
            messages: [
                ToolTurnMessage(role: .user, content: [.text("find")]),
                ToolTurnMessage(role: .assistant, content: [.text("searching"), .toolUse(call)]),
                ToolTurnMessage(role: .user, content: [
                    .toolResult(ToolResult(toolUseID: "call_1", content: "3 hits")),
                ]),
            ], tools: [Self.toolDef], maxTokens: 512)
        let body = try decodeBody(try makeProvider().buildToolURLRequest(req))
        let messages = try #require(body["messages"] as? [[String: Any]])
        // [system, user, assistant, tool]
        #expect(messages.count == 4)
        let asst = messages[2]
        #expect(asst["role"] as? String == "assistant")
        #expect(asst["content"] as? String == "searching")
        let toolCalls = try #require(asst["tool_calls"] as? [[String: Any]])
        #expect(toolCalls[0]["id"] as? String == "call_1")
        #expect(toolCalls[0]["type"] as? String == "function")
        let fn = try #require(toolCalls[0]["function"] as? [String: Any])
        #expect(fn["name"] as? String == "search")
        // arguments MUST be a JSON string, not an object.
        let argsStr = try #require(fn["arguments"] as? String)
        #expect(argsStr.contains("\"q\""))
        #expect(argsStr.contains("darcy"))
        // the tool_result user turn became a role:tool message.
        #expect(messages[3]["role"] as? String == "tool")
        #expect(messages[3]["tool_call_id"] as? String == "call_1")
        #expect(messages[3]["content"] as? String == "3 hits")
    }

    @Test("an assistant turn with only tool_calls sets content to null")
    func assistantNoTextContentNull() throws {
        let call = ToolCall(id: "c", name: "n", input: .null)
        let req = AIToolRequest(systemPrompt: "s",
            messages: [ToolTurnMessage(role: .assistant, content: [.toolUse(call)]),
                       ToolTurnMessage(role: .user, content: [.toolResult(ToolResult(toolUseID: "c", content: "r"))])],
            tools: [], maxTokens: 256)
        let body = try decodeBody(try makeProvider().buildToolURLRequest(req))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages[1]["content"] is NSNull)
    }

    @Test("Bearer auth + chat/completions endpoint")
    func headers() throws {
        let req = AIToolRequest(systemPrompt: "s",
            messages: [ToolTurnMessage(role: .user, content: [.text("hi")])],
            tools: [], maxTokens: 128)
        let urlReq = try makeProvider().buildToolURLRequest(req)
        #expect(urlReq.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        #expect(urlReq.url?.absoluteString.hasSuffix("/chat/completions") == true)
    }

    // MARK: - arguments JSON-string round-trip

    @Test("encodeArguments emits a JSON object string; decodeArguments round-trips it")
    func argumentsRoundTrip() {
        let input = JSONValue.object(["q": .string("x"), "n": .number(2)])
        let str = OpenAICompatibleProvider.encodeArguments(input)
        #expect(OpenAICompatibleProvider.decodeArguments(str) == input)
        // degenerate inputs degrade safely.
        #expect(OpenAICompatibleProvider.encodeArguments(.null) == "{}" ||
                OpenAICompatibleProvider.encodeArguments(.null) == "null")
        #expect(OpenAICompatibleProvider.decodeArguments(nil) == .object([:]))
        #expect(OpenAICompatibleProvider.decodeArguments("not json") == .object([:]))
    }

    // MARK: - Response parsing

    @Test("a tool_calls response parses to a .toolUse turn (arguments string → JSONValue)")
    func parseToolCallsResponse() throws {
        let json: [String: Any] = [
            "choices": [[
                "message": [
                    "role": "assistant", "content": NSNull(),
                    "tool_calls": [[
                        "id": "call_9", "type": "function",
                        "function": ["name": "search_current_book", "arguments": "{\"query\":\"darcy\"}"],
                    ]],
                ],
                "finish_reason": "tool_calls",
            ]],
        ]
        let turn = try OpenAICompatibleProvider.parseToolResponse(json)
        #expect(turn.toolCalls == [ToolCall(id: "call_9", name: "search_current_book",
                                            input: .object(["query": .string("darcy")]))])
    }

    @Test("a text response parses to a .text turn")
    func parseTextResponse() throws {
        let json: [String: Any] = [
            "choices": [["message": ["content": "Final answer."], "finish_reason": "stop"]],
        ]
        #expect(try OpenAICompatibleProvider.parseToolResponse(json) == .text("Final answer."))
    }

    @Test("a length-truncated response is rejected")
    func parseTruncatedThrows() {
        let json: [String: Any] = [
            "choices": [["message": ["content": "partial"], "finish_reason": "length"]],
        ]
        #expect(throws: AIError.self) { _ = try OpenAICompatibleProvider.parseToolResponse(json) }
    }

    @Test("a missing/empty choices response throws invalidResponse")
    func parseMissingChoicesThrows() {
        #expect(throws: AIError.self) { _ = try OpenAICompatibleProvider.parseToolResponse([:]) }
        #expect(throws: AIError.self) {
            _ = try OpenAICompatibleProvider.parseToolResponse(["choices": []])
        }
    }

    @Test("a malformed tool_call (missing id) is skipped")
    func parseMalformedToolCallSkipped() throws {
        let json: [String: Any] = [
            "choices": [[
                "message": [
                    "content": NSNull(),
                    "tool_calls": [
                        ["type": "function", "function": ["name": "x", "arguments": "{}"]],  // no id
                        ["id": "ok", "type": "function", "function": ["name": "y", "arguments": "{}"]],
                    ],
                ],
                "finish_reason": "tool_calls",
            ]],
        ]
        let turn = try OpenAICompatibleProvider.parseToolResponse(json)
        #expect(turn.toolCalls.map(\.id) == ["ok"])
    }

    @Test("tool_calls present but ALL malformed → fall back to text (not an empty .toolUse)")
    func allMalformedToolCallsFallBack() throws {
        // Gate-4 Medium: a .toolUse turn with zero executable calls would wedge
        // the loop — fall back to assistant text when present.
        let withText: [String: Any] = [
            "choices": [[
                "message": [
                    "content": "here is my answer",
                    "tool_calls": [["type": "function", "function": ["name": "x"]]],  // no id
                ],
                "finish_reason": "tool_calls",
            ]],
        ]
        #expect(try OpenAICompatibleProvider.parseToolResponse(withText) == .text("here is my answer"))
        // …and throw when neither a valid call nor text remains.
        let noText: [String: Any] = [
            "choices": [["message": [
                "content": NSNull(),
                "tool_calls": [["type": "function", "function": ["name": "x"]]],
            ]]],
        ]
        #expect(throws: AIError.self) { _ = try OpenAICompatibleProvider.parseToolResponse(noText) }
    }

    @Test("buildToolURLRequest validates the tool-use history (shared validator)")
    func buildValidatesHistory() {
        let call = ToolCall(id: "c", name: "n", input: .null)
        // assistant tool_use with NO answering tool_result → invalid → throws.
        let bad = AIToolRequest(systemPrompt: "s",
            messages: [ToolTurnMessage(role: .assistant, content: [.toolUse(call)])],
            tools: [], maxTokens: 256)
        #expect(throws: AIError.self) { _ = try makeProvider().buildToolURLRequest(bad) }
    }
}
