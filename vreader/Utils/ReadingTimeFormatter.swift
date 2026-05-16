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

    // MARK: - Relative Last-Read

    /// Formats a "last read" timestamp into a compact relative string
    /// for the Library list row's metadata line (feature #60 WI-8 —
    /// the design's `{progress}% · {last-read}` span in `ListView`).
    ///
    /// Buckets are deterministic and locale-independent so the output
    /// is stable across devices/OS versions and unit-testable with a
    /// fixed `now` — unlike `RelativeDateTimeFormatter`, whose wording
    /// shifts with locale and SDK:
    /// - under 1 minute (or a future timestamp) → "Just now"
    /// - under 1 hour   → "Xm ago"
    /// - under 1 day    → "Xh ago"
    /// - exactly 1 day  → "Yesterday"
    /// - under 1 week   → "Xd ago"
    /// - under 5 weeks  → "Xw ago"
    /// - under 1 year   → "Xmo ago"
    /// - otherwise      → "Xy ago"
    ///
    /// A future `date` (clock skew between the position write and the
    /// render) falls into the "Just now" bucket rather than producing
    /// a negative count.
    static func formatRelativeLastRead(
        from date: Date,
        relativeTo now: Date = Date()
    ) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }

        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)m ago" }

        let hours = Int(elapsed / 3_600)
        if hours < 24 { return "\(hours)h ago" }

        let days = Int(elapsed / 86_400)
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }

        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w ago" }

        let months = days / 30
        if months < 12 { return "\(months)mo ago" }

        return "\(days / 365)y ago"
    }
}
