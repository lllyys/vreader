// Purpose: Tests for AIAssistantViewModel — state machine transitions,
// error mapping, consent/feature-disabled states, cache hit behavior.

import Testing
import Foundation
@testable import vreader

@Suite("AIAssistantViewModel")
struct AIAssistantViewModelTests {

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(
        featureEnabled: Bool = true,
        hasConsent: Bool = true,
        provider: StubAIProvider? = nil
    ) -> (AIAssistantViewModel, StubAIProvider) {
        var flags = FeatureFlags(environment: .prod)
        if featureEnabled {
            flags.setOverride(.aiAssistant, value: true)
        }

        let stub = provider ?? StubAIProvider()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: hasConsent),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        let vm = AIAssistantViewModel(aiService: service)
        return (vm, stub)
    }

    // MARK: - Initial State

    @Test @MainActor func initialStateIsIdle() {
        let (vm, _) = makeViewModel()
        #expect(vm.state == .idle)
        #expect(vm.responseText.isEmpty)
        #expect(vm.currentAction == nil)
    }

    // MARK: - Feature Disabled

    @Test @MainActor func featureDisabledShowsDisabledState() async {
        let (vm, _) = makeViewModel(featureEnabled: false)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "Some text content for testing.",
            format: .txt
        )

        #expect(vm.state == .featureDisabled)
    }

    // MARK: - Consent Required

    @Test @MainActor func noConsentShowsConsentRequired() async {
        let (vm, _) = makeViewModel(hasConsent: false)

        await vm.explain(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "Some text content for testing.",
            format: .txt
        )

        #expect(vm.state == .consentRequired)
    }

    // MARK: - Successful Request

    @Test @MainActor func successfulRequestShowsComplete() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "This is a summary",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "Some text content for testing.",
            format: .txt
        )

        #expect(vm.state == .complete)
        #expect(vm.responseText == "This is a summary")
        #expect(vm.currentAction == .summarize)
    }

    // MARK: - Error State

    @Test @MainActor func providerErrorShowsError() async {
        let stub = StubAIProvider()
        stub.stubbedError = AIError.providerError("Server down")

        let (vm, _) = makeViewModel(provider: stub)

        await vm.explain(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "Some text content for testing.",
            format: .txt
        )

        if case .error(let message) = vm.state {
            #expect(message.contains("Server down"))
        } else {
            #expect(Bool(false), "Expected error state, got \(vm.state)")
        }
    }

    // MARK: - Empty Context

    @Test @MainActor func emptyTextContentShowsContextError() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Should not reach",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "", // empty!
            format: .txt
        )

        if case .error(let message) = vm.state {
            #expect(message.contains("context"))
        } else {
            #expect(Bool(false), "Expected context extraction error")
        }
        #expect(stub.sendRequestCallCount == 0, "Provider should not be called with empty context")
    }

    // MARK: - Cache Hit Shows Immediate Response

    @Test @MainActor func cacheHitShowsImmediateResponse() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Cached content",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)
        let locator = WI11TestHelpers.makeLocator()
        let text = "Some text content for testing."

        // First call populates cache
        await vm.summarize(locator: locator, textContent: text, format: .txt)
        #expect(vm.state == .complete)
        #expect(stub.sendRequestCallCount == 1)

        // Reset and call again — should hit cache
        vm.reset()
        await vm.summarize(locator: locator, textContent: text, format: .txt)
        #expect(vm.state == .complete)
        #expect(vm.responseText == "Cached content")
        #expect(stub.sendRequestCallCount == 1, "Provider should not be called on cache hit")
    }

    // MARK: - Reset

    @Test @MainActor func resetClearsState() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "response",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "Some text content for testing.",
            format: .txt
        )
        #expect(vm.state == .complete)

        vm.reset()
        #expect(vm.state == .idle)
        #expect(vm.responseText.isEmpty)
        #expect(vm.currentAction == nil)
    }

    // MARK: - Different Actions

    @Test @MainActor func translateSetsCorrectAction() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "翻译结果",
            actionType: .translate,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.translate(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "Some text content for testing.",
            format: .txt,
            targetLanguage: "Chinese"
        )

        #expect(vm.state == .complete)
        #expect(vm.currentAction == .translate)
    }

    @Test @MainActor func vocabularySetsCorrectAction() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Vocabulary list",
            actionType: .vocabulary,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.vocabulary(
            locator: WI11TestHelpers.makeLocator(),
            textContent: "Some text content for testing.",
            format: .txt
        )

        #expect(vm.state == .complete)
        #expect(vm.currentAction == .vocabulary)
    }

    @Test @MainActor func askQuestionSetsCorrectAction() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Answer to your question",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _) = makeViewModel(provider: stub)

        await vm.askQuestion(
            question: "What does this mean?",
            locator: WI11TestHelpers.makeLocator(),
            textContent: "Some text content for testing.",
            format: .txt
        )

        #expect(vm.state == .complete)
        #expect(vm.currentAction == .questionAnswer)
    }
}
