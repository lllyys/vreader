// Purpose: Tests for WebDAVProfileListViewModel (feature #52 WI-4a).
// Validates loadProfiles / setActive / deleteProfile against a real
// WebDAVServerProfileStore backed by a fresh UserDefaults suite + fresh
// KeychainService per test. Mirrors the AISettingsViewModel list-ops
// test shape (Feature #50 WI-6a).
//
// @coordinates-with: WebDAVProfileListViewModel.swift,
//   WebDAVServerProfileStore.swift, WebDAVServerProfile.swift

import Testing
import Foundation
@testable import vreader

@Suite("WebDAVProfileListViewModel — list ops (#52 WI-4a)")
@MainActor
struct WebDAVProfileListViewModelTests {

    // MARK: - Helpers

    /// Fresh UserDefaults per test for isolation. Mirrors the pattern in
    /// `WebDAVProviderFactoryProfileDispatchTests`.
    private func makeDefaults() -> UserDefaults {
        let suite = "WebDAVProfileListViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeKeychain() -> KeychainService {
        KeychainService(serviceIdentifier: "com.vreader.test.webdav-list-vm.\(UUID().uuidString)")
    }

    private func makeProfile(
        name: String = "Test",
        serverURL: String = "https://dav.example.com/",
        username: String = "alice"
    ) -> WebDAVServerProfile {
        WebDAVServerProfile(id: UUID(), name: name, serverURL: serverURL, username: username)
    }

    // MARK: - loadProfiles

    @Test func loadProfiles_emptyStore_setsEmptyAndNilActive() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        await vm.loadProfiles()

        #expect(vm.profiles.isEmpty)
        #expect(vm.activeID == nil)
        #expect(vm.listError == nil)
    }

    @Test func loadProfiles_withTwoProfiles_andSetActive_publishesBoth() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let a = makeProfile(name: "Home")
        let b = makeProfile(name: "Work")
        await store.upsert(a)
        await store.upsert(b)
        await store.setActiveProfileID(b.id)

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        #expect(vm.profiles.count == 2)
        #expect(vm.profiles.map(\.id).contains(a.id))
        #expect(vm.profiles.map(\.id).contains(b.id))
        #expect(vm.activeID == b.id)
    }

    @Test func loadProfiles_withDanglingActiveID_resolvesToNil() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let p = makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(UUID()) // points to nonexistent profile

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        #expect(vm.profiles.count == 1)
        #expect(vm.activeID == nil)
    }

    // MARK: - setActive

    @Test func setActive_knownID_updatesActiveID() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let a = makeProfile(name: "Home")
        let b = makeProfile(name: "Work")
        await store.upsert(a)
        await store.upsert(b)
        await store.setActiveProfileID(a.id)

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        await vm.setActive(b.id)

        #expect(vm.activeID == b.id)
        let storeActive = await store.activeProfileID()
        #expect(storeActive == b.id)
    }

    @Test func setActive_nilClearsActive() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let p = makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        await vm.setActive(nil)

        #expect(vm.activeID == nil)
        let storeActive = await store.activeProfileID()
        #expect(storeActive == nil)
    }

    @Test func setActive_unknownID_isNoOp() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let p = makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        // Attempt to activate an id not in the loaded profile list.
        await vm.setActive(UUID())

        #expect(vm.activeID == p.id, "setActive must reject unknown ids and leave active unchanged")
        let storeActive = await store.activeProfileID()
        #expect(storeActive == p.id, "store's active id must not be overwritten with a dangling reference")
    }

    // MARK: - deleteProfile

    @Test func deleteProfile_removesFromListAndStore() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let a = makeProfile(name: "Home")
        let b = makeProfile(name: "Work")
        await store.upsert(a)
        await store.upsert(b)

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        await vm.deleteProfile(a.id)

        #expect(vm.profiles.count == 1)
        #expect(vm.profiles.first?.id == b.id)
        let remaining = await store.loadAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == b.id)
    }

    @Test func deleteProfile_activeBeingDeleted_clearsActiveID() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let p = makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        #expect(vm.activeID == p.id)

        await vm.deleteProfile(p.id)

        #expect(vm.activeID == nil, "deleting the active profile must clear activeID in the VM")
        let storeActive = await store.activeProfileID()
        #expect(storeActive == nil, "store must also clear active id when the active profile is removed")
    }

    @Test func deleteProfile_unknownID_isNoOp() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let p = makeProfile()
        await store.upsert(p)

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        await vm.deleteProfile(UUID())

        #expect(vm.profiles.count == 1)
        let remaining = await store.loadAll()
        #expect(remaining.count == 1)
    }

    @Test func deleteProfile_clearsKeychainPasswordViaStore() async throws {
        nonisolated(unsafe) let defaults = makeDefaults()
        let keychain = makeKeychain()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: keychain)
        let p = makeProfile()
        await store.upsert(p)
        try await store.writePassword("secret-1", for: p.id)
        // sanity: password readable before delete
        let pre = try await store.readPassword(for: p.id)
        #expect(pre == "secret-1")

        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()
        await vm.deleteProfile(p.id)

        let post = try await store.readPassword(for: p.id)
        #expect(post == nil, "store.remove(id:) must clear the per-profile keychain password entry")
    }

    // MARK: - Reload after mutation

    @Test func loadProfiles_reflectsExternalMutations_betweenCalls() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)

        await vm.loadProfiles()
        #expect(vm.profiles.isEmpty)

        // Mutation outside the VM (e.g. via the editor sheet in WI-4b).
        let p = makeProfile(name: "Late Add")
        await store.upsert(p)

        await vm.loadProfiles()
        #expect(vm.profiles.count == 1)
        #expect(vm.profiles.first?.name == "Late Add")
    }

    // MARK: - Notification-driven resync surface

    /// The list view subscribes to `.webdavProfilesDidChange` and re-runs
    /// `loadProfiles()` on each post. This test pins the contract by
    /// driving the notification surface directly and confirming the VM
    /// converges to the latest store state after the call.
    @Test func loadProfiles_afterPostedNotification_picksUpExternalUpsert() async {
        nonisolated(unsafe) let defaults = makeDefaults()
        let store = WebDAVServerProfileStore(defaults: defaults, keychain: makeKeychain())
        let vm = WebDAVProfileListViewModel(profileStore: store)
        await vm.loadProfiles()

        // External path mutates the store and posts the same notification
        // the list view listens for (the store does this on every mutation
        // — see `WebDAVServerProfileStore.postDidChangeNotification`).
        let p = makeProfile(name: "Posted")
        await store.upsert(p)

        // The view's `.onReceive(.webdavProfilesDidChange)` would run this
        // load. Driving directly here gives us the same convergence
        // behavior without booting SwiftUI.
        await vm.loadProfiles()

        #expect(vm.profiles.count == 1)
        #expect(vm.profiles.first?.name == "Posted")
    }
}

