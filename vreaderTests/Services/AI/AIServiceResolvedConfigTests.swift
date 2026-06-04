// Purpose: Tests for the feature #56 WI-5 AIService resolved-provider seam —
// ResolvedAIProviderConfig, resolveActiveProviderConfig(),
// resolveProviderConfig(profileID:modelOverride:), and sendRequest(_:using:).
//
// @coordinates-with: AIService.swift, ResolvedAIProviderConfig.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-5)

import Testing
import Foundation
@testable import vreader

@Suite("AIService — resolved-provider seam (WI-5)")
struct AIServiceResolvedConfigTests {

    // MARK: - Infrastructure (mirrors AIServiceProfileDispatchTests)

    private static func makeTestStore() -> (
        store: ProviderProfileStore, keychain: KeychainService
    ) {
        let prefs = MockPreferenceStore()
        let keychain = KeychainService(serviceIdentifier: "com.vreader.test.\(UUID().uuidString)")
        prefs.set("true", forKey: DefaultProviderProfileMigrator.migrationFlagKey)
        let store = ProviderProfileStore(
            preferences: prefs, migrator: DefaultProviderProfileMigrator(), keychain: keychain)
        return (store, keychain)
    }

    private static func makeOpenAIProfile(model: String = "gpt-test-1") -> ProviderProfile {
        ProviderProfile(
            id: UUID(), name: "Test OpenAI", kind: .openAICompatible,
            baseURL: URL(string: "https://api.test.openai.example.com/v1")!,
            model: model, temperature: 0.5, maxTokens: 1234)
    }

    private static func makeAnthropicProfile(model: String = "claude-test-1") -> ProviderProfile {
        ProviderProfile(
            id: UUID(), name: "Test Anthropic", kind: .anthropicNative,
            baseURL: URL(string: "https://api.test.anthropic.example.com")!,
            model: model, temperature: 0.7, maxTokens: 4321)
    }

