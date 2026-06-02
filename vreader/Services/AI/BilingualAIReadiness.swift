// Purpose: Bug #301 — the readiness probe for bilingual translation. Mirrors the
// EXACT gate the live pipeline enforces (unlike `AIReaderAvailability`, which
// checks the legacy keychain key and the wrong surface): the `aiAssistant`
// feature flag, AI consent, an ACTIVE provider profile, and that profile's
// per-profile API key (`AIService.resolveProviderConfig` → `AIService.sendRequest`).
//
// Async because the active-profile lookup is an actor call and the per-profile
// key is a keychain read. The bilingual setup sheet resolves this into state
// (`BilingualReadingViewModel.aiConfigured`) so its `configured` descriptor
// truthfully predicts whether bilingual will actually translate.
//
// @coordinates-with: AIService.swift (the gate this mirrors),
//   ProviderProfileStore.swift, KeychainService+ProviderProfile.swift,
//   AIConsentManager.swift, BilingualReadingViewModel.swift

import Foundation

enum BilingualAIReadiness {

    /// True when bilingual translation would actually run: `aiAssistant` flag ON,
    /// consent granted, an active provider profile exists, and that profile has a
    /// non-empty per-profile API key. Injectable for testing; defaults to the
    /// production singletons.
    @MainActor
    static func resolve(
        featureFlags: FeatureFlags = .shared,
        consentManager: AIConsentManager = AIConsentManager(),
        profileStore: ProviderProfileStore = .shared,
        keychainService: KeychainService = KeychainService()
    ) async -> Bool {
        guard featureFlags.isEnabled(.aiAssistant) else { return false }
        guard consentManager.hasConsent else { return false }
        guard let profile = await profileStore.activeProfileSnapshot() else { return false }
        let key = try? keychainService.readAPIKey(forProfile: profile.id)
        return (key?.isEmpty == false)
    }
}
