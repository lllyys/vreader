// Purpose: Tests for ErrorMessageAuditor — user-friendly error message sanitization.

import Testing
import Foundation
@testable import vreader

@Suite("ErrorMessageAuditor")
struct ErrorMessageAuditorTests {

    // MARK: - ImportError

    @Test func importUnsupportedFormat() {
        let msg = ErrorMessageAuditor.sanitize(ImportError.unsupportedFormat("docx"))
        #expect(msg == "The file format \"docx\" is not supported.")
    }

    @Test func importBinaryMasquerade() {
        let msg = ErrorMessageAuditor.sanitize(ImportError.binaryMasquerade)
        #expect(msg == "This file appears to be a binary file, not a text document.")
    }

    @Test func importFileNotReadable() {
        let msg = ErrorMessageAuditor.sanitize(ImportError.fileNotReadable("/private/secret/path.epub"))
        #expect(!msg.contains("/private"))
        #expect(!msg.contains("secret"))
        #expect(msg == "The file could not be read. It may be missing or inaccessible.")
    }

    @Test func importHashFailed() {
        let msg = ErrorMessageAuditor.sanitize(ImportError.hashComputationFailed("CC_SHA256 returned nil"))
        #expect(!msg.contains("CC_SHA256"))
        #expect(msg == "Could not verify file integrity.")
    }

    @Test func importDuplicate() {
        let msg = ErrorMessageAuditor.sanitize(ImportError.duplicateBook(fingerprintKey: "sha256:abc123"))
        #expect(!msg.contains("sha256"))
        #expect(msg == "This book is already in your library.")
    }

    @Test func importCancelled() {
        let msg = ErrorMessageAuditor.sanitize(ImportError.cancelled)
        #expect(msg == "Import was cancelled.")
    }

    @Test func importSandboxCopyFailed() {
        let msg = ErrorMessageAuditor.sanitize(ImportError.sandboxCopyFailed("POSIX error 13"))
        #expect(!msg.contains("POSIX"))
        #expect(msg == "Could not save the file to the library.")
    }

    @Test func importSecurityScopeDenied() {
        let msg = ErrorMessageAuditor.sanitize(ImportError.securityScopeAccessDenied)
        #expect(msg == "Permission to access this file was denied.")
    }

    // MARK: - PersistenceError

    @Test func persistenceRecordNotFound() {
        let msg = ErrorMessageAuditor.sanitize(PersistenceError.recordNotFound("sha256:xyz"))
        #expect(!msg.contains("sha256"))
        #expect(msg.contains("found"))
    }

    @Test func persistenceInvalidContent() {
        let msg = ErrorMessageAuditor.sanitize(PersistenceError.invalidContent("JSON parse failed"))
        #expect(!msg.contains("JSON"))
        #expect(msg.contains("content"))
    }

    // MARK: - KeychainError

    @Test func keychainEncodingFailed() {
        let msg = ErrorMessageAuditor.sanitize(KeychainError.dataEncodingFailed)
        #expect(msg.contains("secure storage"))
    }

    @Test func keychainUnexpectedStatus() {
        let msg = ErrorMessageAuditor.sanitize(KeychainError.unexpectedStatus(-25300))
        #expect(!msg.contains("-25300"))
        #expect(msg.contains("secure storage"))
    }

    @Test func keychainUnexpectedResult() {
        let msg = ErrorMessageAuditor.sanitize(KeychainError.unexpectedResultType)
        #expect(msg.contains("secure storage"))
    }

    // MARK: - AIError

    @Test func aiFeatureDisabled() {
        let msg = ErrorMessageAuditor.sanitize(AIError.featureDisabled)
        #expect(msg == "AI features are currently disabled.")
    }

    @Test func aiConsentRequired() {
        let msg = ErrorMessageAuditor.sanitize(AIError.consentRequired)
        #expect(msg == "Please grant consent to use AI features.")
    }

