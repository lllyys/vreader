// Purpose: Tests for ProviderProfileStore actor (feature #50 WI-2).
// Verifies:
//   - empty-load returns []
//   - save+loadAll round-trips
//   - setActiveProfileID + activeProfile correctness
//   - remove(id:) clears activeID if it referenced removed profile
//   - concurrency stress (round-1 audit finding [4])
//   - snapshot semantics (round-1 audit finding [6])
//   - shared-instance contract (round-2 audit finding [2])

import Testing
import Foundation
@testable import vreader

@Suite("ProviderProfileStore")
struct ProviderProfileStoreTests {

    /// Builds a store backed by per-test mock preferences + keychain. Each
    /// call returns a fresh, isolated instance so tests don't pollute each
    /// other or `.shared`.
    private static func makeStore() -> (ProviderProfileStore, MockPreferenceStore, KeychainService) {
        let preferences = MockPreferenceStore()
        let keychain = KeychainService(serviceIdentifier: "com.vreader.tests.\(UUID().uuidString)")
        let store = ProviderProfileStore(
            preferences: preferences,
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )
        return (store, preferences, keychain)
    }

    private static func makeProfile(
        id: UUID = UUID(),
        kind: ProviderKind = .openAICompatible,
        name: String = "Test"
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

    // MARK: - Empty load

    @Test func emptyLoad_returnsEmptyList() async {
        let (store, _, _) = Self.makeStore()
        let profiles = await store.loadAll()
        #expect(profiles.isEmpty)
        let active = await store.activeProfile()
        #expect(active == nil)
    }

    // MARK: - Save + load round-trip

    @Test func upsertNewProfile_thenLoadAll_roundTrips() async {
        let (store, _, _) = Self.makeStore()
        let profile = Self.makeProfile(name: "MyOpenAI")
        await store.upsert(profile)

        let loaded = await store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first == profile)
    }

