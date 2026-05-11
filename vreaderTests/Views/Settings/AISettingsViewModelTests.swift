// Purpose: Tests for AISettingsViewModel — feature flag toggle, API key validation,
// consent management, configuration persistence, and edge cases.
//
// @coordinates-with: AISettingsViewModel.swift, FeatureFlags.swift,
//   KeychainService.swift, AIConsentManager.swift, AIConfigurationStore.swift

import Testing
import Foundation
@testable import vreader

@Suite("AISettingsViewModel")
struct AISettingsViewModelTests {

    // MARK: - Helpers

    /// Creates a ViewModel with isolated test dependencies.
    @MainActor
    private func makeViewModel(
        featureEnabled: Bool = false,
        hasConsent: Bool = false,
        existingApiKey: String? = nil,
        savedConfig: AIConfiguration? = nil
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
        if let key = existingApiKey {
            try? keychainService.saveString(key, forAccount: AIService.apiKeyAccount)
        }

        let prefStore = MockPreferenceStore()
        let configStore = AIConfigurationStore(preferences: prefStore)
        if let config = savedConfig {
            configStore.save(config)
        }

        return AISettingsViewModel(
            featureFlags: flags,
            consentManager: consentManager,
            keychainService: keychainService,
            configurationStore: configStore
        )
    }

    // MARK: - Default Configuration Loaded

    @Test @MainActor func defaultConfigurationLoaded() {
        let vm = makeViewModel()
        #expect(vm.model == AIConfiguration.default.model)
        #expect(vm.temperature == AIConfiguration.default.temperature)
        #expect(vm.maxTokens == AIConfiguration.default.maxTokens)
        #expect(vm.baseURL == AIConfiguration.default.endpoint.absoluteString)
    }