    @Test func aiApiKeyMissing() {
        let msg = ErrorMessageAuditor.sanitize(AIError.apiKeyMissing)
        #expect(msg.contains("API key") || msg.contains("Settings"))
    }

    @Test func aiProviderError() {
        let msg = ErrorMessageAuditor.sanitize(AIError.providerError("HTTP 500 Internal Server Error"))
        #expect(!msg.contains("HTTP 500"))
        #expect(msg.contains("AI") || msg.contains("provider"))
    }

    @Test func aiNetworkError() {
        let msg = ErrorMessageAuditor.sanitize(AIError.networkError("POSIX connect() timeout"))
        #expect(!msg.contains("POSIX"))
        #expect(msg.contains("network") || msg.contains("connection"))
    }

    @Test func aiRateLimited() {
        let msg = ErrorMessageAuditor.sanitize(AIError.rateLimited(retryAfterSeconds: 30))
        #expect(msg.contains("try again"))
    }

    @Test func aiRateLimitedNoRetry() {
        let msg = ErrorMessageAuditor.sanitize(AIError.rateLimited(retryAfterSeconds: nil))
        #expect(msg.contains("try again"))
    }

    @Test func aiContextExtractionFailed() {
        let msg = ErrorMessageAuditor.sanitize(AIError.contextExtractionFailed)
        #expect(msg.contains("text") || msg.contains("context"))
    }

    @Test func aiInvalidResponse() {
        let msg = ErrorMessageAuditor.sanitize(AIError.invalidResponse)
        #expect(msg.contains("response"))
    }

    // MARK: - SyncError

    @Test func syncDisabled() {
        let msg = ErrorMessageAuditor.sanitize(SyncError.syncDisabled)
        #expect(msg.contains("sync") || msg.contains("Sync"))
    }

    @Test func syncNetworkUnavailable() {
        let msg = ErrorMessageAuditor.sanitize(SyncError.networkUnavailable)
        #expect(msg.contains("network") || msg.contains("connection") || msg.contains("offline"))
    }

    @Test func syncQuotaExceeded() {
        let msg = ErrorMessageAuditor.sanitize(SyncError.quotaExceeded)
        #expect(msg.contains("storage") || msg.contains("quota"))
    }

    @Test func syncAuthFailed() {
        let msg = ErrorMessageAuditor.sanitize(SyncError.authenticationFailed)
        #expect(msg.contains("sign in") || msg.contains("authentication"))
    }

    @Test func syncUnknown() {
        let msg = ErrorMessageAuditor.sanitize(SyncError.unknown("raw.internal.detail"))
        #expect(!msg.contains("raw.internal.detail"))
    }

    // MARK: - SearchIndexError

    @Test func searchDatabaseOpenFailed() {
        let msg = ErrorMessageAuditor.sanitize(SearchIndexError.databaseOpenFailed("sqlite3_open failed"))
        #expect(!msg.contains("sqlite3"))
        #expect(msg.contains("search"))
    }

    @Test func searchQueryFailed() {
        let msg = ErrorMessageAuditor.sanitize(SearchIndexError.queryFailed("SQLITE_CORRUPT"))
        #expect(!msg.contains("SQLITE"))
        #expect(msg.contains("search"))
    }

    @Test func searchIndexFailed() {
        let msg = ErrorMessageAuditor.sanitize(SearchIndexError.indexFailed("insert failed"))
        #expect(!msg.contains("insert"))
        #expect(msg.contains("search"))
    }

    // MARK: - Unknown / generic errors

    @Test func unknownNSError() {
        let error = NSError(domain: "com.test", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Something detailed happened at /var/private/path"
        ])
        let msg = ErrorMessageAuditor.sanitize(error)
        #expect(!msg.contains("/var/private"))
        #expect(msg == "An unexpected error occurred. Please try again.")
    }

    @Test func genericSwiftError() {
        struct CustomError: Error {}
        let msg = ErrorMessageAuditor.sanitize(CustomError())
        #expect(msg == "An unexpected error occurred. Please try again.")
    }
}