    private static func makeService(
        store: ProviderProfileStore,
        keychain: KeychainService,
        aiEnabled: Bool = true,
        hasConsent: Bool = true,
        provider: (any AIProvider)? = nil
    ) -> AIService {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(aiEnabled, for: .aiAssistant)
        return AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: hasConsent),
            keychainService: keychain,
            provider: provider,
            profileStore: store)
    }

    private static func translateRequest() -> AIRequest {
        AIRequest(
            actionType: .translate, bookFingerprint: nil, locator: nil,
            contextText: "source text", userPrompt: "translate this",
            targetLanguage: "Chinese", promptVersion: "v1")
    }

    // MARK: - resolveActiveProviderConfig

    @Test func resolveActiveProviderConfig_snapshotsActiveOpenAIProfile() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-openai-active", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain)
        let config = try await service.resolveActiveProviderConfig()
        #expect(config.kind == .openAICompatible)
        #expect(config.baseURL == profile.baseURL)
        #expect(config.apiKey == "sk-openai-active")
        #expect(config.model == "gpt-test-1")
    }

    @Test func resolveActiveProviderConfig_snapshotsActiveAnthropicProfileWithMaxTokens() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeAnthropicProfile()
        try keychain.saveAPIKey("sk-ant-active", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain)
        let config = try await service.resolveActiveProviderConfig()
        #expect(config.kind == .anthropicNative)
        #expect(config.maxTokens == 4321)
    }

    @Test func resolveActiveProviderConfig_throwsFeatureDisabledWhenFlagOff() async {
        let (store, keychain) = Self.makeTestStore()
        let service = Self.makeService(store: store, keychain: keychain, aiEnabled: false)
        await #expect(throws: AIError.featureDisabled) {
            _ = try await service.resolveActiveProviderConfig()
        }
    }

    @Test func resolveActiveProviderConfig_throwsConsentRequiredWhenNoConsent() async {
        let (store, keychain) = Self.makeTestStore()
        let service = Self.makeService(store: store, keychain: keychain, hasConsent: false)
        await #expect(throws: AIError.consentRequired) {
            _ = try await service.resolveActiveProviderConfig()
        }
    }

    @Test func resolveActiveProviderConfig_throwsApiKeyMissingWithNoKey() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        // No keychain key saved.
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)
        let service = Self.makeService(store: store, keychain: keychain)
        await #expect(throws: AIError.apiKeyMissing) {
            _ = try await service.resolveActiveProviderConfig()
        }
    }

    @Test func resolveActiveProviderConfig_throwsProviderErrorWhenNoActiveProfile() async {
        let (store, keychain) = Self.makeTestStore()
        let service = Self.makeService(store: store, keychain: keychain)
        await #expect(throws: AIError.providerError("Configure a provider in Settings.")) {
            _ = try await service.resolveActiveProviderConfig()
        }
    }

    // MARK: - resolveToolProvider / sendToolTurn (Feature #91 WI-8)

    /// A tool-capable provider stub (supportsToolUse = true, returns a canned tool
    /// turn) — the injected `provider:` short-circuits `providerInstance(for:)`.
    private final class ToolCapableStub: AIProvider, @unchecked Sendable {
        let providerName = "ToolStub"
        var supportsToolUse: Bool { true }
        func sendRequest(_ request: AIRequest) async throws -> AIResponse {
            throw AIError.invalidResponse
        }
        func streamRequest(_ request: AIRequest) -> AsyncThrowingStream<AIStreamChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func sendToolRequest(_ request: AIToolRequest) async throws -> AIToolTurn {
            .text("tool answer")
        }
    }

    private static func toolRequest() -> AIToolRequest {
        AIToolRequest(
            systemPrompt: "s", messages: [ToolTurnMessage(role: .user, content: [.text("q")])],
            tools: [], maxTokens: 128)
    }

    /// Build a service with a held FeatureFlags handle so a test can flip a gate
    /// mid-loop.
    private static func makeServiceHoldingFlags(
        store: ProviderProfileStore, keychain: KeychainService,
        provider: any AIProvider
    ) -> (AIService, FeatureFlags) {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: keychain, provider: provider, profileStore: store)
        return (service, flags)
    }

    @Test func resolveToolProvider_returnsConfigCapabilityAndMaxTokens() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeAnthropicProfile()   // maxTokens 4321
        try keychain.saveAPIKey("sk-ant-active", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain, provider: ToolCapableStub())
        let (config, supports) = try await service.resolveToolProvider()
        #expect(supports == true)
        #expect(config.maxTokens == 4321)            // pinned from the resolved config
        #expect(config.kind == .anthropicNative)
    }

    @Test func resolveToolProvider_reportsUnsupportedForNonToolProvider() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-openai-active", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain, provider: StubAIProvider())
        let (_, supports) = try await service.resolveToolProvider()
        #expect(supports == false)   // StubAIProvider defaults supportsToolUse=false
    }

    @Test func resolveToolProvider_failsClosedOnEveryGate() async throws {
        // Same gate set as resolveActiveProviderConfig — the agentic path never
        // reaches a provider when AI is off / no consent / no key.
        let (store, keychain) = Self.makeTestStore()
        await #expect(throws: AIError.featureDisabled) {
            _ = try await Self.makeService(store: store, keychain: keychain, aiEnabled: false)
                .resolveToolProvider()
        }
        await #expect(throws: AIError.consentRequired) {
            _ = try await Self.makeService(store: store, keychain: keychain, hasConsent: false)
                .resolveToolProvider()
        }
        // Active profile but no stored key → apiKeyMissing.
        let profile = Self.makeOpenAIProfile()
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)
        await #expect(throws: AIError.apiKeyMissing) {
            _ = try await Self.makeService(store: store, keychain: keychain).resolveToolProvider()
        }
    }

    @Test func sendToolTurn_forwardsThroughThePinnedConfigWhenGatesPass() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-openai-active", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain, provider: ToolCapableStub())
        let (config, _) = try await service.resolveToolProvider()
        let turn = try await service.sendToolTurn(Self.toolRequest(), using: config)
        #expect(turn == .text("tool answer"))
    }

    @Test func sendToolTurn_reChecksTheLiveFlagEachTurn() async throws {
        // Gate-4 Medium: a flag flip / consent revoke MID-loop must fail the next
        // tool turn closed, even though the config was already resolved.
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-openai-active", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let (service, flags) = Self.makeServiceHoldingFlags(
            store: store, keychain: keychain, provider: ToolCapableStub())
        let (config, _) = try await service.resolveToolProvider()

        flags.setOverride(false, for: .aiAssistant)   // AI disabled mid-loop
        await #expect(throws: AIError.featureDisabled) {
            _ = try await service.sendToolTurn(Self.toolRequest(), using: config)
        }
    }

    // MARK: - resolveProviderConfig(profileID:modelOverride:)

    @Test func resolveProviderConfig_resolvesANamedNonActiveProfile() async throws {
        let (store, keychain) = Self.makeTestStore()
        let active = Self.makeOpenAIProfile(model: "gpt-active")
        let other = Self.makeAnthropicProfile(model: "claude-other")
        try keychain.saveAPIKey("sk-active", forProfile: active.id)
        try keychain.saveAPIKey("sk-other", forProfile: other.id)
        await store.upsert(active)
        await store.upsert(other)
        await store.setActiveProfileID(active.id)

        let service = Self.makeService(store: store, keychain: keychain)
        // Resolve the NON-active profile by id.
        let config = try await service.resolveProviderConfig(profileID: other.id, modelOverride: nil)
        #expect(config.kind == .anthropicNative)
        #expect(config.model == "claude-other")
        #expect(config.apiKey == "sk-other")
    }

    @Test func resolveProviderConfig_appliesModelOverride() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile(model: "gpt-default")
        try keychain.saveAPIKey("sk-k", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain)
        let config = try await service.resolveProviderConfig(
            profileID: profile.id, modelOverride: "gpt-override-4")
        // The override wins; the profile's own model is not used.
        #expect(config.model == "gpt-override-4")
    }

    @Test func resolveProviderConfig_nilOverrideKeepsProfileModel() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile(model: "gpt-keep")
        try keychain.saveAPIKey("sk-k", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)
        let service = Self.makeService(store: store, keychain: keychain)
        let config = try await service.resolveProviderConfig(profileID: profile.id, modelOverride: nil)
        #expect(config.model == "gpt-keep")
    }

    @Test func resolveProviderConfig_throwsProviderErrorForUnknownProfileID() async {
        let (store, keychain) = Self.makeTestStore()
        let service = Self.makeService(store: store, keychain: keychain)
        let unknownID = UUID()
        await #expect(throws: AIError.providerError("The selected AI provider no longer exists.")) {
            _ = try await service.resolveProviderConfig(profileID: unknownID, modelOverride: nil)
        }
    }

    // MARK: - sendRequest(_:using:)

    @Test func sendRequestUsing_dispatchesThroughTheConfigsProvider() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-k", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let stub = StubAIProvider()
        stub.stubbedResponse = AIResponse(
            content: #"["译文"]"#, actionType: .translate,
            promptVersion: "v1", createdAt: Date())
        let service = Self.makeService(store: store, keychain: keychain, provider: stub)
        let config = try await service.resolveActiveProviderConfig()
        let response = try await service.sendRequest(Self.translateRequest(), using: config)
        #expect(response.content == #"["译文"]"#)
        #expect(stub.sendRequestCallCount == 1)
    }

    @Test func sendRequestUsing_throwsFeatureDisabledWhenFlagOff() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-k", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)
        // Resolve a config while AI is enabled, then send while disabled.
        let enabledService = Self.makeService(store: store, keychain: keychain)
        let config = try await enabledService.resolveActiveProviderConfig()

        let disabledService = Self.makeService(
            store: store, keychain: keychain, aiEnabled: false, provider: StubAIProvider())
        await #expect(throws: AIError.featureDisabled) {
            _ = try await disabledService.sendRequest(Self.translateRequest(), using: config)
        }
    }

    @Test func sendRequestUsing_throwsConsentRequiredWithoutConsent() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-k", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)
        let enabledService = Self.makeService(store: store, keychain: keychain)
        let config = try await enabledService.resolveActiveProviderConfig()

        let noConsentService = Self.makeService(
            store: store, keychain: keychain, hasConsent: false, provider: StubAIProvider())
        await #expect(throws: AIError.consentRequired) {
            _ = try await noConsentService.sendRequest(Self.translateRequest(), using: config)
        }
    }

    // MARK: - Config pinning

    @Test func resolvedConfig_isPinned_activeProfileSwapDoesNotChangeIt() async throws {
        // The config is a value snapshot — swapping the active profile after
        // resolution must not change the resolved config's fields.
        let (store, keychain) = Self.makeTestStore()
        let first = Self.makeOpenAIProfile(model: "gpt-first")
        let second = Self.makeAnthropicProfile(model: "claude-second")
        try keychain.saveAPIKey("sk-first", forProfile: first.id)
        try keychain.saveAPIKey("sk-second", forProfile: second.id)
        await store.upsert(first)
        await store.upsert(second)
        await store.setActiveProfileID(first.id)

        let service = Self.makeService(store: store, keychain: keychain)
        let config = try await service.resolveActiveProviderConfig()
        // Swap the active profile.
        await store.setActiveProfileID(second.id)
        // The already-resolved config still reflects the FIRST profile.
        #expect(config.kind == .openAICompatible)
        #expect(config.model == "gpt-first")
        #expect(config.apiKey == "sk-first")
    }

    @Test func resolvedAIProviderConfig_isEquatable() {
        let url = URL(string: "https://x.example.com")!
        let a = ResolvedAIProviderConfig(
            kind: .openAICompatible, baseURL: url, apiKey: "k", model: "m", maxTokens: 100)
        let b = ResolvedAIProviderConfig(
            kind: .openAICompatible, baseURL: url, apiKey: "k", model: "m", maxTokens: 100)
        #expect(a == b)
    }

    // MARK: - Existing API unchanged

    @Test func resolveProvider_stillWorksUnchanged() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-k", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)
        let service = Self.makeService(store: store, keychain: keychain)
        let provider = try await service.resolveProvider()
        #expect(provider is OpenAICompatibleProvider)
    }

    // MARK: - providerFactory injection + credential pinning

    /// A factory-injected service: records the (profile, apiKey) pair the
    /// `sendRequest(_:using:)` path constructs its provider with.
    private static func makeServiceWithCapturingFactory(
        store: ProviderProfileStore,
        keychain: KeychainService
    ) -> (service: AIService, captured: CapturedFactoryArgs) {
        let captured = CapturedFactoryArgs()
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let factory: @Sendable (ProviderProfile, String) -> any AIProvider = { profile, key in
            captured.record(profile: profile, apiKey: key)
            let stub = StubAIProvider()
            stub.stubbedResponse = AIResponse(
                content: "[]", actionType: .translate, promptVersion: "v1", createdAt: Date())
            return stub
        }
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: keychain,
            providerFactory: factory,
            profileStore: store)
        return (service, captured)
    }

    @Test func sendRequestUsing_honorsProviderFactoryInjection() async throws {
        // The plan requires the resolved-config path to honor providerFactory
        // test injection (Gate-4 round-1 Medium).
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile(model: "gpt-factory")
        try keychain.saveAPIKey("sk-factory", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let (service, captured) = Self.makeServiceWithCapturingFactory(
            store: store, keychain: keychain)
        let config = try await service.resolveActiveProviderConfig()
        _ = try await service.sendRequest(Self.translateRequest(), using: config)

        // The factory was invoked, with the config's resolved model + key.
        #expect(captured.invocationCount == 1)
        #expect(captured.lastProfile?.model == "gpt-factory")
        #expect(captured.lastProfile?.kind == .openAICompatible)
        #expect(captured.lastAPIKey == "sk-factory")
    }

    @Test func sendRequestUsing_keepsResolvedCredentialAfterKeychainRotation() async throws {
        // Credential pinning: resolve a config, ROTATE the Keychain key, then
        // send — the send path must still use the ORIGINALLY resolved key.
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-original", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let (service, captured) = Self.makeServiceWithCapturingFactory(
            store: store, keychain: keychain)
        let config = try await service.resolveActiveProviderConfig()
        #expect(config.apiKey == "sk-original")

        // Rotate the stored key AFTER resolution.
        try keychain.saveAPIKey("sk-rotated", forProfile: profile.id)
        _ = try await service.sendRequest(Self.translateRequest(), using: config)

        // The send path used the pinned original key, not the rotated one.
        #expect(captured.lastAPIKey == "sk-original")
    }
}

/// Thread-safe recorder for the capturing `providerFactory` (the factory
/// closure must be `@Sendable`).
private final class CapturedFactoryArgs: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var _profile: ProviderProfile?
    private var _apiKey: String?

    func record(profile: ProviderProfile, apiKey: String) {
        lock.lock(); defer { lock.unlock() }
        _count += 1
        _profile = profile
        _apiKey = apiKey
    }
    var invocationCount: Int { lock.lock(); defer { lock.unlock() }; return _count }
    var lastProfile: ProviderProfile? { lock.lock(); defer { lock.unlock() }; return _profile }
    var lastAPIKey: String? { lock.lock(); defer { lock.unlock() }; return _apiKey }
}
