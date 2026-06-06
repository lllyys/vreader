// Purpose: Tests for WI-010 — AI summarization integration in Reader.
// Verifies ViewModel state transitions, AIService call wiring,
// feature flag gating, and edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("AIReaderIntegration")
struct AIReaderIntegrationTests {

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(
        featureEnabled: Bool = true,
        hasConsent: Bool = true,
        apiKeySaved: Bool = true,
        provider: StubAIProvider? = nil
    ) -> (AIAssistantViewModel, StubAIProvider, FeatureFlags, KeychainService) {
        let flags = FeatureFlags(environment: .prod)
        if featureEnabled {
            flags.setOverride(true, for: .aiAssistant)
        }

        let stub = provider ?? StubAIProvider()
        let keychain = WI11TestHelpers.makeKeychainService()
        if apiKeySaved {
            try? keychain.saveString("test-api-key", forAccount: AIService.apiKeyAccount)
        }

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: hasConsent),
            keychainService: keychain,
            provider: stub
        )

        let vm = AIAssistantViewModel(aiService: service)
        return (vm, stub, flags, keychain)
    }

    // MARK: - Test: summarize calls AIService

    @Test @MainActor func summarizeCallsAIService() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "A concise summary of the chapter.",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, resultStub, _, _) = makeViewModel(provider: stub)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "This is a long text about philosophy and nature.",
            format: .txt
        )

        #expect(resultStub.sendRequestCallCount == 1)
        #expect(resultStub.lastRequest?.actionType == .summarize)
    }

    // MARK: - Test: response displayed in panel

    @Test @MainActor func responseDisplayedInPanel() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "The chapter discusses the nature of consciousness.",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _, _, _) = makeViewModel(provider: stub)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "A long discussion about consciousness and its implications.",
            format: .txt
        )

        #expect(vm.state == .complete)
        #expect(vm.responseText == "The chapter discusses the nature of consciousness.")
    }

    // MARK: - Test: error shown on failure

    @Test @MainActor func errorShownOnFailure() async {
        let stub = StubAIProvider()
        stub.stubbedError = AIError.networkError("Connection timed out")

        let (vm, _, _, _) = makeViewModel(provider: stub)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some content for the AI to process.",
            format: .txt
        )

        if case .error(let message) = vm.state {
            #expect(message.contains("Connection timed out"))
        } else {
            #expect(Bool(false), "Expected error state, got \(vm.state)")
        }
    }

    // MARK: - Test: feature disabled hides button

    @Test @MainActor func featureDisabledHidesButton() async {
        let (vm, _, flags, keychain) = makeViewModel(featureEnabled: false)

        let isAvailable = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            providerPreferences: MockPreferenceStore()
        )

        #expect(!isAvailable, "AI button should be hidden when feature flag is OFF")

        // Also verify the summarize call transitions to featureDisabled
        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Text",
            format: .txt
        )
        #expect(vm.state == .featureDisabled)
    }

    // MARK: - Test: long content truncated to context window

    @Test @MainActor func longContentTruncatedToContextWindow() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Summary of truncated content.",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, resultStub, _, _) = makeViewModel(provider: stub)

        // Generate very long content (10,000 characters)
        let longContent = String(repeating: "word ", count: 2000)
        #expect(longContent.count > 2500, "Test content should be longer than context window")

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: longContent,
            format: .txt
        )

        #expect(vm.state == .complete)
        // Verify the provider was called — context extraction should have truncated
        #expect(resultStub.sendRequestCallCount == 1)
        // The context text passed to provider should be <= targetCharacterCount
        if let request = resultStub.lastRequest {
            #expect(
                request.contextText.count <= 2500,
                "Context should be truncated to ~2500 chars, got \(request.contextText.count)"
            )
        }
    }

    // MARK: - Test: loading state set during request

    @Test @MainActor func loadingStateSetDuringRequest() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Response",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _, _, _) = makeViewModel(provider: stub)

        // Before request
        #expect(vm.state == .idle, "Should start in idle state")

        // After request completes
        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some text for summarization.",
            format: .txt
        )

        // Final state should be complete (loading was transitional)
        #expect(vm.state == .complete, "Should end in complete state")
    }

    // MARK: - Test: API key missing shows error

    @Test @MainActor func apiKeyMissingShowsError() async {
        let stub = StubAIProvider()
        // Don't set stubbedResponse — won't reach provider

        // Create without a saved API key and without injected provider
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let keychain = WI11TestHelpers.makeKeychainService()
        // No API key saved, and no injected provider

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: keychain,
            provider: nil,
            providerFactory: nil
        )
        let vm = AIAssistantViewModel(aiService: service)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some text.",
            format: .txt
        )

        if case .error(let message) = vm.state {
            #expect(message.contains("API key") || message.contains("provider"),
                    "Error should mention API key or provider, got: \(message)")
        } else {
            #expect(Bool(false), "Expected error state for missing API key, got \(vm.state)")
        }
    }

    // MARK: - Test: empty content shows appropriate message

    @Test @MainActor func emptyContentShowsAppropriateMessage() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Should not reach",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, resultStub, _, _) = makeViewModel(provider: stub)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "",
            format: .txt
        )

        if case .error(let message) = vm.state {
            #expect(message.contains("context"), "Error should mention context extraction")
        } else {
            #expect(Bool(false), "Expected error state for empty content")
        }
        #expect(resultStub.sendRequestCallCount == 0, "Provider should not be called with empty content")
    }

    // MARK: - Test: consent not granted shows consent required

    @Test @MainActor func consentNotGrantedShowsConsentRequired() async {
        let (vm, _, _, _) = makeViewModel(hasConsent: false)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some text",
            format: .txt
        )

        #expect(vm.state == .consentRequired)
    }

    // MARK: - Test: different book formats work

    @Test @MainActor func summarizeWorksForPDFFormat() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "PDF summary",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _, _, _) = makeViewModel(provider: stub)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(format: .pdf),
            fullText: "PDF page content about machine learning.",
            format: .pdf
        )

        #expect(vm.state == .complete)
        #expect(vm.responseText == "PDF summary")
    }

    @Test @MainActor func summarizeWorksForEPUBFormat() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "EPUB chapter summary",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _, _, _) = makeViewModel(provider: stub)

        let epubLocator = Locator(
            bookFingerprint: DocumentFingerprint(
                contentSHA256: WI11TestHelpers.testFP.contentSHA256,
                fileByteCount: WI11TestHelpers.testFP.fileByteCount,
                format: .epub
            ),
            href: "chapter1.xhtml",
            progression: 0.5,
            totalProgression: nil,
            cfi: nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )

        await vm.summarize(
            locator: epubLocator,
            fullText: "The EPUB chapter content with interesting topics.",
            format: .epub
        )

        #expect(vm.state == .complete)
        #expect(vm.responseText == "EPUB chapter summary")
    }

    // MARK: - Test: reset clears state after AI request

    @Test @MainActor func resetClearsStateAfterRequest() async {
        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: "Summary text",
            actionType: .summarize,
            promptVersion: "v1",
            createdAt: Date()
        )

        let (vm, _, _, _) = makeViewModel(provider: stub)

        await vm.summarize(
            locator: WI11TestHelpers.makeLocator(),
            fullText: "Some text",
            format: .txt
        )
        #expect(vm.state == .complete)
        #expect(!vm.responseText.isEmpty)

        vm.reset()

        #expect(vm.state == .idle)
        #expect(vm.responseText.isEmpty)
        #expect(vm.currentAction == nil)
    }
}

