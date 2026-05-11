// Purpose: Tests for AIProviderPickerViewModel — feature #50 WI-7.
// Covers the in-reader picker's read-side (loadProfiles) and write-side
// (setActive). The picker is a slimmer surface than AISettingsViewModel
// — it doesn't own editor state, just reflects the saved list and lets
// the user flip the active selection from inside the reader.
//
// @coordinates-with: AIProviderPickerViewModel.swift,
//   ProviderProfileStore.swift

import Testing
import Foundation
@testable import vreader

@Suite("AIProviderPickerViewModel (WI-7)")
struct AIProviderPickerViewModelTests {

    // MARK: - Helpers

    @MainActor
    private static func makeVM(store: ProviderProfileStore) -> AIProviderPickerViewModel {
        AIProviderPickerViewModel(store: store)
    }

    private static func makeStore() -> ProviderProfileStore {
        ProviderProfileStore(
            preferences: MockPreferenceStore(),
            migrator: DefaultProviderProfileMigrator(),
            keychain: KeychainService(serviceIdentifier: "com.vreader.test.picker.\(UUID().uuidString)")
        )
    }

    private static func makeProfile(name: String = "Test Profile", kind: ProviderKind = .openAICompatible) -> ProviderProfile {
        ProviderProfile(
            id: UUID(), name: name, kind: kind,
            baseURL: kind.defaultBaseURL,
            model: kind.defaultModel,
            temperature: 0.7, maxTokens: 2048
        )
    }

    // MARK: - loadProfiles

    @Test @MainActor func loadProfiles_emptyStore_publishesEmptyListAndNilActive() async {
        let store = Self.makeStore()
        let vm = Self.makeVM(store: store)

        await vm.loadProfiles()

        #expect(vm.profiles.isEmpty)
        #expect(vm.activeID == nil)
    }

    @Test @MainActor func loadProfiles_storeHasProfiles_publishesListAndActiveID() async {
        let store = Self.makeStore()
        let first = Self.makeProfile(name: "ChatGPT")
        let second = Self.makeProfile(name: "Claude", kind: .anthropicNative)
        await store.upsert(first)
        await store.upsert(second)
        await store.setActiveProfileID(first.id)

        let vm = Self.makeVM(store: store)
        await vm.loadProfiles()

        #expect(vm.profiles.count == 2)
        #expect(vm.activeID == first.id, "loadProfiles must publish the persisted active id")
    }

    @Test @MainActor func loadProfiles_activeIDNotInList_resolvesToNil() async {
        // Defensive contract: if the store somehow returns an activeID
        // that doesn't resolve to a present profile, the picker should
        // surface nil rather than dangle on a phantom id. This mirrors
        // AISettingsViewModel.loadProfiles's defensive check (WI-6a
        // round-1 audit finding) — the in-reader picker has the same
        // requirement.
        let store = Self.makeStore()
        let p = Self.makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(UUID())  // unrelated UUID

        let vm = Self.makeVM(store: store)
        await vm.loadProfiles()

        #expect(vm.profiles.count == 1)
        #expect(vm.activeID == nil, "Active id that doesn't resolve to a profile in the list must surface as nil")
    }

    // MARK: - setActive

    @Test @MainActor func setActive_changesActiveID_andPersistsToStore() async {
        let store = Self.makeStore()
        let first = Self.makeProfile(name: "First")
        let second = Self.makeProfile(name: "Second")
        await store.upsert(first)
        await store.upsert(second)
        await store.setActiveProfileID(first.id)

        let vm = Self.makeVM(store: store)
        await vm.loadProfiles()
        #expect(vm.activeID == first.id)

        await vm.setActive(second.id)

        #expect(vm.activeID == second.id)
        let storedActive = await store.activeProfile()
        #expect(storedActive?.id == second.id, "setActive must persist the new selection to the store")
    }

