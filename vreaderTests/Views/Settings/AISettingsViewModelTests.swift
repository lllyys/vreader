// Purpose: Tests for AISettingsViewModel — global AI feature flag toggle
// and consent state only. Provider-list operations are covered separately
// by `AISettingsViewModelMultiProfileTests.swift` (feature #50 WI-6a).
//
// Feature #50 WI-6a: the previous incarnation of this file tested the
// single-profile fields (apiKeyInput, model, baseURL, temperature,
// maxTokens, saveAPIKey/deleteAPIKey/saveConfiguration). Those fields
// moved off the VM when the multi-profile rewrite landed. The
// editor-side counterparts will be re-added by WI-6b under
// `AISettingsViewModelMultiProfileTests`.
//
// What stays here:
// - Bug #167 regression: isAIEnabled must be a stored property + didSet,
//   not a pure computed property, so the @Observable macro instruments
//   the storage and SwiftUI re-renders.
// - Write-through to FeatureFlags so cross-app readers (e.g.
//   AIReaderAvailability) see the change.
// - Same-value-set deduping to prevent redundant UserDefaults writes.
// - Consent grant/revoke pass-through.
//
// @coordinates-with: AISettingsViewModel.swift, FeatureFlags.swift,
//   AIConsentManager.swift

import Testing
import Foundation
@testable import vreader

@Suite("AISettingsViewModel")
struct AISettingsViewModelTests {

    // MARK: - Helpers

    /// Creates a ViewModel with isolated test dependencies. The store
    /// parameter defaults to a fresh test-isolated ProviderProfileStore
    /// (so this suite doesn't touch `.shared`).
    @MainActor
    private func makeViewModel(
        featureEnabled: Bool = false,
        hasConsent: Bool = false
    ) -> AISettingsViewModel {
        let flags = FeatureFlags(environment: .prod)
        if featureEnabled {
            flags.setOverride(true, for: .aiAssistant)
        }

        let consentSuiteName = "com.vreader.test.consent.\(UUID().uuidString)"
        let consentDefaults = UserDefaults(suiteName: consentSuiteName)!
        let consentManager = AIConsentManager(defaults: consentDefaults)
        if hasConsent {
            consentManager.grantConsent()
        }

        let keychainService = KeychainService(
            serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"
        )

        let store = ProviderProfileStore(
            preferences: MockPreferenceStore(),
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychainService
        )

        return AISettingsViewModel(
            featureFlags: flags,
            consentManager: consentManager,
            keychainService: keychainService,
            profileStore: store
        )
    }

    // MARK: - Toggle AI Updates Feature Flag

    @Test @MainActor func toggleAIUpdatesFeatureFlag() {
        let vm = makeViewModel(featureEnabled: false)
        #expect(vm.isAIEnabled == false)

        vm.isAIEnabled = true
        #expect(vm.isAIEnabled == true)

        vm.isAIEnabled = false
        #expect(vm.isAIEnabled == false)
    }

    // MARK: - Observation Notification (Bug #167)

    /// Bug #167: `isAIEnabled` was a pure get/set computed property
    /// delegating to `FeatureFlags.isEnabled` / `setOverride`. The
    /// `@Observable` macro only instruments stored properties — a pure
    /// computed property whose body reads/writes a non-Observable class
    /// bypasses the observation registrar entirely. As a result, toggling
    /// the AI Settings switch flipped the underlying flag in `FeatureFlags`
    /// but did NOT notify SwiftUI to re-render, so the conditional
    /// `if viewModel.isAIEnabled` block in `AISettingsSection` (Providers,
    /// Data & Privacy) stayed hidden until the app was killed and
    /// relaunched. This test pins the fix: writing to `isAIEnabled` MUST
    /// fire the Observation tracker so dependent views re-render.
    @Test @MainActor func toggleNotifiesObservationTracker() {
        let vm = makeViewModel(featureEnabled: false)
        // Swift 6 strict concurrency: the `onChange` closure runs on the
        // Observation registrar's executor, not @MainActor. Use a final
        // reference type to capture state without crossing isolation.
        final class FireFlag: @unchecked Sendable { var value = false }
        let observationFired = FireFlag()

        withObservationTracking {
            _ = vm.isAIEnabled
        } onChange: {
            observationFired.value = true
        }

        vm.isAIEnabled = true

        #expect(observationFired.value, "Toggling isAIEnabled must notify SwiftUI's Observation tracker so AISettingsSection re-renders the conditional sections without an app relaunch.")
    }