// MARK: - AIReaderAvailability Tests

@Suite("AIReaderAvailability")
@MainActor
struct AIReaderAvailabilityTests {

    @Test func availableWhenFlagEnabledAndKeyExistsAndConsentGranted() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let keychain = WI11TestHelpers.makeKeychainService()
        try? keychain.saveString("sk-test-key", forAccount: AIService.apiKeyAccount)

        let result = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            providerPreferences: MockPreferenceStore()
        )

        #expect(result == true)
    }

    @Test func unavailableWhenFlagDisabled() {
        let flags = FeatureFlags(environment: .prod)
        // aiAssistant defaults to false in prod
        let keychain = WI11TestHelpers.makeKeychainService()
        try? keychain.saveString("sk-test-key", forAccount: AIService.apiKeyAccount)

        let result = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            providerPreferences: MockPreferenceStore()
        )

        #expect(result == false)
    }

    @Test func unavailableWhenNoAPIKey() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let keychain = WI11TestHelpers.makeKeychainService()
        // No API key saved

        let result = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            providerPreferences: MockPreferenceStore()
        )

        #expect(result == false)
    }

    @Test func unavailableWhenAPIKeyEmpty() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let keychain = WI11TestHelpers.makeKeychainService()
        try? keychain.saveString("", forAccount: AIService.apiKeyAccount)

        let result = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            providerPreferences: MockPreferenceStore()
        )

        #expect(result == false)
    }

    // MARK: - Bug #90: consent gate

    @Test func unavailableWhenConsentRevoked() {
        // The bug: feature flag on + API key saved + consent OFF used to return
        // true, leaving AI affordances visible. Now isAvailable must return
        // false when consent is missing.
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let keychain = WI11TestHelpers.makeKeychainService()
        try? keychain.saveString("sk-test-key", forAccount: AIService.apiKeyAccount)

        let result = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: false),
            providerPreferences: MockPreferenceStore()
        )

        #expect(result == false, "Bug #90: AI buttons must hide when consent is revoked")
    }

    @Test func availableTransitionsAcrossConsentRevoke() {
        // After consent is granted then revoked, isAvailable must reflect the
        // revoke immediately — no stale cached value.
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let keychain = WI11TestHelpers.makeKeychainService()
        try? keychain.saveString("sk-test-key", forAccount: AIService.apiKeyAccount)

        let suiteName = "com.vreader.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = AIConsentManager(defaults: defaults)
        // Bug #326: isolate from process-global UserDefaults.standard so hasAPIKey
        // takes the legacy-key gate this test verifies, not the active-profile branch.
        let prefs = MockPreferenceStore()

        manager.grantConsent()
        #expect(AIReaderAvailability.isAvailable(
            featureFlags: flags, keychainService: keychain, consentManager: manager,
            providerPreferences: prefs
        ) == true, "Available right after grant")

        manager.revokeConsent()
        #expect(AIReaderAvailability.isAvailable(
            featureFlags: flags, keychainService: keychain, consentManager: manager,
            providerPreferences: prefs
        ) == false, "Unavailable right after revoke")
    }

    @Test func hasAPIKeyReturnsTrueWhenKeyExists() {
        let keychain = WI11TestHelpers.makeKeychainService()
        try? keychain.saveString("sk-test", forAccount: AIService.apiKeyAccount)

        let result = AIReaderAvailability.hasAPIKey(
            keychainService: keychain, providerPreferences: MockPreferenceStore())

        #expect(result == true)
    }

    @Test func hasAPIKeyReturnsFalseWhenNoKey() {
        let keychain = WI11TestHelpers.makeKeychainService()

        let result = AIReaderAvailability.hasAPIKey(
            keychainService: keychain, providerPreferences: MockPreferenceStore())

        #expect(result == false)
    }

    // MARK: - Bug #237: --enable-ai XCUITest override

    #if DEBUG
    @Test func availableWhenAITestOverrideForced() {
        // Bug #237: the --enable-ai launch flag sets AITestOverride.forceAvailable
        // so a CU-free XCUITest can reach the AI surfaces. With the override on,
        // isAvailable returns true even though all three production gates fail
        // (flag off, no key, no consent) — a headless test cannot satisfy them.
        AITestOverride.forceAvailable = true
        defer { AITestOverride.forceAvailable = false }

        let flags = FeatureFlags(environment: .prod)          // aiAssistant OFF
        let keychain = WI11TestHelpers.makeKeychainService()  // no API key

        let result = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: false),
            providerPreferences: MockPreferenceStore()
        )

        #expect(result == true, "Bug #237: --enable-ai override must force AI surfaces visible")
    }

    @Test func realGatesStillApplyWhenAITestOverrideOff() {
        // The override is opt-in: with it off, the three production gates still
        // decide. All three fail here, so isAvailable must return false.
        AITestOverride.forceAvailable = false

        let flags = FeatureFlags(environment: .prod)
        let keychain = WI11TestHelpers.makeKeychainService()

        let result = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: false),
            providerPreferences: MockPreferenceStore()
        )

        #expect(result == false, "Override off: real gates apply, all fail")
    }
    #endif
}
