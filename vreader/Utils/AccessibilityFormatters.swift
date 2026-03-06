// Purpose: VoiceOver-friendly text formatting for accessibility labels.
// Expands abbreviated display strings into full words spoken clearly by VoiceOver.
//
// Key decisions:
// - Mirrors ReadingTimeFormatter but produces expanded strings.
// - Singular/plural handled for hours, minutes, pages.
// - Does not duplicate display logic — only adds accessible alternatives.
// - All methods are pure functions with no side effects.
//
// @coordinates-with: ReadingTimeFormatter.swift, BookCardView.swift, BookRowView.swift,
//   FileAvailabilityBadge.swift, SyncStatusView.swift

import Foundation

/// Formatting utilities for VoiceOver-accessible labels.
enum AccessibilityFormatters {

    // MARK: - Reading Time

    /// Formats total reading seconds into VoiceOver-friendly text.
    /// Returns nil for zero or negative values.
    ///
    /// Examples:
    /// - 0 -> nil
    /// - 30 -> "less than 1 minute read"
    /// - 120 -> "2 minutes read"
    /// - 5400 -> "1 hour 30 minutes read"
    static func accessibleReadingTime(totalSeconds: Int) -> String? {
        guard totalSeconds > 0 else { return nil }

        let totalMinutes = totalSeconds / 60

        if totalMinutes < 1 {
            return "less than 1 minute read"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            let minuteWord = minutes == 1 ? "minute" : "minutes"
            return "\(minutes) \(minuteWord) read"
        }

        let hourWord = hours == 1 ? "hour" : "hours"

        if minutes == 0 {
            return "\(hours) \(hourWord) read"
        }

        let minuteWord = minutes == 1 ? "minute" : "minutes"
        return "\(hours) \(hourWord) \(minutes) \(minuteWord) read"
    }

    // MARK: - Speed

    /// Formats reading speed into VoiceOver-friendly text.
    /// Returns nil if total reading time is under 60 seconds or no data available.
    static func accessibleSpeed(
        averagePagesPerHour: Double?,
        averageWordsPerMinute: Double?,
        totalSeconds: Int
    ) -> String? {
        guard totalSeconds >= 60 else { return nil }

        if let pph = averagePagesPerHour {
            let rounded = Int(pph.rounded())
            if rounded > 0 {
                let pageWord = rounded == 1 ? "page" : "pages"
                return "approximately \(rounded) \(pageWord) per hour"
            }
        }

        if let wpm = averageWordsPerMinute {
            let rounded = Int((wpm / 10.0).rounded()) * 10
            if rounded > 0 {
                return "approximately \(rounded) words per minute"
            }
        }

        return nil
    }

    // MARK: - Format Badge

    /// Returns an accessible format description (e.g., "EPUB format").
    static func accessibleFormatBadge(format: String) -> String {
        let badge = ReadingTimeFormatter.formatBadgeLabel(format: format)
        if badge.isEmpty {
            return "Unknown format"
        }
        return "\(badge) format"
    }

    // MARK: - Book Description

    /// Constructs a complete VoiceOver description for a book item.
    static func accessibleBookDescription(
        title: String,
        author: String?,
        format: String,
        readingTimeSeconds: Int
    ) -> String {
        var parts: [String] = [title]

        if let author, !author.isEmpty {
            parts.append("by \(author)")
        }

        parts.append(accessibleFormatBadge(format: format))

        if let time = accessibleReadingTime(totalSeconds: readingTimeSeconds) {
            parts.append(time)
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - Page Indicator

    /// Returns an accessible page indicator (e.g., "Page 5 of 20").
    static func accessiblePageIndicator(current: Int, total: Int) -> String {
        "Page \(current) of \(total)"
    }

    // MARK: - File Availability

    /// Returns a VoiceOver-friendly description of file download state.
    static func accessibleFileAvailability(state: FileAvailability) -> String {
        switch state {
        case .metadataOnly: return "Available for download"
        case .queuedDownload: return "Download queued"
        case .downloading: return "Downloading"
        case .available: return "Downloaded"
        case .failed: return "Download failed"
        case .stale: return "Update available"
        }
    }

    // MARK: - Sync Status

    /// Returns a VoiceOver-friendly description of sync state.
    static func accessibleSyncStatus(_ status: SyncStatus) -> String {
        switch status {
        case .disabled: return "Sync disabled"
        case .idle: return "Synced"
        case .syncing: return "Syncing in progress"
        case .error: return "Sync error"
        case .offline: return "Offline"
        }
    }
}