    @Test @MainActor func setActive_unknownID_isIgnored_doesNotMutateStore() async {
        // Mirrors the WI-6a setActive contract — unknown ids are
        // rejected rather than written through, so a stale view can't
        // leave the VM with a dangling active id.
        let store = Self.makeStore()
        let p = Self.makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)

        let vm = Self.makeVM(store: store)
        await vm.loadProfiles()

        await vm.setActive(UUID())  // not in the list

        #expect(vm.activeID == p.id, "Unknown id must NOT mutate activeID")
        let storedActive = await store.activeProfile()
        #expect(storedActive?.id == p.id, "Unknown id must NOT mutate the store")
    }

    @Test @MainActor func setActive_nilClearsActive_andPersists() async {
        let store = Self.makeStore()
        let p = Self.makeProfile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)

        let vm = Self.makeVM(store: store)
        await vm.loadProfiles()

        await vm.setActive(nil)

        #expect(vm.activeID == nil)
        let storedActive = await store.activeProfile()
        #expect(storedActive == nil, "Nil active must clear the store too")
    }

    // MARK: - hasProfiles convenience flag

    @Test @MainActor func hasProfiles_reflectsListEmptiness() async {
        let store = Self.makeStore()
        let vm = Self.makeVM(store: store)

        await vm.loadProfiles()
        #expect(vm.hasProfiles == false, "Empty store => hasProfiles false")

        await store.upsert(Self.makeProfile())
        await vm.loadProfiles()
        #expect(vm.hasProfiles == true, "Non-empty store => hasProfiles true")
    }

    // MARK: - Live resync via providerProfilesDidChange notification
    //
    // Round-1 audit finding [1] — without the notification observer,
    // edits made from Settings while the in-reader picker is presented
    // wouldn't propagate (rename/delete/active flip stayed stale until
    // sheet dismiss+reopen). The store now posts on every mutation;
    // the picker VM subscribes in init and re-runs loadProfiles().
    //
    // Note: notification delivery hops through NotificationCenter +
    // Task @MainActor, so the test polls briefly for the expected
    // state rather than asserting synchronously.

    @Test @MainActor func notification_resyncsActiveID_afterStoreMutation() async throws {
        let store = Self.makeStore()
        let first = Self.makeProfile(name: "First")
        let second = Self.makeProfile(name: "Second")
        await store.upsert(first)
        await store.upsert(second)
        await store.setActiveProfileID(first.id)

        let vm = Self.makeVM(store: store)
        await vm.loadProfiles()
        #expect(vm.activeID == first.id)

        // Mutate the store directly (simulating an edit from Settings).
        await store.setActiveProfileID(second.id)

        // Poll for the notification-driven resync. Bound the wait so a
        // genuine regression fails the test instead of hanging.
        try await pollUntil(timeoutMs: 500) { @MainActor in
            vm.activeID == second.id
        }
        #expect(vm.activeID == second.id, "Picker must resync activeID after a Notification post")
    }

    @Test @MainActor func notification_resyncsProfilesList_afterUpsert() async throws {
        let store = Self.makeStore()
        let vm = Self.makeVM(store: store)
        await vm.loadProfiles()
        #expect(vm.profiles.isEmpty)

        let p = Self.makeProfile(name: "Late Comer")
        await store.upsert(p)

        try await pollUntil(timeoutMs: 500) { @MainActor in
            vm.profiles.count == 1
        }
        #expect(vm.profiles.first?.id == p.id, "Newly-upserted profile must appear in picker via notification resync")
    }

    /// Polls every 10ms until `condition()` is true or `timeoutMs`
    /// elapses. Used for notification-driven state changes that hop
    /// through Task @MainActor and don't complete synchronously.
    @MainActor
    private func pollUntil(timeoutMs: Int, condition: @MainActor @escaping () -> Bool) async throws {
        let start = Date()
        let limit = TimeInterval(timeoutMs) / 1000.0
        while Date().timeIntervalSince(start) < limit {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
    }
}
