// Purpose: Manages user consent for AI features.
// Consent is stored in UserDefaults (not a secret — just a preference).
//
// Key decisions:
// - Struct-based with injected UserDefaults for testability.
// - Consent date is recorded for audit/compliance.
// - Revoking consent returns a flag indicating cache should be cleared.
// - No outbound calls are allowed before consent is granted.
// - Sendable for cross-actor use.
//
// @coordinates-with: AIService.swift, AIConsentView.swift

import Foundation

/// Manages user consent for AI outbound network calls.
struct AIConsentManager: Sendable {

    private static let consentKey = "com.vreader.ai.consentGranted"
    private static let consentDateKey = "com.vreader.ai.consentDate"

    // UserDefaults is thread-safe but not marked Sendable in Swift 6.
    // nonisolated(unsafe) is safe here because UserDefaults' methods are thread-safe.
    private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the user has granted consent for AI features.
    var hasConsent: Bool {
        defaults.bool(forKey: Self.consentKey)
    }

    /// The date consent was granted, if any.
    var consentDate: Date? {
        defaults.object(forKey: Self.consentDateKey) as? Date
    }

    /// Records that the user has granted consent.
    func grantConsent() {
        defaults.set(true, forKey: Self.consentKey)
        defaults.set(Date(), forKey: Self.consentDateKey)
    }

    /// Revokes consent and clears the consent date.
    func revokeConsent() {
        defaults.removeObject(forKey: Self.consentKey)
        defaults.removeObject(forKey: Self.consentDateKey)
    }
}
