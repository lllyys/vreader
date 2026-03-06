// Purpose: Main coordinator for the AI assistant feature.
// Enforces the gate sequence: feature flag → consent → API key → cache → provider.
//
// Key decisions:
// - Actor-based for thread safety with cache and provider.
// - Gate order is strict: disabled flag short-circuits before consent check, etc.
// - Cache is checked before making any network call.
// - Successful provider responses are cached automatically.
// - Streaming bypasses cache (streams cannot be cached mid-flight).
// - Provider is injected for testability.
//
// @coordinates-with: AIProvider.swift, AIResponseCache.swift, AIConsentManager.swift

import Foundation

/// Coordinates AI requests through feature flag, consent, API key, and cache gates.
actor AIService {

    private let featureFlags: FeatureFlags
    let consentManager: AIConsentManager
    private let keychainService: KeychainService
    private let cache: AIResponseCache
    private let provider: (any AIProvider)?
    private let providerFactory: (@Sendable (String) -> any AIProvider)?

    /// Keychain account name for the AI API key.
    static let apiKeyAccount = "com.vreader.ai.apiKey"

    /// Creates an AIService with explicit dependencies.
    ///
    /// - Parameters:
    ///   - featureFlags: Feature flags to check AI enablement.
    ///   - consentManager: Manages user consent state.
    ///   - keychainService: Provides API key storage.
    ///   - cache: Response cache.
    ///   - provider: Optional pre-built provider (for testing). If nil, providerFactory is used.
    ///   - providerFactory: Creates a provider from an API key. Used when provider is nil.
    init(
        featureFlags: FeatureFlags,
        consentManager: AIConsentManager,
        keychainService: KeychainService,
        cache: AIResponseCache = AIResponseCache(),
        provider: (any AIProvider)? = nil,
        providerFactory: (@Sendable (String) -> any AIProvider)? = nil
    ) {
        self.featureFlags = featureFlags
        self.consentManager = consentManager
        self.keychainService = keychainService
        self.cache = cache
        self.provider = provider
        self.providerFactory = providerFactory
    }

    /// Sends a non-streaming AI request through all gates.
    ///
    /// Gate sequence:
    /// 1. Feature flag check
    /// 2. Consent check
    /// 3. API key check
    /// 4. Cache lookup
    /// 5. Provider call (on cache miss)
    ///
    /// - Parameter request: The AI request to process.
    /// - Returns: The AI response (from cache or provider).
    /// - Throws: `AIError` at any failed gate.
    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        // Gate 1: Feature flag
        guard featureFlags.aiAssistant else {
            throw AIError.featureDisabled
        }

        // Gate 2: Consent
        guard consentManager.hasConsent else {
            throw AIError.consentRequired
        }

        // Gate 3: API key
        let resolvedProvider = try resolveProvider()

        // Gate 4: Cache
        if let cached = await cache.get(forKey: request.cacheKey) {
            return cached
        }

        // Gate 5: Provider call
        let response = try await resolvedProvider.sendRequest(request)
        await cache.set(response, forKey: request.cacheKey)
        return response
    }

    /// Streams an AI request through all gates except cache.
    ///
    /// - Parameter request: The AI request to stream.
    /// - Returns: An async stream of response chunks.
    /// - Throws: `AIError` at any failed gate (before streaming begins).
    func streamRequest(_ request: AIRequest) throws -> AsyncThrowingStream<AIStreamChunk, Error> {
        // Gate 1: Feature flag
        guard featureFlags.aiAssistant else {
            throw AIError.featureDisabled
        }

        // Gate 2: Consent
        guard consentManager.hasConsent else {
            throw AIError.consentRequired
        }

        // Gate 3: API key + provider
        let resolvedProvider = try resolveProvider()

        return resolvedProvider.streamRequest(request)
    }

    /// Clears the response cache. Called when consent is revoked.
    func clearCache() async {
        await cache.clearAll()
    }

    // MARK: - Private

    private func resolveProvider() throws -> any AIProvider {
        if let provider {
            return provider
        }

        guard let apiKey = try keychainService.readString(forAccount: Self.apiKeyAccount),
              !apiKey.isEmpty else {
            throw AIError.apiKeyMissing
        }

        guard let factory = providerFactory else {
            throw AIError.providerError("No AI provider configured.")
        }

        return factory(apiKey)
    }
}
