// Purpose: Tests for ReadingTimeFormatter — reading time and speed formatting.

import Testing
import Foundation
@testable import vreader

@Suite("ReadingTimeFormatter")
struct ReadingTimeFormatterTests {

    // MARK: - formatReadingTime

    @Test func zeroSecondsReturnsNil() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 0) == nil)
    }

    @Test func negativeSecondsReturnsNil() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: -100) == nil)
    }

    @Test func oneSecondReturnsLessThanOneMinute() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 1) == "<1m read")
    }

    @Test func fiftyNineSecondsReturnsLessThanOneMinute() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 59) == "<1m read")
    }

    @Test func exactlySixtySecondsReturnsOneMinute() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 60) == "1m read")
    }

    @Test func ninetySecondsReturnsOneMinute() {
        // 90s = 1m 30s, displayed as 1m (minutes only, no seconds)
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 90) == "1m read")
    }

    @Test func thirtyMinutesExact() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 1800) == "30m read")
    }

    @Test func fiftyNineMinutes() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 3540) == "59m read")
    }

    @Test func exactlyOneHour() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 3600) == "1h 0m read")
    }

    @Test func oneHourThirtyMinutes() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 5400) == "1h 30m read")
    }

    @Test func twoHoursFifteenMinutes() {
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 8100) == "2h 15m read")
    }

    @Test func largeValue999Hours() {
        let seconds = 999 * 3600 + 59 * 60
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: seconds) == "999h 59m read")
    }

    @Test func oneHourWithLeftoverSeconds() {
        // 3661s = 1h 1m 1s, displayed as 1h 1m
        #expect(ReadingTimeFormatter.formatReadingTime(totalSeconds: 3661) == "1h 1m read")
    }

    // MARK: - formatSpeed (pages per hour)

    @Test func formatSpeedPagesPerHourNilWhenNil() {
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil,
            totalReadingSeconds: 3600
        ) == nil)
    }

    @Test func formatSpeedPagesPerHourRoundsToNearestInt() {
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: 23.7,
            averageWordsPerMinute: nil,
            totalReadingSeconds: 3600
        ) == "~24 pages/hr")
    }

    @Test func formatSpeedPagesPerHourRoundsDown() {
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: 23.2,
            averageWordsPerMinute: nil,
            totalReadingSeconds: 3600
        ) == "~23 pages/hr")
    }

    @Test func formatSpeedWordsPerMinuteRoundsToNearest10() {
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: nil,
            averageWordsPerMinute: 247.0,
            totalReadingSeconds: 3600
        ) == "~250 wpm")
    }

    @Test func formatSpeedWordsPerMinuteRoundsDown() {
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: nil,
            averageWordsPerMinute: 244.0,
            totalReadingSeconds: 3600
        ) == "~240 wpm")
    }

    @Test func formatSpeedPrefersPagesThenWords() {
        // When both available, pages/hr takes priority
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: 30.0,
            averageWordsPerMinute: 250.0,
            totalReadingSeconds: 3600
        ) == "~30 pages/hr")
    }

    @Test func formatSpeedNilWhenUnder60Seconds() {
        // No speed displayed for sessions under 60s total
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: 30.0,
            averageWordsPerMinute: 250.0,
            totalReadingSeconds: 59
        ) == nil)
    }

    @Test func formatSpeedNilWhenExactly0Seconds() {
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: 30.0,
            averageWordsPerMinute: 250.0,
            totalReadingSeconds: 0
        ) == nil)
    }

    @Test func formatSpeedAtExactly60Seconds() {
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: 30.0,
            averageWordsPerMinute: nil,
            totalReadingSeconds: 60
        ) == "~30 pages/hr")
    }

    @Test func formatSpeedZeroPagesPerHourReturnsNil() {
        // 0 pages/hr is not meaningful
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: 0.0,
            averageWordsPerMinute: nil,
            totalReadingSeconds: 3600
        ) == nil)
    }

    @Test func formatSpeedZeroWpmFallsThrough() {
        // 0 wpm not meaningful, but if pages available, use pages
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: nil,
            averageWordsPerMinute: 0.0,
            totalReadingSeconds: 3600
        ) == nil)
    }

    @Test func formatSpeedWpmRoundsToZeroReturnsNil() {
        // 4 wpm rounds to 0 wpm with nearest-10 rounding -> nil
        #expect(ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: nil,
            averageWordsPerMinute: 4.0,
            totalReadingSeconds: 3600
        ) == nil)
    }

    // MARK: - formatFormatBadge

    @Test func formatBadgeEpub() {
        #expect(ReadingTimeFormatter.formatBadgeLabel(format: "epub") == "EPUB")
    }

    @Test func formatBadgePdf() {
        #expect(ReadingTimeFormatter.formatBadgeLabel(format: "pdf") == "PDF")
    }

    @Test func formatBadgeTxt() {
        #expect(ReadingTimeFormatter.formatBadgeLabel(format: "txt") == "TXT")
    }

    @Test func formatBadgeMd() {
        #expect(ReadingTimeFormatter.formatBadgeLabel(format: "md") == "MD")
    }

    @Test func formatBadgeUnknown() {
        #expect(ReadingTimeFormatter.formatBadgeLabel(format: "unknown") == "UNKNOWN")
    }

    @Test func formatBadgeMixedCase() {
        #expect(ReadingTimeFormatter.formatBadgeLabel(format: "Epub") == "EPUB")
    }

    @Test func formatBadgeEmptyString() {
        #expect(ReadingTimeFormatter.formatBadgeLabel(format: "") == "")
    }
}
