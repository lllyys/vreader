// Purpose: Bug #323 integration — `consumeStream` must drain the coalescer's
// buffered tail on EVERY exit path (normal, Stop, AND a thrown error), so the
// partial-reply contract is preserved after delta-coalescing was added.

import Testing
import Foundation
@testable import vreader

/// Yields a fixed list of chunks, then finishes by THROWING the given error
/// (after the chunks land). Lets the test stage "chunk 1 flushes, chunk 2 is
/// buffered, then the stream errors" against the real `consumeStream`.
private final class ChunkThenThrowProvider: AIProvider, @unchecked Sendable {
    let providerName = "ChunkThenThrow"
    let chunks: [String]
    let finalError: Error
    init(chunks: [String], finalError: Error) {
        self.chunks = chunks
        self.finalError = finalError
    }
    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        throw AIError.invalidResponse
    }
    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        let chunks = self.chunks
        let finalError = self.finalError
        return AsyncThrowingStream { continuation in
            for c in chunks { continuation.yield(AIStreamChunk(text: c, isComplete: false)) }
            continuation.finish(throwing: finalError)
        }
    }
}

@Suite("AIChat stream coalescing — Bug #323")
@MainActor
struct AIChatStreamCoalesceTests {

    private func makeVM(provider: AIProvider) -> AIChatViewModel {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: provider
        )
        return AIChatViewModel(aiService: service, bookFingerprint: nil, contextWindowSize: 20)
    }

    // The buffered tail (chunk 2, below the char threshold and within the time
    // window) must survive a stream that THROWS before the next flush — the
    // post-loop drain is skipped on a throw, so the catch path must drain.
    @Test func bufferedTailKeptWhenStreamThrows() async {
        let provider = ChunkThenThrowProvider(
            chunks: ["Alpha ", "Bravo"],          // both small; chunk 1 flushes, chunk 2 buffers
            finalError: AIError.invalidResponse)
        let vm = makeVM(provider: provider)

        await vm.sendMessage("hi")

        // Final assistant message keeps BOTH chunks (nothing dropped on the error).
        let assistant = vm.messages.last { $0.role == .assistant }
        #expect(assistant?.content == "Alpha Bravo")
        // It surfaced the provider error, and the composer re-enabled.
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage != nil)
    }

    // A normal (non-erroring) multi-chunk stream still assembles the full text.
    @Test func fullTextAssembledOnNormalCompletion() async {
        // A provider that yields chunks then finishes cleanly.
        final class CleanChunks: AIProvider, @unchecked Sendable {
            let providerName = "CleanChunks"
            func sendRequest(_ r: AIRequest) async throws -> AIResponse { throw AIError.invalidResponse }
            func streamRequest(_ r: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
                AsyncThrowingStream { c in
                    for s in ["The ", "quick ", "brown ", "fox"] {
                        c.yield(AIStreamChunk(text: s, isComplete: false))
                    }
                    c.yield(AIStreamChunk(text: "", isComplete: true))
                    c.finish()
                }
            }
        }
        let vm = makeVM(provider: CleanChunks())
        await vm.sendMessage("hi")
        let assistant = vm.messages.last { $0.role == .assistant }
        #expect(assistant?.content == "The quick brown fox")
        #expect(vm.isLoading == false)
    }
}