    @Test func upsertExistingID_replacesProfile() async {
        let (store, _, _) = Self.makeStore()
        let id = UUID()
        let original = Self.makeProfile(id: id, name: "Original")
        await store.upsert(original)

        var modified = original
        modified.name = "Renamed"
        modified.model = "gpt-4o"
        await store.upsert(modified)

        let loaded = await store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == id)
        #expect(loaded.first?.name == "Renamed")
        #expect(loaded.first?.model == "gpt-4o")
    }

    // MARK: - setActiveProfileID + activeProfile

    @Test func setActiveProfileID_returnsViaActiveProfile() async {
        let (store, _, _) = Self.makeStore()
        let a = Self.makeProfile(name: "A")
        let b = Self.makeProfile(name: "B")
        await store.upsert(a)
        await store.upsert(b)

        await store.setActiveProfileID(b.id)
        let active = await store.activeProfile()
        #expect(active?.id == b.id)
        #expect(active?.name == "B")
    }

    @Test func setActiveProfileID_nil_clearsActive() async {
        let (store, _, _) = Self.makeStore()
        let a = Self.makeProfile(name: "A")
        await store.upsert(a)
        await store.setActiveProfileID(a.id)

        await store.setActiveProfileID(nil)
        #expect(await store.activeProfile() == nil)
    }

    @Test func setActiveProfileID_unknownID_doesNotCrash() async {
        let (store, _, _) = Self.makeStore()
        let unknownID = UUID()
        await store.setActiveProfileID(unknownID)
        // activeProfile() should return nil because the unknown ID doesn't
        // resolve to a profile, even though activeProfileID was set.
        let active = await store.activeProfile()
        #expect(active == nil)
    }

    // MARK: - remove(id:)

    @Test func removeProfile_clearsActiveIDIfReferenced() async {
        let (store, _, _) = Self.makeStore()
        let a = Self.makeProfile(name: "A")
        let b = Self.makeProfile(name: "B")
        await store.upsert(a)
        await store.upsert(b)
        await store.setActiveProfileID(a.id)

        await store.remove(id: a.id)

        let remaining = await store.loadAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == b.id)

        // Active was a; after removing a, active should clear (or shift —
        // contract is "clear" per the plan).
        let active = await store.activeProfile()
        #expect(active == nil)
    }

    @Test func removeProfile_doesNotChangeActiveIfDifferent() async {
        let (store, _, _) = Self.makeStore()
        let a = Self.makeProfile(name: "A")
        let b = Self.makeProfile(name: "B")
        await store.upsert(a)
        await store.upsert(b)
        await store.setActiveProfileID(a.id)

        await store.remove(id: b.id)

        let active = await store.activeProfile()
        #expect(active?.id == a.id)
    }

    // MARK: - Snapshot semantics (round-1 audit finding [6])

    @Test func activeProfileSnapshot_returnsByValue_independentOfStore() async {
        let (store, _, _) = Self.makeStore()
        let id = UUID()
        let profile = Self.makeProfile(id: id, name: "Original")
        await store.upsert(profile)
        await store.setActiveProfileID(id)

        let snapshot = await store.activeProfileSnapshot()
        #expect(snapshot?.name == "Original")

        // Mutate the store's record post-snapshot.
        var renamed = profile
        renamed.name = "Renamed"
        await store.upsert(renamed)

        // Snapshot stays as-was — by-value semantics.
        #expect(snapshot?.name == "Original")
    }

    @Test func activeProfileSnapshot_unaffectedByRemove() async {
        let (store, _, _) = Self.makeStore()
        let id = UUID()
        let profile = Self.makeProfile(id: id, name: "Will be removed")
        await store.upsert(profile)
        await store.setActiveProfileID(id)

        let snapshot = await store.activeProfileSnapshot()

        await store.remove(id: id)

        // Snapshot survives even after the profile is gone.
        #expect(snapshot?.id == id)
        #expect(snapshot?.name == "Will be removed")
    }

    // MARK: - Concurrency stress (round-1 audit finding [4])

    @Test func concurrentUpserts_allLandWithoutLoss() async {
        let (store, _, _) = Self.makeStore()
        let profileCount = 20
        let profiles = (0..<profileCount).map { i in
            Self.makeProfile(name: "P\(i)")
        }

        // Spawn N concurrent upserts.
        await withTaskGroup(of: Void.self) { group in
            for profile in profiles {
                group.addTask {
                    await store.upsert(profile)
                }
            }
        }

        let loaded = await store.loadAll()
        #expect(loaded.count == profileCount)
        let loadedIDs = Set(loaded.map(\.id))
        let expectedIDs = Set(profiles.map(\.id))
        #expect(loadedIDs == expectedIDs)
    }

    // MARK: - Shared-instance contract (round-2 audit finding [2])

    @Test func sharedInstance_isIdentitySameAcrossCalls() async {
        let a = ProviderProfileStore.shared
        let b = ProviderProfileStore.shared
        #expect(ObjectIdentifier(a) == ObjectIdentifier(b))
    }

    @Test func customInitInstances_areDistinctFromShared() async {
        let custom = Self.makeStore().0
        let shared = ProviderProfileStore.shared
        #expect(ObjectIdentifier(custom) != ObjectIdentifier(shared))
    }

    // MARK: - Migration runs lazily on first read (round-1 audit finding [1])

    @Test func loadAll_triggersLazyMigration() async throws {
        let preferences = MockPreferenceStore()
        let keychain = KeychainService(serviceIdentifier: "com.vreader.tests.\(UUID().uuidString)")

        // Seed legacy data BEFORE constructing the store.
        let legacy = AIConfigurationStore(preferences: preferences)
        legacy.save(AIConfiguration(
            model: "gpt-4o", temperature: 0.5,
            endpoint: URL(string: "https://api.openai.com/v1")!, maxTokens: 4096
        ))
        try keychain.saveString("sk-legacy", forAccount: AIService.apiKeyAccount)

        let store = ProviderProfileStore(
            preferences: preferences,
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )

        // First read triggers migration. Profile list goes from empty to one.
        let profiles = await store.loadAll()
        defer { for p in profiles { try? keychain.deleteAPIKey(forProfile: p.id) } }
        #expect(profiles.count == 1)
        #expect(profiles.first?.kind == .openAICompatible)
        #expect(profiles.first?.model == "gpt-4o")
    }

    @Test func activeProfileSnapshot_alsoTriggersLazyMigration() async throws {
        let preferences = MockPreferenceStore()
        let keychain = KeychainService(serviceIdentifier: "com.vreader.tests.\(UUID().uuidString)")

        let legacy = AIConfigurationStore(preferences: preferences)
        legacy.save(AIConfiguration(
            model: "gpt-4o-mini", temperature: 0.7,
            endpoint: URL(string: "https://api.openai.com/v1")!, maxTokens: 2048
        ))
        try keychain.saveString("sk-legacy-2", forAccount: AIService.apiKeyAccount)

        let store = ProviderProfileStore(
            preferences: preferences,
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )

        // First call: activeProfileSnapshot triggers migration which sets
        // active to the migrated profile.
        let snapshot = await store.activeProfileSnapshot()
        defer {
            if let id = snapshot?.id {
                try? keychain.deleteAPIKey(forProfile: id)
            }
        }
        #expect(snapshot != nil)
        #expect(snapshot?.kind == .openAICompatible)
    }
}
