// Purpose: Tests for the DEBUG MockAIProvider — deterministic, request-reflecting
// replies + a real streaming shape (delayed chunks, terminal complete).

#if DEBUG

import Testing
import Foundation
@testable import vreader

@Suite("MockAIProvider")
struct MockAIProviderTests {

    private func request(
        action: AIActionType = .questionAnswer,
        prompt: String? = "What is this about?",
        context: String = "Some assembled scope context."
    ) -> AIRequest {
        AIRequest(
            actionType: action, bookFingerprint: nil, locator: nil,
            contextText: context, userPrompt: prompt, targetLanguage: nil,
            promptVersion: "v1"
        )
    }

    @Test func sendRequest_isDeterministicAndReflectsTheRequest() async throws {
        let provider = MockAIProvider(chunkDelayNanos: 0)
        let resp = try await provider.sendRequest(request())
        #expect(resp.content.contains("[MOCK]"))
        #expect(resp.content.contains("What is this about?"))
        #expect(resp.actionType == .questionAnswer)
        // Deterministic: same request → identical content.
        let again = try await provider.sendRequest(request())
        #expect(resp.content == again.content)
    }

    @Test func streamRequest_emitsIncrementalChunksThenTerminalComplete() async throws {
        let provider = MockAIProvider(chunkDelayNanos: 0)
        var assembled = ""
        var sawComplete = false
        var chunkCount = 0
        for try await chunk in provider.streamRequest(request()) {
            chunkCount += 1
            assembled += chunk.text
            if chunk.isComplete { sawComplete = true }
        }
        #expect(sawComplete)
        #expect(chunkCount > 1)                 // streamed, not one shot
        #expect(assembled.contains("[MOCK]"))
        #expect(assembled.contains("Drew on"))  // citation-style context reflection
    }

    @Test func reply_translateActionProducesInterlinearMarker() {
        let r = MockAIProvider.reply(for: request(action: .translate, prompt: "床前明月光"))
        #expect(r.contains("[MOCK译]"))
        #expect(r.contains("床前明月光"))
    }

    @Test func reply_summarizeActionReportsContextSize() {
        let r = MockAIProvider.reply(for: request(action: .summarize, prompt: nil, context: "abcde"))
        #expect(r.contains("[MOCK]"))
        #expect(r.contains("5 chars"))
    }
}

#endif
