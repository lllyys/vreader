// Purpose: Tests for the editor-side operations on
// `WebDAVProfileListViewModel` (Feature #52 WI-4b — addProfile,
// updateProfile, savePassword, deletePassword, testConnection).
//
// Mirrors `AISettingsViewModelEditorTests` shape from Feature #50 WI-6b.
// Real `WebDAVServerProfileStore` backed by fresh UserDefaults +
// fresh `KeychainService` per test; `WebDAVTransport` is mocked via a
// in-place test double for testConnection HTTP-shape coverage.
//
// @coordinates-with: WebDAVProfileListViewModel.swift,
//   WebDAVProfileListViewModel+Editor.swift, WebDAVServerProfile.swift,
//   WebDAVServerProfileStore.swift, WebDAVClient.swift

import Testing
import Foundation
@testable import vreader

@Suite("WebDAVProfileListViewModel — editor ops (#52 WI-4b)")
@MainActor
struct WebDAVProfileListViewModelEditorTests {

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suite = "WebDAVEditorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeKeychain() -> KeychainService {
        KeychainService(serviceIdentifier: "com.vreader.test.webdav-editor.\(UUID().uuidString)")
    }

    private func makeProfile(
        id: UUID = UUID(),
        name: String = "Home",
        serverURL: String = "https://dav.example.com/",
        username: String = "alice"
    ) -> WebDAVServerProfile {
        WebDAVServerProfile(id: id, name: name, serverURL: serverURL, username: username)
    }

    // MARK: - addProfile

    @Test func addProfile_writesProfileAndPasswordAtomically() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        let profile = makeProfile()
        await vm.addProfile(profile, password: "secret")

        #expect(vm.editorError == nil)
        #expect(vm.profiles.contains(where: { $0.id == profile.id }))
        let stored = try await store.readPassword(for: profile.id)
        #expect(stored == "secret")
    }

    @Test func addProfile_appendsToExistingProfiles() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let first = makeProfile(name: "Home")
        await store.upsert(first)

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        let second = makeProfile(name: "Work")
        await vm.addProfile(second, password: "pw")

        #expect(vm.profiles.count == 2)
        #expect(vm.editorError == nil)
    }

    // MARK: - updateProfile

    @Test func updateProfile_persistsRenamedMetadata_keychainUnchanged() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        let profile = makeProfile(name: "Home")
        await vm.addProfile(profile, password: "secret")
        var renamed = profile
        renamed.name = "Renamed Home"
        await vm.updateProfile(renamed)

        #expect(vm.editorError == nil)
        let updated = vm.profiles.first(where: { $0.id == profile.id })
        #expect(updated?.name == "Renamed Home")
        // Keychain entry preserved (updateProfile MUST NOT touch keychain).
        let stored = try await store.readPassword(for: profile.id)
        #expect(stored == "secret")
    }

    // MARK: - savePassword / deletePassword

    @Test func savePassword_writesNewPasswordToKeychain() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        let profile = makeProfile()
        await vm.addProfile(profile, password: "old")
        await vm.savePassword("new", forID: profile.id)

        #expect(vm.editorError == nil)
        let stored = try await store.readPassword(for: profile.id)
        #expect(stored == "new")
    }

    @Test func savePassword_rejectsEmptyPassword() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        let profile = makeProfile()
        await vm.addProfile(profile, password: "secret")

        await vm.savePassword("   ", forID: profile.id)
        #expect(vm.editorError != nil)
        // Old password preserved.
        let stored = try await store.readPassword(for: profile.id)
        #expect(stored == "secret")
    }

    @Test func deletePassword_removesKeychainEntry() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        let profile = makeProfile()
        await vm.addProfile(profile, password: "secret")

        await vm.deletePassword(forID: profile.id)
        #expect(vm.editorError == nil)
        let stored = try await store.readPassword(for: profile.id)
        #expect(stored == nil)
    }

    @Test func deletePassword_unknownID_isIdempotent() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        await vm.deletePassword(forID: UUID())
        #expect(vm.editorError == nil)
    }

    // MARK: - testConnection (HTTP-shape branches via mock transport)

    @Test func testConnection_success_onTransportSuccess() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        let result = await vm.testConnection(
            serverURL: "https://dav.example.com/",
            username: "alice",
            password: "secret",
            makeTransport: { _, _, _ in
                EditorTestWebDAVTransport(testConnectionResult: .success(()))
            }
        )
        guard case .success = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
    }

    @Test func testConnection_failsOnAuthenticationError() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        let result = await vm.testConnection(
            serverURL: "https://dav.example.com/",
            username: "alice",
            password: "wrong",
            makeTransport: { _, _, _ in
                EditorTestWebDAVTransport(testConnectionResult: .failure(WebDAVError.authenticationFailed))
            }
        )
        guard case .failure(let error) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect((error as? WebDAVError) == .authenticationFailed)
    }

    @Test func testConnection_failsOnInvalidURL() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        let result = await vm.testConnection(
            serverURL: "not-a-url",
            username: "alice",
            password: "secret"
        )
        guard case .failure(let error) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect((error as? WebDAVTestConnectionError) == .invalidURL)
    }

    @Test func testConnection_failsOnMissingUsername() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        let result = await vm.testConnection(
            serverURL: "https://dav.example.com/",
            username: "",
            password: "secret"
        )
        guard case .failure(let error) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect((error as? WebDAVTestConnectionError) == .missingUsername)
    }

    @Test func testConnection_failsOnMissingPassword() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        let result = await vm.testConnection(
            serverURL: "https://dav.example.com/",
            username: "alice",
            password: ""
        )
        guard case .failure(let error) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect((error as? WebDAVTestConnectionError) == .missingPassword)
    }

    @Test func testConnection_failsOnConnectionFailed() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        let result = await vm.testConnection(
            serverURL: "https://offline.example.com/",
            username: "alice",
            password: "secret",
            makeTransport: { _, _, _ in
                EditorTestWebDAVTransport(testConnectionResult: .failure(WebDAVError.connectionFailed("network down")))
            }
        )
        guard case .failure(let error) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        if case .connectionFailed(let detail) = error as? WebDAVError {
            #expect(detail == "network down")
        } else {
            Issue.record("Expected .connectionFailed, got \(error)")
        }
    }

    // MARK: - URL validator (Codex round-1 High fix [1])

    @Test func validatedServerURL_acceptsHttpsWithHost() {
        let url = WebDAVProfileListViewModel.validatedServerURL(from: "https://dav.example.com/")
        #expect(url != nil)
        #expect(url?.host == "dav.example.com")
    }

    @Test func validatedServerURL_acceptsHttpForLocalNetworks() {
        // Bug #110: HTTP accepted for Tailscale + local-network WebDAV.
        let url = WebDAVProfileListViewModel.validatedServerURL(from: "http://nas.local/dav/")
        #expect(url != nil)
    }

    @Test func validatedServerURL_rejectsSchemeOnlyHostless() {
        #expect(WebDAVProfileListViewModel.validatedServerURL(from: "https://") == nil)
        #expect(WebDAVProfileListViewModel.validatedServerURL(from: "http://") == nil)
    }

    @Test func validatedServerURL_rejectsMissingScheme() {
        #expect(WebDAVProfileListViewModel.validatedServerURL(from: "dav.example.com") == nil)
    }

    @Test func validatedServerURL_rejectsWrongScheme() {
        #expect(WebDAVProfileListViewModel.validatedServerURL(from: "ftp://dav.example.com/") == nil)
    }

    @Test func validatedServerURL_trimsWhitespace() {
        let url = WebDAVProfileListViewModel.validatedServerURL(from: "  https://dav.example.com/  ")
        #expect(url != nil)
    }

    // MARK: - updateProfile stale-view guard (Codex round-1 Medium [2])

    @Test func updateProfile_rejectsUnknownID() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        let stale = makeProfile() // never added to the store
        await vm.updateProfile(stale)

        #expect(vm.editorError != nil)
        // Stale profile must NOT have been silently re-added.
        let after = await store.loadAll()
        #expect(after.isEmpty)
    }

    // MARK: - testConnection trims whitespace-only credentials (Codex round-1 Medium [4])

    @Test func testConnection_failsOnWhitespaceOnlyUsername() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        let result = await vm.testConnection(
            serverURL: "https://dav.example.com/",
            username: "   ",
            password: "secret"
        )
        guard case .failure(let error) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect((error as? WebDAVTestConnectionError) == .missingUsername)
    }

    @Test func testConnection_failsOnWhitespaceOnlyPassword() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        let result = await vm.testConnection(
            serverURL: "https://dav.example.com/",
            username: "alice",
            password: "  \t  "
        )
        guard case .failure(let error) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        #expect((error as? WebDAVTestConnectionError) == .missingPassword)
    }

    // MARK: - readStoredPassword (Codex round-1 Low [6])

    @Test func readStoredPassword_returnsStoredPassword() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        let profile = makeProfile()
        await vm.addProfile(profile, password: "secret")

        let stored = await vm.readStoredPassword(for: profile.id)
        #expect(stored == "secret")
    }

    @Test func readStoredPassword_returnsNilForUnknownID() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)
        let stored = await vm.readStoredPassword(for: UUID())
        #expect(stored == nil)
    }

    // MARK: - WebDAVError LocalizedError (Codex round-1 Medium [3])

    @Test func webdavError_authenticationFailed_hasSpecificMessage() {
        let msg = WebDAVError.authenticationFailed.localizedDescription
        #expect(msg.contains("Authentication") || msg.contains("authentication"))
        #expect(msg.contains("username") || msg.contains("password"))
    }

    @Test func webdavError_httpError405_mentionsPropfind() {
        let msg = WebDAVError.httpError(405).localizedDescription
        #expect(msg.contains("PROPFIND") || msg.contains("WebDAV"))
        #expect(msg.contains("405"))
    }

    @Test func webdavError_connectionFailed_includesDetail() {
        let msg = WebDAVError.connectionFailed("network down").localizedDescription
        #expect(msg.contains("network down"))
    }

    // MARK: - Codex round-2 fixes

    @Test func updateProfile_singleHopRejectsConcurrentlyDeletedProfile() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        // Add then immediately delete from the store directly (simulating
        // the racy "deleted while edit sheet open" scenario).
        let profile = makeProfile()
        await vm.addProfile(profile, password: "secret")
        await store.remove(id: profile.id)
        // Now the edit-sheet's stale view tries to save.
        var renamed = profile
        renamed.name = "Renamed (stale)"
        await vm.updateProfile(renamed)

        #expect(vm.editorError != nil)
        let after = await store.loadAll()
        #expect(after.contains(where: { $0.id == profile.id }) == false)
    }

    @Test func addProfile_persistsTrimmedPassword() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        let profile = makeProfile()
        await vm.addProfile(profile, password: "  secret  ")
        #expect(vm.editorError == nil)
        let stored = try await store.readPassword(for: profile.id)
        #expect(stored == "secret")
    }

    @Test func addProfile_rejectsWhitespaceOnlyPassword() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        let profile = makeProfile()
        await vm.addProfile(profile, password: "   ")
        #expect(vm.editorError != nil)
        // Profile must NOT have been added.
        let after = await store.loadAll()
        #expect(after.contains(where: { $0.id == profile.id }) == false)
    }

    @Test func savePassword_persistsTrimmedPassword() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        let profile = makeProfile()
        await vm.addProfile(profile, password: "old")

        await vm.savePassword("  fresh  ", forID: profile.id)
        #expect(vm.editorError == nil)
        let stored = try await store.readPassword(for: profile.id)
        #expect(stored == "fresh")
    }
}

