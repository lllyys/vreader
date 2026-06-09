// Purpose: DEBUG-only deterministic AIProvider for CU-free verification of the
// AI request pipeline WITHOUT a real provider API key (which an automated /
// headless verification run cannot enter — see AGENTS.md prohibited actions).
//
// Why it exists: AI surfaces (Chat answer + "Drew on" citations #86, bilingual
// translate #85, multi-turn chat hang repro #323) need a provider that actually
// returns content to exercise the end-observable pipeline. A real provider needs
// a key; a synchronous unit stub returns INSTANTLY and so can't surface
// timing-dependent multi-turn bugs. This provider streams a deterministic reply
// over several chunks WITH small delays, so it drives the REAL async streaming +
// session-lane + relocate path the production providers do — the same boundaries
// Bug #323's turn-2 hang lives at — just with canned, assertable content.
//
// Activated by the `--mock-ai` launch flag (AITestSetup → AITestOverride.
// mockProvider); AIService.resolveProvider / providerInstance return it ahead of
// any real profile resolution, so no provider profile or key is required.
//
// @coordinates-with: AIService.swift (resolveProvider / providerInstance inject
//   this ahead of profile resolution), AIReaderAvailability.swift
//   (AITestOverride.mockProvider seam), AITestSetup.swift (--mock-ai wiring).
// DEBUG-only.

#if DEBUG

import Foundation

/// Deterministic, key-free AIProvider for verification. Streams a canned reply
/// that REFLECTS the request (action + prompt + context length) so the rendered
/// answer is assertable, over delayed chunks so the real async streaming path is
/// exercised (not an instant stub).
final class MockAIProvider: AIProvider {

    /// Per-chunk delay. Small but non-zero so multi-turn / cancel / lane timing
    /// is exercised the way a real over-the-wire stream would be.
    private let chunkDelayNanos: UInt64

    /// Whole-request delay applied to the non-streaming `sendRequest` path
    /// (bilingual translate uses `sendRequest`, not `streamRequest`). Default 0
    /// keeps the instant deterministic behavior existing AI verification relies
    /// on. Feature #77 Gate-5b sets this (via `--mock-ai-translate-delay-ms`) so
    /// the bilingual translate stays IN-FLIGHT long enough for a CU-free snapshot
    /// to catch the loading shimmer before the translation lands and clears it.
    private let requestDelayNanos: UInt64

    init(chunkDelayNanos: UInt64 = 20_000_000, // 20ms/chunk
         requestDelayNanos: UInt64 = 0) {
        self.chunkDelayNanos = chunkDelayNanos
        self.requestDelayNanos = requestDelayNanos
    }

    var providerName: String { "MockAIProvider" }

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        if requestDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: requestDelayNanos)
        }
        return AIResponse(
            content: Self.reply(for: request),
            actionType: request.actionType,
            promptVersion: request.promptVersion,
            createdAt: Date()
        )
    }

    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        let reply = Self.reply(for: request)
        let delay = chunkDelayNanos
        return AsyncThrowingStream { continuation in
            let task = Task {
                // Split into word chunks so the consumer sees incremental growth.
                let pieces = reply.split(separator: " ", omittingEmptySubsequences: false)
                for piece in pieces {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: delay)
                    continuation.yield(AIStreamChunk(text: String(piece) + " ", isComplete: false))
                }
                continuation.yield(AIStreamChunk(text: "", isComplete: true))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Deterministic, request-reflecting reply. Marked `[MOCK]` so verification
    /// can assert the mock path ran (and never confuse it with a real answer).
    static func reply(for request: AIRequest) -> String {
        let prompt = request.userPrompt ?? ""
        switch request.actionType {
        case .translate:
            // Bilingual (#85) asserts an interlinear translation rendered.
            return "[MOCK译] \(prompt.isEmpty ? request.contextText.prefix(40) : prompt.prefix(40))"
        case .summarize:
            return "[MOCK] Summary of \(request.contextText.count) chars of context."
        default:
            return "[MOCK] Re: \(prompt). Drew on \(request.contextText.count) chars of context."
        }
    }
}

#endif
