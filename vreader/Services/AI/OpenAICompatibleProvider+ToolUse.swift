// Purpose: Feature #91 WI-4 — OpenAI-style function-calling for the agentic chat
// loop. Adds `supportsToolUse`/`sendToolRequest` (the WI-2 seam) for
// `OpenAICompatibleProvider`. OpenAI's wire shape differs from Anthropic's
// (WI-3), so this maps the shared `ToolTurnMessage` model onto it:
//
//   tools:        [{type:"function", function:{name, description, parameters}}]
//   assistant:    {role:"assistant", content:<text|null>, tool_calls:[{id, type:"function", function:{name, arguments:<JSON STRING>}}]}
//   tool result:  a SEPARATE {role:"tool", tool_call_id, content} message (NOT a content block)
//   response:     choices[0].message.tool_calls (else .content); finish_reason "tool_calls" | "stop" | "length"
//
// Key translation quirks vs Anthropic: `arguments` is a JSON STRING (encode the
// input object, parse the string back); a user turn carrying `tool_result` blocks
// expands to N `role:"tool"` messages; `finish_reason == "length"` is the
// truncation analog of Anthropic's `max_tokens` stop_reason.
//
// @coordinates-with: AIProvider.swift (OpenAICompatibleProvider + WI-2 seam),
//   AITool.swift (DTOs), AnthropicProvider+ToolUse.swift (the Anthropic sibling),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-4)

import Foundation

extension OpenAICompatibleProvider {

    var supportsToolUse: Bool { true }

    func sendToolRequest(_ request: AIToolRequest) async throws -> AIToolTurn {
        let urlRequest = try buildToolURLRequest(request)
        let (data, response) = try await session.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }
        return try Self.parseToolResponse(json)
    }

    /// Assemble the `/chat/completions` body for a tool-use turn.
    func buildToolURLRequest(_ request: AIToolRequest) throws -> URLRequest {
        // Gate-4 Medium: fail fast on a malformed tool-use history (shared with
        // the Anthropic path) — every assistant tool_call must be answered.
        try ToolHistoryValidator.validate(request.messages)
        var urlRequest = try makeChatCompletionsURLRequest()
        var messages: [[String: Any]] = [
            ["role": "system", "content": request.systemPrompt],
        ]
        for message in request.messages {
            messages.append(contentsOf: Self.encodeMessage(message))
        }
        var body: [String: Any] = ["model": model, "messages": messages]
        if request.maxTokens >= 1 {
            body["max_tokens"] = request.maxTokens
        }
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { Self.encodeTool($0) }
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: - Encode (shared DTO → OpenAI JSON)

    static func encodeTool(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.inputSchema.toFoundation(),
            ],
        ]
    }

    /// Map ONE shared `ToolTurnMessage` to one-or-more OpenAI messages — a user
    /// turn carrying `tool_result` blocks expands into separate `role:"tool"`
    /// messages (OpenAI has no tool_result-block concept).
    static func encodeMessage(_ message: ToolTurnMessage) -> [[String: Any]] {
        switch message.role {
        case .user:
            var out: [[String: Any]] = []
            // tool_result blocks → individual tool messages.
            for block in message.content {
                if case .toolResult(let result) = block {
                    out.append([
                        "role": "tool",
                        "tool_call_id": result.toolUseID,
                        "content": result.content,
                    ])
                }
            }
            // Any text blocks → one user message (rare in a tool-result turn).
            let text = message.content.compactMap {
                if case .text(let t) = $0 { return t } else { return nil }
            }.joined(separator: "\n")
            if !text.isEmpty {
                out.append(["role": "user", "content": text])
            }
            return out
        case .assistant:
            let text = message.content.compactMap {
                if case .text(let t) = $0 { return t } else { return nil }
            }.joined(separator: "\n")
            let toolCalls: [[String: Any]] = message.content.compactMap {
                guard case .toolUse(let call) = $0 else { return nil }
                return [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": encodeArguments(call.input),
                    ],
                ]
            }
            var msg: [String: Any] = ["role": "assistant"]
            // OpenAI wants content null when only tool_calls are present.
            msg["content"] = text.isEmpty ? NSNull() : text
            if !toolCalls.isEmpty {
                msg["tool_calls"] = toolCalls
            }
            return [msg]
        }
    }

    /// OpenAI `function.arguments` is a JSON STRING (not an object). Encode the
    /// input object; an empty / non-object input degrades to "{}".
    static func encodeArguments(_ input: JSONValue) -> String {
        guard input.isWellFormed,
              let data = try? JSONSerialization.data(
                withJSONObject: input.toFoundation(), options: [.fragmentsAllowed]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    // MARK: - Parse (OpenAI JSON → AIToolTurn)

    /// Parse a `/chat/completions` response into an `AIToolTurn`, honoring
    /// `finish_reason` (a `length` truncation is rejected as retriable, the
    /// analog of Anthropic's `max_tokens`).
    static func parseToolResponse(_ json: [String: Any]) throws -> AIToolTurn {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AIError.invalidResponse
        }
        if first["finish_reason"] as? String == "length" {
            throw AIError.providerError(
                "Response truncated (finish_reason=length) — increase the token budget and retry.")
        }
        // tool_calls present → parse the VALID calls first (Gate-4 Medium: don't
        // return a .toolUse turn with zero executable calls — that would wedge the
        // loop). Only commit to .toolUse if at least one valid call survives.
        if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
            var blocks: [ToolContentBlock] = []
            if let text = message["content"] as? String, !text.isEmpty {
                blocks.append(.text(text))
            }
            var validCalls = 0
            for call in toolCalls {
                guard let id = call["id"] as? String,
                      let fn = call["function"] as? [String: Any],
                      let name = fn["name"] as? String else { continue }
                let input = Self.decodeArguments(fn["arguments"] as? String)
                blocks.append(.toolUse(ToolCall(id: id, name: name, input: input)))
                validCalls += 1
            }
            if validCalls > 0 {
                return .toolUse(blocks: blocks)
            }
            // All tool_calls were malformed — fall back to any text, else fail.
            if let text = message["content"] as? String, !text.isEmpty {
                return .text(text)
            }
            throw AIError.invalidResponse
        }
        // Otherwise final text.
        let content = message["content"] as? String ?? ""
        return .text(content)
    }

    /// Parse an OpenAI `function.arguments` JSON string back into a `JSONValue`.
    /// A nil / malformed string degrades to an empty object (the loop's tool
    /// executor then reports an `isError` result for missing required fields).
    static func decodeArguments(_ arguments: String?) -> JSONValue {
        guard let arguments, let data = arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                with: data, options: [.fragmentsAllowed]) else {
            return .object([:])
        }
        return JSONValue(foundation: obj)
    }
}
