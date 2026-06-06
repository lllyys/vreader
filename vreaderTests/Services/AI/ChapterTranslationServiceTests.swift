// Purpose: Tests for ChapterTranslationService — translates one chapter unit
// for feature #56 bilingual reading: cache batch-read → chunk → sendRequest
// → strict JSON decode + per-segment fallback → cache-write.
//
// @coordinates-with: ChapterTranslationService.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-6)

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("ChapterTranslationService")
struct ChapterTranslationServiceTests {

    private static let profileID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!

    private static func makeConfig(model: String = "gpt-test") -> ResolvedAIProviderConfig {
        ResolvedAIProviderConfig(
            kind: .openAICompatible,
            baseURL: URL(string: "https://api.test.example.com")!,
            apiKey: "sk-test", model: model, maxTokens: 4096)
    }

    private static func makeStore() throws -> ChapterTranslationStore {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ChapterTranslationStore(modelContainer: container)
    }

    private static func unit() -> TranslationUnitID {
        TranslationUnitID(kind: .epubHref, value: "OEBPS/ch1.xhtml")
    }

    /// A controllable AI seam: returns canned responses per call, records
    /// every request, and can be made to throw. An `actor` — `Sendable` by
    /// construction, and its serialized state needs no manual lock (`NSLock`
    /// is unavailable in async contexts under Swift 6).
    actor MockTranslationSender: TranslationRequestSending {
        private var responses: [String]
        private(set) var requests: [AIRequest] = []
        private var errorToThrow: Error?

        init(responses: [String]) { self.responses = responses }

        func setErrorToThrow(_ error: Error?) { self.errorToThrow = error }

        var requestCount: Int { requests.count }

        func sendTranslationRequest(
            _ request: AIRequest, using config: ResolvedAIProviderConfig
        ) async throws -> AIResponse {
            requests.append(request)
            if let errorToThrow { throw errorToThrow }
            let next = responses.isEmpty ? "[]" : responses.removeFirst()
            return AIResponse(
                content: next, actionType: .translate, promptVersion: "v1", createdAt: Date())
        }
    }

    private func makeService(
        sender: MockTranslationSender, store: ChapterTranslationStore
    ) -> ChapterTranslationService {
        ChapterTranslationService(sender: sender, store: store, promptVersion: "v1")
    }

    // MARK: - Cache hit

    @Test func cacheHit_returnsCachedSegmentsWithoutAnAPICall() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        // Seed the cache for this exact lookup key.
        let key = ChapterTranslationRecord.lookupKey(
            bookFingerprintKey: "fp", unitStorageKey: Self.unit().storageKey,
            targetLanguage: "Chinese", providerProfileID: Self.profileID, promptVersion: "v1")
        try await store.upsert(ChapterTranslationRecord(
            bookFingerprintKey: "fp", unitStorageKey: Self.unit().storageKey,
            targetLanguage: "Chinese", providerProfileID: Self.profileID, promptVersion: "v1",
            translatedSegments: ["缓存译文"], sourceParagraphCount: 1))
        _ = key

