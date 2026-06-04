// Purpose: Feature #91 WI-5 — pin the AIToolRegistry dispatch contract (call→tool,
// id-binding, unknown-tool error, definitions order) + the JSONValue input
// accessors the WI-6 executors read arguments with. Pure-value tests.
//
// @coordinates-with: AIToolRegistry.swift, AITool.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-5)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #91 WI-5 — AIToolRegistry")
struct AIToolRegistryTests {

    /// A stub tool that echoes its input (or errors) — and ignores the toolUseID
    /// it sets (the registry must rebind it to the call id).
    private struct EchoTool: AITool {
        let name: String
        let fail: Bool
        var definition: ToolDefinition {
            ToolDefinition(name: name, description: "echo \(name)", inputSchema: .object([:]))
        }
        func run(_ input: JSONValue) async -> ToolResult {
            // Deliberately set a WRONG toolUseID — the registry must overwrite it.
            ToolResult(toolUseID: "WRONG", content: input.stringValue ?? "ran:\(name)", isError: fail)
        }
    }

    @Test("run dispatches to the named tool and binds the call id (not the tool's)")
    func dispatchBindsCallID() async {
        let registry = AIToolRegistry([EchoTool(name: "a", fail: false)])
        let result = await registry.run(
            ToolCall(id: "call_42", name: "a", input: .string("hi")))
        #expect(result.toolUseID == "call_42")   // rebound from the call, NOT "WRONG"
        #expect(result.content == "hi")
        #expect(result.isError == false)
    }

    @Test("a tool that reports failure surfaces isError, still bound to the call id")
    func failingToolIsError() async {
        let registry = AIToolRegistry([EchoTool(name: "a", fail: true)])
        let result = await registry.run(ToolCall(id: "c", name: "a", input: .null))
        #expect(result.isError == true)
        #expect(result.toolUseID == "c")
    }

    @Test("an unknown tool name yields an isError result, never a crash")
    func unknownToolIsError() async {
        let registry = AIToolRegistry([EchoTool(name: "a", fail: false)])
        let result = await registry.run(ToolCall(id: "c", name: "nope", input: .null))
        #expect(result.isError == true)
        #expect(result.toolUseID == "c")
        #expect(result.content.contains("Unknown tool 'nope'"))
    }

    @Test("definitions() returns every tool's definition, name-sorted + isEmpty")
    func definitionsAndEmpty() {
        #expect(AIToolRegistry([]).isEmpty)
        let registry = AIToolRegistry([
            EchoTool(name: "zebra", fail: false), EchoTool(name: "alpha", fail: false)])
        #expect(registry.isEmpty == false)
        #expect(registry.definitions().map(\.name) == ["alpha", "zebra"])
    }

    @Test("duplicate tool names are last-wins (registration is never a trap)")
    func duplicateNamesLastWins() async {
        // Two tools named "dup" — the SECOND wins; no crash.
        let registry = AIToolRegistry([
            EchoTool(name: "dup", fail: false), EchoTool(name: "dup", fail: true)])
        #expect(registry.definitions().count == 1)
        let result = await registry.run(ToolCall(id: "c", name: "dup", input: .null))
        #expect(result.isError == true)   // the last (failing) tool won
    }

    // MARK: - JSONValue accessors

    @Test("JSONValue object subscript + typed accessors")
    func jsonAccessors() {
        let v = JSONValue.object([
            "q": .string("darcy"), "page": .number(2), "ratio": .number(0.5),
            "flag": .bool(true), "nested": .object(["k": .string("x")]),
        ])
        #expect(v["q"]?.stringValue == "darcy")
        #expect(v["page"]?.intValue == 2)
        #expect(v["page"]?.doubleValue == 2)
        #expect(v["ratio"]?.intValue == nil)         // non-integral → not an Int
        #expect(v["ratio"]?.doubleValue == 0.5)
        #expect(v["flag"]?.boolValue == true)
        #expect(v["nested"]?["k"]?.stringValue == "x")
        #expect(v["absent"] == nil)
        // subscript on a non-object is nil.
        #expect(JSONValue.string("s")["q"] == nil)
        // a non-finite number is not an Int/Double-as-int.
        #expect(JSONValue.number(.nan).intValue == nil)
    }

    @Test("intValue is precision-safe: rejects integers beyond 2^53 (lossy)")
    func intValuePrecisionBoundary() {
        // 2^53 - 1 is the largest exactly-representable consecutive integer.
        #expect(JSONValue.number(9_007_199_254_740_991).intValue == 9_007_199_254_740_991)
        // 2^53 and beyond are NOT exactly representable as Double → rejected (nil)
        // rather than silently truncated.
        #expect(JSONValue.number(9_007_199_254_740_992).intValue == nil)
        #expect(JSONValue.number(-9_007_199_254_740_992).intValue == nil)
        #expect(JSONValue.number(.infinity).intValue == nil)
    }
}