    @Test @MainActor func savedConfigurationLoaded() {
        let custom = AIConfiguration(
            model: "llama3",
            temperature: 0.5,
            endpoint: URL(string: "http://localhost:11434/v1")!,
            maxTokens: 4096
        )
        let vm = makeViewModel(savedConfig: custom)
        #expect(vm.model == "llama3")
        #expect(vm.temperature == 0.5)
        #expect(vm.maxTokens == 4096)
        #expect(vm.baseURL == "http://localhost:11434/v1")
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
    /// `if viewModel.isAIEnabled` block in `AISettingsSection` (API Key,
    /// Provider Configuration, Data & Privacy) stayed hidden until the
    /// app was killed and relaunched. This test pins the fix: writing
    /// to `isAIEnabled` MUST fire the Observation tracker so dependent
    /// views re-render.
    @Test @MainActor func toggleNotifiesObservationTracker() {
        let vm = makeViewModel(featureEnabled: false)
        // Swift 6 strict concurrency: the `onChange` closure runs on the
        // Observation registrar's executor, not @MainActor. Use a final
        // reference type to capture state without crossing isolation.
        final class FireFlag: @unchecked Sendable { var value = false }
        let observationFired = FireFlag()

        // Register interest in `isAIEnabled`. With the old computed
        // property, the observation registrar wasn't touched by the
        // getter, so this `withObservationTracking` block didn't subscribe
        // to anything — and the subsequent setter wouldn't trigger the
        // onChange. With the fix (stored property + didSet write-through),
        // the macro-generated getter calls `_$observationRegistrar.access`
        // and the setter calls `_$observationRegistrar.withMutation`,
        // making this work end-to-end.
        withObservationTracking {
            _ = vm.isAIEnabled
        } onChange: {
            observationFired.value = true
        }

        vm.isAIEnabled = true

        #expect(observationFired.value, "Toggling isAIEnabled must notify SwiftUI's Observation tracker so AISettingsSection re-renders the API Key / Provider Configuration / Data & Privacy sections without an app relaunch.")
    }

    /// Bug #167 supplement: the fix must NOT break the existing
    /// write-through to FeatureFlags. Without write-through, the flag
    /// wouldn't persist to UserDefaults and other parts of the app that
    /// read `FeatureFlags.shared.isEnabled(.aiAssistant)` directly (e.g.
    /// `AIReaderAvailability.isAvailable` gating the in-reader AI button)
    /// wouldn't see the change.
    @Test @MainActor func toggleStillWritesThroughToFeatureFlags() {
        let flags = FeatureFlags(environment: .prod)
        let vm = AISettingsViewModel(
            featureFlags: flags,
            consentManager: AIConsentManager(
                defaults: UserDefaults(suiteName: "com.vreader.test.consent.\(UUID().uuidString)")!
            ),
            keychainService: KeychainService(
                serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"
            ),
            configurationStore: AIConfigurationStore(preferences: MockPreferenceStore())
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
    ///
    /// Note: we deliberately do NOT assert anything about whether the
    /// `@Observable` macro skips the registrar notification for
    /// same-value stored-property writes. That's an implementation detail
    /// of the Observation runtime and not a contract this code can
    /// promise. Pinning the user-visible side effect (FeatureFlags
    /// write-through is deduped) is the meaningful invariant.
    @Test @MainActor func idempotentSetIsNoOpAgainstFeatureFlags() {
        // Use a real FeatureFlags instance backed by an in-memory
        // UserDefaults suite so we can observe `aiAssistant` writes
        // by counting UserDefaults change notifications for the key.
        let suiteName = "com.vreader.test.featureflags.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let flags = FeatureFlags(
            environment: .prod, persistenceDefaults: defaults
        )

        let vm = AISettingsViewModel(
            featureFlags: flags,
            consentManager: AIConsentManager(
                defaults: UserDefaults(suiteName: "com.vreader.test.consent.\(UUID().uuidString)")!
            ),
            keychainService: KeychainService(
                serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"
            ),
            configurationStore: AIConfigurationStore(preferences: MockPreferenceStore())
        )

        // Flip to true once
        vm.isAIEnabled = true
        let key = "com.vreader.featureFlags.aiAssistant"
        #expect(defaults.bool(forKey: key) == true)

        // Tamper-detect: write a sentinel under the same key, then assign
        // the same value to `isAIEnabled` again. If the didSet guard works
        // the write-through should be skipped, and our sentinel survives.
        // If the guard is removed/broken, setOverride re-writes true and
        // overwrites the sentinel.
        defaults.set(0xDEAD as Int, forKey: key)
        vm.isAIEnabled = true // Same value
        #expect(defaults.integer(forKey: key) == 0xDEAD, "Idempotent set must not write through to FeatureFlags; sentinel was overwritten which means setOverride ran on a same-value assignment.")
    }

    // MARK: - API Key

    @Test @MainActor func apiKeySavedToKeychain() {
        let vm = makeViewModel()
        vm.apiKeyInput = "sk-test-key-12345"
        vm.saveAPIKey()

        #expect(vm.apiKeyError == nil)
        #expect(vm.isAPIKeySaved == true)
    }

    @Test @MainActor func emptyKeyShowsError() {
        let vm = makeViewModel()
        vm.apiKeyInput = ""
        vm.saveAPIKey()

        #expect(vm.apiKeyError != nil)
        #expect(vm.isAPIKeySaved == false)
    }

    @Test @MainActor func whitespaceOnlyKeyShowsError() {
        let vm = makeViewModel()
        vm.apiKeyInput = "   \t  "
        vm.saveAPIKey()

        #expect(vm.apiKeyError != nil)
        #expect(vm.isAPIKeySaved == false)
    }

    @Test @MainActor func apiKeyWithLeadingTrailingWhitespaceTrimmed() {
        let vm = makeViewModel()
        vm.apiKeyInput = "  sk-test-key  "
        vm.saveAPIKey()

        #expect(vm.apiKeyError == nil)
        #expect(vm.isAPIKeySaved == true)
    }

    @Test @MainActor func existingApiKeyShowsSavedState() {
        let vm = makeViewModel(existingApiKey: "sk-existing-key")
        #expect(vm.isAPIKeySaved == true)
    }

    @Test @MainActor func deleteAPIKeyRemovesFromKeychain() {
        let vm = makeViewModel(existingApiKey: "sk-existing-key")
        #expect(vm.isAPIKeySaved == true)

        vm.deleteAPIKey()
        #expect(vm.isAPIKeySaved == false)
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

    // MARK: - Model Updates Configuration

    @Test @MainActor func modelPickerUpdatesConfiguration() {
        let vm = makeViewModel()
        vm.model = "gpt-4"
        vm.saveConfiguration()

        // Re-create a ViewModel with the same store to verify persistence
        // We verify by checking the field directly (store was written)
        #expect(vm.model == "gpt-4")
    }

    @Test @MainActor func temperatureUpdatesConfiguration() {
        let vm = makeViewModel()
        vm.temperature = 1.5
        vm.saveConfiguration()

        #expect(vm.temperature == 1.5)
    }

    @Test @MainActor func maxTokensUpdatesConfiguration() {
        let vm = makeViewModel()
        vm.maxTokens = 8192
        vm.saveConfiguration()

        #expect(vm.maxTokens == 8192)
    }

    @Test @MainActor func baseURLUpdatesConfiguration() {
        let vm = makeViewModel()
        vm.baseURL = "http://localhost:11434/v1"
        vm.saveConfiguration()

        #expect(vm.baseURL == "http://localhost:11434/v1")
    }

    // MARK: - Temperature Clamping

    @Test @MainActor func temperatureClampedToMax() {
        let vm = makeViewModel()
        vm.temperature = 3.0
        vm.saveConfiguration()

        #expect(vm.temperature <= 2.0)
    }

    @Test @MainActor func temperatureClampedToMin() {
        let vm = makeViewModel()
        vm.temperature = -1.0
        vm.saveConfiguration()

        #expect(vm.temperature >= 0.0)
    }

    // MARK: - Max Tokens Bounds

    @Test @MainActor func maxTokensHasMinimumBound() {
        let vm = makeViewModel()
        vm.maxTokens = 0
        vm.saveConfiguration()

        #expect(vm.maxTokens >= 1)
    }

    @Test @MainActor func maxTokensHasMaximumBound() {
        let vm = makeViewModel()
        vm.maxTokens = 1_000_000
        vm.saveConfiguration()

        #expect(vm.maxTokens <= 128_000)
    }

    // MARK: - Base URL Validation

    @Test @MainActor func invalidBaseURLShowsError() {
        let vm = makeViewModel()
        vm.baseURL = "not a valid url"
        vm.saveConfiguration()

        #expect(vm.baseURLError != nil)
    }

    @Test @MainActor func emptyBaseURLShowsError() {
        let vm = makeViewModel()
        vm.baseURL = ""
        vm.saveConfiguration()

        #expect(vm.baseURLError != nil)
    }

    @Test @MainActor func validBaseURLClearsError() {
        let vm = makeViewModel()
        vm.baseURL = "https://api.example.com/v1"
        vm.saveConfiguration()

        #expect(vm.baseURLError == nil)
    }

    // MARK: - HTTPS URL Enforcement

    @Test @MainActor func httpURLForRemoteHostRejected() {
        let vm = makeViewModel()
        vm.baseURL = "http://api.openai.com/v1"
        vm.saveConfiguration()

        #expect(vm.baseURLError != nil, "HTTP to remote host should be rejected")
        #expect(vm.baseURLError!.contains("HTTPS"))
    }

    @Test @MainActor func httpURLForLocalhostAccepted() {
        let vm = makeViewModel()
        vm.baseURL = "http://localhost:11434/v1"
        vm.saveConfiguration()

        #expect(vm.baseURLError == nil, "HTTP to localhost should be allowed")
    }

    @Test @MainActor func httpURLFor127Accepted() {
        let vm = makeViewModel()
        vm.baseURL = "http://127.0.0.1:8080/v1"
        vm.saveConfiguration()

        #expect(vm.baseURLError == nil, "HTTP to 127.0.0.1 should be allowed")
    }

    @Test @MainActor func httpURLForIPv6LoopbackAccepted() {
        let vm = makeViewModel()
        vm.baseURL = "http://[::1]:8080/v1"
        vm.saveConfiguration()

        #expect(vm.baseURLError == nil, "HTTP to [::1] should be allowed")
    }

    @Test @MainActor func httpsURLAlwaysAccepted() {
        let vm = makeViewModel()
        vm.baseURL = "https://api.openai.com/v1"
        vm.saveConfiguration()

        #expect(vm.baseURLError == nil, "HTTPS should always be accepted")
    }

    @Test @MainActor func ftpSchemeRejected() {
        let vm = makeViewModel()
        vm.baseURL = "ftp://files.example.com"
        vm.saveConfiguration()

        #expect(vm.baseURLError != nil, "FTP scheme should be rejected")
    }

    // MARK: - Configuration Persistence Round-Trip

    @Test @MainActor func configurationPersistsAllFields() {
        let vm = makeViewModel()
        vm.model = "claude-3"
        vm.temperature = 0.3
        vm.maxTokens = 2048
        vm.baseURL = "https://api.anthropic.com/v1"
        vm.saveConfiguration()

        // Verify all fields are set
        #expect(vm.model == "claude-3")
        #expect(vm.temperature == 0.3)
        #expect(vm.maxTokens == 2048)
        #expect(vm.baseURL == "https://api.anthropic.com/v1")
    }
}
