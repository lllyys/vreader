// Purpose: Tests for AIService — gate sequence (feature flag, consent, API key),
// cache behavior, provider error propagation, cache key uniqueness.

import Testing
import Foundation
@testable import vreader

@Suite("AIService")
struct AIServiceTests {

    // MARK: - Gate 1: Feature Flag

    @Test func featureFlagOffReturnsDisabled() async throws {
        let flags = FeatureFlags(environment: .prod)
        // AI is off by default in prod
        #expect(flags.aiAssistant == false)

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService()
        )

        do {
            _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false), "Should have thrown featureDisabled")
        } catch let error as AIError {
            #expect(error == .featureDisabled)
        }
    }

    // MARK: - Gate 2: Consent

    @Test func noConsentReturnsConsentRequired() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: false),
            keychainService: WI11TestHelpers.makeKeychainService()
        )

        do {
            _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false), "Should have thrown consentRequired")
        } catch let error as AIError {
            #expect(error == .consentRequired)
        }
    }

    // MARK: - Gate 3: API Key

    /// Feature #50 WI-5 retuning: an active profile must exist in the
    /// (non-`.shared`) profile store before this gate is exercised —
    /// otherwise resolveProvider() now bails earlier with
    /// `.providerError("Configure a provider in Settings.")`. The
    /// "missing key" semantic still applies once a profile is present
    /// but its per-profile keychain entry is absent.
    @Test func noApiKeyReturnsApiKeyMissing() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let keychain = WI11TestHelpers.makeKeychainService()
        // Pre-seed an active profile but no API key.
        let prefs = MockPreferenceStore()
        prefs.set("true", forKey: DefaultProviderProfileMigrator.migrationFlagKey)
        let store = ProviderProfileStore(
            preferences: prefs,
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )
        let profile = ProviderProfile(
            id: UUID(),
            name: "Test",
            kind: .openAICompatible,
            baseURL: URL(string: "https://api.openai.example.com/v1")!,
            model: "gpt-test",
            temperature: 0.5,
            maxTokens: 1024
        )
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: keychain,
            profileStore: store
        )

        do {
            _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false), "Should have thrown apiKeyMissing")
        } catch let error as AIError {
            #expect(error == .apiKeyMissing)
        }
    }

    // MARK: - Gate 4: Cache Hit

    @Test func cachedResponseReturnedWithoutProviderCall() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let stub = StubAIProvider()
        stub.stubbedResponse = WI11TestHelpers.makeResponse(content: "fresh response")

        let cache = AIResponseCache()
        let request = WI11TestHelpers.makeRequest()
        let cachedResponse = WI11TestHelpers.makeResponse(content: "cached response")
        await cache.set(cachedResponse, forKey: request.cacheKey)

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            cache: cache,
            provider: stub
        )

        let result = try await service.sendRequest(request)
        #expect(result.content == "cached response")
        #expect(stub.sendRequestCallCount == 0, "Provider should not be called on cache hit")
    }

    // MARK: - Gate 5: Provider Call

    @Test func cacheMissTriggersProviderCall() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let stub = StubAIProvider()
        stub.stubbedResponse = WI11TestHelpers.makeResponse(content: "provider response")

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        let result = try await service.sendRequest(WI11TestHelpers.makeRequest())
        #expect(result.content == "provider response")
        #expect(stub.sendRequestCallCount == 1)
    }

    @Test func providerResponseIsCached() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let stub = StubAIProvider()
        stub.stubbedResponse = WI11TestHelpers.makeResponse(content: "will be cached")

        let cache = AIResponseCache()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            cache: cache,
            provider: stub
        )

        let request = WI11TestHelpers.makeRequest()
        _ = try await service.sendRequest(request)

        // Second call should hit cache
        let result = try await service.sendRequest(request)
        #expect(result.content == "will be cached")
        #expect(stub.sendRequestCallCount == 1, "Provider called only once; second call hit cache")
    }

    // MARK: - Provider Error Propagation

    @Test func providerErrorPropagated() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let stub = StubAIProvider()
        stub.stubbedError = AIError.providerError("Server error")

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        do {
            _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false), "Should have thrown providerError")
        } catch let error as AIError {
            #expect(error == .providerError("Server error"))
        }
    }

    @Test func rateLimitedErrorPropagated() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let stub = StubAIProvider()
        stub.stubbedError = AIError.rateLimited(retryAfterSeconds: 30)

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        do {
            _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false), "Should have thrown rateLimited")
        } catch let error as AIError {
            #expect(error == .rateLimited(retryAfterSeconds: 30))
        }
    }

    // MARK: - Cache Key Uniqueness

    @Test func differentActionTypesHaveDifferentCacheKeys() {
        let request1 = WI11TestHelpers.makeRequest(actionType: .summarize)
        let request2 = WI11TestHelpers.makeRequest(actionType: .explain)
        #expect(request1.cacheKey != request2.cacheKey)
    }

    @Test func differentPromptVersionsHaveDifferentCacheKeys() {
        let request1 = WI11TestHelpers.makeRequest(promptVersion: "v1")
        let request2 = WI11TestHelpers.makeRequest(promptVersion: "v2")
        #expect(request1.cacheKey != request2.cacheKey)
    }

    @Test func sameParametersHaveSameCacheKey() {
        let request1 = WI11TestHelpers.makeRequest()
        let request2 = WI11TestHelpers.makeRequest()
        #expect(request1.cacheKey == request2.cacheKey)
    }

    // MARK: - Streaming Gates

    @Test func streamFeatureFlagOffThrows() async throws {
        let flags = FeatureFlags(environment: .prod)
        let stub = StubAIProvider()

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        do {
            _ = try await service.streamRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false), "Should have thrown featureDisabled")
        } catch let error as AIError {
            #expect(error == .featureDisabled)
        }
    }

    @Test func streamNoConsentThrows() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: false),
            keychainService: WI11TestHelpers.makeKeychainService()
        )

        do {
            _ = try await service.streamRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false), "Should have thrown consentRequired")
        } catch let error as AIError {
            #expect(error == .consentRequired)
        }
    }

    // MARK: - Clear Cache

    @Test func clearCacheRemovesEntries() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let stub = StubAIProvider()
        stub.stubbedResponse = WI11TestHelpers.makeResponse(content: "response")

        let cache = AIResponseCache()
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            cache: cache,
            provider: stub
        )

        // Populate cache
        _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
        #expect(await cache.count == 1)

        // Clear
        await service.clearCache()
        #expect(await cache.count == 0)
    }

    // MARK: - Gate Order

    @Test func featureFlagCheckedBeforeConsent() async throws {
        // Even with consent, feature flag OFF should give featureDisabled, not consentRequired
        let flags = FeatureFlags(environment: .prod) // aiAssistant OFF

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService()
        )

        do {
            _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false))
        } catch let error as AIError {
            #expect(error == .featureDisabled, "Feature flag should be checked before consent")
        }
    }

    @Test func consentCheckedBeforeApiKey() async throws {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)

        let keychain = WI11TestHelpers.makeKeychainService()
        // No API key, but also no consent

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: false),
            keychainService: keychain
        )

        do {
            _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false))
        } catch let error as AIError {
            #expect(error == .consentRequired, "Consent should be checked before API key")
        }
    }

    // MARK: - Live Feature Flag (Issue 1)

    @Test func featureFlagToggleLiveReflectsInService() async throws {
        let flags = FeatureFlags(environment: .prod)
        // Start with AI disabled
        let stub = StubAIProvider()
        stub.stubbedResponse = WI11TestHelpers.makeResponse(content: "response")

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService(),
            provider: stub
        )

        // Should fail with featureDisabled
        do {
            _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false))
        } catch let error as AIError {
            #expect(error == .featureDisabled)
        }

        // Now enable AI on the same flags instance
        flags.setOverride(true, for: .aiAssistant)

        // Should now succeed because service reads live from the reference
        let result = try await service.sendRequest(WI11TestHelpers.makeRequest())
        #expect(result.content == "response")
    }
}
