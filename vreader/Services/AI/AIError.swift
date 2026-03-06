// Purpose: Error taxonomy for the AI assistant feature.
// Maps every failure mode to a user-friendly message and a programmatic case.
//
// Key decisions:
// - Each gate (feature flag, consent, API key) has its own error case.
// - Provider and network errors carry underlying messages for debugging.
// - rateLimited includes optional retry-after for backoff.
// - cacheMiss is internal-only — never surfaced to the user.
// - Conforms to LocalizedError for SwiftUI error display.
//
// @coordinates-with: AIService.swift, AIAssistantViewModel.swift

import Foundation

/// Errors from the AI assistant subsystem.
enum AIError: Error, LocalizedError, Sendable, Equatable {
    /// The AI assistant feature flag is disabled.
    case featureDisabled

    /// The user has not granted consent for AI features.
    case consentRequired

    /// No API key is stored in the Keychain.
    case apiKeyMissing

    /// The AI provider returned an error.
    case providerError(String)

    /// A network-level error occurred.
    case networkError(String)

    /// The provider rate-limited the request.
    case rateLimited(retryAfterSeconds: Int?)

    /// Context extraction around the locator failed.
    case contextExtractionFailed

    /// The provider returned an unparseable response.
    case invalidResponse

    /// No cached response found. Internal only — not user-facing.
    case cacheMiss

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "AI features are currently disabled."
        case .consentRequired:
            return "Please grant consent to use AI features."
        case .apiKeyMissing:
            return "No API key configured. Add one in Settings."
        case .providerError(let message):
            return "AI provider error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Try again in \(seconds) seconds."
            }
            return "Rate limited. Please try again later."
        case .contextExtractionFailed:
            return "Could not extract text context for AI."
        case .invalidResponse:
            return "Received an invalid response from the AI provider."
        case .cacheMiss:
            return "No cached response available."
        }
    }
}