        let sender = MockTranslationSender(responses: [])
        let service = makeService(sender: sender, store: store)
        let result = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: "Some paragraph.", targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)

        #expect(result.fromCache == true)
        #expect(result.segments == ["缓存译文"])
        #expect(await sender.requestCount == 0)
    }

    // MARK: - Cache miss

    @Test func cacheMiss_callsAPIOnceAndWritesBack() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        // One paragraph → one chunk → one well-formed JSON response.
        let sender = MockTranslationSender(responses: [#"["你好世界"]"#])
        let service = makeService(sender: sender, store: store)

        let result = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: "Hello world.", targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)

        #expect(result.fromCache == false)
        #expect(result.segments == ["你好世界"])
        #expect(await sender.requestCount == 1)

        // Written to the cache — a second translate is a hit.
        let second = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: "Hello world.", targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)
        #expect(second.fromCache == true)
        #expect(second.segments == ["你好世界"])
    }

    @Test func multiParagraph_decodesArrayInOrder() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let source = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let sender = MockTranslationSender(responses: [#"["第一段","第二段","第三段"]"#])
        let service = makeService(sender: sender, store: store)

        let result = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: source, targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)
        #expect(result.segments == ["第一段", "第二段", "第三段"])
    }

    // MARK: - JSON-array decode fallback

    @Test func malformedArray_fallsBackToPerSegmentRequests() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let source = "Para one.\n\nPara two."
        // First (whole-chunk) response is garbage → fallback issues 2
        // per-segment requests, each returning a 1-element array.
        let sender = MockTranslationSender(responses: [
            "this is not json",       // chunk attempt — fails decode
            #"["译一"]"#,              // per-segment 0
            #"["译二"]"#,              // per-segment 1
        ])
        let service = makeService(sender: sender, store: store)

        let result = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: source, targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)
        #expect(result.segments == ["译一", "译二"])
        // 1 failed chunk attempt + 2 per-segment retries.
        #expect(await sender.requestCount == 3)
    }

    @Test func countMismatch_fallsBackToPerSegmentRequests() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let source = "A.\n\nB.\n\nC."
        // Chunk returns 2 elements for 3 segments → count mismatch → fallback.
        let sender = MockTranslationSender(responses: [
            #"["only","two"]"#,
            #"["译A"]"#, #"["译B"]"#, #"["译C"]"#,
        ])
        let service = makeService(sender: sender, store: store)
        let result = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: source, targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)
        #expect(result.segments == ["译A", "译B", "译C"])
    }

    @Test func nonStringElement_fallsBackToPerSegmentRequests() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let sender = MockTranslationSender(responses: [
            #"["ok", 42]"#,           // numeric element → not a string array
            #"["译X"]"#, #"["译Y"]"#,
        ])
        let service = makeService(sender: sender, store: store)
        let result = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: "X.\n\nY.", targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)
        #expect(result.segments == ["译X", "译Y"])
    }

    // MARK: - Style folds into the prompt

    @Test func styleAppearsInTheChunkPrompt() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let sender = MockTranslationSender(responses: [#"["译"]"#])
        let service = makeService(sender: sender, store: store)
        _ = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: "Text.", targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .literary)
        let prompt = await sender.requests.first?.userPrompt ?? ""
        #expect(prompt.lowercased().contains("literary"))
    }

    // MARK: - Provider error

    @Test func providerError_throwsProviderFailed() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let sender = MockTranslationSender(responses: [])
        await sender.setErrorToThrow(ChapterTranslationError.providerFailed("network down"))
        let service = makeService(sender: sender, store: store)

        await #expect(throws: ChapterTranslationError.providerFailed("network down")) {
            _ = try await service.translate(
                bookFingerprintKey: "fp", unit: Self.unit(),
                sourceText: "Text.", targetLanguage: "Chinese",
                providerProfileID: Self.profileID, config: config, style: .natural)
        }
    }

    @Test func offlineURLError_throwsOfflineNotProviderFailed() async throws {
        // A URLError.notConnectedToInternet maps to .offline so the caller
        // can render source-only (edge case (c)) rather than show an error.
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let sender = MockTranslationSender(responses: [])
        await sender.setErrorToThrow(URLError(.notConnectedToInternet))
        let service = makeService(sender: sender, store: store)

        await #expect(throws: ChapterTranslationError.offline) {
            _ = try await service.translate(
                bookFingerprintKey: "fp", unit: Self.unit(),
                sourceText: "Text.", targetLanguage: "Chinese",
                providerProfileID: Self.profileID, config: config, style: .natural)
        }
    }

    @Test func aiNetworkError_mapsToProviderFailedNotOffline() async throws {
        // AIError.networkError is a catch-all (also thrown for invalid
        // responses / misconfigured URLs) — it must NOT map to .offline, which
        // would mis-drive the source-only fallback on a provider/config fault.
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let sender = MockTranslationSender(responses: [])
        await sender.setErrorToThrow(AIError.networkError("connection lost"))
        let service = makeService(sender: sender, store: store)
        await #expect(throws: ChapterTranslationError.self) {
            _ = try await service.translate(
                bookFingerprintKey: "fp", unit: Self.unit(),
                sourceText: "Text.", targetLanguage: "Chinese",
                providerProfileID: Self.profileID, config: config, style: .natural)
        }
        // It is .providerFailed, NOT .offline.
        do {
            _ = try await service.translate(
                bookFingerprintKey: "fp", unit: Self.unit(),
                sourceText: "Text.", targetLanguage: "Chinese",
                providerProfileID: Self.profileID, config: config, style: .natural)
            Issue.record("expected a throw")
        } catch let error as ChapterTranslationError {
            #expect(error != .offline)
            if case .providerFailed = error {} else {
                Issue.record("expected .providerFailed, got \(error)")
            }
        }
    }

    // MARK: - Stale cache

    @Test func staleCacheRow_isBypassedAndReTranslated() async throws {
        // A cached row whose sourceParagraphCount no longer matches the live
        // chapter (the chapter's source changed) must be treated as STALE:
        // dropped, re-translated, not served.
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        // Seed a row claiming 1 source paragraph...
        try await store.upsert(ChapterTranslationRecord(
            bookFingerprintKey: "fp", unitStorageKey: Self.unit().storageKey,
            targetLanguage: "Chinese", providerProfileID: Self.profileID, promptVersion: "v1",
            translatedSegments: ["旧译文"], sourceParagraphCount: 1))

        // ...but the live source now has 2 paragraphs.
        let sender = MockTranslationSender(responses: [#"["新一","新二"]"#])
        let service = makeService(sender: sender, store: store)
        let result = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: "Para one.\n\nPara two.", targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)

        #expect(result.fromCache == false)              // stale row not served
        #expect(result.segments == ["新一", "新二"])     // re-translated
        #expect(await sender.requestCount == 1)
    }

    @Test func freshCacheRow_withMatchingCount_isServed() async throws {
        // The counterpart: a row whose count DOES match is a hit.
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        try await store.upsert(ChapterTranslationRecord(
            bookFingerprintKey: "fp", unitStorageKey: Self.unit().storageKey,
            targetLanguage: "Chinese", providerProfileID: Self.profileID, promptVersion: "v1",
            translatedSegments: ["译一", "译二"], sourceParagraphCount: 2))
        let sender = MockTranslationSender(responses: [])
        let service = makeService(sender: sender, store: store)
        let result = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: "Para one.\n\nPara two.", targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)
        #expect(result.fromCache == true)
        #expect(await sender.requestCount == 0)
    }

    // MARK: - Cancellation

    @Test func cancelledTask_throwsTypedCancelled() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let sender = MockTranslationSender(responses: [#"["译"]"#])
        let service = makeService(sender: sender, store: store)

        // A pre-cancelled task: the first Task.checkCancellation() between
        // chunks throws CancellationError, which the service surfaces as the
        // typed ChapterTranslationError.cancelled.
        let task = Task {
            try await service.translate(
                bookFingerprintKey: "fp", unit: Self.unit(),
                sourceText: "Para one.\n\nPara two.\n\nPara three.", targetLanguage: "Chinese",
                providerProfileID: Self.profileID, config: config, style: .natural)
        }
        task.cancel()
        await #expect(throws: ChapterTranslationError.cancelled) {
            _ = try await task.value
        }
    }

    // MARK: - Empty source

    @Test func emptySourceText_returnsNoSegmentsWithoutAnAPICall() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        let sender = MockTranslationSender(responses: [])
        let service = makeService(sender: sender, store: store)
        let result = try await service.translate(
            bookFingerprintKey: "fp", unit: Self.unit(),
            sourceText: "   \n\n  ", targetLanguage: "Chinese",
            providerProfileID: Self.profileID, config: config, style: .natural)
        #expect(result.segments.isEmpty)
        #expect(await sender.requestCount == 0)
    }

    // MARK: - translatePreSegmented (Bug #268 — block-text-direct translation)

    @Test func translatePreSegmented_translatesGivenSegments1to1_andDoesNotCache() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        // Two source segments → one chunk → one 2-element JSON-array response.
        // Two responses queued for the two calls below.
        let sender = MockTranslationSender(responses: [#"["译一","译二"]"#, #"["译一","译二"]"#])
        let service = makeService(sender: sender, store: store)

        let result = try await service.translatePreSegmented(
            segments: ["Para one.", "Para two."],
            targetLanguage: "Chinese", config: config, style: .natural)
        #expect(result.count == 2)            // 1:1 with input, by construction
        #expect(result == ["译一", "译二"])
        #expect(await sender.requestCount == 1)

        // No disk cache — a second identical call re-translates (sender hit again).
        _ = try await service.translatePreSegmented(
            segments: ["Para one.", "Para two."],
            targetLanguage: "Chinese", config: config, style: .natural)
        #expect(await sender.requestCount == 2)
    }

    @Test func translatePreSegmented_emptyInput_returnsEmpty_withNoRequest() async throws {
        let store = try Self.makeStore()
        let sender = MockTranslationSender(responses: [])
        let service = makeService(sender: sender, store: store)
        let result = try await service.translatePreSegmented(
            segments: [], targetLanguage: "Chinese", config: Self.makeConfig(), style: .natural)
        #expect(result.isEmpty)
        #expect(await sender.requestCount == 0)
    }

    @Test func translatePreSegmented_malformedChunkDecode_fallsBackPerSegment_stays1to1() async throws {
        let store = try Self.makeStore()
        let config = Self.makeConfig()
        // Whole-chunk response is malformed (not a 2-element array) → translateChunk
        // falls back to one request per segment; the result must still be 1:1.
        let sender = MockTranslationSender(responses: [
            "not-a-json-array",   // whole-chunk decode fails
            #"["译一"]"#,          // per-segment fallback #1
            #"["译二"]"#,          // per-segment fallback #2
        ])
        let service = makeService(sender: sender, store: store)
        let result = try await service.translatePreSegmented(
            segments: ["One.", "Two."], targetLanguage: "Chinese", config: config, style: .natural)
        #expect(result.count == 2)   // 1:1 preserved through the per-segment fallback
        #expect(result == ["译一", "译二"])
        #expect(await sender.requestCount == 3)  // 1 whole-chunk attempt + 2 per-segment
    }

    // MARK: - Bug #320 — sanitized provider failure message (no raw Swift dump)

    @Test func sanitizedProviderMessage_AIError_usesErrorDescription_notRawDump() {
        // A provider HTTP error must surface as the sanitized `errorDescription`
        // (the same path the Chat/Summarize/Translate tabs use), NOT
        // `String(describing:)` — which stringifies to `providerError("HTTP 400:
        // {…raw JSON…}")` (enum-case syntax + raw blob, reading as a crash).
        let raw = AIError.providerError("HTTP 400: {\"error\":\"bad request\"}")
        let message = ChapterTranslationService.sanitizedProviderMessage(raw)
        #expect(message == raw.errorDescription)
        #expect(!message.contains("providerError("))      // no enum-case syntax
        #expect(message.hasPrefix("AI provider error:"))   // the sanitized prefix
    }

    @Test func sanitizedProviderMessage_genericError_usesLocalizedDescription() {
        struct Boom: Error {}
        let error: Error = Boom()
        let message = ChapterTranslationService.sanitizedProviderMessage(error)
        #expect(message == error.localizedDescription)
        #expect(message != String(describing: error))      // never the raw dump
    }
}
