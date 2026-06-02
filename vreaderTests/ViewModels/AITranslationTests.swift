// Purpose: Tests for AITranslationViewModel — translation state management,
// bilingual view model, language picker, caching, edge cases, and
// (feature #65 WI-3) in-flight cancellation when an overlapping
// translate request is started before the previous one settles.

import Testing
import Foundation
@testable import vreader

// MARK: - Gated provider (feature #65 WI-3)

/// The actor that backs `WI3GatedTranslationProvider` — owns the
/// per-call gate state so two overlapping translate requests can be
/// completed in a test-controlled order without `Task.sleep` and
/// without a non-async-safe lock.
private actor WI3TranslationGate {
    /// One canned response per call index (0-based). A call index with
    /// no entry throws `AIError.invalidResponse`.
    private var responses: [Int: AIResponse] = [:]
    /// Continuations parked by `sendRequest`, keyed by call index.
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    /// Call indices whose gate was released before `sendRequest` parked.
    private var preReleased: Set<Int> = []

    private(set) var callCount = 0

    func stubResponse(_ response: AIResponse, forCall index: Int) {
        responses[index] = response
    }

    /// Records a new `sendRequest` entry and returns its 0-based index.
    func registerCall() -> Int {
        let index = callCount
        callCount += 1
        return index
    }

    /// Releases the gate for `index` so its `sendRequest` returns. Safe
    /// to call before or after the call parks.
    func release(callIndex index: Int) {
        if let continuation = continuations.removeValue(forKey: index) {
            continuation.resume()
        } else {
            preReleased.insert(index)
        }
    }

    /// Suspends until the gate for `index` is released.
    func waitForRelease(callIndex index: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if preReleased.remove(index) != nil {
                continuation.resume()
            } else {
                continuations[index] = continuation
            }
        }
    }

    func response(forCall index: Int) throws -> AIResponse {
        guard let response = responses[index] else {
            throw AIError.invalidResponse
        }
        return response
    }
}

/// An `AIProvider` whose `sendRequest` suspends on a per-call gate
/// until `release(callIndex:)` is invoked, so a test can pin the order
/// in which two overlapping translate requests complete. Used to make
/// `AITranslationViewModel.translate` cancellation deterministic
/// without `Task.sleep`. Named with a `WI3` prefix to avoid colliding
/// with the unrelated single-gate `GatedAIProvider` in
/// `AISummaryTabViewTests`.
final class WI3GatedTranslationProvider: AIProvider, Sendable {
    let providerName = "WI3Gated"

    private let gate = WI3TranslationGate()

    /// The number of `sendRequest` calls observed so far.
    var sendRequestCallCount: Int {
        get async { await gate.callCount }
    }

    func stubResponse(_ response: AIResponse, forCall index: Int) async {
        await gate.stubResponse(response, forCall: index)
    }

    /// Releases the gate for the given call index so its `sendRequest`
    /// returns. Safe to call before or after the call parks.
    func release(callIndex index: Int) async {
        await gate.release(callIndex: index)
    }

    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        let index = await gate.registerCall()
        await gate.waitForRelease(callIndex: index)
        return try await gate.response(forCall: index)
    }

    func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@Suite("AITranslationViewModel")
