// Purpose: Tests for AISettingsViewModel's multi-profile list operations
// (feature #50 WI-6a) — loadProfiles, setActive, deleteProfile, and the
// `profiles` / `activeID` published state. Editor-side operations
// (addProfile, updateProfile, saveAPIKey, testConnection) land in WI-6b.
//
// Each test builds a fresh `ProviderProfileStore` backed by per-test
// `MockPreferenceStore` + isolated `KeychainService` (a unique
// `serviceIdentifier`) so the suite never touches `.shared` and parallel
// runs don't interfere.
//
// @coordinates-with: AISettingsViewModel.swift, ProviderProfileStore.swift,
//   ProviderProfile.swift, KeychainService+ProviderProfile.swift

import Testing
import Foundation
@testable import vreader

@Suite("AISettingsViewModel multi-profile list")
struct AISettingsViewModelMultiProfileTests {

    // MARK: - Helpers

    private static func makeIsolatedDeps() -> (FeatureFlags, AIConsentManager, KeychainService, ProviderProfileStore, MockPreferenceStore) {
        let flags = FeatureFlags(environment: .prod)
        let consentDefaults = UserDefaults(
            suiteName: "com.vreader.test.consent.\(UUID().uuidString)"
        )!
        let consent = AIConsentManager(defaults: consentDefaults)
        let keychain = KeychainService(
            serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"
        )
        let preferences = MockPreferenceStore()
        let store = ProviderProfileStore(
            preferences: preferences,
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )
        return (flags, consent, keychain, store, preferences)
    }

    @MainActor
    private static func makeVM(
        store: ProviderProfileStore,
        flags: FeatureFlags,
        consent: AIConsentManager,
        keychain: KeychainService
    ) -> AISettingsViewModel {
        AISettingsViewModel(
            featureFlags: flags,
            consentManager: consent,
            keychainService: keychain,
            profileStore: store
        )
    }

    private static func makeProfile(
        id: UUID = UUID(),
        name: String = "OpenAI",
        kind: ProviderKind = .openAICompatible
    ) -> ProviderProfile {
        ProviderProfile(
            id: id,
            name: name,
            kind: kind,
            baseURL: kind.defaultBaseURL,
            model: kind.defaultModel,
            temperature: 0.7,
            maxTokens: 2048
        )
    }

    // MARK: - loadProfiles

    @Test @MainActor func loadProfiles_emptyStore_yieldsEmptyListAndNoActive() async {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)

        await vm.loadProfiles()

