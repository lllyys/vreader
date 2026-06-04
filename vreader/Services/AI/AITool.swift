// Purpose: Feature #91 WI-1 (foundational) — the tool/function-calling DTOs for
// the agentic AI chat. Pure `Sendable` value types + the `AITool` protocol; no
// provider wiring, registry, or executors yet (those are WI-2..7).
//
// Why a dedicated `JSONValue`:
// - Tool input/output and JSON-Schema definitions are arbitrary JSON. Using
//   `[String: Any]` would open Sendable holes across the actor / @MainActor /
//   off-VM-driver boundaries the loop crosses (AIService actor → AgenticChatDriver
//   → AIChatViewModel). `JSONValue` is a `Sendable` + `Codable` + `Equatable`
//   sum type, with `toFoundation()` / `init(foundation:)` bridges applied ONLY at
//   the provider HTTP boundary (where `JSONSerialization` needs `Any`).
//
// The multi-turn carrier (`AIToolRequest` + `ToolTurnMessage` + `ToolContentBlock`)
// models the Anthropic tool-use shape (a `messages` array whose blocks are
// text / tool_use / tool_result) that WI-3 (Anthropic) and WI-4 (OpenAI) serialize
// and WI-7's `AgenticChatDriver` assembles. `AIToolTurn` is the parsed result of
// ONE provider turn: either final text, or a set of tool calls to execute.
//
// @coordinates-with: AITypes.swift, AIProvider.swift (WI-2 seam),
//   AnthropicProvider.swift (WI-3), AIToolRegistry.swift (WI-5),
//   AgenticChatDriver.swift (WI-7),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-1)

import Foundation

// MARK: - JSONValue

/// A `Sendable`, `Codable`, `Equatable` JSON value — the lingua franca for tool
/// input/output and JSON-Schema definitions, so arbitrary JSON crosses the
/// agentic loop's concurrency boundaries without `[String: Any]` Sendable holes.
indirect enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): n.isFinite ? try container.encode(n) : try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    // MARK: Validation

    /// Whether this value is well-formed JSON throughout — i.e. carries no
    /// non-finite number (NaN / ±Inf), which is NOT representable in JSON and
    /// would crash `JSONSerialization` at the provider boundary. A non-finite
    /// `.number` is coerced to `null` by `toFoundation()` / `encode(to:)` as a
    /// last line of defence; callers that build tool input from untrusted floats
    /// should prefer to check this first.
    var isWellFormed: Bool {
        switch self {
        case .number(let n): return n.isFinite
        case .object(let o): return o.values.allSatisfy { $0.isWellFormed }
        case .array(let a): return a.allSatisfy { $0.isWellFormed }
        case .string, .bool, .null: return true
        }
    }

    // MARK: Foundation bridge (provider HTTP boundary only)

    /// Convert to a Foundation `Any` (`String`/`NSNumber`/`[String: Any]`/`[Any]`/
    /// `NSNull`) for `JSONSerialization` request-body assembly. A whole-valued
    /// `.number` emits an `Int` so a JSON-Schema integer / page index doesn't
    /// serialize as `8.0`.
    func toFoundation() -> Any {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b
        case .number(let n):
            // Non-finite (NaN/±Inf) is not valid JSON and would crash
            // JSONSerialization — degrade to null (last line of defence; see
            // `isWellFormed`).
            guard n.isFinite else { return NSNull() }
            if n.rounded() == n, abs(n) < 9.007e15 { return Int(n) }
            return n
        case .object(let o): return o.mapValues { $0.toFoundation() }
        case .array(let a): return a.map { $0.toFoundation() }
        case .null: return NSNull()
        }
    }

    /// Build a `JSONValue` from a Foundation `Any` (a `JSONSerialization` output) —
    /// used to parse a provider's `tool_use` input back into the Sendable model.
    init(foundation value: Any) {
        switch value {
        case let s as String: self = .string(s)
        case let b as Bool where type(of: value) == type(of: NSNumber(value: true)):
            // Bool must be checked before NSNumber — NSNumber bridges Bool.
            self = .bool(b)
        case let n as NSNumber:
            // Distinguish a boxed Bool (objCType "c") from a numeric NSNumber.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let o as [String: Any]: self = .object(o.mapValues { JSONValue(foundation: $0) })
        case let a as [Any]: self = .array(a.map { JSONValue(foundation: $0) })
        case is NSNull: self = .null
        default: self = .null
        }
    }
}

// MARK: - Tool definition / call / result

/// A tool the model may invoke — name + human description + a JSON-Schema for the
/// input (the schema is sent to the provider's `tools` array verbatim).
struct ToolDefinition: Sendable, Equatable, Codable {
    let name: String
    let description: String
    /// JSON-Schema object describing the tool's input (e.g.
    /// `{"type":"object","properties":{...},"required":[...]}`).
    let inputSchema: JSONValue
}

/// A model-requested tool invocation parsed from one provider turn.
struct ToolCall: Sendable, Equatable, Codable {
    /// Provider-assigned id (Anthropic `tool_use.id` / OpenAI `tool_calls[].id`) —
    /// echoed back in the matching `ToolResult.toolUseID`.
    let id: String
    let name: String
    let input: JSONValue
}

