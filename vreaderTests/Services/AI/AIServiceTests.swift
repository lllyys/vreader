// Purpose: Tests for AIService — gate sequence (feature flag, consent, API key),
// cache behavior, provider error propagation, cache key uniqueness.

import Testing
import Foundation
@testable import vreader

@Suite("AIService")
struct AIServiceTests {

    // MARK: - Gate 1: Feature Flag

    @Test func featureFlagOffReturnsDisabled() async throws {
        var flags = FeatureFlags(environment: .prod)
        // AI is off by default in prod
        #expect(flags.aiAssistant == false)

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: WI11TestHelpers.makeKeychainService()
        )
        _ = flags // suppress mutation warning

        do {
            _ = try await service.sendRequest(WI11TestHelpers.makeRequest())
            #expect(Bool(false), "Should have thrown featureDisabled")
        } catch let error as AIError {
            #expect(error == .featureDisabled)
        }
    }

    // MARK: - Gate 2: Consent

    @Test func noConsentReturnsConsentRequired() async throws {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

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

    @Test func noApiKeyReturnsApiKeyMissing() async throws {
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

        let keychain = WI11TestHelpers.makeKeychainService()
        // No API key stored

        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: keychain
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
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

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
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

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
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

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
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

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
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

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
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

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
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

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
        var flags = FeatureFlags(environment: .prod)
        flags.setOverride(.aiAssistant, value: true)

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
}