    /// Bug #167 supplement: the fix must NOT break the existing
    /// write-through to FeatureFlags. Without write-through, the flag
    /// wouldn't persist to UserDefaults and other parts of the app that
    /// read `FeatureFlags.shared.isEnabled(.aiAssistant)` directly (e.g.
    /// `AIReaderAvailability.isAvailable` gating the in-reader AI button)
    /// wouldn't see the change.
    @Test @MainActor func toggleStillWritesThroughToFeatureFlags() {
        let flags = FeatureFlags(environment: .prod)
        let keychain = KeychainService(
            serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"
        )
        let store = ProviderProfileStore(
            preferences: MockPreferenceStore(),
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )
        let vm = AISettingsViewModel(
            featureFlags: flags,
            consentManager: AIConsentManager(
                defaults: UserDefaults(suiteName: "com.vreader.test.consent.\(UUID().uuidString)")!
            ),
            keychainService: keychain,
            profileStore: store
        )

        #expect(flags.isEnabled(.aiAssistant) == false)

        vm.isAIEnabled = true
        #expect(flags.isEnabled(.aiAssistant) == true, "Setting isAIEnabled = true must write through to FeatureFlags so cross-app readers see the change.")

        vm.isAIEnabled = false
        #expect(flags.isEnabled(.aiAssistant) == false, "Setting isAIEnabled = false must write through to FeatureFlags so cross-app readers see the change.")
    }

    /// Bug #167 supplement: the `oldValue != isAIEnabled` guard inside
    /// the didSet prevents redundant `FeatureFlags.setOverride` calls
    /// (and the resulting redundant UserDefaults writes) when the toggle
    /// is reassigned to its current value — e.g. SwiftUI's `@Bindable`
    /// re-evaluating the same value during view rebinding.
    @Test @MainActor func idempotentSetIsNoOpAgainstFeatureFlags() {
        let suiteName = "com.vreader.test.featureflags.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let flags = FeatureFlags(
            environment: .prod, persistenceDefaults: defaults
        )

        let keychain = KeychainService(
            serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"
        )
        let store = ProviderProfileStore(
            preferences: MockPreferenceStore(),
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )
        let vm = AISettingsViewModel(
            featureFlags: flags,
            consentManager: AIConsentManager(
                defaults: UserDefaults(suiteName: "com.vreader.test.consent.\(UUID().uuidString)")!
            ),
            keychainService: keychain,
            profileStore: store
        )

        vm.isAIEnabled = true
        let key = "com.vreader.featureFlags.aiAssistant"
        #expect(defaults.bool(forKey: key) == true)

        // Tamper-detect: write a sentinel under the same key, then assign
        // the same value to `isAIEnabled` again. If the didSet guard works
        // the write-through should be skipped and our sentinel survives.
        defaults.set(0xDEAD as Int, forKey: key)
        vm.isAIEnabled = true // Same value
        #expect(defaults.integer(forKey: key) == 0xDEAD, "Idempotent set must not write through to FeatureFlags; sentinel was overwritten which means setOverride ran on a same-value assignment.")
    }

    // MARK: - Consent Toggle

    @Test @MainActor func consentToggleGrantsConsent() {
        let vm = makeViewModel(hasConsent: false)
        #expect(vm.hasConsent == false)

        vm.hasConsent = true
        #expect(vm.hasConsent == true)
    }

    @Test @MainActor func consentToggleRevokesConsent() {
        let vm = makeViewModel(hasConsent: true)
        #expect(vm.hasConsent == true)

        vm.hasConsent = false
        #expect(vm.hasConsent == false)
    }
}
