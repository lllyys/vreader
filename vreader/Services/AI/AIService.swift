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

    /// Stream through a PINNED resolved config (re-checking the live flag + consent),
    /// so a caller that already resolved once — e.g. the agentic chat probing
    /// `supportsToolUse` — can fall back to streaming WITHOUT re-resolving (no
    /// profile/model/key drift between the probe and the stream — Feature #91 Gate-4).
    func streamRequest(
        _ request: AIRequest, using config: ResolvedAIProviderConfig
    ) async throws -> AsyncThrowingStream<AIStreamChunk, Error> {
        guard featureFlags.aiAssistant else { throw AIError.featureDisabled }
        guard consentManager.hasConsent else { throw AIError.consentRequired }
        return providerInstance(for: config).streamRequest(request)
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
        #if DEBUG
        if let mock = AITestOverride.mockProvider { return mock }
        #endif
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

    // MARK: - Resolved-provider seam (feature #56 WI-5)
    //
    // `resolveProvider()` snapshots the active profile once *per request*.
    // Chapter translation is a *multi-request* operation: it must use ONE
    // consistent provider + credential + model for the whole operation, so
    // these methods produce / consume a `ResolvedAIProviderConfig` snapshot
    // taken once per operation. The credential is pinned in the config so a
    // mid-operation Keychain rotation cannot straddle chunks; `model` is
    // pinned so a re-translate model override applies for the whole operation
    // without mutating the saved `ProviderProfile`.

    /// Resolves the *active* provider into an immutable config snapshot.
    /// Runs the feature-flag + consent gates, snapshots the active
    /// `ProviderProfile`, and reads its Keychain key once — throwing
    /// `featureDisabled` / `consentRequired` / `providerError` / `apiKeyMissing`
    /// early so a long translation operation fails fast rather than mid-chunk.
    func resolveActiveProviderConfig() async throws -> ResolvedAIProviderConfig {
        guard featureFlags.aiAssistant else { throw AIError.featureDisabled }
        guard consentManager.hasConsent else { throw AIError.consentRequired }

        guard let snapshot = await profileStore.activeProfileSnapshot() else {
            throw AIError.providerError("Configure a provider in Settings.")
        }
        return try config(from: snapshot, modelOverride: nil)
    }

    /// Feature #91: resolve the active provider config ONCE for an agentic tool-use
    /// turn — the same flag + consent + active-profile + key gates as
    /// `resolveActiveProviderConfig` — and report whether the built provider
    /// supports tool-use. The driver pins THIS config for the whole loop (no
    /// provider/model/key drift mid-operation — Gate-2 Medium); each round-trip
    /// goes back through `sendToolTurn(_:using:)`, which re-checks the LIVE gates
    /// (Gate-4 Medium). `maxTokens` comes from `config.maxTokens`.
    func resolveToolProvider() async throws -> (config: ResolvedAIProviderConfig, supportsToolUse: Bool) {
        let config = try await resolveActiveProviderConfig()
        return (config, providerInstance(for: config).supportsToolUse)
    }

    /// Send ONE tool-use turn through a PINNED resolved config. Re-checks the live
    /// `aiAssistant` flag + consent EACH turn (Gate-4 Medium: a multi-turn agentic
    /// loop must stop the instant AI is disabled or consent is revoked mid-loop),
    /// while reusing the same `config` so the provider/model/key never drift
    /// (Gate-2 Medium).
    func sendToolTurn(
        _ request: AIToolRequest, using config: ResolvedAIProviderConfig
    ) async throws -> AIToolTurn {
        guard featureFlags.aiAssistant else { throw AIError.featureDisabled }
        guard consentManager.hasConsent else { throw AIError.consentRequired }
        return try await providerInstance(for: config).sendToolRequest(request)
    }

    /// Resolves a *named* provider profile (not necessarily the active one)
    /// into a config snapshot, applying an optional `modelOverride`. Used by
    /// the re-translate flow's provider-override picker. Throws `providerError`
    /// for an unknown `profileID` and `apiKeyMissing` with no stored key.
    func resolveProviderConfig(
        profileID: UUID,
        modelOverride: String?
    ) async throws -> ResolvedAIProviderConfig {
        guard featureFlags.aiAssistant else { throw AIError.featureDisabled }
        guard consentManager.hasConsent else { throw AIError.consentRequired }

        let snapshot = await profileStore.loadSnapshot()
        guard let profile = snapshot.profiles.first(where: { $0.id == profileID }) else {
            throw AIError.providerError("The selected AI provider no longer exists.")
        }
        return try config(from: profile, modelOverride: modelOverride)
    }

    /// Sends a request through a pre-resolved `ResolvedAIProviderConfig`.
    /// Runs the feature-flag + consent gates and builds the concrete provider
    /// from the config — it does NOT re-snapshot the active profile (so a
    /// chunked operation stays on one provider) and **deliberately does not
    /// consult `AIResponseCache`**: `AIRequest.cacheKey` carries no provider
    /// identity, so a config-pinned request could otherwise be served a
    /// cross-provider cached response. Chapter translation has its own
    /// provider-aware disk cache (`ChapterTranslation.lookupKey`).
    func sendRequest(
        _ request: AIRequest,
        using config: ResolvedAIProviderConfig
    ) async throws -> AIResponse {
        guard featureFlags.aiAssistant else { throw AIError.featureDisabled }
        guard consentManager.hasConsent else { throw AIError.consentRequired }

        return try await providerInstance(for: config).sendRequest(request)
    }

    // MARK: - Resolved-config helpers

    /// Builds a `ResolvedAIProviderConfig` from a profile snapshot, reading the
    /// Keychain key once and applying an optional model override.
    private func config(
        from profile: ProviderProfile,
        modelOverride: String?
    ) throws -> ResolvedAIProviderConfig {
        let storedKey = try keychainService.readAPIKey(forProfile: profile.id)
        guard let apiKey = storedKey, !apiKey.isEmpty else {
            throw AIError.apiKeyMissing
        }
        return ResolvedAIProviderConfig(
            kind: profile.kind,
            baseURL: profile.baseURL,
            apiKey: apiKey,
            model: modelOverride ?? profile.model,
            maxTokens: profile.maxTokens
        )
    }

    /// Builds the concrete provider for a resolved config, honoring the SAME
    /// test-injection precedence as `resolveProvider()`:
    /// `provider` (pre-built stub) → `providerFactory` (factory seam) →
    /// production dispatch switch keyed on `config.kind`. For the factory
    /// seam, the config is reflected back into a `ProviderProfile` so the
    /// existing `(ProviderProfile, String) -> any AIProvider` factory shape
    /// is reused (a test observes the resolved `model` / `apiKey` it carries).
    private func providerInstance(for config: ResolvedAIProviderConfig) -> any AIProvider {
        #if DEBUG
        if let mock = AITestOverride.mockProvider { return mock }
        #endif
        if let provider {
            return provider
        }
        if let factory = providerFactory {
            return factory(Self.profile(reflecting: config), config.apiKey)
        }
        switch config.kind {
        case .openAICompatible:
            return OpenAICompatibleProvider(
                baseURL: config.baseURL,
                apiKey: config.apiKey,
                model: config.model
            )
        case .anthropicNative:
            return AnthropicProvider(
                baseURL: config.baseURL,
                apiKey: config.apiKey,
                model: config.model,
                maxTokens: config.maxTokens
            )
        }
    }

    /// Reflects a resolved config back into a `ProviderProfile` for the
    /// `providerFactory` test seam. The `id`/`name`/`temperature` fields are
    /// synthesized (the config does not carry them and the factory only ever
    /// uses `kind`/`baseURL`/`model`/`maxTokens` + the explicit `apiKey` arg).
    private static func profile(reflecting config: ResolvedAIProviderConfig) -> ProviderProfile {
        ProviderProfile(
            id: UUID(),
            name: "resolved-config",
            kind: config.kind,
            baseURL: config.baseURL,
            model: config.model,
            temperature: 0,
            maxTokens: config.maxTokens
        )
    }
}
