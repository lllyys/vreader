// Purpose: Centralizes error → user-facing message mapping.
// Ensures no raw paths, URLs, or technical details leak to the UI.
//
// Key decisions:
// - Delegates to domain-specific userMessage where available (ImportError).
// - For errors with LocalizedError conformance, uses sanitized messages.
// - Unknown errors get a generic fallback.
// - Never exposes file paths, stack traces, or internal identifiers.
//
// @coordinates-with: ImportError.swift, AIError.swift, SyncTypes.swift,
//   KeychainService.swift, SearchIndexStore.swift

import Foundation

/// Sanitizes errors into user-friendly messages for UI display.
enum ErrorMessageAuditor {

    /// The generic fallback message for unrecognized errors.
    static let genericMessage = "An unexpected error occurred. Please try again."

    /// Returns a user-safe error message for any Error.
    /// Never exposes file paths, technical details, or internal state.
    static func sanitize(_ error: Error) -> String {
        switch error {
        // ImportError already has carefully written userMessage
        case let importError as ImportError:
            return importError.userMessage

        case let persistenceError as PersistenceError:
            return sanitizePersistence(persistenceError)

        case let keychainError as KeychainError:
            return sanitizeKeychain(keychainError)

        case let aiError as AIError:
            return sanitizeAI(aiError)

        case let syncError as SyncError:
            return sanitizeSync(syncError)

        case let searchError as SearchIndexError:
            return sanitizeSearch(searchError)

        default:
            return genericMessage
        }
    }

    // MARK: - Private

    private static func sanitizePersistence(_ error: PersistenceError) -> String {
        switch error {
        case .recordNotFound:
            return "The requested item could not be found."
        case .invalidContent:
            return "The content could not be processed."
        }
    }

    private static func sanitizeKeychain(_ error: KeychainError) -> String {
        // All keychain errors map to one user-facing message — details are internal.
        "A secure storage error occurred. Please try again."
    }

    private static func sanitizeAI(_ error: AIError) -> String {
        switch error {
        case .featureDisabled:
            return "AI features are currently disabled."
        case .consentRequired:
            return "Please grant consent to use AI features."
        case .apiKeyMissing:
            return "No API key configured. Add one in Settings."
        case .providerError:
            return "The AI service encountered an error. Please try again."
        case .networkError:
            return "A network error occurred. Check your connection and try again."
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .contextExtractionFailed:
            return "Could not extract text context for AI."
        case .invalidResponse:
            return "Received an invalid response from the AI provider."
        case .cacheMiss:
            // Internal-only error; should not reach UI. Generic fallback.
            return genericMessage
        }
    }

    private static func sanitizeSync(_ error: SyncError) -> String {
        switch error {
        case .syncDisabled:
            return "Sync is currently disabled."
        case .networkUnavailable:
            return "No network connection. Sync will resume when you're back online."
        case .authenticationFailed:
            return "Could not sign in to sync. Please check your account."
        case .quotaExceeded:
            return "Cloud storage quota exceeded. Free up space to continue syncing."
        case .checksumMismatch:
            return "A file verification error occurred during sync."
        case .mergeConflict:
            return "A sync conflict occurred. Please try again."
        case .unknown:
            return "A sync error occurred. Please try again."
        }
    }

    private static func sanitizeSearch(_ error: SearchIndexError) -> String {
        switch error {
        case .databaseOpenFailed:
            return "Could not open the search index. Please restart the app."
        case .queryFailed:
            return "The search query failed. Please try a different search."
        case .indexFailed:
            return "Could not index content for search."
        }
    }
}
