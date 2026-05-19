// Purpose: Tests for AIAssistantViewModel's summary-scope wiring
// (feature #69 WI-4) — the selectedScope observable, setScope, and the
// scope / chapterBounds / fullText forwarded to AIContextExtracting.
// Uses a recording AIContextExtracting conformer to assert the
// extractor receives exactly what summarize(scope:) was given.

import Testing
import Foundation
@testable import vreader

@Suite("AIAssistantViewModel scope wiring")
struct AIAssistantViewModelScopeTests {

    // MARK: - Recording extractor

    /// Records the arguments of the last `extractContext` call so a test
    /// can assert what `AIAssistantViewModel` forwarded. Returns a
    /// non-empty string so the view model proceeds past the empty-context
    /// guard.
    final class RecordingExtractor: AIContextExtracting, @unchecked Sendable {
        struct Call: Sendable {
            let fullText: String
            let scope: SummaryScope
            let chapterBounds: ChapterBounds?
            let maxUTF16: Int
        }
        private let lock = NSLock()
        private var _calls: [Call] = []
        var calls: [Call] {
            lock.lock(); defer { lock.unlock() }
            return _calls
        }
        var lastCall: Call? { calls.last }

        func extractContext(
            locator: Locator, fullText: String, format: BookFormat,
            scope: SummaryScope, chapterBounds: ChapterBounds?, maxUTF16: Int
        ) -> String {
            lock.lock()
            _calls.append(Call(
                fullText: fullText, scope: scope,
                chapterBounds: chapterBounds, maxUTF16: maxUTF16
            ))
            lock.unlock()
            return "EXTRACTED-CONTEXT"
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(
        extractor: any AIContextExtracting,
        provider: StubAIProvider? = nil
    ) -> (AIAssistantViewModel, StubAIProvider) {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let stub = provider ?? StubAIProvider()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )
        let vm = AIAssistantViewModel(aiService: service, contextExtractor: extractor)
        return (vm, stub)
    }

    private func okResponse() -> AIResponse {
        AIResponse(
            content: "summary text", actionType: .summarize,
            promptVersion: "v1", createdAt: Date()
        )
    }

    // MARK: - selectedScope default + setScope

    @Test @MainActor func selectedScopeDefaultsToSection() {
        let (vm, _) = makeViewModel(extractor: RecordingExtractor())
        #expect(vm.selectedScope == .section)
    }

    @Test @MainActor func setScopeUpdatesSelectedScope() {
        let (vm, _) = makeViewModel(extractor: RecordingExtractor())
        vm.setScope(.chapter)
        #expect(vm.selectedScope == .chapter)
        vm.setScope(.bookSoFar)
        #expect(vm.selectedScope == .bookSoFar)
        vm.setScope(.section)
        #expect(vm.selectedScope == .section)
    }

    @Test @MainActor func setScopeDoesNotStartARequest() {
        // A bare setScope must not transition the state machine — the
        // user explicitly taps Summarize/Regenerate to run.
        let (vm, stub) = makeViewModel(extractor: RecordingExtractor())
        vm.setScope(.chapter)
        #expect(vm.state == .idle)
        #expect(stub.sendRequestCallCount == 0)
    }

    // MARK: - summarize forwards scope + chapterBounds + fullText

    @Test @MainActor func summarizeSectionForwardsSectionScope() async {
        let extractor = RecordingExtractor()
        let (vm, _) = makeViewModel(extractor: extractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = okResponse(); return s
        }())

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "the full flattened book text",
            format: .txt
        )