// MARK: - Editor context (sheet-swap contract)

/// Tests the `WebDAVEditorContext` Identifiable wrapper that drives
/// `.sheet(item:)`. The wrapper's `id` MUST change between add and edit
/// modes (and between editing different profiles) so SwiftUI re-creates
/// the sheet body on target swap. Mirrors the `AIEditorContext` test
/// shape (Feature #50 bug #174 fix).
@Suite("WebDAVEditorContext — sheet swap identity (#52 WI-4a)")
struct WebDAVEditorContextTests {

    @Test func addContextHasNewID() {
        let ctx = WebDAVEditorContext.add()
        #expect(ctx.id == "new")
        #expect(ctx.profile == nil)
    }

    @Test func editContextHasProfileUUIDID() {
        let profile = WebDAVServerProfile(
            id: UUID(), name: "Edit me", serverURL: "https://h/", username: "u"
        )
        let ctx = WebDAVEditorContext.edit(profile)
        #expect(ctx.id == profile.id.uuidString)
        #expect(ctx.profile?.id == profile.id)
    }

    @Test func addAndEditHaveDifferentIDs() {
        let profile = WebDAVServerProfile(
            id: UUID(), name: "x", serverURL: "https://h/", username: "u"
        )
        #expect(WebDAVEditorContext.add().id != WebDAVEditorContext.edit(profile).id)
    }

    @Test func editTwoProfilesHaveDifferentIDs() {
        let a = WebDAVServerProfile(id: UUID(), name: "A", serverURL: "https://h/", username: "u")
        let b = WebDAVServerProfile(id: UUID(), name: "B", serverURL: "https://h/", username: "u")
        #expect(WebDAVEditorContext.edit(a).id != WebDAVEditorContext.edit(b).id)
    }

    @Test func editSameProfileTwiceProducesSameID() {
        let p = WebDAVServerProfile(id: UUID(), name: "P", serverURL: "https://h/", username: "u")
        #expect(WebDAVEditorContext.edit(p).id == WebDAVEditorContext.edit(p).id)
    }

    @Test func equatable_addEqualsAdd() {
        #expect(WebDAVEditorContext.add() == WebDAVEditorContext.add())
    }

    @Test func equatable_sameProfileEdits_areEqual() {
        let p = WebDAVServerProfile(id: UUID(), name: "P", serverURL: "https://h/", username: "u")
        #expect(WebDAVEditorContext.edit(p) == WebDAVEditorContext.edit(p))
    }
}

// Note: WI-4a's stub-editor placeholder-save sub-suite was removed in
// WI-4b along with the stub editor itself. The full add/edit form
// (WebDAVServerProfileEditSheet) and the editor-side VM operations
// are covered by WebDAVProfileListViewModelEditorTests.swift.