// MARK: - Mock WebDAVTransport

/// In-test minimal WebDAVTransport double. Only `testConnection` is
/// exercised by the editor's runTest; other methods throw to make
/// any unexpected call site explicit in test output.
private final class EditorTestWebDAVTransport: WebDAVTransport, @unchecked Sendable {
    let testConnectionResult: Result<Void, Error>

    init(testConnectionResult: Result<Void, Error>) {
        self.testConnectionResult = testConnectionResult
    }

    func testConnection() async throws {
        switch testConnectionResult {
        case .success: return
        case .failure(let error): throw error
        }
    }

    // Unused in WI-4b editor tests — throw to surface accidental use.
    func upload(data: Data, toPath path: String) async throws {
        throw WebDAVError.connectionFailed("not implemented for test")
    }
    func download(fromPath path: String) async throws -> Data {
        throw WebDAVError.connectionFailed("not implemented for test")
    }
    func delete(path: String) async throws {
        throw WebDAVError.connectionFailed("not implemented for test")
    }
    func listDirectory(path: String) async throws -> [WebDAVEntry] {
        throw WebDAVError.connectionFailed("not implemented for test")
    }
    func createDirectory(path: String) async throws {
        throw WebDAVError.connectionFailed("not implemented for test")
    }
    func move(fromPath: String, toPath: String) async throws {
        throw WebDAVError.connectionFailed("not implemented for test")
    }
    func existsWithSize(at path: String) async throws -> Int64? {
        throw WebDAVError.connectionFailed("not implemented for test")
    }
}
