// Purpose: Tests for WI-013 — General AI Chat Interface.
// Verifies general chat mode (nil bookFingerprint), book chat mode distinction,
// and that the entry point requirements are met.

import Testing
import Foundation
@testable import vreader

@Suite("AIChatGeneralMode")
struct AIChatGeneralTests {

    // MARK: - Helpers

    @MainActor
    private func makeSUT(
        featureEnabled: Bool = true,
        hasConsent: Bool = true,
        bookFingerprint: DocumentFingerprint? = nil
    ) -> (AIChatViewModel, StubChatAIProvider) {
        let flags = FeatureFlags(environment: .prod)
        if featureEnabled {
            flags.setOverride(true, for: .aiAssistant)
        }

        let stub = StubChatAIProvider()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: hasConsent),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        let vm = AIChatViewModel(
            aiService: service,
            bookFingerprint: bookFingerprint
        )
        return (vm, stub)
    }

    // MARK: - General Chat Has No Book Context

    @Test @MainActor func generalChatHasNoBookContext() async {
        let (vm, stub) = makeSUT(bookFingerprint: nil)
        stub.stubbedResponse = AIResponse(
            content: "General answer",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        await vm.sendMessage("What is the meaning of life?")

        #expect(vm.bookFingerprint == nil, "General chat should have nil bookFingerprint")
        #expect(stub.streamRequestCallCount == 1)
        if let request = stub.lastRequest {
            #expect(request.bookFingerprint == nil, "Request should not include book context")
        }
    }

    // MARK: - Book Chat Still Includes Context

    @Test @MainActor func bookChatStillIncludesContext() async {
        let fp = DocumentFingerprint(
            contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            fileByteCount: 2048,
            format: .epub
        )

        let (vm, stub) = makeSUT(bookFingerprint: fp)
        stub.stubbedResponse = AIResponse(
            content: "About your book...",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        await vm.sendMessage("Summarize chapter 1")

        #expect(vm.bookFingerprint != nil, "Book chat should have non-nil bookFingerprint")
        #expect(vm.bookFingerprint == fp)
        if let request = stub.lastRequest {
            #expect(request.bookFingerprint == fp, "Request should include book fingerprint")
        }
    }

    // MARK: - Switch Between Book And General

    @Test @MainActor func switchBetweenBookAndGeneral() async {
        let fp = DocumentFingerprint(
            contentSHA256: "bbccddee11223344bbccddee11223344bbccddee11223344bbccddee11223344",
            fileByteCount: 4096,
            format: .pdf
        )

        // General mode instance
        let (generalVM, generalStub) = makeSUT(bookFingerprint: nil)
        generalStub.stubbedResponse = AIResponse(
            content: "General response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        // Book mode instance
        let (bookVM, bookStub) = makeSUT(bookFingerprint: fp)
        bookStub.stubbedResponse = AIResponse(
            content: "Book response",
            actionType: .questionAnswer,
            promptVersion: "v1",
            createdAt: Date()
        )

        // Use general
        await generalVM.sendMessage("General question")
        #expect(generalVM.messages.count == 2)
        #expect(generalStub.lastRequest?.bookFingerprint == nil)

        // Use book
        await bookVM.sendMessage("Book question")
        #expect(bookVM.messages.count == 2)
        #expect(bookStub.lastRequest?.bookFingerprint == fp)

        // Verify they are independent — general VM unaffected
        #expect(generalVM.messages.count == 2, "General VM should still have exactly 2 messages")
        #expect(generalVM.messages[0].content == "General question")
    }

    // MARK: - General Chat Accessible From Library

    @Test @MainActor func generalChatAccessibleFromLibrary() {
        // Verify the LibraryView exposes AI chat availability check.
        // The availability function must return true when feature + API key + consent are set.
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let keychain = WI11TestHelpers.makeKeychainService()
        try? keychain.saveString("test-api-key", forAccount: AIService.apiKeyAccount)

        let available = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            providerPreferences: MockPreferenceStore()
        )
        #expect(available, "AI chat should be available when flag is on, API key is set, and consent is granted")
    }

    // MARK: - Feature Flag Off Hides Chat

    @Test @MainActor func featureFlagOffHidesChat() {
        let flags = FeatureFlags(environment: .prod)
        // aiAssistant defaults to false in prod, no override set

        let keychain = WI11TestHelpers.makeKeychainService()
        try? keychain.saveString("test-api-key", forAccount: AIService.apiKeyAccount)

        let available = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            providerPreferences: MockPreferenceStore()
        )
        #expect(!available, "AI chat should be hidden when feature flag is OFF")
    }

    // MARK: - No API Key Hides Chat

    @Test @MainActor func noAPIKeyHidesChat() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let keychain = WI11TestHelpers.makeKeychainService()
        // No API key saved

        let available = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            providerPreferences: MockPreferenceStore()
        )
        #expect(!available, "AI chat should be hidden when no API key is set")
    }

    // MARK: - Consent Off Hides Chat (bug #90)

    @Test @MainActor func consentOffHidesChat() {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let keychain = WI11TestHelpers.makeKeychainService()
        try? keychain.saveString("test-api-key", forAccount: AIService.apiKeyAccount)

        let available = AIReaderAvailability.isAvailable(
            featureFlags: flags,
            keychainService: keychain,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: false),
            providerPreferences: MockPreferenceStore()
        )
        #expect(!available, "Bug #90: AI chat must hide when user consent is revoked")
    }

    // MARK: - General Chat Title

    @Test @MainActor func generalChatViewModelHasNilFingerprint() {
        let (vm, _) = makeSUT(bookFingerprint: nil)
        #expect(vm.bookFingerprint == nil, "General chat VM should have nil bookFingerprint for title logic")
    }

    // MARK: - General Chat Empty State Text

    @Test @MainActor func generalChatEmptyStateDistinctFromBookChat() {
        // General mode
        let (generalVM, _) = makeSUT(bookFingerprint: nil)
        #expect(generalVM.bookFingerprint == nil)

        // Book mode
        let fp = DocumentFingerprint(
            contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            fileByteCount: 1024,
            format: .epub
        )
        let (bookVM, _) = makeSUT(bookFingerprint: fp)
        #expect(bookVM.bookFingerprint != nil)

        // The AIChatView uses bookFingerprint to decide empty state text.
        // This test verifies the data layer distinction that drives the UI.
    }
}