        #expect(extractor.lastCall?.scope == .section)
        #expect(extractor.lastCall?.fullText == "the full flattened book text")
        #expect(extractor.lastCall?.chapterBounds == nil)
    }

    @Test @MainActor func summarizeChapterForwardsScopeAndBounds() async {
        let extractor = RecordingExtractor()
        let (vm, _) = makeViewModel(extractor: extractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = okResponse(); return s
        }())
        let bounds = ChapterBounds(startUTF16: 100, endUTF16: 2000)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "full book text here",
            format: .txt,
            scope: .chapter,
            chapterBounds: bounds
        )

        #expect(extractor.lastCall?.scope == .chapter)
        #expect(extractor.lastCall?.chapterBounds == bounds)
        #expect(extractor.lastCall?.fullText == "full book text here")
    }

    @Test @MainActor func summarizeBookSoFarForwardsScope() async {
        let extractor = RecordingExtractor()
        let (vm, _) = makeViewModel(extractor: extractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = okResponse(); return s
        }())

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "full book text",
            format: .txt,
            scope: .bookSoFar
        )

        #expect(extractor.lastCall?.scope == .bookSoFar)
    }

    @Test @MainActor func summarizeForwardsDefaultBudget() async {
        // performAction passes AIContextBudget.defaultMaxUTF16 explicitly
        // (a protocol-requirement default argument is invisible through
        // the existential).
        let extractor = RecordingExtractor()
        let (vm, _) = makeViewModel(extractor: extractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = okResponse(); return s
        }())

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "full book text",
            format: .txt,
            scope: .chapter,
            chapterBounds: ChapterBounds(startUTF16: 0, endUTF16: 50)
        )

        #expect(extractor.lastCall?.maxUTF16 == AIContextBudget.defaultMaxUTF16)
    }

    // MARK: - summarize default scope is .section

    @Test @MainActor func summarizeDefaultsToSectionScope() async {
        // summarize with no explicit scope behaves as .section — the
        // pre-#69 behavior.
        let extractor = RecordingExtractor()
        let (vm, _) = makeViewModel(extractor: extractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = okResponse(); return s
        }())

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "full text",
            format: .txt
        )

        #expect(extractor.lastCall?.scope == .section)
    }

    // MARK: - selectedScope changes during a genuine in-flight request

    /// An AI provider whose `sendRequest` blocks until the test releases
    /// it — so a test can prove a summarize call is GENUINELY in flight
    /// (the request handler entered, then suspended) before mutating
    /// scope. `sendRequest` runs off the MainActor, so the test (which is
    /// `@MainActor`) can interleave a `setScope` call while it suspends.
    ///
    /// Two `AsyncStream`s coordinate it: the provider yields to `entered`
    /// once `sendRequest` is reached, then awaits `release`; the test
    /// awaits `entered`, mutates scope, then yields to `release`.
    final class GatedAIProvider: AIProvider, @unchecked Sendable {
        let providerName = "Gated"
        private let response: AIResponse
        private let enteredContinuation: AsyncStream<Void>.Continuation
        private let releaseStream: AsyncStream<Void>

        init(
            response: AIResponse,
            enteredContinuation: AsyncStream<Void>.Continuation,
            releaseStream: AsyncStream<Void>
        ) {
            self.response = response
            self.enteredContinuation = enteredContinuation
            self.releaseStream = releaseStream
        }

        func sendRequest(_ request: AIRequest) async throws -> AIResponse {
            enteredContinuation.yield(())        // signal: request in flight
            enteredContinuation.finish()
            var it = releaseStream.makeAsyncIterator()
            _ = await it.next()                  // block until the test releases
            return response
        }

        func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    @Test @MainActor func setScopeDuringInFlightRequestDoesNotCorruptState() async {
        let extractor = RecordingExtractor()
        let (enteredStream, enteredContinuation) = AsyncStream<Void>.makeStream()
        let (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream()

        let provider = GatedAIProvider(
            response: okResponse(),
            enteredContinuation: enteredContinuation,
            releaseStream: releaseStream
        )
        // Build the view model directly (makeViewModel takes a StubAIProvider).
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: provider
        )
        let vm = AIAssistantViewModel(aiService: service, contextExtractor: extractor)

        // Start a .section summarize; it suspends inside the gated provider.
        let summarizeTask = Task { @MainActor in
            await vm.summarize(
                locator: WI11TestHelpers.makeLocator(),
                fullText: "full text", format: .txt, scope: .section
            )
        }

        // Wait until the request is GENUINELY in flight (sendRequest entered).
        var enteredIterator = enteredStream.makeAsyncIterator()
        _ = await enteredIterator.next()

        // The request is mid-flight: state is .loading, extractor already
        // saw .section. Now flip the scope chip.
        #expect(vm.state == .loading)
        #expect(extractor.lastCall?.scope == .section)
        vm.setScope(.bookSoFar)
        #expect(vm.selectedScope == .bookSoFar)
        // No second request was spawned by the scope change.
        #expect(extractor.calls.count == 1)

        // Release the gated provider; the request completes cleanly.
        releaseContinuation.yield(())
        releaseContinuation.finish()
        await summarizeTask.value

        #expect(vm.state == .complete)
        #expect(vm.selectedScope == .bookSoFar)
        // The completed request used the ORIGINAL .section scope.
        #expect(extractor.calls.count == 1)
        #expect(extractor.lastCall?.scope == .section)
    }

    // MARK: - explain / translate / vocabulary / askQuestion unaffected (regression pins)

    @Test @MainActor func explainStillUsesSectionScope() async {
        let extractor = RecordingExtractor()
        let (vm, _) = makeViewModel(extractor: extractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = AIResponse(
                content: "explanation", actionType: .explain,
                promptVersion: "v1", createdAt: Date()
            ); return s
        }())

        await vm.explain(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "selected passage to explain",
            format: .txt
        )

        // explain is selection-driven and out of #69 scope — it still
        // extracts with .section, and its existing textContent param.
        #expect(extractor.lastCall?.scope == .section)
        #expect(extractor.lastCall?.fullText == "selected passage to explain")
        #expect(vm.currentAction == .explain)
    }

    @Test @MainActor func vocabularyStillUsesSectionScope() async {
        let extractor = RecordingExtractor()
        let (vm, _) = makeViewModel(extractor: extractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = AIResponse(
                content: "vocab", actionType: .vocabulary,
                promptVersion: "v1", createdAt: Date()
            ); return s
        }())

        await vm.vocabulary(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "passage for vocabulary",
            format: .txt
        )

        #expect(extractor.lastCall?.scope == .section)
        #expect(vm.currentAction == .vocabulary)
    }

    @Test @MainActor func translateStillUsesSectionScope() async {
        let extractor = RecordingExtractor()
        let (vm, _) = makeViewModel(extractor: extractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = AIResponse(
                content: "翻译", actionType: .translate,
                promptVersion: "v1", createdAt: Date()
            ); return s
        }())

        await vm.translate(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "passage to translate",
            format: .txt,
            targetLanguage: "Chinese"
        )

        // translate is selection-driven — still .section, still passes
        // its textContent through as fullText.
        #expect(extractor.lastCall?.scope == .section)
        #expect(extractor.lastCall?.fullText == "passage to translate")
        #expect(extractor.lastCall?.chapterBounds == nil)
        #expect(vm.currentAction == .translate)
    }

    @Test @MainActor func askQuestionStillUsesSectionScope() async {
        let extractor = RecordingExtractor()
        let (vm, _) = makeViewModel(extractor: extractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = AIResponse(
                content: "answer", actionType: .questionAnswer,
                promptVersion: "v1", createdAt: Date()
            ); return s
        }())

        await vm.askQuestion(
            question: "what does this mean?",
            locator: WI11TestHelpers.makeLocator(),
            textContent: "passage the question is about",
            format: .txt
        )

        #expect(extractor.lastCall?.scope == .section)
        #expect(extractor.lastCall?.fullText == "passage the question is about")
        #expect(extractor.lastCall?.chapterBounds == nil)
        #expect(vm.currentAction == .questionAnswer)
    }

    // MARK: - Empty fullText still produces a context error

    @Test @MainActor func summarizeEmptyFullTextShowsContextError() async {
        // The extractor returns "" for empty input; the view model maps
        // an empty context to .error — an existing path, preserved.
        let realExtractor = AIContextExtractor()
        let (vm, stub) = makeViewModel(extractor: realExtractor, provider: {
            let s = StubAIProvider(); s.stubbedResponse = okResponse(); return s
        }())

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "",
            format: .txt,
            scope: .chapter,
            chapterBounds: ChapterBounds(startUTF16: 0, endUTF16: 100)
        )

        if case .error = vm.state {} else {
            #expect(Bool(false), "empty fullText should yield .error")
        }
        #expect(stub.sendRequestCallCount == 0)
    }
}
