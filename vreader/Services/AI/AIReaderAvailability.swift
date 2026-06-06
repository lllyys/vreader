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
        consentManager: AIConsentManager,
        providerPreferences: any PreferenceStoring = UserDefaultsPreferenceStore()
    ) -> Bool {
        #if DEBUG
        // Bug #237: the --enable-ai XCUITest launch flag forces availability
        // so a CU-free verification test can reach the AI surfaces. A headless
        // XCUITest cannot supply a real API key or a consent grant, so the
        // three production gates below can never all pass under test. DEBUG-only.
        if AITestOverride.forceAvailable { return true }
        #endif
        guard featureFlags.aiAssistant else { return false }
        guard hasAPIKey(keychainService: keychainService, providerPreferences: providerPreferences) else { return false }
        return consentManager.hasConsent
    }

    /// Returns true when a usable API key exists — either the legacy single-key
    /// account OR the **active provider profile's per-profile key**.
    ///
    /// Feature #82 / Bug #308: the AI panel/button previously gated only on the
    /// legacy `AIService.apiKeyAccount` key, so a user who configured a provider
    /// through the multi-profile path (in-reader readiness flow, Library AI
    /// settings) had no legacy key and the AI button stayed a silent no-op —
    /// looping back to readiness forever. This now mirrors the gate the live
    /// request path (`AIService` / `BilingualAIReadiness`) actually uses. The
    /// active-provider lookup is a synchronous static read of the same
    /// UserDefaults the shared `ProviderProfileStore` writes, so `isAvailable`
    /// stays sync (no async ripple) and re-reads fresh on each access.
    ///
    /// - Parameters:
    ///   - keychainService: The keychain to read keys from.
    ///   - providerPreferences: The preference store the provider list lives in
    ///     (defaults to the shared `UserDefaultsPreferenceStore`).
    static func hasAPIKey(
        keychainService: KeychainService,
        providerPreferences: any PreferenceStoring = UserDefaultsPreferenceStore()
    ) -> Bool {
        // Active provider FIRST — mirror the live request gate
        // (`AIService.resolveProvider` uses the active profile). When an active
        // profile exists, ITS per-profile key is authoritative: a stale legacy
        // key must NOT mask a key-less active profile (which would make
        // `isAvailable` true while the request throws `apiKeyMissing`).
        if let activeID = DefaultProviderProfileMigrator.readActiveID(preferences: providerPreferences) {
            if let key = try? keychainService.readAPIKey(forProfile: activeID),
               !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return false
        }
        // No active profile → legacy single-key fallback (pre-migration installs
        // that never adopted the multi-profile store).
        if let legacy = try? keychainService.readString(forAccount: AIService.apiKeyAccount),
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
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

    /// When set (via the `--mock-ai` launch flag), `AIService.resolveProvider`
    /// and `providerInstance(for:)` return this provider ahead of any real
    /// profile resolution — so AI flows run key-free + deterministic for CU-free
    /// verification. `nonisolated(unsafe)`: set ONCE at launch (before any AI
    /// request) and read-only thereafter, including from the `AIService` actor;
    /// `any AIProvider` is `Sendable`, so the read is data-race-free in practice.
    nonisolated(unsafe) static var mockProvider: (any AIProvider)?
}
#endif