struct AITranslationViewModelTests {

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(
        featureEnabled: Bool = true,
        hasConsent: Bool = true,
        provider: StubAIProvider? = nil
    ) -> (AITranslationViewModel, StubAIProvider) {
        let flags = FeatureFlags(environment: .prod)
        if featureEnabled {
            flags.setOverride(true, for: .aiAssistant)
        }

        let stub = provider ?? StubAIProvider()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: hasConsent),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        let vm = AITranslationViewModel(aiService: service)
        return (vm, stub)
    }

    // MARK: - Initial State

    @Test @MainActor func initialStateIsIdle() {
        let (vm, _) = makeViewModel()
        #expect(vm.originalText.isEmpty)
        #expect(vm.translatedText == nil)
        #expect(vm.targetLanguage == "Chinese")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.supportedLanguages.count >= 9)
    }

    // MARK: - Translate calls AI with target language

    @Test @MainActor func translateCallsAIWithTargetLanguage() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "这是翻译结果",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "This is the original text.",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Chinese"
        )

        #expect(stub.sendRequestCallCount == 1)
        #expect(stub.lastRequest?.actionType == .translate)
        #expect(stub.lastRequest?.targetLanguage == "Chinese")
    }

    // MARK: - Bug #314: explicit selection translated verbatim

    @Test @MainActor func translate_explicitSelection_translatesVerbatim_noWindowExtraction() async {
        // Bug #314: with an explicit selection, the request's contextText must be
        // the SELECTION verbatim — NOT a re-extracted `.section` context window.
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "译文", actionType: .translate, promptVersion: "v1", createdAt: Date())
        let (vm, _) = makeViewModel(provider: stub)

        let selection = "The sentinel word here is alpha-1."
        await vm.translate(
            originalText: selection,
            locator: WI11TestHelpers.makeLocator(),
            format: .epub,
            targetLanguage: "Chinese",
            isExplicitSelection: true
        )

        #expect(stub.lastRequest?.contextText == selection,
                "explicit selection must be sent verbatim, not a re-extracted window")
    }

    @Test @MainActor func translate_coldContext_defaultsToExtractionPath() async {
        // Default (isExplicitSelection == false) → the cold context-translate
        // path: contextText comes from the extractor (path preserved, not the
        // verbatim-selection shortcut).
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "译文", actionType: .translate, promptVersion: "v1", createdAt: Date())
        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "Section context text.",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Chinese"
        )
        #expect(stub.sendRequestCallCount == 1)
        #expect(stub.lastRequest?.contextText != nil)  // went through the extractor path
    }

    @Test @MainActor func reset_clearsHasExplicitSelection() {
        let (vm, _) = makeViewModel()
        vm.hasExplicitSelection = true
        vm.originalText = "sel"
        vm.reset()
        #expect(vm.hasExplicitSelection == false)
        #expect(vm.originalText.isEmpty)
    }

    // MARK: - Translate uses the passed language, not the property

    @Test @MainActor func translateUsesThePassedLanguageNotTheStaleProperty() async {
        // Gate-4 finding #1: `translate` must translate the language
        // PASSED to it, never whatever `targetLanguage` happens to
        // hold. Pre-set the property to a stale value (as an
        // overlapping rail tap would), then request a different
        // language: the provider must receive the passed language and
        // the property must be updated to follow the request.
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "翻訳結果",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )
        let (vm, _) = makeViewModel(provider: stub)

        vm.targetLanguage = "German"   // stale UI state from an earlier tap
        await vm.translate(
            originalText: "A passage to translate.",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Japanese"
        )

        #expect(stub.lastRequest?.targetLanguage == "Japanese",
                "The request must carry the language passed to translate, not the stale property")
        #expect(vm.targetLanguage == "Japanese",
                "translate must update the property so the rail's selection follows the request")
    }

    // MARK: - Bilingual view model shows both texts

    @Test @MainActor func bilingualViewModelShowsBothTexts() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "翻译后的文本",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "Original text for translation.",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Chinese"
        )

        #expect(vm.originalText == "Original text for translation.")
        #expect(vm.translatedText == "翻译后的文本")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Language picker sets target

    @Test @MainActor func languagePickerSetsTarget() {
        let (vm, _) = makeViewModel()

        vm.targetLanguage = "Japanese"
        #expect(vm.targetLanguage == "Japanese")

        vm.targetLanguage = "Spanish"
        #expect(vm.targetLanguage == "Spanish")
    }

    // MARK: - Translation cached for same content

    @Test @MainActor func translationCachedForSameContent() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Cached translation",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)
        let locator = WI11TestHelpers.makeLocator()

        // First call — hits provider
        await vm.translate(
            originalText: "Some text to translate.",
            locator: locator,
            format: .txt,
            targetLanguage: "Chinese"
        )
        #expect(stub.sendRequestCallCount == 1)
        #expect(vm.translatedText == "Cached translation")

        // Reset translated text to prove it's refetched from cache, not leftover
        vm.translatedText = nil
        vm.originalText = ""

        // Second call with same content + language — should use cache
        await vm.translate(
            originalText: "Some text to translate.",
            locator: locator,
            format: .txt,
            targetLanguage: "Chinese"
        )
        #expect(stub.sendRequestCallCount == 1, "Provider should not be called on cache hit")
        #expect(vm.translatedText == "Cached translation")
    }

    // MARK: - Different language produces different result

    @Test @MainActor func differentLanguageProducesDifferentResult() async {
        let stub = StubAIProvider()
        var callCount = 0
        stub.stubbedResponse = AIResponse(
            content: "Chinese translation",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)
        let locator = WI11TestHelpers.makeLocator()

        // Translate to Chinese
        await vm.translate(
            originalText: "Hello world",
            locator: locator,
            format: .txt,
            targetLanguage: "Chinese"
        )
        #expect(stub.sendRequestCallCount == 1)

        // Change to Japanese — different cache key, should call provider again
        stub.stubbedResponse = AIResponse(
            content: "Japanese translation",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        await vm.translate(
            originalText: "Hello world",
            locator: locator,
            format: .txt,
            targetLanguage: "Japanese"
        )
        #expect(stub.sendRequestCallCount == 2, "Different language should produce a new provider call")
        #expect(vm.translatedText == "Japanese translation")
    }

    // MARK: - Empty content shows error

    @Test @MainActor func emptyContentShowsError() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Should not reach",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Chinese"
        )

        #expect(vm.errorMessage != nil)
        #expect(vm.translatedText == nil)
        #expect(vm.isLoading == false)
        #expect(stub.sendRequestCallCount == 0, "Provider should not be called with empty content")
    }

    // MARK: - Error shown on failure

    @Test @MainActor func errorShownOnFailure() async {
        let stub = StubAIProvider()
        stub.stubbedError = AIError.networkError("Connection refused")

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "Text to translate",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Chinese"
        )

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("Connection refused") == true)
        #expect(vm.translatedText == nil)
        #expect(vm.isLoading == false)
    }

    // MARK: - Feature disabled shows error

    @Test @MainActor func featureDisabledShowsError() async {
        let (vm, _) = makeViewModel(featureEnabled: false)

        await vm.translate(
            originalText: "Text to translate",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Chinese"
        )

        #expect(vm.errorMessage != nil)
        #expect(vm.translatedText == nil)
    }

    // MARK: - Consent required shows error

    @Test @MainActor func consentRequiredShowsError() async {
        let (vm, _) = makeViewModel(hasConsent: false)

        await vm.translate(
            originalText: "Text to translate",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Chinese"
        )

        #expect(vm.errorMessage != nil)
        #expect(vm.translatedText == nil)
    }

    // MARK: - CJK source text works

    @Test @MainActor func cjkSourceTextTranslates() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "This is the translated text from Chinese",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)
        await vm.translate(
            originalText: "这是一段中文文本，用于测试翻译功能。",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "English"
        )

        #expect(vm.translatedText == "This is the translated text from Chinese")
        #expect(vm.originalText == "这是一段中文文本，用于测试翻译功能。")
    }

    // MARK: - Reset clears all state

    @Test @MainActor func resetClearsAllState() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Translation",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            originalText: "Some text",
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Chinese"
        )
        #expect(vm.translatedText != nil)

        vm.reset()

        #expect(vm.originalText.isEmpty)
        #expect(vm.translatedText == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.isLoading == false)
    }

    // MARK: - Supported languages list

    @Test @MainActor func supportedLanguagesContainsExpected() {
        let (vm, _) = makeViewModel()

        let expected = ["Chinese", "Japanese", "Korean", "Spanish", "French",
                        "German", "Portuguese", "Russian", "Arabic"]

        for lang in expected {
            #expect(vm.supportedLanguages.contains(lang),
                    "\(lang) should be in supported languages")
        }
    }

    // MARK: - Long content is handled (truncated by context extractor)

    @Test @MainActor func longContentHandled() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Translation of long text",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        let longContent = String(repeating: "word ", count: 2000)

        await vm.translate(
            originalText: longContent,
            locator: WI11TestHelpers.makeLocator(),
            format: .txt,
            targetLanguage: "Chinese"
        )

        #expect(vm.translatedText == "Translation of long text")
        #expect(stub.sendRequestCallCount == 1)
    }

    // MARK: - In-flight cancellation (feature #65 WI-3)

    /// Builds a view model wired to a `WI3GatedTranslationProvider` so a
    /// test can control exactly when each translate request's provider
    /// call returns.
    @MainActor
    private func makeGatedViewModel() -> (AITranslationViewModel, WI3GatedTranslationProvider) {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let gated = WI3GatedTranslationProvider()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: gated
        )
        return (AITranslationViewModel(aiService: service), gated)
    }

    @Test @MainActor func secondTranslateCancelsTheFirst() async {
        // The re-skinned Translate language rail (#65 WI-3) fires
        // `translate(...)` on every pill tap with no separate Translate
        // button. Rapid pill taps therefore overlap. Pin that starting a
        // second translate while the first is in flight cancels the
        // first: the first request's Task must be cancelled so its
        // settled result is the SECOND language's, never the first's.
        let (vm, gated) = makeGatedViewModel()
        let locator = WI11TestHelpers.makeLocator()

        await gated.stubResponse(
            AIResponse(content: "FIRST-RESULT", actionType: .translate,
                       promptVersion: "v1", createdAt: Date()),
            forCall: 0
        )
        await gated.stubResponse(
            AIResponse(content: "SECOND-RESULT", actionType: .translate,
                       promptVersion: "v1", createdAt: Date()),
            forCall: 1
        )

        // Call 1 — distinct content so it is not a cache hit of call 2.
        let first = Task { @MainActor in
            await vm.translate(
                originalText: "First passage to translate.",
                locator: locator, format: .txt,
                targetLanguage: "Chinese"
            )
        }
        // Yield so call 1 reaches the provider and parks on its gate.
        while await gated.sendRequestCallCount < 1 { await Task.yield() }

        // Call 2 — overlaps call 1. This must cancel call 1.
        let second = Task { @MainActor in
            await vm.translate(
                originalText: "Second passage to translate.",
                locator: locator, format: .txt,
                targetLanguage: "Japanese"
            )
        }
        while await gated.sendRequestCallCount < 2 { await Task.yield() }

        // Release call 2 first, then call 1's now-stale gate.
        await gated.release(callIndex: 1)
        await second.value
        await gated.release(callIndex: 0)
        await first.value

        // The settled state must reflect call 2 only.
        #expect(vm.translatedText == "SECOND-RESULT",
                "The newest translate must win; the cancelled first must not overwrite it")
        #expect(vm.originalText == "Second passage to translate.")
        #expect(vm.isLoading == false)
    }

    @Test @MainActor func cancelledTranslateLateResultDoesNotOverwrite() async {
        // A cancelled translate whose provider response arrives AFTER a
        // newer translate has already settled must NOT overwrite the
        // newer result. This is the stale-response race the Gate-2
        // audit (finding #5) flagged. Here call 1 (the cancelled one)
        // is released LAST, so its late `translatedText` write — if any
        // — would clobber call 2's. It must not.
        let (vm, gated) = makeGatedViewModel()
        let locator = WI11TestHelpers.makeLocator()

        await gated.stubResponse(
            AIResponse(content: "STALE-FIRST", actionType: .translate,
                       promptVersion: "v1", createdAt: Date()),
            forCall: 0
        )
        await gated.stubResponse(
            AIResponse(content: "FRESH-SECOND", actionType: .translate,
                       promptVersion: "v1", createdAt: Date()),
            forCall: 1
        )

        let first = Task { @MainActor in
            await vm.translate(
                originalText: "Stale first passage.",
                locator: locator, format: .txt,
                targetLanguage: "Chinese"
            )
        }
        while await gated.sendRequestCallCount < 1 { await Task.yield() }

        let second = Task { @MainActor in
            await vm.translate(
                originalText: "Fresh second passage.",
                locator: locator, format: .txt,
                targetLanguage: "Korean"
            )
        }
        while await gated.sendRequestCallCount < 2 { await Task.yield() }

        // Settle call 2 fully first.
        await gated.release(callIndex: 1)
        await second.value
        #expect(vm.translatedText == "FRESH-SECOND")

        // Now let the cancelled call 1 return its stale response. It
        // must be discarded — `translatedText` stays the fresh result.
        await gated.release(callIndex: 0)
        await first.value
        #expect(vm.translatedText == "FRESH-SECOND",
                "A cancelled translate's late response must not overwrite a newer result")
        #expect(vm.errorMessage == nil,
                "A cancelled translate must not surface an error either")
    }

    @Test @MainActor func singleTranslateStillCompletesNormally() async {
        // Regression: the cancellation machinery must not break the
        // ordinary single-request case. One `translate(...)` with no
        // overlap settles to its result exactly as before, and the call
        // remains `await`-able with settled state afterward.
        let (vm, gated) = makeGatedViewModel()

        await gated.stubResponse(
            AIResponse(content: "ONLY-RESULT", actionType: .translate,
                       promptVersion: "v1", createdAt: Date()),
            forCall: 0
        )
        // No overlap — release the gate as soon as the call parks.
        let work = Task { @MainActor in
            await vm.translate(
                originalText: "A single passage with no overlap.",
                locator: WI11TestHelpers.makeLocator(), format: .txt,
                targetLanguage: "Chinese"
            )
        }
        while await gated.sendRequestCallCount < 1 { await Task.yield() }
        await gated.release(callIndex: 0)
        await work.value

        #expect(vm.translatedText == "ONLY-RESULT")
        #expect(vm.originalText == "A single passage with no overlap.")
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        let finalCallCount = await gated.sendRequestCallCount
        #expect(finalCallCount == 1)
    }
}
