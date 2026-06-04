// Purpose: Feature #91 WI-2 — pin the `AIProvider` tool-use capability seam: a
// provider that doesn't implement tool-use inherits `supportsToolUse == false`
// and a `sendToolRequest` that throws `AIError.toolUseUnsupported` (fails closed,
// keeps the chat on the non-tool path), while a provider that overrides both
// reports support + returns its parsed turn. No real provider impl yet (WI-3/4).
//
// @coordinates-with: AIProvider.swift, AITool.swift, AIError.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-2)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #91 WI-2 — AIProvider tool-use seam")
struct AIProviderToolSeamTests {

    /// A provider that implements ONLY the base requirements — it inherits the
    /// default tool-use behavior (unsupported).
    private struct NonToolProvider: AIProvider {
        let providerName = "stub"
        func sendRequest(_ request: AIRequest) async throws -> AIResponse {
            AIResponse(content: "", actionType: .questionAnswer,
                       promptVersion: "v1", createdAt: Date(timeIntervalSince1970: 0))
        }
        func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    /// A provider that OPTS IN to tool-use by overriding both members.
    private struct ToolProvider: AIProvider {
        let providerName = "tool-stub"
        let stubbedTurn: AIToolTurn
        func sendRequest(_ request: AIRequest) async throws -> AIResponse {
            AIResponse(content: "", actionType: .questionAnswer,
                       promptVersion: "v1", createdAt: Date(timeIntervalSince1970: 0))
        }
        func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        var supportsToolUse: Bool { true }
        func sendToolRequest(_ request: AIToolRequest) async throws -> AIToolTurn {
            stubbedTurn
        }
    }

    private static let request = AIToolRequest(
        systemPrompt: "sys",
        messages: [ToolTurnMessage(role: .user, content: [.text("hi")])],
        tools: [],
        maxTokens: 1024)

    @Test("a non-overriding provider, held as any AIProvider, reports false + throws")
    func defaultIsUnsupportedThroughExistential() async {
        // Gate-4: exercise the default through the EXISTENTIAL — both members are
        // protocol REQUIREMENTS, so the extension default must dispatch via the
        // witness table even through `any AIProvider` (not the static-dispatch trap).
        let provider: any AIProvider = NonToolProvider()
        #expect(provider.supportsToolUse == false)
        await #expect(throws: AIError.toolUseUnsupported) {
            _ = try await provider.sendToolRequest(Self.request)
        }
    }

    @Test("an OVERRIDING provider, held as any AIProvider, dispatches to its impl")
    func overridingDispatchesThroughExistential() async throws {
        // The classic protocol-extension dispatch trap: if these were extension-only
        // (non-requirement) members, a `ToolProvider` held as `any AIProvider` would
        // hit the DEFAULT (false / throws). Because they're requirements, the
        // override must win even through the existential.
        let calls = [ToolCall(id: "t1", name: "search", input: .object(["q": .string("x")]))]
        let provider: any AIProvider = ToolProvider(
            stubbedTurn: .toolUse(blocks: [.toolUse(calls[0])]))
        #expect(provider.supportsToolUse == true)          // NOT the default false
        let turn = try await provider.sendToolRequest(Self.request)  // NOT a throw
        #expect(turn.toolCalls == calls)
    }

    @Test("an overriding provider can also return a final-text turn")
    func overridingProviderText() async throws {
        let provider: any AIProvider = ToolProvider(stubbedTurn: .text("done"))
        let turn = try await provider.sendToolRequest(Self.request)
        #expect(turn == .text("done"))
        #expect(turn.toolCalls.isEmpty)
    }
}
