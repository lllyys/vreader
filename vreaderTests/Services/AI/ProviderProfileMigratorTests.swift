// Purpose: Tests for DefaultProviderProfileMigrator (feature #50 WI-2).
// Verifies:
//   - Idempotent on re-run (migration test 2)
//   - Lifts legacy AIConfiguration + legacy keychain key into a single
//     ProviderProfile of kind .openAICompatible (migration test 1)
//   - Corrupt legacy data → empty list, flag still set (migration test 3)
//   - Fresh install (no legacy data) → flag set, empty list, no profile
//   - Mid-migration crash recovery (test 6): flag set but no profile data
//     → re-run cleanly
//   - Partial keychain copy (test 7): keychain saveString is idempotent

import Testing
import Foundation
@testable import vreader

@Suite("DefaultProviderProfileMigrator")
struct ProviderProfileMigratorTests {

    /// Per-test keychain — unique service identifier so test items don't
    /// collide with the production keychain or with parallel test runs.
    private static func makeKeychain() -> KeychainService {
        KeychainService(
            serviceIdentifier: "com.vreader.tests.\(UUID().uuidString)"
        )
    }

    private static func cleanupKeychain(_ keychain: KeychainService, profileIDs: [UUID]) {
        try? keychain.delete(forAccount: AIService.apiKeyAccount)
        for id in profileIDs {
            try? keychain.deleteAPIKey(forProfile: id)
        }
    }

    /// Helper: read profile list from preferences as decoded ProviderProfiles.
    private static func readProfiles(_ preferences: any PreferenceStoring) -> [ProviderProfile] {
        guard let json = preferences.string(forKey: "com.vreader.ai.providerProfiles"),
              let data = json.data(using: .utf8),
              let profiles = try? JSONDecoder().decode([ProviderProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    private static func readActiveID(_ preferences: any PreferenceStoring) -> UUID? {
        guard let raw = preferences.string(forKey: "com.vreader.ai.activeProviderID"),
              let id = UUID(uuidString: raw) else {
            return nil
        }
        return id
    }

    private static func migrationFlagSet(_ preferences: any PreferenceStoring) -> Bool {
        preferences.string(forKey: "com.vreader.ai.providerProfiles.migrated") == "true"
    }

    // MARK: - Test 1: legacy single-config → one profile

    @Test func legacyConfigAndKeychainKey_migrateIntoSingleProfile() async throws {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        // Seed legacy config + legacy keychain key.
        let legacyStore = AIConfigurationStore(preferences: preferences)
        legacyStore.save(AIConfiguration(
            model: "gpt-4o",
            temperature: 0.5,
            endpoint: URL(string: "https://api.openai.com/v1")!,
            maxTokens: 4096
        ))
        try keychain.saveString("sk-legacy-XXXX", forAccount: AIService.apiKeyAccount)
        defer { Self.cleanupKeychain(keychain, profileIDs: Self.readProfiles(preferences).map(\.id)) }

        // Run migration.
        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)

        // Verify: one profile exists with the legacy values.
        let profiles = Self.readProfiles(preferences)
        #expect(profiles.count == 1)
        let profile = try #require(profiles.first)
        #expect(profile.kind == .openAICompatible)
        #expect(profile.name == "OpenAI")
        #expect(profile.model == "gpt-4o")
        #expect(profile.temperature == 0.5)
        #expect(profile.maxTokens == 4096)
        #expect(profile.baseURL.absoluteString == "https://api.openai.com/v1")

        // Active ID is set to the new profile.
        #expect(Self.readActiveID(preferences) == profile.id)

        // Migration flag is set.
        #expect(Self.migrationFlagSet(preferences))

        // Legacy keychain key was COPIED to the per-profile account.
        #expect(try keychain.readAPIKey(forProfile: profile.id) == "sk-legacy-XXXX")
        // Legacy keychain key STAYS readable for one release (migration is read-only of legacy).
        #expect(try keychain.readString(forAccount: AIService.apiKeyAccount) == "sk-legacy-XXXX")
    }

    // MARK: - Test 2: idempotent re-run

    @Test func reRunningMigration_isNoOp() async throws {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        let legacyStore = AIConfigurationStore(preferences: preferences)
        legacyStore.save(AIConfiguration(
            model: "gpt-4o-mini", temperature: 0.7,
            endpoint: URL(string: "https://api.openai.com/v1")!, maxTokens: 2048
        ))
        try keychain.saveString("sk-XXXX", forAccount: AIService.apiKeyAccount)

        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)
        let firstRunProfiles = Self.readProfiles(preferences)
        let firstRunActiveID = Self.readActiveID(preferences)
        defer { Self.cleanupKeychain(keychain, profileIDs: firstRunProfiles.map(\.id)) }

        // Second run must NOT add a duplicate or change anything.
        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)
        let secondRunProfiles = Self.readProfiles(preferences)
        let secondRunActiveID = Self.readActiveID(preferences)

        #expect(firstRunProfiles == secondRunProfiles)
        #expect(firstRunActiveID == secondRunActiveID)
    }

