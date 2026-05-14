// Purpose: Tests for WebDAVProfileMigrator (feature #52 WI-2). Pins the
// legacy-flat-keychain → "Default"-profile contract, idempotency on
// repeated calls, the non-empty-store guard, and the partial-legacy
// (URL only / no password) edge case.

import Testing
import Foundation
@testable import vreader

@Suite("WebDAVProfileMigrator")
struct WebDAVProfileMigratorTests {

    // MARK: - Helpers

    /// Fresh UserDefaults suite per test for isolation.
    private func makeDefaults() -> UserDefaults {
        let suite = "WebDAVProfileMigratorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Fresh KeychainService with a unique service identifier per test
    /// so simulator keychain state doesn't leak between tests.
    private func makeKeychain() -> KeychainService {
        KeychainService(serviceIdentifier: "com.vreader.test.webdav-migrator.\(UUID().uuidString)")
    }

    /// Seeds the three legacy flat-keychain entries.
    private func seedLegacyKeychain(_ keychain: KeychainService, url: String, user: String, password: String) throws {
        if !url.isEmpty {
            try keychain.saveString(url, forAccount: WebDAVProfileMigrator.legacyServerURLAccount)
        }
        if !user.isEmpty {
            try keychain.saveString(user, forAccount: WebDAVProfileMigrator.legacyUsernameAccount)
        }
        if !password.isEmpty {
            try keychain.saveString(password, forAccount: WebDAVProfileMigrator.legacyPasswordAccount)
        }
    }

    // MARK: - Fresh install (no legacy data)

    @Test func migrateIfNeeded_freshInstall_setsMarkerCreatesNoProfile() async throws {
        // UserDefaults can't satisfy Swift 6 strict Sendable across an
        // actor hop, so localize the marker via nonisolated(unsafe).
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)

        try await WebDAVProfileMigrator.migrateIfNeeded(
            store: store,
            keychain: keychain,
            defaults: defaults
        )

        let profiles = await store.loadAll()
        let activeID = await store.activeProfileID()
        #expect(profiles.isEmpty, "Fresh install should produce no profile.")
        #expect(activeID == nil, "Fresh install should leave active unset.")
        #expect(defaults.bool(forKey: WebDAVProfileMigrator.migrationMarkerKey), "Marker must be set so next launch skips the migration check.")
    }

    // MARK: - Single legacy server → Default profile

    @Test func migrateIfNeeded_existingLegacy_createsDefaultProfile() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)

        try seedLegacyKeychain(
            keychain,
            url: "https://dav.example.com/files/",
            user: "alice",
            password: "s3cret-pw"
        )

        try await WebDAVProfileMigrator.migrateIfNeeded(
            store: store,
            keychain: keychain,
            defaults: defaults
        )

        let profiles = await store.loadAll()
        #expect(profiles.count == 1)
        let profile = try #require(profiles.first)
        #expect(profile.id == WebDAVProfileMigrator.migratedProfileID, "Default profile must use the stable migrated UUID.")
        #expect(profile.name == "Default")
        #expect(profile.serverURL == "https://dav.example.com/files/")
        #expect(profile.username == "alice")

        let activeID = await store.activeProfileID()
        #expect(activeID == profile.id, "Migrated Default profile must be the active one.")

        let copiedPassword = try await store.readPassword(for: profile.id)
        #expect(copiedPassword == "s3cret-pw", "Password must be copied to the per-profile keychain slot.")

        #expect(defaults.bool(forKey: WebDAVProfileMigrator.migrationMarkerKey))
    }

    // MARK: - Partial legacy (URL + username but no password)

    @Test func migrateIfNeeded_partialLegacy_urlOnly_createsProfileWithEmptyPasswordSlot() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)

        try seedLegacyKeychain(
            keychain,
            url: "https://nas.example.local/dav/",
            user: "bob",
            password: ""
        )

        try await WebDAVProfileMigrator.migrateIfNeeded(
            store: store,
            keychain: keychain,
            defaults: defaults
        )

        let profiles = await store.loadAll()
        #expect(profiles.count == 1, "Partial legacy data should still produce one Default profile so the URL/username aren't lost.")
        let profile = try #require(profiles.first)
        #expect(profile.serverURL == "https://nas.example.local/dav/")
        #expect(profile.username == "bob")

        let copiedPassword = try await store.readPassword(for: profile.id)
        #expect(copiedPassword == nil, "No legacy password → no per-profile keychain entry.")

        #expect(defaults.bool(forKey: WebDAVProfileMigrator.migrationMarkerKey))
    }

    // MARK: - Idempotency: marker already set

    @Test func migrateIfNeeded_markerAlreadySet_isNoOp() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)

        // Pre-set the marker so the migrator should return immediately.
        defaults.set(true, forKey: WebDAVProfileMigrator.migrationMarkerKey)

        // Seed legacy data — should NOT be migrated.
        try seedLegacyKeychain(
            keychain,
            url: "https://legacy.example.com/",
            user: "carol",
            password: "shouldnt-migrate"
        )

        try await WebDAVProfileMigrator.migrateIfNeeded(
            store: store,
            keychain: keychain,
            defaults: defaults
        )

        let profiles = await store.loadAll()
        #expect(profiles.isEmpty, "Marker pre-set must short-circuit the migration regardless of legacy data presence.")
    }

    // MARK: - Defensive idempotency: store non-empty but marker missing

    @Test func migrateIfNeeded_storeNonEmpty_setsMarkerWithoutMigrating() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)

        // Pre-populate the store with a user-added profile (NOT the
        // migrator's Default UUID) and DO NOT set the marker.
        let userProfile = WebDAVServerProfile(
            id: UUID(),
            name: "My NAS",
            serverURL: "https://my-nas.example.com/dav/",
            username: "dave"
        )
        await store.upsert(userProfile)

        try seedLegacyKeychain(
            keychain,
            url: "https://legacy.example.com/",
            user: "legacy-user",
            password: "legacy-pw"
        )

        try await WebDAVProfileMigrator.migrateIfNeeded(
            store: store,
            keychain: keychain,
            defaults: defaults
        )

        let profiles = await store.loadAll()
        #expect(profiles.count == 1, "Migrator must NOT add a Default profile when the store already has a user-added one.")
        #expect(profiles.first?.name == "My NAS", "Existing user profile must remain untouched.")
        #expect(defaults.bool(forKey: WebDAVProfileMigrator.migrationMarkerKey), "Marker must be set so subsequent launches don't re-evaluate the legacy keys.")
    }

    // MARK: - Repeat-call idempotency

    @Test func migrateIfNeeded_secondCall_doesNotDuplicateProfile() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)

        try seedLegacyKeychain(
            keychain,
            url: "https://repeat.example.com/dav/",
            user: "eve",
            password: "pw-1"
        )

        try await WebDAVProfileMigrator.migrateIfNeeded(
            store: store,
            keychain: keychain,
            defaults: defaults
        )
        try await WebDAVProfileMigrator.migrateIfNeeded(
            store: store,
            keychain: keychain,
            defaults: defaults
        )

        let profiles = await store.loadAll()
        #expect(profiles.count == 1, "Second migrateIfNeeded call must not duplicate the Default profile (marker short-circuits).")
        #expect(profiles.first?.id == WebDAVProfileMigrator.migratedProfileID)
    }
}
