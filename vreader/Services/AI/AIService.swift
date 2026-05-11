// Purpose: Main coordinator for the AI assistant feature.
// Enforces the gate sequence: feature flag → consent → API key → cache → provider.
//
// Key decisions:
// - Actor-based for thread safety with cache and provider.
// - Gate order is strict: disabled flag short-circuits before consent check, etc.
// - Feature flags are read from FeatureFlags instance (live reference, not a copy).
// - Cache is checked before making any network call.
// - Successful provider responses are cached automatically.
// - Streaming bypasses cache (streams cannot be cached mid-flight).
// - Provider is injected for testability.
// - Feature #50 WI-5: provider construction now dispatches on the active
//   `ProviderProfile` from `ProviderProfileStore`. `resolveProvider()`
//   takes ONE snapshot at request start (Gate-2 round-1 finding [6]) so
//   the in-flight request keeps its profile state even if the user
//   swaps the active profile mid-stream.
// - `apiKeyAccount` constant retained for migration backward-compat only;
//   no new code reads it (the migrator does, transparently).
//
// @coordinates-with: AIProvider.swift, AnthropicProvider.swift,
//   AIResponseCache.swift, AIConsentManager.swift,
//   ProviderProfileStore.swift, ProviderProfile.swift,
//   KeychainService+ProviderProfile.swift

import Foundation

/// Coordinates AI requests through feature flag, consent, API key, and cache gates.
actor AIService {

    private let featureFlags: FeatureFlags
    let consentManager: AIConsentManager
    private let keychainService: KeychainService
    private let cache: AIResponseCache
    private let provider: (any AIProvider)?
    private let providerFactory: (@Sendable (ProviderProfile, String) -> any AIProvider)?
    private let profileStore: ProviderProfileStore

    /// Legacy single-profile keychain account.
    ///
    /// DO NOT CALL FROM NEW CODE. This constant exists only so that
    /// `ProviderProfileMigrator` can find an existing user's legacy API
    /// key during one-time migration to the per-profile account scheme
    /// (`KeychainService.providerAccount(for:)`).
    ///
    /// `@available(*, deprecated)` is intentionally NOT applied yet:
    /// `AISettingsViewModel` (WI-6a/6b) and `AIReaderAvailability` (WI-7)
    /// still read/write this account in production. Annotating now would
    /// flood the compile log with warnings on every intermediate WI PR.
    /// The annotation lands together with the cleanup PR that removes
    /// `AIConfigurationStore`, after WI-7 ships and migration has run on
    /// shipped users for one release (per the plan's Backward compat
    /// table → "AIConfiguration struct" row).
    static let apiKeyAccount = "com.vreader.ai.apiKey"

    /// Creates an AIService with explicit dependencies.
    ///
    /// - Parameters:
    ///   - featureFlags: Feature flags to check AI enablement. Uses live reference.
    ///   - consentManager: Manages user consent state.
    ///   - keychainService: Provides per-profile API key storage.
    ///   - cache: Response cache.
    ///   - provider: Optional pre-built provider (for testing). If non-nil,
    ///     resolveProvider short-circuits to this without consulting the
    ///     store or keychain.
    ///   - providerFactory: Optional test-injection factory. If non-nil,
    ///     `resolveProvider()` calls it with the active profile snapshot
    ///     and resolved API key INSTEAD of using the production dispatch
    ///     switch. Used by tests to observe what the snapshot resolved to.
    ///   - profileStore: The provider profile store. Defaults to `.shared`
    ///     (Gate-2 round-2 finding [2] — production callers MUST use the
    ///     singleton; tests inject a non-shared instance per round-3
    ///     finding [1]).
    init(
        featureFlags: FeatureFlags,
        consentManager: AIConsentManager,
        keychainService: KeychainService,
        cache: AIResponseCache = AIResponseCache(),
        provider: (any AIProvider)? = nil,
        providerFactory: (@Sendable (ProviderProfile, String) -> any AIProvider)? = nil,
        profileStore: ProviderProfileStore = .shared
    ) {
        self.featureFlags = featureFlags
        self.consentManager = consentManager
        self.keychainService = keychainService
        self.cache = cache
        self.provider = provider
        self.providerFactory = providerFactory
        self.profileStore = profileStore
    }

    /// Sends a non-streaming AI request through all gates.
    ///
    /// Gate sequence:
    /// 1. Feature flag check
    /// 2. Consent check
    /// 3. API key + provider snapshot
    /// 4. Cache lookup
    /// 5. Provider call (on cache miss)
    func sendRequest(_ request: AIRequest) async throws -> AIResponse {
        guard featureFlags.aiAssistant else {
            throw AIError.featureDisabled
        }
        guard consentManager.hasConsent else {
            throw AIError.consentRequired
        }

        let resolvedProvider = try await resolveProvider()

        if let cached = await cache.get(forKey: request.cacheKey) {
            return cached
        }

        let response = try await resolvedProvider.sendRequest(request)
        await cache.set(response, forKey: request.cacheKey)
        return response
    }

    /// Streams an AI request through all gates except cache.
    ///
    /// Made `async throws` (was just `throws`) so the provider snapshot
    /// can be taken via `await profileStore.activeProfileSnapshot()` before
    /// the stream begins. The sole production caller (`AIChatViewModel`)
    /// already invokes via `try await`.
    func streamRequest(_ request: AIRequest) async throws -> AsyncThrowingStream<AIStreamChunk, Error> {
        guard featureFlags.aiAssistant else {
            throw AIError.featureDisabled
        }
        guard consentManager.hasConsent else {
            throw AIError.consentRequired
        }

        let resolvedProvider = try await resolveProvider()
        return resolvedProvider.streamRequest(request)
    }

    /// Clears the response cache. Called when consent is revoked.
    func clearCache() async {
        await cache.clearAll()
    }

    // MARK: - Provider resolution
    //
    // Exposed as default visibility (not `private`) so unit tests under
    // `vreaderTests/Services/AI/AIServiceProfileDispatchTests.swift` can
    // assert the dispatch returns the right concrete provider type with
    // the right snapshot fields.

    func resolveProvider() async throws -> any AIProvider {
        if let provider {
            return provider
        }

        // Single snapshot read at request start. ProviderProfile is a
        // value type — once read, the in-flight request is insulated
        // from later store mutations.
        guard let snapshot = await profileStore.activeProfileSnapshot() else {
            throw AIError.providerError("Configure a provider in Settings.")
        }

        // Per-profile keychain account (KeychainService+ProviderProfile).
        let storedKey = try keychainService.readAPIKey(forProfile: snapshot.id)
        guard let apiKey = storedKey, !apiKey.isEmpty else {
            throw AIError.apiKeyMissing
        }

        if let factory = providerFactory {
            return factory(snapshot, apiKey)
        }

        // Production dispatch on profile kind.
        switch snapshot.kind {
        case .openAICompatible:
            return OpenAICompatibleProvider(
                baseURL: snapshot.baseURL,
                apiKey: apiKey,
                model: snapshot.model
            )
        case .anthropicNative:
            return AnthropicProvider(
                baseURL: snapshot.baseURL,
                apiKey: apiKey,
                model: snapshot.model,
                maxTokens: snapshot.maxTokens
            )
        }
    }
}