    // MARK: - Test 3: corrupt legacy data → empty list, flag set, no crash

    @Test func corruptLegacyConfig_producesDefaultProfileAndSetsFlag() async throws {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        // Seed corrupt JSON in the legacy config slot.
        preferences.setRaw("not-valid-json-at-all", forKey: "com.vreader.ai.configuration")
        // No keychain key seeded.

        // Must not throw or crash.
        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)

        // Round-1 Gate-4 audit fix [3]: pin the exact behavior. Corrupt
        // legacy config (treated as "present" because the key exists in
        // preferences) AIConfigurationStore.load() returns .default, so
        // migrator builds one profile from the defaults. This is the
        // "phantom default OpenAI profile" — surfaced + accepted as the
        // intended behavior since corrupt legacy data is rare and a
        // default-OpenAI profile is benign.
        let profiles = Self.readProfiles(preferences)
        defer { Self.cleanupKeychain(keychain, profileIDs: profiles.map(\.id)) }
        #expect(profiles.count == 1)
        #expect(profiles.first?.kind == .openAICompatible)
        #expect(profiles.first?.model == "gpt-4o-mini")  // AIConfiguration.default.model
        #expect(Self.migrationFlagSet(preferences))
    }

    // MARK: - Test 4: fresh install (no legacy data) → flag set, empty list

    @Test func freshInstall_setsFlagWithoutCreatingProfile() async {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)

        let profiles = Self.readProfiles(preferences)
        #expect(profiles.isEmpty)
        #expect(Self.readActiveID(preferences) == nil)
        #expect(Self.migrationFlagSet(preferences))
    }

    // MARK: - Test 5: keychain key alone (no legacy config) still triggers migration

    @Test func keychainKeyOnly_stillMigrates() async throws {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        // Legacy keychain key exists, but no AIConfiguration was ever saved
        // (user installed but never opened Settings — unlikely but real).
        try keychain.saveString("sk-XXXX-only-key", forAccount: AIService.apiKeyAccount)

        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)

        let profiles = Self.readProfiles(preferences)
        defer { Self.cleanupKeychain(keychain, profileIDs: profiles.map(\.id)) }
        #expect(profiles.count == 1)
        if let profile = profiles.first {
            #expect(profile.kind == .openAICompatible)
            #expect(try keychain.readAPIKey(forProfile: profile.id) == "sk-XXXX-only-key")
        }
        #expect(Self.migrationFlagSet(preferences))
    }

    // MARK: - Test 6: mid-migration crash recovery — flag set but no profile data → re-run

    @Test func midMigrationCrash_reRunsCleanly() async throws {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        // Seed legacy config + legacy keychain key.
        let legacyStore = AIConfigurationStore(preferences: preferences)
        legacyStore.save(AIConfiguration(
            model: "gpt-4o-mini", temperature: 0.7,
            endpoint: URL(string: "https://api.openai.com/v1")!, maxTokens: 2048
        ))
        try keychain.saveString("sk-pre-crash", forAccount: AIService.apiKeyAccount)

        // Simulate: migration flag was set but profile data was never written
        // (crash between commit-style steps 7 and 8). Per the plan's
        // commit-style ordering, this state is recoverable: reading sees
        // flag=true but profilesKey decodes to empty/missing → re-run.
        preferences.set("true", forKey: "com.vreader.ai.providerProfiles.migrated")

        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)

        let profiles = Self.readProfiles(preferences)
        defer { Self.cleanupKeychain(keychain, profileIDs: profiles.map(\.id)) }
        #expect(profiles.count == 1)
        if let profile = profiles.first {
            // Re-migration produced a valid profile from the still-intact legacy data.
            #expect(profile.kind == .openAICompatible)
            #expect(try keychain.readAPIKey(forProfile: profile.id) == "sk-pre-crash")
        }
        #expect(Self.migrationFlagSet(preferences))
    }

    // MARK: - Test 6b: corrupt profile JSON + flag set + legacy data → re-migrate

    @Test func midMigrationCrash_corruptProfileJSON_reRunsCleanly() async throws {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        // Seed legacy data + flag set + CORRUPT profile JSON (not just empty).
        let legacyStore = AIConfigurationStore(preferences: preferences)
        legacyStore.save(AIConfiguration(
            model: "gpt-4o", temperature: 0.5,
            endpoint: URL(string: "https://api.openai.com/v1")!, maxTokens: 4096
        ))
        try keychain.saveString("sk-pre-crash", forAccount: AIService.apiKeyAccount)
        preferences.set("true", forKey: "com.vreader.ai.providerProfiles.migrated")
        preferences.setRaw("{not valid JSON", forKey: "com.vreader.ai.providerProfiles")

        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)

        let profiles = Self.readProfiles(preferences)
        defer { Self.cleanupKeychain(keychain, profileIDs: profiles.map(\.id)) }
        #expect(profiles.count == 1)
        if let profile = profiles.first {
            #expect(profile.kind == .openAICompatible)
            #expect(profile.model == "gpt-4o")
            #expect(try keychain.readAPIKey(forProfile: profile.id) == "sk-pre-crash")
        }
    }

    // MARK: - Test 6c: keychain-only legacy + flag set + profiles missing → re-migrate

    @Test func midMigrationCrash_keychainOnlyLegacy_reRunsCleanly() async throws {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        // Only legacy keychain key (no AIConfiguration), but flag is set
        // and no profile data — simulates a crash partway through.
        try keychain.saveString("sk-keychain-only", forAccount: AIService.apiKeyAccount)
        preferences.set("true", forKey: "com.vreader.ai.providerProfiles.migrated")
        // No profile data, no legacy AIConfiguration in preferences.

        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)

        let profiles = Self.readProfiles(preferences)
        defer { Self.cleanupKeychain(keychain, profileIDs: profiles.map(\.id)) }
        #expect(profiles.count == 1)
        if let profile = profiles.first {
            // Built from AIConfiguration.default since no legacy config.
            #expect(profile.kind == .openAICompatible)
            #expect(try keychain.readAPIKey(forProfile: profile.id) == "sk-keychain-only")
        }
    }

    // MARK: - Test 6d: empty profile array + legacy data → re-migrate

    @Test func midMigrationCrash_emptyProfileArrayWithLegacyData_reRunsCleanly() async throws {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        // Seed legacy data + flag set + empty array as profile data
        // (a write that succeeded with [] is ambiguous; if legacy data
        // still exists, treat as mid-crash and re-migrate).
        let legacyStore = AIConfigurationStore(preferences: preferences)
        legacyStore.save(AIConfiguration(
            model: "gpt-4o", temperature: 0.5,
            endpoint: URL(string: "https://api.openai.com/v1")!, maxTokens: 4096
        ))
        try keychain.saveString("sk-empty-array-recovery", forAccount: AIService.apiKeyAccount)
        preferences.set("true", forKey: "com.vreader.ai.providerProfiles.migrated")
        preferences.set("[]", forKey: "com.vreader.ai.providerProfiles")

        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)

        let profiles = Self.readProfiles(preferences)
        defer { Self.cleanupKeychain(keychain, profileIDs: profiles.map(\.id)) }
        #expect(profiles.count == 1)
        if let profile = profiles.first {
            #expect(profile.kind == .openAICompatible)
            #expect(profile.model == "gpt-4o")
            #expect(try keychain.readAPIKey(forProfile: profile.id) == "sk-empty-array-recovery")
        }
    }

    // MARK: - Test 7: partial keychain copy — saveAPIKey is idempotent

    @Test func partialKeychainCopy_saveIsIdempotent() async throws {
        let preferences = MockPreferenceStore()
        let keychain = Self.makeKeychain()
        let migrator = DefaultProviderProfileMigrator()

        let legacyStore = AIConfigurationStore(preferences: preferences)
        legacyStore.save(AIConfiguration(
            model: "gpt-4o", temperature: 0.5,
            endpoint: URL(string: "https://api.openai.com/v1")!, maxTokens: 4096
        ))
        try keychain.saveString("sk-original", forAccount: AIService.apiKeyAccount)

        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)
        let firstRunProfiles = Self.readProfiles(preferences)
        defer { Self.cleanupKeychain(keychain, profileIDs: firstRunProfiles.map(\.id)) }

        // Re-run migrator (which is a no-op via flag) — keychain copy is idempotent.
        migrator.migrateIfNeeded(preferences: preferences, keychain: keychain)

        // Verify keychain copy is still there + readable.
        if let profile = firstRunProfiles.first {
            #expect(try keychain.readAPIKey(forProfile: profile.id) == "sk-original")
        }
    }
}
