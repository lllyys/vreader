// Purpose: Tests for AIService's provider dispatch on the active
// ProviderProfile (feature #50 WI-5).
//
// Coverage targets from the plan's test catalogue:
//   - active profile of kind .openAICompatible → OpenAICompatibleProvider
//     with snapshot baseURL/model/apiKey
//   - active profile of kind .anthropicNative → AnthropicProvider
//     with snapshot baseURL/model/apiKey/maxTokens
//   - snapshot semantics: mutate active profile mid-stream, stream
//     continues with the original snapshot
//   - no active profile → AIError.providerError("Configure a provider in Settings.")
//   - active profile but missing keychain key → AIError.apiKeyMissing
//   - per-profile keychain account read correctly
//   - shared-instance contract: tests construct a non-`.shared` store
//     (round-3 audit finding [1])
//
// All tests construct a non-`.shared` `ProviderProfileStore` via the
// `init(preferences:migrator:keychain:)` test seam, with a fresh
// MockPreferenceStore + fresh KeychainService (unique service identifier
// per test) to avoid cross-test state leakage.
//
// @coordinates-with: AIService.swift, ProviderProfileStore.swift,
//   ProviderProfile.swift, WI11TestHelpers.swift

import Testing
import Foundation
@testable import vreader

@Suite("AIService — provider dispatch (WI-5)")
struct AIServiceProfileDispatchTests {

    // MARK: - Test infrastructure

    /// Builds a non-`.shared` ProviderProfileStore with fresh in-memory
    /// preferences and a fresh keychain. Per the test isolation contract
    /// (Gate-2 round-3 audit finding [1]), tests MUST NOT touch
    /// `ProviderProfileStore.shared`.
    private static func makeTestStore() -> (
        store: ProviderProfileStore,
        keychain: KeychainService
    ) {
        let prefs = MockPreferenceStore()
        let keychain = KeychainService(
            serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"
        )
        // Bypass migration so the store starts empty and predictable.
        // We seed profiles explicitly via `upsert` per-test.
        prefs.set("true", forKey: DefaultProviderProfileMigrator.migrationFlagKey)
        let store = ProviderProfileStore(
            preferences: prefs,
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )
        return (store, keychain)
    }

    private static func makeOpenAIProfile() -> ProviderProfile {
        ProviderProfile(
            id: UUID(),
            name: "Test OpenAI",
            kind: .openAICompatible,
            baseURL: URL(string: "https://api.test.openai.example.com/v1")!,
            model: "gpt-test-1",
            temperature: 0.5,
            maxTokens: 1234
        )
    }

    private static func makeAnthropicProfile() -> ProviderProfile {
        ProviderProfile(
            id: UUID(),
            name: "Test Anthropic",
            kind: .anthropicNative,
            baseURL: URL(string: "https://api.test.anthropic.example.com")!,
            model: "claude-test-1",
            temperature: 0.7,
            maxTokens: 4321
        )
    }

