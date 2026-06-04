// Purpose: Feature #91 WI-1 — pin the agentic tool-calling DTOs: the `JSONValue`
// Codable round-trip + Foundation bridge (the load-bearing Sendable JSON type),
// and the tool definition / call / result / content-block / multi-turn carrier
// value semantics. Pure-value tests, no provider/registry/loop yet.
//
// @coordinates-with: AITool.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-1)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #91 WI-1 — agentic tool DTOs")
struct AIToolDTOTests {

    // MARK: - JSONValue Codable

    /// A mixed object exercising every case (wrapped in an object so the
    /// top-level JSON is never a bare fragment). CJK string included.
    private static let sample = JSONValue.object([
        "s": .string("héllo 世界 — quote ' and \" ok"),
        "whole": .number(8),
        "frac": .number(8.5),
        "neg": .number(-3),
        "b": .bool(true),
        "nada": .null,
        "arr": .array([.number(1), .string("x"), .bool(false), .null]),
        "nested": .object(["k": .string("v"), "deep": .array([.object(["z": .number(0)])])]),
    ])

    @Test("JSONValue round-trips through JSONEncoder/JSONDecoder")
    func jsonValueCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Self.sample)
        let back = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(back == Self.sample)
    }

    @Test("a whole-valued number bridges to Int (the load-bearing toFoundation path)")
    func wholeNumberBridgesToInt() throws {
        // Gate-4 Low: exercise toFoundation() (used for provider JSONSerialization
        // body assembly), not just JSONEncoder. Round-trip the bridged object
        // through JSONSerialization to prove the integer emission survives.
        #expect(JSONValue.number(8).toFoundation() as? Int == 8)
        #expect(JSONValue.number(8.5).toFoundation() as? Double == 8.5)
        let bridged = JSONValue.object(["n": .number(8), "f": .number(2.5)]).toFoundation()
        let data = try JSONSerialization.data(withJSONObject: bridged)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"n\":8") && !json.contains("8.0"))
        #expect(json.contains("\"f\":2.5"))
    }

    @Test("non-finite numbers (NaN/Inf) are rejected as malformed and coerced to null")
    func nonFiniteIsWellFormedAndCoerced() throws {
        // Gate-4 Medium: NaN/±Inf are not valid JSON and would crash
        // JSONSerialization — `isWellFormed` flags them; the boundaries coerce to null.
        #expect(JSONValue.number(.nan).isWellFormed == false)
        #expect(JSONValue.object(["x": .number(.infinity)]).isWellFormed == false)
        #expect(Self.sample.isWellFormed == true)
        #expect(JSONValue.number(.nan).toFoundation() is NSNull)
        // toFoundation must not produce a value JSONSerialization rejects.
        let bridged = JSONValue.object(["bad": .number(.infinity)]).toFoundation()
        #expect(throws: Never.self) { _ = try JSONSerialization.data(withJSONObject: bridged) }
    }

    // MARK: - Foundation bridge

    @Test("toFoundation → init(foundation:) round-trips the value")
    func foundationBridgeRoundTrip() {
        let foundation = Self.sample.toFoundation()
        let back = JSONValue(foundation: foundation)
        #expect(back == Self.sample)
    }

    @Test("toFoundation distinguishes Bool from a numeric NSNumber")
    func foundationBoolVsNumber() {
        // A boxed Bool must come back as .bool, NOT .number(1) — the classic
        // NSNumber/Bool bridging trap.
        #expect(JSONValue(foundation: NSNumber(value: true)) == .bool(true))
        #expect(JSONValue(foundation: NSNumber(value: 1)) == .number(1))
        // And the forward direction emits the right Foundation type.
        #expect(JSONValue.bool(true).toFoundation() as? Bool == true)
        #expect(JSONValue.number(8).toFoundation() as? Int == 8)
        #expect(JSONValue.number(8.5).toFoundation() as? Double == 8.5)
        #expect(JSONValue.null.toFoundation() is NSNull)
    }

    @Test("a JSONSerialization parse feeds init(foundation:) cleanly")
    func foundationFromJSONSerialization() throws {
        let raw = #"{"query":"darcy","page":2,"flag":true,"items":["a","b"],"x":null}"#
        let obj = try JSONSerialization.jsonObject(with: Data(raw.utf8))
        let v = JSONValue(foundation: obj)
        #expect(v == .object([
            "query": .string("darcy"),
            "page": .number(2),
            "flag": .bool(true),
            "items": .array([.string("a"), .string("b")]),
            "x": .null,
        ]))
    }

    // MARK: - Tool DTOs

    @Test("ToolResult defaults isError to false")
    func toolResultDefaultsNotError() {
        let r = ToolResult(toolUseID: "t1", content: "ok")
        #expect(r.isError == false)
        #expect(ToolResult(toolUseID: "t2", content: "bad", isError: true).isError)
    }

    @Test("ToolDefinition with a JSON-Schema inputSchema round-trips (Codable)")
    func toolDefinitionRoundTrip() throws {
        let def = ToolDefinition(
            name: "search_current_book",
            description: "Full-text search the open book.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["query": .object(["type": .string("string")])]),
                "required": .array([.string("query")]),
            ]))
        let back = try JSONDecoder().decode(
            ToolDefinition.self, from: try JSONEncoder().encode(def))
        #expect(back == def)
    }

    @Test("ToolCall + ToolContentBlock value semantics + Codable")
    func toolCallAndContentBlocks() throws {
        let call = ToolCall(id: "tu_1", name: "get_book_content",
                            input: .object(["bookId": .string("k"), "range": .number(0)]))
        #expect(call == ToolCall(id: "tu_1", name: "get_book_content",
                                 input: .object(["bookId": .string("k"), "range": .number(0)])))
        // Each content-block kind round-trips through Codable.
        let blocks: [ToolContentBlock] = [
            .text("hello"),
            .toolUse(call),
            .toolResult(ToolResult(toolUseID: "tu_1", content: "…", isError: false)),
        ]
        let back = try JSONDecoder().decode(
            [ToolContentBlock].self, from: try JSONEncoder().encode(blocks))
        #expect(back == blocks)
    }

    @Test("AIToolTurn preserves the FULL ordered blocks of a tool-use turn (lossless)")
    func toolTurnCases() {
        #expect(AIToolTurn.text("done") == .text("done"))
        #expect(AIToolTurn.text("done").toolCalls.isEmpty)

        // Gate-4 Medium (round 2): a tool-use turn keeps multiple text blocks AND
        // multiple tool_use blocks in their original order — not just one preamble.
        let c1 = ToolCall(id: "a", name: "search", input: .object(["q": .string("x")]))
        let c2 = ToolCall(id: "b", name: "fetch", input: .null)
        let turn = AIToolTurn.toolUse(blocks: [
            .text("Let me look that up."),
            .toolUse(c1),
            .text("and also fetch this:"),
            .toolUse(c2),
        ])
        // Both calls extracted, in order.
        #expect(turn.toolCalls == [c1, c2])
        // Both text blocks preserved + concatenated.
        #expect(turn.assistantText == "Let me look that up.\nand also fetch this:")
        // Equality is over the full ordered block list (order matters).
        #expect(turn == .toolUse(blocks: [
            .text("Let me look that up."), .toolUse(c1),
            .text("and also fetch this:"), .toolUse(c2),
        ]))
        #expect(turn != .toolUse(blocks: [.toolUse(c1), .toolUse(c2)]))  // dropped text → not equal
        #expect(AIToolTurn.text("x") != turn)
    }
}
