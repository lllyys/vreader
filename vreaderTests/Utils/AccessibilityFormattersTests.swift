// Purpose: Tests for AccessibilityFormatters — VoiceOver-friendly text formatting.

import Testing
import Foundation
@testable import vreader

@Suite("AccessibilityFormatters")
struct AccessibilityFormattersTests {

    // MARK: - accessibleReadingTime

    @Test func readingTimeZeroReturnsNil() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 0) == nil)
    }

    @Test func readingTimeNegativeReturnsNil() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: -50) == nil)
    }

    @Test func readingTimeOneSecond() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 1) == "less than 1 minute read")
    }

    @Test func readingTimeFiftyNineSeconds() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 59) == "less than 1 minute read")
    }

    @Test func readingTimeExactlyOneMinute() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 60) == "1 minute read")
    }

    @Test func readingTimeTwoMinutes() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 120) == "2 minutes read")
    }

    @Test func readingTimeFiftyNineMinutes() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 3540) == "59 minutes read")
    }

    @Test func readingTimeExactlyOneHour() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 3600) == "1 hour read")
    }

    @Test func readingTimeOneHourOneMinute() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 3660) == "1 hour 1 minute read")
    }

    @Test func readingTimeOneHourThirtyMinutes() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 5400) == "1 hour 30 minutes read")
    }

    @Test func readingTimeTwoHoursFifteenMinutes() {
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: 8100) == "2 hours 15 minutes read")
    }

    @Test func readingTimeLargeValue() {
        let seconds = 100 * 3600 + 59 * 60
        #expect(AccessibilityFormatters.accessibleReadingTime(totalSeconds: seconds) == "100 hours 59 minutes read")
    }

    // MARK: - accessibleSpeed

    @Test func speedNilWhenBothNil() {
        #expect(AccessibilityFormatters.accessibleSpeed(
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil,
            totalSeconds: 3600
        ) == nil)
    }

    @Test func speedNilWhenUnder60Seconds() {
        #expect(AccessibilityFormatters.accessibleSpeed(
            averagePagesPerHour: 30.0,
            averageWordsPerMinute: nil,
            totalSeconds: 59
        ) == nil)
    }

    @Test func speedPagesPerHour() {
        #expect(AccessibilityFormatters.accessibleSpeed(
            averagePagesPerHour: 42.3,
            averageWordsPerMinute: nil,
            totalSeconds: 3600
        ) == "approximately 42 pages per hour")
    }

    @Test func speedWordsPerMinute() {
        #expect(AccessibilityFormatters.accessibleSpeed(
            averagePagesPerHour: nil,
            averageWordsPerMinute: 247.0,
            totalSeconds: 3600
        ) == "approximately 250 words per minute")
    }

    @Test func speedPrefersPages() {
        #expect(AccessibilityFormatters.accessibleSpeed(
            averagePagesPerHour: 30.0,
            averageWordsPerMinute: 250.0,
            totalSeconds: 3600
        ) == "approximately 30 pages per hour")
    }

    @Test func speedOnePage() {
        #expect(AccessibilityFormatters.accessibleSpeed(
            averagePagesPerHour: 1.0,
            averageWordsPerMinute: nil,
            totalSeconds: 3600
        ) == "approximately 1 page per hour")
    }

    // MARK: - accessibleFormatBadge

    @Test func formatBadgeEpub() {
        #expect(AccessibilityFormatters.accessibleFormatBadge(format: "epub") == "EPUB format")
    }

    @Test func formatBadgePdf() {
        #expect(AccessibilityFormatters.accessibleFormatBadge(format: "pdf") == "PDF format")
    }

    @Test func formatBadgeTxt() {
        #expect(AccessibilityFormatters.accessibleFormatBadge(format: "txt") == "TXT format")
    }

    @Test func formatBadgeEmpty() {
        #expect(AccessibilityFormatters.accessibleFormatBadge(format: "") == "Unknown format")
    }

    @Test func formatBadgeMixedCase() {
        #expect(AccessibilityFormatters.accessibleFormatBadge(format: "Epub") == "EPUB format")
    }

    // MARK: - accessibleBookDescription

    @Test func bookDescriptionFullInfo() {
        let result = AccessibilityFormatters.accessibleBookDescription(
            title: "The Great Gatsby",
            author: "F. Scott Fitzgerald",
            format: "epub",
            readingTimeSeconds: 5400
        )
        #expect(result == "The Great Gatsby, by F. Scott Fitzgerald, EPUB format, 1 hour 30 minutes read")
    }

    @Test func bookDescriptionNoAuthor() {
        let result = AccessibilityFormatters.accessibleBookDescription(
            title: "README",
            author: nil,
            format: "txt",
            readingTimeSeconds: 120
        )
        #expect(result == "README, TXT format, 2 minutes read")
    }

    @Test func bookDescriptionNoReadingTime() {
        let result = AccessibilityFormatters.accessibleBookDescription(
            title: "New Book",
            author: "Author",
            format: "pdf",
            readingTimeSeconds: 0
        )
        #expect(result == "New Book, by Author, PDF format")
    }

    @Test func bookDescriptionMinimal() {
        let result = AccessibilityFormatters.accessibleBookDescription(
            title: "Untitled",
            author: nil,
            format: "epub",
            readingTimeSeconds: 0
        )
        #expect(result == "Untitled, EPUB format")
    }

    @Test func bookDescriptionUnicodeTitle() {
        let result = AccessibilityFormatters.accessibleBookDescription(
            title: "三体",
            author: "刘慈欣",
            format: "epub",
            readingTimeSeconds: 0
        )
        #expect(result == "三体, by 刘慈欣, EPUB format")
    }

    @Test func bookDescriptionVeryLongTitle() {
        let longTitle = String(repeating: "A", count: 500)
        let result = AccessibilityFormatters.accessibleBookDescription(
            title: longTitle,
            author: nil,
            format: "pdf",
            readingTimeSeconds: 0
        )
        #expect(result.hasPrefix("AAAAA"))
        #expect(result.hasSuffix("PDF format"))
    }

    // MARK: - accessiblePageIndicator

    @Test func pageIndicatorNormal() {
        #expect(AccessibilityFormatters.accessiblePageIndicator(current: 5, total: 20) == "Page 5 of 20")
    }

    @Test func pageIndicatorFirstPage() {
        #expect(AccessibilityFormatters.accessiblePageIndicator(current: 1, total: 100) == "Page 1 of 100")
    }

    @Test func pageIndicatorLastPage() {
        #expect(AccessibilityFormatters.accessiblePageIndicator(current: 100, total: 100) == "Page 100 of 100")
    }

    @Test func pageIndicatorZeroTotal() {
        #expect(AccessibilityFormatters.accessiblePageIndicator(current: 0, total: 0) == "Page 0 of 0")
    }

    // MARK: - accessibleFileAvailability

    @Test func fileAvailabilityMetadataOnly() {
        #expect(AccessibilityFormatters.accessibleFileAvailability(state: .metadataOnly) == "Available for download")
    }

    @Test func fileAvailabilityQueued() {
        #expect(AccessibilityFormatters.accessibleFileAvailability(state: .queuedDownload) == "Download queued")
    }

    @Test func fileAvailabilityDownloading() {
        #expect(AccessibilityFormatters.accessibleFileAvailability(state: .downloading) == "Downloading")
    }

    @Test func fileAvailabilityAvailable() {
        #expect(AccessibilityFormatters.accessibleFileAvailability(state: .available) == "Downloaded")
    }

    @Test func fileAvailabilityFailed() {
        #expect(AccessibilityFormatters.accessibleFileAvailability(state: .failed) == "Download failed")
    }

    @Test func fileAvailabilityStale() {
        #expect(AccessibilityFormatters.accessibleFileAvailability(state: .stale) == "Update available")
    }

    // MARK: - accessibleSyncStatus

    @Test func syncStatusDisabled() {
        #expect(AccessibilityFormatters.accessibleSyncStatus(.disabled) == "Sync disabled")
    }

    @Test func syncStatusIdle() {
        #expect(AccessibilityFormatters.accessibleSyncStatus(.idle) == "Synced")
    }

    @Test func syncStatusSyncing() {
        #expect(AccessibilityFormatters.accessibleSyncStatus(.syncing) == "Syncing in progress")
    }

    @Test func syncStatusError() {
        #expect(AccessibilityFormatters.accessibleSyncStatus(.error("network")) == "Sync error")
    }

    @Test func syncStatusOffline() {
        #expect(AccessibilityFormatters.accessibleSyncStatus(.offline) == "Offline")
    }
}
