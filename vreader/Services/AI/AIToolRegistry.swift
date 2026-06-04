// Purpose: Feature #91 WI-5 (foundational) — the tool registry that the agentic
// loop (WI-7) dispatches `ToolCall`s through, plus small `JSONValue` input
// accessors the tool executors (WI-6) read their arguments with. Pure value type;
// no concrete tools yet.
//
// Key decisions:
// - The registry OWNS the call→result binding: a tool's `run(_ input:)` produces
//   content + isError, and the registry stamps `call.id` onto the returned
//   `ToolResult` (the tool doesn't know the provider-assigned call id). So an
//   executor can build a `ToolResult` with any `toolUseID` — the registry
//   overwrites it.
// - `run` NEVER throws: an unknown tool name yields an `isError` result the model
//   can route around, so a hallucinated tool name can't crash the loop.
// - Duplicate tool names are last-wins (not a trap) so registration order is safe.
//
// @coordinates-with: AITool.swift (DTOs + AITool protocol),
//   AgenticChatDriver.swift (WI-7 consumer), AnthropicProvider+ToolUse.swift /
//   OpenAICompatibleProvider+ToolUse.swift (the providers that emit ToolCalls),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-5)

import Foundation
import OSLog

/// Maps tool name → `AITool`, exposes the tool definitions for the provider
/// `tools` array, and dispatches a `ToolCall` to its tool (binding the call id).
struct AIToolRegistry: Sendable {

    private static let log = Logger(subsystem: "com.vreader.app", category: "AIToolRegistry")

    private let toolsByName: [String: any AITool]
    /// Gate-4 Medium: the tool definitions are SNAPSHOT once at registration so
    /// `definitions()` (what the provider is told) can never drift from the
    /// dispatch key in `toolsByName` — even if a conformer's `definition` is
    /// computed from mutable state.
    private let definitionsByName: [String: ToolDefinition]

    init(_ tools: [any AITool]) {
        var byName: [String: any AITool] = [:]
        var defs: [String: ToolDefinition] = [:]
        for tool in tools {
            let definition = tool.definition  // snapshot ONCE — frozen metadata.
            // Last-wins on a duplicate name (registration safe; never traps), but
            // LOG it so an accidental collision is visible during development
            // (a non-trapping warning — the "never traps" contract is load-bearing
            // for the agentic loop's robustness).
            if byName[definition.name] != nil {
                Self.log.warning(
                    "duplicate tool name '\(definition.name, privacy: .public)' — the later one wins.")
            }
            byName[definition.name] = tool
            defs[definition.name] = definition
        }
        toolsByName = byName
        definitionsByName = defs
    }

    /// Whether the registry has any tools (the loop only enables tool-use when so).
    var isEmpty: Bool { toolsByName.isEmpty }

    /// The tool definitions to send in the provider `tools` array (the frozen
    /// init-time snapshot, name-sorted for a deterministic request).
    func definitions() -> [ToolDefinition] {
        definitionsByName.keys.sorted().compactMap { definitionsByName[$0] }
    }

    /// Dispatch a `ToolCall` to its tool, binding the result to THIS call's id.
    /// An unknown tool name yields an `isError` result (never a throw).
    func run(_ call: ToolCall) async -> ToolResult {
        guard let tool = toolsByName[call.name] else {
            return ToolResult(
                toolUseID: call.id,
                content: "Unknown tool '\(call.name)'. Available: \(toolsByName.keys.sorted().joined(separator: ", ")).",
                isError: true)
        }
        let result = await tool.run(call.input)
        // The tool doesn't know the provider-assigned call id — bind it here so
        // the provider can match this result to its tool_use/tool_call.
        return ToolResult(toolUseID: call.id, content: result.content, isError: result.isError)
    }
}

// MARK: - JSONValue input accessors (WI-6 ergonomics)

extension JSONValue {
    /// Member of an `.object` by key (nil for non-objects / absent keys).
    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    /// The `.string` payload, or nil.
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// The `.number` as an `Int` when it is finite, integral, AND within the
    /// precision-safe range (`|n| < 2^53`) — beyond that a `Double` can't
    /// represent consecutive integers, so the conversion would be lossy and is
    /// rejected (nil) rather than silently truncated. Tool inputs (page indices,
    /// counts) live far below this bound.
    var intValue: Int? {
        let maxSafe = 9_007_199_254_740_992.0  // 2^53
        if case .number(let n) = self, n.isFinite, n.rounded() == n,
           abs(n) < maxSafe { return Int(n) }
        return nil
    }

    /// The `.number` as a `Double`, or nil.
    var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// The `.bool` payload, or nil.
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}