    private static func makeService(
        store: ProviderProfileStore,
        keychain: KeychainService,
        providerFactory: (@Sendable (ProviderProfile, String) -> any AIProvider)? = nil
    ) -> AIService {
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        return AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: keychain,
            providerFactory: providerFactory,
            profileStore: store
        )
    }

    // MARK: - Dispatch — OpenAI compatible

    @Test func openAICompatibleProfile_yieldsOpenAIProvider_withSnapshotFields() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-test-openai", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain)
        let resolved = try await service.resolveProvider()

        // The concrete type must be the OpenAI-compatible provider.
        let openAI = resolved as? OpenAICompatibleProvider
        #expect(openAI != nil, "Expected OpenAICompatibleProvider, got \(type(of: resolved))")
        #expect(openAI?.baseURL == profile.baseURL)
        #expect(openAI?.model == profile.model)
        #expect(openAI?.apiKey == "sk-test-openai")
    }

    // MARK: - Dispatch — Anthropic native

    @Test func anthropicNativeProfile_yieldsAnthropicProvider_withSnapshotFields() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeAnthropicProfile()
        try keychain.saveAPIKey("sk-ant-test", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain)
        let resolved = try await service.resolveProvider()

        let anthropic = resolved as? AnthropicProvider
        #expect(anthropic != nil, "Expected AnthropicProvider, got \(type(of: resolved))")
        #expect(anthropic?.baseURL == profile.baseURL)
        #expect(anthropic?.model == profile.model)
        #expect(anthropic?.apiKey == "sk-ant-test")
        #expect(anthropic?.maxTokens == profile.maxTokens)
    }

    // MARK: - No active profile

    @Test func noActiveProfile_throwsProviderError() async throws {
        let (store, keychain) = Self.makeTestStore()
        // Empty store — no profiles, no active id.
        let service = Self.makeService(store: store, keychain: keychain)

        do {
            _ = try await service.resolveProvider()
            #expect(Bool(false), "expected providerError")
        } catch let error as AIError {
            #expect(error == .providerError("Configure a provider in Settings."))
        }
    }

    @Test func profileExistsButNoneActive_throwsProviderError() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-test", forProfile: profile.id)
        await store.upsert(profile)
        // Deliberately do NOT call setActiveProfileID.

        let service = Self.makeService(store: store, keychain: keychain)

        do {
            _ = try await service.resolveProvider()
            #expect(Bool(false), "expected providerError when no active profile")
        } catch let error as AIError {
            #expect(error == .providerError("Configure a provider in Settings."))
        }
    }

    // MARK: - Active profile but missing API key

    @Test func activeProfileNoKey_throwsApiKeyMissing() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        // No keychain entry written.
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain)

        do {
            _ = try await service.resolveProvider()
            #expect(Bool(false), "expected apiKeyMissing")
        } catch let error as AIError {
            #expect(error == .apiKeyMissing)
        }
    }

    @Test func activeProfileEmptyKey_throwsApiKeyMissing() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("", forProfile: profile.id)  // empty string
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain)

        do {
            _ = try await service.resolveProvider()
            #expect(Bool(false), "expected apiKeyMissing on empty key")
        } catch let error as AIError {
            #expect(error == .apiKeyMissing)
        }
    }

    // MARK: - Per-profile keychain account isolation

    @Test func perProfileKeychainAccountsIsolated() async throws {
        let (store, keychain) = Self.makeTestStore()
        let openAI = Self.makeOpenAIProfile()
        let anthropic = Self.makeAnthropicProfile()
        try keychain.saveAPIKey("sk-openai-only", forProfile: openAI.id)
        try keychain.saveAPIKey("sk-ant-only",    forProfile: anthropic.id)
        await store.upsert(openAI)
        await store.upsert(anthropic)

        // Activate OpenAI first → must read OpenAI's key.
        await store.setActiveProfileID(openAI.id)
        let svc1 = Self.makeService(store: store, keychain: keychain)
        let r1 = try await svc1.resolveProvider() as? OpenAICompatibleProvider
        #expect(r1?.apiKey == "sk-openai-only")

        // Activate Anthropic → must read Anthropic's key (not OpenAI's).
        await store.setActiveProfileID(anthropic.id)
        let svc2 = Self.makeService(store: store, keychain: keychain)
        let r2 = try await svc2.resolveProvider() as? AnthropicProvider
        #expect(r2?.apiKey == "sk-ant-only")
    }

    // MARK: - providerFactory injection (test seam)

    @Test func providerFactory_receivesSnapshotAndKey() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeOpenAIProfile()
        try keychain.saveAPIKey("sk-factory-test", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        // Capture-box for what the factory sees.
        //
        // The factory closure is invoked SYNCHRONOUSLY inside
        // `AIService.resolveProvider()`. Once `try await resolveProvider`
        // returns, the actor has hopped back out and the box is safe to
        // read from the test thread — no concurrent access, so no timing
        // assumption (Gate-4 round-1 finding [2]).
        final class Inbox: @unchecked Sendable {
            var seenProfile: ProviderProfile?
            var seenKey: String?
        }
        let inbox = Inbox()
        let stub = StubAIProvider()

        let factory: @Sendable (ProviderProfile, String) -> any AIProvider = { p, k in
            inbox.seenProfile = p
            inbox.seenKey = k
            return stub
        }

        let service = Self.makeService(
            store: store, keychain: keychain, providerFactory: factory
        )
        _ = try await service.resolveProvider()

        #expect(inbox.seenProfile?.id == profile.id)
        #expect(inbox.seenProfile?.kind == .openAICompatible)
        #expect(inbox.seenProfile?.baseURL == profile.baseURL)
        #expect(inbox.seenKey == "sk-factory-test")
    }

    // MARK: - Snapshot semantics: in-flight stream survives profile change

    @Test func snapshotSurvivesMidFlightProfileSwap() async throws {
        let (store, keychain) = Self.makeTestStore()
        let original = Self.makeOpenAIProfile()
        let replacement = Self.makeAnthropicProfile()
        try keychain.saveAPIKey("sk-original",    forProfile: original.id)
        try keychain.saveAPIKey("sk-replacement", forProfile: replacement.id)
        await store.upsert(original)
        await store.upsert(replacement)
        await store.setActiveProfileID(original.id)

        let service = Self.makeService(store: store, keychain: keychain)

        // Snapshot at request 1 sees the OpenAI profile.
        let r1 = try await service.resolveProvider() as? OpenAICompatibleProvider
        #expect(r1?.apiKey == "sk-original")

        // Swap active profile.
        await store.setActiveProfileID(replacement.id)

        // r1 — already resolved — keeps its snapshot. The snapshot was
        // taken by-value, so the by-reference store change can't affect
        // an already-resolved struct. (This test asserts the contract;
        // ProviderProfileStoreTests.swift covers the store-side
        // immutability of snapshots more directly.)
        #expect(r1?.apiKey == "sk-original",
                "Already-resolved provider must keep its original snapshot")

        // A NEW request, however, must see the new active profile.
        let r2 = try await service.resolveProvider() as? AnthropicProvider
        #expect(r2?.apiKey == "sk-replacement")
    }

    // MARK: - Deleted active profile mid-flight

    @Test func deleteActiveProfileMidFlight_doesNotAffectAlreadyResolved() async throws {
        let (store, keychain) = Self.makeTestStore()
        let profile = Self.makeAnthropicProfile()
        try keychain.saveAPIKey("sk-doomed", forProfile: profile.id)
        await store.upsert(profile)
        await store.setActiveProfileID(profile.id)

        let service = Self.makeService(store: store, keychain: keychain)
        let resolved = try await service.resolveProvider() as? AnthropicProvider
        #expect(resolved?.apiKey == "sk-doomed")

        // Delete the profile that was just resolved.
        await store.remove(id: profile.id)

        // Already-resolved provider keeps its snapshot fields — the
        // struct is by-value and doesn't reference the store.
        #expect(resolved?.apiKey == "sk-doomed")
        #expect(resolved?.baseURL == profile.baseURL)

        // A NEW request would now fail with no active profile.
        do {
            _ = try await service.resolveProvider()
            #expect(Bool(false), "expected providerError after delete")
        } catch let error as AIError {
            #expect(error == .providerError("Configure a provider in Settings."))
        }
    }

    // MARK: - Pre-built provider short-circuits dispatch (existing contract)

    @Test func preBuiltProviderShortCircuits_profileStoreUntouched() async throws {
        // If `provider:` is passed (legacy test pattern), resolveProvider
        // must return it without consulting the store or keychain — so a
        // service constructed with `provider:` works even with an empty
        // store. This preserves the existing test surface.
        let (store, keychain) = Self.makeTestStore()
        // Empty store + empty keychain.
        let stub = StubAIProvider()

        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(true, for: .aiAssistant)
        let service = AIService(
            featureFlags: flags,
            consentManager: WI11TestHelpers.makeConsentManager(hasConsent: true),
            keychainService: keychain,
            provider: stub,
            profileStore: store
        )

        let resolved = try await service.resolveProvider()
        #expect((resolved as? StubAIProvider) === stub)
    }
}