/// The outcome of running a `ToolCall` — fed back to the model as a tool_result.
/// `isError` lets a tool report a recoverable failure (unknown book, unsupported
/// format, bad input) as DATA the model can route around, never a thrown error.
struct ToolResult: Sendable, Equatable, Codable {
    let toolUseID: String
    let content: String
    let isError: Bool

    init(toolUseID: String, content: String, isError: Bool = false) {
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
    }
}

/// A read-only tool the agentic loop can run. Implementors (WI-6a/6b/6c) wrap an
/// existing capability (search, book content). `run` NEVER throws — a failure is
/// an `isError` `ToolResult` so the loop continues and the model adapts.
protocol AITool: Sendable {
    var definition: ToolDefinition { get }
    func run(_ input: JSONValue) async -> ToolResult
}

// MARK: - Multi-turn carrier + parsed turn

/// One message in a tool-use conversation. Content is a list of blocks because a
/// single assistant turn can interleave text and `tool_use`, and a user turn can
/// carry multiple `tool_result`s.
struct ToolTurnMessage: Sendable, Equatable, Codable {
    enum Role: String, Sendable, Equatable, Codable {
        case user
        case assistant
    }
    let role: Role
    let content: [ToolContentBlock]
}

/// A content block within a `ToolTurnMessage`.
enum ToolContentBlock: Sendable, Equatable, Codable {
    case text(String)
    case toolUse(ToolCall)
    case toolResult(ToolResult)
}

/// A tool-use request to a provider for ONE turn of the agentic loop — the
/// accumulated multi-turn conversation + the available tools.
struct AIToolRequest: Sendable, Equatable {
    let systemPrompt: String
    let messages: [ToolTurnMessage]
    let tools: [ToolDefinition]
    let maxTokens: Int
}

/// Feature #91: shared validation of a tool-use message history — the
/// provider-agnostic `ToolTurnMessage` invariants BOTH Anthropic (WI-3) and
/// OpenAI (WI-4) require, so a malformed caller fails fast HERE instead of
/// burning a provider 400 round-trip. Throws `AIError.providerError`.
enum ToolHistoryValidator {
    static func validate(_ messages: [ToolTurnMessage]) throws {
        for (i, message) in messages.enumerated() {
            let toolUseIDs: Set<String> = Set(message.content.compactMap {
                if case .toolUse(let call) = $0 { return call.id } else { return nil }
            })
            if message.role == .assistant, !toolUseIDs.isEmpty {
                guard i + 1 < messages.count, messages[i + 1].role == .user else {
                    throw AIError.providerError(
                        "malformed tool-use history: an assistant tool_use turn must be immediately followed by a user tool_result turn.")
                }
                let next = messages[i + 1]
                guard case .toolResult = next.content.first else {
                    throw AIError.providerError(
                        "malformed tool-use history: the user turn after a tool_use must lead with tool_result blocks.")
                }
                // Every tool_use id MUST have a matching tool_result (providers
                // 400 on a missing id).
                let resultIDs: Set<String> = Set(next.content.compactMap {
                    if case .toolResult(let r) = $0 { return r.toolUseID } else { return nil }
                })
                guard toolUseIDs.isSubset(of: resultIDs) else {
                    throw AIError.providerError(
                        "malformed tool-use history: every tool_use must have a matching tool_result (missing: \(toolUseIDs.subtracting(resultIDs).sorted().joined(separator: ", "))).")
                }
            }
            // tool_result-blocks-first within any user message.
            if message.role == .user {
                var seenNonResult = false
                for block in message.content {
                    if case .toolResult = block {
                        if seenNonResult {
                            throw AIError.providerError(
                                "malformed tool-use history: tool_result blocks must come before any other block in a user message.")
                        }
                    } else {
                        seenNonResult = true
                    }
                }
            }
        }
    }
}

/// The parsed result of one provider turn: either the model produced a final
/// answer with NO tool calls, or its turn contains at least one `tool_use`.
///
/// The tool-use case preserves the FULL ordered assistant content blocks
/// (interleaved text + tool_use, ANY multiplicity / order) — Anthropic permits
/// "I'll search for X" + a tool_use, possibly several of each — so WI-7 can
/// re-append the assistant message to history losslessly (the API requires the
/// re-sent assistant turn to carry exactly those blocks) and surface any text.
/// `toolCalls` extracts the calls to run.
enum AIToolTurn: Sendable, Equatable {
    /// Final answer, no tool calls — the concatenated assistant text.
    case text(String)
    /// A turn containing ≥1 `tool_use` — the full ordered content blocks.
    case toolUse(blocks: [ToolContentBlock])

    /// The tool calls requested in a `.toolUse` turn, in order (empty for `.text`).
    var toolCalls: [ToolCall] {
        guard case .toolUse(let blocks) = self else { return [] }
        return blocks.compactMap {
            if case .toolUse(let call) = $0 { return call } else { return nil }
        }
    }

    /// The assistant text in this turn (concatenated), for surfacing/logging.
    var assistantText: String {
        switch self {
        case .text(let t): return t
        case .toolUse(let blocks):
            return blocks.compactMap {
                if case .text(let t) = $0 { return t } else { return nil }
            }.joined(separator: "\n")
        }
    }
}
