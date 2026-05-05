// Purpose: Determines whether AI reader features are available to display in the UI.
// Encapsulates the feature-flag + API-key + consent gate so views and tests
// don't depend on AIService internals.
//
// Key decisions:
// - Pure functions with no side effects — easy to test.
// - Checks feature flag AND API key presence AND consent (all three must be true).
// - Bug #90: consent must be checked here, not only at request time. Showing
//   the button when consent is revoked led the user to discover the
//   consent-required error mid-task instead of at the entry point.
//
// @coordinates-with: FeatureFlags.swift, KeychainService.swift,
//   AIConsentManager.swift, ReaderContainerView.swift

import Foundation

/// Utility to check AI feature availability for reader UI.
enum AIReaderAvailability {

    /// Returns true when AI features should appear in the UI: feature flag on,
    /// API key saved, AND user consent granted. All three gates apply.
    ///
    /// - Parameters:
    ///   - featureFlags: The feature flags instance to check.
    ///   - keychainService: The keychain service to look up the API key.
    ///   - consentManager: The consent manager holding the user's outbound-call
    ///     opt-in. Required: showing AI affordances when consent is revoked
    ///     misleads users into believing the action will succeed.
    /// - Returns: Whether the AI button should be shown in the reader toolbar.
    static func isAvailable(
        featureFlags: FeatureFlags,
        keychainService: KeychainService,
        consentManager: AIConsentManager
    ) -> Bool {
        guard featureFlags.aiAssistant else { return false }
        guard hasAPIKey(keychainService: keychainService) else { return false }
        return consentManager.hasConsent
    }

    /// Returns true when a non-empty API key exists in the keychain.
    ///
    /// - Parameter keychainService: The keychain service to check.
    /// - Returns: Whether an API key is saved.
    static func hasAPIKey(keychainService: KeychainService) -> Bool {
        guard let key = try? keychainService.readString(
            forAccount: AIService.apiKeyAccount
        ) else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
