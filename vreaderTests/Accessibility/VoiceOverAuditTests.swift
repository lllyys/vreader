// Purpose: Tests that verify VoiceOver accessibility text is properly formatted.
// Covers reading time labels, page indicators, file availability, and book descriptions.

import Testing
import Foundation
@testable import vreader

@Suite("VoiceOverAudit")
struct VoiceOverAuditTests {

    // MARK: - Reading time is expanded (not abbreviated)

    @Test func readingTimeNeverContainsAbbreviatedMinutes() {
        // Ensure VoiceOver never says "2m read" — it should say "2 minutes read"
        let cases = [60, 120, 300, 1800, 3540]
        for seconds in cases {
            let result = AccessibilityFormatters.accessibleReadingTime(totalSeconds: seconds)
            #expect(result != nil)
            if let text = result {
                #expect(!text.contains("m read") || text.contains("minute"))
                #expect(!text.hasSuffix("m read"))
            }
        }
    }

    @Test func readingTimeNeverContainsAbbreviatedHours() {
        let cases = [3600, 5400, 7200, 36000]
        for seconds in cases {
            let result = AccessibilityFormatters.accessibleReadingTime(totalSeconds: seconds)
            #expect(result != nil)
            if let text = result {
                #expect(!text.contains("h "))
                #expect(text.contains("hour"))
            }
        }
    }

    // MARK: - Page indicator is complete sentences

    @Test func pageIndicatorContainsPageWord() {
        let result = AccessibilityFormatters.accessiblePageIndicator(current: 3, total: 10)
        #expect(result.contains("Page"))
        #expect(result.contains("of"))
    }

    @Test func pageIndicatorContainsBothNumbers() {
        let result = AccessibilityFormatters.accessiblePageIndicator(current: 42, total: 315)
        #expect(result.contains("42"))
        #expect(result.contains("315"))
    }

    // MARK: - Format badge is expanded

    @Test func formatBadgeAlwaysIncludesFormatWord() {
        let formats = ["epub", "pdf", "txt", "md", "unknown"]
        for format in formats {
            let result = AccessibilityFormatters.accessibleFormatBadge(format: format)
            #expect(result.contains("format"))
        }
    }

    // MARK: - File availability uses full words

    @Test func fileAvailabilityNeverUsesIconNames() {
        let states: [FileAvailability] = [
            .metadataOnly, .queuedDownload, .downloading,
            .available, .failed, .stale
        ]
        for state in states {
            let result = AccessibilityFormatters.accessibleFileAvailability(state: state)
            // Should not contain SF Symbol names or technical terms
            #expect(!result.contains("icloud"))
            #expect(!result.contains("arrow"))
            #expect(!result.contains("exclamationmark"))
        }
    }

    // MARK: - Book description is well-formed

    @Test func bookDescriptionPartsAreSeparatedByCommas() {
        let result = AccessibilityFormatters.accessibleBookDescription(
            title: "Test Book",
            author: "Author",
            format: "epub",
            readingTimeSeconds: 120
        )
        let parts = result.components(separatedBy: ", ")
        #expect(parts.count >= 3)
    }

    @Test func bookDescriptionWithEmptyAuthorOmitsBy() {
        let result = AccessibilityFormatters.accessibleBookDescription(
            title: "Solo",
            author: nil,
            format: "pdf",
            readingTimeSeconds: 0
        )
        #expect(!result.contains("by"))
    }

    // MARK: - Sync status is human-readable

    @Test func syncStatusNeverContainsTechnicalDetails() {
        let statuses: [SyncStatus] = [
            .disabled, .idle, .syncing, .error("raw technical detail"), .offline
        ]
        for status in statuses {
            let result = AccessibilityFormatters.accessibleSyncStatus(status)
            #expect(!result.contains("raw technical detail"))
        }
    }

    // MARK: - Error messages are user-safe

    @Test func errorMessagesNeverContainFilePaths() {
        let errors: [Error] = [
            ImportError.fileNotReadable("/Users/john/Documents/private.epub"),
            ImportError.sandboxCopyFailed("/var/containers/Bundle/Application/abc123/"),
            ImportError.hashComputationFailed("/tmp/hash_error"),
        ]
        for error in errors {
            let msg = ErrorMessageAuditor.sanitize(error)
            #expect(!msg.contains("/Users"))
            #expect(!msg.contains("/var"))
            #expect(!msg.contains("/tmp"))
        }
    }

    @Test func errorMessagesNeverContainStackTraces() {
        let errors: [Error] = [
            AIError.providerError("at line 42 in /src/handler.swift"),
            SyncError.unknown("Thread 1: signal SIGABRT"),
        ]
        for error in errors {
            let msg = ErrorMessageAuditor.sanitize(error)
            #expect(!msg.contains("line 42"))
            #expect(!msg.contains("SIGABRT"))
        }
    }
}
