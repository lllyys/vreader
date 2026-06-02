// Purpose: Feature #81 — pin the `AIProviderEditSheet.onSaveSuccess` reader
// hook. The hook fires AFTER a successful add/update (just before dismiss),
// carrying the saved profile id + `wasAdd`, and does NOT fire when the save
// fails (validation / unknown-profile). The Library path passes nil, so its
// behavior is unchanged.
//
// These are behavior tests on the view's `save()` method (callback contract),
// not render tests — `save()` is invoked directly against an isolated
// in-memory AISettingsViewModel. `@Environment(\.dismiss)` defaults to a no-op
// outside a view hierarchy, so calling `save()` is safe.
//
// @coordinates-with: vreader/Views/Settings/AIProviderEditSheet.swift,
//   AISettingsViewModel.swift, AISettingsViewModel+Editor.swift,
//   ProviderProfileStore.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #81 — AIProviderEditSheet.onSaveSuccess")
@MainActor
struct AIProviderEditSheetSaveSuccessTests {

    // MARK: - Helpers

    private static func makeIsolatedVM() -> (AISettingsViewModel, ProviderProfileStore) {
        let flags = FeatureFlags(environment: .prod)
        let consent = AIConsentManager(
            defaults: UserDefaults(suiteName: "com.vreader.test.consent.\(UUID().uuidString)")!
        )
        let keychain = KeychainService(serviceIdentifier: "com.vreader.test.\(UUID().uuidString)")
        let store = ProviderProfileStore(
            preferences: MockPreferenceStore(),
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )
        let vm = AISettingsViewModel(
            featureFlags: flags,
            consentManager: consent,
            keychainService: keychain,
            profileStore: store
        )
        return (vm, store)
    }

    private static func makeProfile(name: String = "OpenAI") -> ProviderProfile {
        let kind = ProviderKind.openAICompatible
        return ProviderProfile(
            id: UUID(), name: name, kind: kind,
            baseURL: kind.defaultBaseURL, model: kind.defaultModel,
            temperature: 0.7, maxTokens: 2048
        )
    }

    // MARK: - Add mode fires with wasAdd == true

    @Test func addModeSave_firesOnSaveSuccess_withWasAddTrue() async {
        let (vm, _) = Self.makeIsolatedVM()

        var captured: (id: UUID, wasAdd: Bool)?
        let sheet = AIProviderEditSheet(
            viewModel: vm,
            existing: nil,
            onSaveSuccess: { id, wasAdd in captured = (id, wasAdd) }
        )
        // Give the add a name so it's a realistic save (canSave parity).
        sheet.name = "My Provider"

        await sheet.save()

        #expect(captured != nil, "onSaveSuccess must fire after a successful add")
        #expect(captured?.id == sheet.profileID)
        #expect(captured?.wasAdd == true)
        // The provider actually landed and became active (first provider).
        await vm.loadProfiles()
        #expect(vm.profiles.contains { $0.id == sheet.profileID })
        #expect(vm.activeID == sheet.profileID)
    }

    // MARK: - Edit mode fires with wasAdd == false

    @Test func editModeSave_firesOnSaveSuccess_withWasAddFalse() async {
        let (vm, _) = Self.makeIsolatedVM()
        let existing = Self.makeProfile(name: "Original")
        await vm.addProfile(existing, apiKey: "k")
        await vm.loadProfiles()

        var captured: (id: UUID, wasAdd: Bool)?
        let sheet = AIProviderEditSheet(
            viewModel: vm,
            existing: existing,
            onSaveSuccess: { id, wasAdd in captured = (id, wasAdd) }
        )

        await sheet.save()

        #expect(captured?.id == existing.id)
        #expect(captured?.wasAdd == false, "an edit of an existing profile is not an add")
    }

    // MARK: - Failure does NOT fire

    @Test func saveFailure_unknownProfile_doesNotFireOnSaveSuccess() async {
        let (vm, _) = Self.makeIsolatedVM()
        // existing profile NOT in the store → updateProfile sets editorError
        // and does not persist; the success hook must not fire.
        let orphan = Self.makeProfile(name: "Ghost")

        var fired = false
        let sheet = AIProviderEditSheet(
            viewModel: vm,
            existing: orphan,
            onSaveSuccess: { _, _ in fired = true }
        )

        await sheet.save()

        #expect(vm.editorError != nil, "updating an unknown profile must error")
        #expect(fired == false, "onSaveSuccess must not fire when the save failed")
    }

    // MARK: - Library path (nil hook) is a no-op

    @Test func nilHook_addStillSucceeds() async {
        let (vm, _) = Self.makeIsolatedVM()
        let sheet = AIProviderEditSheet(viewModel: vm, existing: nil)
        sheet.name = "NoHook"

        await sheet.save()

        await vm.loadProfiles()
        #expect(vm.profiles.contains { $0.id == sheet.profileID },
                "a nil onSaveSuccess must not affect the normal add path")
    }
}
