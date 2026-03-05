// Purpose: Pure formatting functions for reading time and speed display.
//
// Key decisions:
// - Zero total seconds returns nil (caller should omit label).
// - "<1m" for 1-59 seconds; "Xm" for 60-3599s; "Xh Ym" for 3600+.
// - Speed display requires >= 60 seconds total reading time.
// - Pages/hr rounded to nearest int; wpm rounded to nearest 10.
// - Pages/hr preferred over wpm when both available.
// - Format badge is simply uppercased raw value.

import Foundation

/// Formatting utilities for reading time and speed display in the library.
enum ReadingTimeFormatter {

    // MARK: - Reading Time

    /// Formats total reading seconds into a human-readable string.
    /// Returns nil for zero or negative values (caller should omit label).
    ///
    /// Examples:
    /// - 0 -> nil
    /// - 30 -> "<1m read"
    /// - 120 -> "2m read"
    /// - 5400 -> "1h 30m read"
    static func formatReadingTime(totalSeconds: Int) -> String? {
        guard totalSeconds > 0 else { return nil }

        let totalMinutes = totalSeconds / 60

        if totalMinutes < 1 {
            return "<1m read"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m read"
        }

        return "\(hours)h \(minutes)m read"
    }

    // MARK: - Speed

    /// Formats reading speed into a human-readable string.
    /// Returns nil if total reading time is under 60 seconds, or if no speed data is available.
    ///
    /// - Parameters:
    ///   - averagePagesPerHour: Average pages read per hour (rounded to nearest int).
    ///   - averageWordsPerMinute: Average words read per minute (rounded to nearest 10).
    ///   - totalReadingSeconds: Total reading time; speed is hidden for <60s.
    /// - Returns: Formatted speed string or nil.
    static func formatSpeed(
        averagePagesPerHour: Double?,
        averageWordsPerMinute: Double?,
        totalReadingSeconds: Int
    ) -> String? {
        guard totalReadingSeconds >= 60 else { return nil }

        // Prefer pages/hr over wpm
        if let pph = averagePagesPerHour {
            let rounded = Int(pph.rounded())
            if rounded > 0 {
                return "~\(rounded) pages/hr"
            }
        }

        if let wpm = averageWordsPerMinute {
            let rounded = Int((wpm / 10.0).rounded()) * 10
            if rounded > 0 {
                return "~\(rounded) wpm"
            }
        }

        return nil
    }

    // MARK: - Format Badge

    /// Returns the uppercased format label for display in a badge.
    /// Uses root locale for stable results with ASCII format strings.
    static func formatBadgeLabel(format: String) -> String {
        format.uppercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
