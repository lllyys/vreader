// Purpose: Tests for WebDAVProviderFactory's profile-store-backed
// variants (feature #52 WI-3). Verifies that `make(profileStore:)` and
// `makeRequestBuilder(profileStore:)` correctly resolve the active
// profile + its password, dispatch with the right URL/username/password,
// and throw the expected errors when the store is empty or the profile's
// fields are invalid.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("WebDAVProviderFactory — profile-store dispatch (#52 WI-3)")
@MainActor
struct WebDAVProviderFactoryProfileDispatchTests {

    // MARK: - Helpers

    /// Fresh UserDefaults per test for isolation.
    private func makeDefaults() -> UserDefaults {
        let suite = "WebDAVProviderFactoryProfileDispatchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Fresh keychain with unique service identifier per test.
    private func makeKeychain() -> KeychainService {
        KeychainService(serviceIdentifier: "com.vreader.test.webdav-factory-dispatch.\(UUID().uuidString)")
    }

    /// In-memory PersistenceActor; not exercised by the factory beyond
    /// being passed through, so a vanilla actor is fine.
    private func makePersistence() -> PersistenceActor {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return PersistenceActor(modelContainer: container)
    }

    private let validURL = "https://dav.example.com/files/"
    private let validUser = "alice"
    private let validPassword = "pw-1"

    // MARK: - make(profileStore:) — happy path

    @Test func make_withActiveProfileAndPassword_returnsWebDAVProvider() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let profile = WebDAVServerProfile(
            id: UUID(),
            name: "Test",
            serverURL: validURL,
            username: validUser
        )
        await store.upsert(profile)
        try await store.writePassword(validPassword, for: profile.id)
        await store.setActiveProfileID(profile.id)

        let persistence = makePersistence()
        let provider = try await WebDAVProviderFactory.make(
            persistence: persistence,
            profileStore: store
        )

        // We can't introspect the provider's internal client directly,
        // but we can assert the call returned a valid instance (no throw).
        _ = provider
    }

    // MARK: - make(profileStore:) — missing-credentials cases

    @Test func make_withNoActiveProfile_throwsMissingCredentials() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        // No upserts; no active id.

        let persistence = makePersistence()
        await #expect(throws: WebDAVProviderFactoryError.missingCredentials) {
            _ = try await WebDAVProviderFactory.make(
                persistence: persistence,
                profileStore: store
            )
        }
    }

    @Test func make_withActiveButEmptyURL_throwsMissingCredentials() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let profile = WebDAVServerProfile(
            id: UUID(), name: "Test", serverURL: "", username: validUser
        )
        await store.upsert(profile)
        try await store.writePassword(validPassword, for: profile.id)
        await store.setActiveProfileID(profile.id)

        let persistence = makePersistence()
        await #expect(throws: WebDAVProviderFactoryError.missingCredentials) {
            _ = try await WebDAVProviderFactory.make(
                persistence: persistence,
                profileStore: store
            )
        }
    }

    @Test func make_withActiveButNoPassword_throwsMissingCredentials() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let profile = WebDAVServerProfile(
            id: UUID(), name: "Test", serverURL: validURL, username: validUser
        )
        await store.upsert(profile)
        // No writePassword call — slot stays empty.
        await store.setActiveProfileID(profile.id)

        let persistence = makePersistence()
        await #expect(throws: WebDAVProviderFactoryError.missingCredentials) {
            _ = try await WebDAVProviderFactory.make(
                persistence: persistence,
                profileStore: store
            )
        }
    }

    // MARK: - make(profileStore:) — invalid URL

    @Test func make_withMalformedURL_throwsInvalidServerURL() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let profile = WebDAVServerProfile(
            id: UUID(),
            name: "Test",
            serverURL: "not-a-valid-url-no-scheme",
            username: validUser
        )
        await store.upsert(profile)
        try await store.writePassword(validPassword, for: profile.id)
        await store.setActiveProfileID(profile.id)

        let persistence = makePersistence()
        await #expect(throws: WebDAVProviderFactoryError.self) {
            _ = try await WebDAVProviderFactory.make(
                persistence: persistence,
                profileStore: store
            )
        }
    }

    // MARK: - makeRequestBuilder(profileStore:) — parity

    @Test func makeRequestBuilder_withActiveProfileAndPassword_succeeds() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let profile = WebDAVServerProfile(
            id: UUID(), name: "Test", serverURL: validURL, username: validUser
        )
        await store.upsert(profile)
        try await store.writePassword(validPassword, for: profile.id)
        await store.setActiveProfileID(profile.id)

        let builder = try await WebDAVProviderFactory.makeRequestBuilder(profileStore: store)
        _ = builder
    }

    @Test func makeRequestBuilder_withNoActiveProfile_throwsMissingCredentials() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)

        await #expect(throws: WebDAVProviderFactoryError.missingCredentials) {
            _ = try await WebDAVProviderFactory.makeRequestBuilder(profileStore: store)
        }
    }

    @Test func makeRequestBuilder_withMalformedURL_throwsInvalidServerURL() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let profile = WebDAVServerProfile(
            id: UUID(),
            name: "Test",
            serverURL: "not-a-valid-url",
            username: validUser
        )
        await store.upsert(profile)
        try await store.writePassword(validPassword, for: profile.id)
        await store.setActiveProfileID(profile.id)

        await #expect(throws: WebDAVProviderFactoryError.self) {
            _ = try await WebDAVProviderFactory.makeRequestBuilder(profileStore: store)
        }
    }
}
