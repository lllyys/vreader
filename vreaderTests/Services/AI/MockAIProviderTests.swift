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

    // Feature #77 Gate-5b: `requestDelayNanos` holds `sendRequest` in-flight so
    // the bilingual loading shimmer is snapshottable CU-free before the
    // translation lands. Default 0 stays instant (asserted by the tests above).
    @Test func sendRequest_withRequestDelay_holdsInFlightThenReturns() async throws {
        // 80ms delay — long enough to assert a measurable floor without making
        // the suite slow. Content is unchanged (delay only affects timing).
        let provider = MockAIProvider(chunkDelayNanos: 0, requestDelayNanos: 80_000_000)
        let start = DispatchTime.now()
        let resp = try await provider.sendRequest(request(action: .translate, prompt: "床前明月光"))
        let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        #expect(elapsedNanos >= 60_000_000)        // honored the delay (margin for scheduler)
        #expect(resp.content.contains("[MOCK译]")) // still deterministic content
    }

    @Test func sendRequest_zeroRequestDelay_returnsPromptly() async throws {
        let provider = MockAIProvider(chunkDelayNanos: 0, requestDelayNanos: 0)
        let start = DispatchTime.now()
        _ = try await provider.sendRequest(request())
        let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        #expect(elapsedNanos < 50_000_000)         // no artificial hold
    }

    // Feature #77 Gate-5b / GH #1585: a multi-segment chunk-contract translate
    // prompt must get a JSON array of EXACTLY N strings so the strict decode
    // passes on the FIRST attempt (no slow per-segment fallback) — the fix that
    // lets the Foliate multi-paragraph translate→inject land.
    @Test func reply_chunkContractPrompt_returnsDecodableJSONArray() throws {
        let segments = ["第一段。", "第二段落，更长一些。", "Third paragraph."]
        let prompt = TranslationChunkContract.userPrompt(
            segments: segments, targetLanguage: "Italian", style: .natural)
        let req = request(action: .translate, prompt: prompt, context: "")
        let reply = MockAIProvider.reply(for: req)
        // The contract decoder must accept it as exactly N strings.
        let decoded = try TranslationChunkContract.decode(reply, expectedCount: segments.count)
        #expect(decoded.count == segments.count)
        #expect(decoded.allSatisfy { $0.contains("[MOCK译]") })
        // Reflects each source segment, in order.
        #expect(decoded[0].contains("第一段"))
        #expect(decoded[2].contains("Third"))
    }

    // Codex audit Medium: a source segment that itself contains a blank line
    // must NOT over-split — N headers → N array elements.
    @Test func reply_chunkContract_segmentWithInternalBlankLine_keepsCount() throws {
        let segments = ["Line one.\n\nStill segment zero.", "Segment one."]
        let prompt = TranslationChunkContract.userPrompt(
            segments: segments, targetLanguage: "German", style: .literal)
        let reply = MockAIProvider.reply(for: request(action: .translate, prompt: prompt, context: ""))
        let decoded = try TranslationChunkContract.decode(reply, expectedCount: 2)
        #expect(decoded.count == 2)
        #expect(decoded[0].contains("Line one"))
    }

    // Codex audit Low: an empty source segment still yields one array element so
    // the length equals N (decode passes).
    @Test func reply_chunkContract_emptySegment_stillEmitsElement() throws {
        let segments = ["First.", "", "Third."]
        let prompt = TranslationChunkContract.userPrompt(
            segments: segments, targetLanguage: "French", style: .natural)
        let reply = MockAIProvider.reply(for: request(action: .translate, prompt: prompt, context: ""))
        let decoded = try TranslationChunkContract.decode(reply, expectedCount: 3)
        #expect(decoded.count == 3)
        #expect(decoded.allSatisfy { $0.contains("[MOCK译]") })
    }

    @Test func reply_singleSegmentTranslate_staysSingleString() {
        // A plain (non-chunk) translate prompt keeps the single-string reply —
        // the chunk-array path only triggers on the JSON-array contract prompt.
        let r = MockAIProvider.reply(for: request(action: .translate, prompt: "床前明月光"))
        #expect(r.hasPrefix("[MOCK译]"))
        #expect(!r.hasPrefix("[\""))  // not a JSON array of strings (which begins `["`)
    }
}

#endif
