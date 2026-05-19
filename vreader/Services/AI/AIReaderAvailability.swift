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
// - Bug #237: a DEBUG-only AITestOverride.forceAvailable seam short-circuits
//   isAvailable so a headless XCUITest (which cannot supply a real API key or
//   a consent grant) can reach the AI surfaces. Off in Release.
//
// @coordinates-with: FeatureFlags.swift, KeychainService.swift,
//   AIConsentManager.swift, ReaderContainerView.swift, VReaderApp.swift

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
    ///
    /// `@MainActor`-isolated: every caller (LibraryView, ReaderContainerView,
    /// ReaderAICoordinator) is already MainActor, and the DEBUG override below
    /// reads MainActor-isolated `AITestOverride`.
    @MainActor
    static func isAvailable(
        featureFlags: FeatureFlags,
        keychainService: KeychainService,
        consentManager: AIConsentManager
    ) -> Bool {
        #if DEBUG
        // Bug #237: the --enable-ai XCUITest launch flag forces availability
        // so a CU-free verification test can reach the AI surfaces. A headless
        // XCUITest cannot supply a real API key or a consent grant, so the
        // three production gates below can never all pass under test. DEBUG-only.
        if AITestOverride.forceAvailable { return true }
        #endif
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

#if DEBUG
/// DEBUG-only test override for AI reader availability. Set from the
/// `--enable-ai` XCUITest launch flag in `VReaderApp` so a CU-free
/// verification test can reach the AI surfaces (Summarize / Chat /
/// Translate sheet, AI assistant) — a headless XCUITest cannot supply a
/// real API key or a consent grant, so the three production gates in
/// `AIReaderAvailability.isAvailable` can never all pass under test
/// without this seam. Bug #237.
///
/// `@MainActor`-isolated, mirroring `TTSTestOverride`: written once per
/// process at `VReaderApp` launch and read on the same MainActor inside
/// `isAvailable`, so there is no cross-actor write contention — and unit
/// tests that flip it cannot race a parallel `isAvailable` reader.
/// `#if DEBUG` keeps it out of Release builds.
@MainActor
enum AITestOverride {
    /// When true, `AIReaderAvailability.isAvailable` short-circuits to
    /// `true`, bypassing the feature-flag + API-key + consent gates.
    static var forceAvailable = false
}
#endif