        #expect(vm.profiles.isEmpty)
        #expect(vm.activeID == nil)
        #expect(vm.listError == nil)
    }

    @Test @MainActor func loadProfiles_storeHasProfiles_populatesListAndActiveID() async {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let a = Self.makeProfile(name: "A")
        let b = Self.makeProfile(name: "B", kind: .anthropicNative)
        await store.upsert(a)
        await store.upsert(b)
        await store.setActiveProfileID(b.id)

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()

        #expect(vm.profiles.count == 2)
        #expect(vm.profiles.contains(where: { $0.id == a.id }))
        #expect(vm.profiles.contains(where: { $0.id == b.id }))
        #expect(vm.activeID == b.id)
    }

    @Test @MainActor func loadProfiles_isIdempotent_canBeCalledRepeatedly() async {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let p = Self.makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()
        let firstCount = vm.profiles.count
        await vm.loadProfiles()
        await vm.loadProfiles()

        #expect(vm.profiles.count == firstCount)
        #expect(vm.activeID == p.id)
    }

    // MARK: - setActive

    @Test @MainActor func setActive_changesActiveID_andPersistsToStore() async {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let a = Self.makeProfile(name: "A")
        let b = Self.makeProfile(name: "B")
        await store.upsert(a)
        await store.upsert(b)
        await store.setActiveProfileID(a.id)

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()
        #expect(vm.activeID == a.id)

        await vm.setActive(b.id)
        #expect(vm.activeID == b.id)
        // Confirm via the store directly (not just the VM's mirror).
        let storeActive = await store.activeProfile()
        #expect(storeActive?.id == b.id)
    }

    /// Round-2 audit finding [1]: the round-1 dangling-id defense in
    /// `setActive(_:)` rejects ids that aren't in the currently-loaded
    /// `profiles` list. The underlying `ProviderProfileStore` still
    /// accepts unknown ids (so the round-1 fix is vulnerable to silent
    /// regression). Pin the VM-level contract directly: passing an
    /// unknown UUID must leave both the VM mirror AND the store's
    /// authoritative active selection unchanged.
    @Test @MainActor func setActive_unknownID_isIgnored_andDoesNotMutateStore() async {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let known = Self.makeProfile(name: "Known")
        await store.upsert(known)
        await store.setActiveProfileID(known.id)

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()
        #expect(vm.activeID == known.id)

        await vm.setActive(UUID()) // not in profiles list

        #expect(vm.activeID == known.id, "VM must not adopt an id that isn't in its rendered list")
        let storeActive = await store.activeProfile()
        #expect(storeActive?.id == known.id, "Store's active selection must not be mutated by an unknown-id setActive")
    }

    @Test @MainActor func setActive_nilClearsActive_andPersists() async {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let p = Self.makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()

        await vm.setActive(nil)
        #expect(vm.activeID == nil)
        let storeActive = await store.activeProfile()
        #expect(storeActive == nil)
    }

    // MARK: - deleteProfile

    @Test @MainActor func deleteProfile_removesFromList_andClearsKeychain() async throws {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let p = Self.makeProfile(name: "ToDelete")
        await store.upsert(p)
        try keychain.saveAPIKey("secret-key-123", forProfile: p.id)
        #expect(try keychain.readAPIKey(forProfile: p.id) == "secret-key-123")

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()

        await vm.deleteProfile(p.id)

        #expect(vm.profiles.isEmpty)
        let storeProfiles = await store.loadAll()
        #expect(storeProfiles.isEmpty, "Store must reflect the deletion")
        #expect(try keychain.readAPIKey(forProfile: p.id) == nil, "Keychain entry must be cleared")
    }

    @Test @MainActor func deleteProfile_whenActive_clearsActiveID() async {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let p = Self.makeProfile(name: "ActiveOne")
        await store.upsert(p)
        await store.setActiveProfileID(p.id)

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()
        #expect(vm.activeID == p.id)

        await vm.deleteProfile(p.id)
        #expect(vm.activeID == nil)
    }

    @Test @MainActor func deleteProfile_whenNotActive_leavesActiveAlone() async {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let a = Self.makeProfile(name: "Keeper")
        let b = Self.makeProfile(name: "GoingAway")
        await store.upsert(a)
        await store.upsert(b)
        await store.setActiveProfileID(a.id)

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()

        await vm.deleteProfile(b.id)

        #expect(vm.profiles.count == 1)
        #expect(vm.profiles.first?.id == a.id)
        #expect(vm.activeID == a.id, "Deleting a non-active profile must not disturb the active selection")
    }

    @Test @MainActor func deleteProfile_unknownID_isIdempotent_noListErrorRaised() async {
        let (flags, consent, keychain, store, _) = Self.makeIsolatedDeps()
        let p = Self.makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()

        await vm.deleteProfile(UUID()) // unknown id

        #expect(vm.profiles.count == 1, "Profile list must be unchanged when deleting an unknown id")
        #expect(vm.activeID == p.id)
        #expect(vm.listError == nil, "An unknown-id delete must NOT surface a user-facing error")
    }

    // MARK: - Lazy migration on first load

    /// Per the store's lazy-migration contract: the FIRST loadAll() on a
    /// preference store that holds legacy AIConfiguration data must trigger
    /// the migration so the VM picks up the migrated profile transparently.
    ///
    /// Round-1 audit finding [3]: previous version only asserted
    /// `vm.profiles.count == storeProfiles.count`, which would also pass
    /// if both ended up empty or if the migrated profile had the wrong
    /// fields. Pin the actual contract — exactly one profile,
    /// `.openAICompatible` kind, fields copied verbatim from the legacy
    /// AIConfiguration, the migrated profile is set active, and the
    /// legacy API key (if any was stored) is copied to the per-profile
    /// keychain account.
    @Test @MainActor func loadProfiles_triggersLegacyMigration_onFirstReadFromLegacyStore() async throws {
        let (flags, consent, keychain, store, preferences) = Self.makeIsolatedDeps()

        // Seed legacy AIConfiguration in the same preference store the
        // ProviderProfileStore is reading from. The migrator reads from
        // the same UserDefaults/preferences instance per its contract.
        let legacyEndpoint = URL(string: "https://api.openai.com/v1")!
        let legacyConfig = AIConfiguration(
            model: "gpt-4o-mini",
            temperature: 0.5,
            endpoint: legacyEndpoint,
            maxTokens: 4096
        )
        let legacyStore = AIConfigurationStore(preferences: preferences)
        legacyStore.save(legacyConfig)

        // Seed the legacy API key under the original (non-per-profile)
        // keychain account so we can verify the migrator copied it.
        try keychain.saveString("sk-legacy-key-abc123", forAccount: AIService.apiKeyAccount)

        let vm = Self.makeVM(store: store, flags: flags, consent: consent, keychain: keychain)
        await vm.loadProfiles()

        // Contract: exactly one migrated profile, fields verbatim, kind
        // is .openAICompatible (the legacy single-config was always
        // OpenAI-shaped), and it is set active.
        #expect(vm.profiles.count == 1, "Migration must produce exactly one profile from a single legacy config")
        let migrated = try #require(vm.profiles.first)
        #expect(migrated.kind == .openAICompatible, "Legacy AIConfiguration is OpenAI-shaped; migrated profile must be .openAICompatible")
        #expect(migrated.model == "gpt-4o-mini")
        #expect(migrated.baseURL == legacyEndpoint)
        #expect(migrated.temperature == 0.5)
        #expect(migrated.maxTokens == 4096)
        #expect(vm.activeID == migrated.id, "Migrated profile must be set active so existing users don't see 'No active provider' on first launch")

        // API key was copied to per-profile keychain account; legacy
        // account may or may not be cleared (migrator behavior), but the
        // per-profile read MUST succeed with the migrated key.
        let perProfileKey = try keychain.readAPIKey(forProfile: migrated.id)
        #expect(perProfileKey == "sk-legacy-key-abc123", "Legacy API key must be copied to the new per-profile keychain account")
    }
}
