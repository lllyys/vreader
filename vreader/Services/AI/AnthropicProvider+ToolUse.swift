// Purpose: Feature #91 WI-3 — Anthropic tool-use for the agentic chat loop. Adds
// `supportsToolUse`/`sendToolRequest` (the WI-2 seam) for `AnthropicProvider`:
// assembles the `/v1/messages` body with a `tools` array + the accumulated
// multi-turn `messages` (text / tool_use / tool_result content blocks), and
// parses the response `content` blocks into an `AIToolTurn` (a `tool_use` turn
// preserves the full ordered blocks; otherwise the concatenated text).
//
// Anthropic tool-use wire format (Messages API):
//   request.tools:    [{name, description, input_schema}]
//   assistant turn:   content: [{type:text,text}, {type:tool_use,id,name,input}]
//   tool_result turn: content: [{type:tool_result,tool_use_id,content,is_error}]
//   response:         content blocks; stop_reason "tool_use" when a tool is called.
//
// All JSON values route through `JSONValue.toFoundation()` / `init(foundation:)`,
// so a tool's input/output schema crosses the boundary without `[String: Any]`
// Sendable holes and never hands a non-finite number to `JSONSerialization`.
//
// @coordinates-with: AnthropicProvider.swift, AIProvider.swift (WI-2 seam),
//   AITool.swift (DTOs), AnthropicProvider+Streaming.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-3)

import Foundation

extension AnthropicProvider {

    var supportsToolUse: Bool { true }

    /// One turn of a tool-use conversation. Sends the accumulated `messages` +
    /// the `tools`, then parses the assistant's content blocks: a `tool_use`
    /// block makes it a `.toolUse` turn (full ordered blocks preserved), else a
    /// final `.text` turn.
    ///
    /// Gate-4 High: `stop_reason` is honored — a `max_tokens` truncation is
    /// rejected as a clean retriable error rather than silently downgrading a
    /// partial trailing `tool_use` into a `.text`/dropped block.
    func sendToolRequest(_ request: AIToolRequest) async throws -> AIToolTurn {
        let urlRequest = try buildToolURLRequest(request)
        let (data, response) = try await session.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }
        return try Self.parseToolResponse(json)
    }

    /// Parse a full `/v1/messages` response body into an `AIToolTurn`, honoring
    /// `stop_reason` (Gate-4 High). Extracted from `sendToolRequest` so the
    /// stop-reason + content handling is unit-testable without a network stub.
    static func parseToolResponse(_ json: [String: Any]) throws -> AIToolTurn {
        guard let blocks = json["content"] as? [[String: Any]], !blocks.isEmpty else {
            throw AIError.invalidResponse
        }
        // A truncated turn (stop_reason "max_tokens") may carry an incomplete
        // trailing tool_use — fail loud (retriable) instead of acting on it.
        if json["stop_reason"] as? String == "max_tokens" {
            throw AIError.providerError(
                "Anthropic response truncated (stop_reason=max_tokens) — increase the token budget and retry.")
        }
        return parseToolTurn(contentBlocks: blocks)
    }

    /// Assemble the `/v1/messages` body for a tool-use turn.
    func buildToolURLRequest(_ request: AIToolRequest) throws -> URLRequest {
        // Gate-4 Medium: fail fast on a malformed tool-use history (the wire would
        // otherwise 400) — a tool_use assistant turn must be immediately followed
        // by a user turn whose content LEADS with tool_result blocks.
        try Self.validateToolHistory(request.messages)
        // Anthropic requires max_tokens >= 1; the request carries its own budget
        // but fall back to the profile's if the caller passed a non-positive value.
        let maxTok = request.maxTokens >= 1 ? request.maxTokens : maxTokens
        var urlRequest = try makeMessagesURLRequest(validatingMaxTokens: maxTok)
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTok,
            "system": request.systemPrompt,
            "messages": request.messages.map { Self.encodeMessage($0) },
        ]
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { Self.encodeTool($0) }
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: - Encode (DTO → Anthropic JSON)

    static func encodeTool(_ tool: ToolDefinition) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "input_schema": tool.inputSchema.toFoundation(),
        ]
    }

    static func encodeMessage(_ message: ToolTurnMessage) -> [String: Any] {
        [
            "role": message.role.rawValue,
            "content": message.content.map { encodeBlock($0) },
        ]
    }

    static func encodeBlock(_ block: ToolContentBlock) -> [String: Any] {
        switch block {
        case .text(let text):
            return ["type": "text", "text": text]
        case .toolUse(let call):
            return [
                "type": "tool_use",
                "id": call.id,
                "name": call.name,
                "input": call.input.toFoundation(),
            ]
        case .toolResult(let result):
            return [
                "type": "tool_result",
                "tool_use_id": result.toolUseID,
                "content": result.content,
                "is_error": result.isError,
            ]
        }
    }

    // MARK: - Parse (Anthropic JSON → AIToolTurn)

    /// Parse the response `content` blocks. If ANY `tool_use` block is present
    /// it's a `.toolUse` turn carrying the full ordered text + tool_use blocks
    /// (lossless); otherwise the concatenated `text` is the final answer.
    /// Unknown block types are ignored.
    static func parseToolTurn(contentBlocks: [[String: Any]]) -> AIToolTurn {
        var parsed: [ToolContentBlock] = []
        var hasToolUse = false
        for block in contentBlocks {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String {
                    parsed.append(.text(text))
                }
            case "tool_use":
                guard let id = block["id"] as? String,
                      let name = block["name"] as? String else { continue }
                let input = block["input"].map { JSONValue(foundation: $0) } ?? .object([:])
                parsed.append(.toolUse(ToolCall(id: id, name: name, input: input)))
                hasToolUse = true
            default:
                continue
            }
        }
        if hasToolUse {
            return .toolUse(blocks: parsed)
        }
        let text = parsed.compactMap {
            if case .text(let t) = $0 { return t } else { return nil }
        }.joined()
        return .text(text)
    }

    // MARK: - History validation (Gate-4 Medium)

    /// Validate a tool-use message history — forwards to the shared
    /// `ToolHistoryValidator` (Gate-4 WI-4: the rules are provider-agnostic, so
    /// OpenAI reuses the same validator). Kept as a forwarder so existing tests
    /// and `buildToolURLRequest` keep their call site.
    static func validateToolHistory(_ messages: [ToolTurnMessage]) throws {
        try ToolHistoryValidator.validate(messages)
    }
}
