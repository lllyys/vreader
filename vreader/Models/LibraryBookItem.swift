// Purpose: Lightweight value type for library display. Combines book metadata
// with reading stats for cross-boundary transfer to the view layer.
//
// Key decisions:
// - Sendable + Identifiable for safe use in SwiftUI views and across actors.
// - id is fingerprintKey for stable list identity.
// - Includes computed properties for formatted reading time and speed.
// - Does not include full fingerprint (not needed for library display).

import Foundation

/// Lightweight value type combining Book metadata and ReadingStats for library display.
struct LibraryBookItem: Sendable, Identifiable, Equatable {
    var id: String { fingerprintKey }

    let fingerprintKey: String
    let title: String
    let author: String?
    let coverImagePath: String?
    let format: String
    let addedAt: Date
    let lastOpenedAt: Date?
    let isFavorite: Bool
    let totalReadingSeconds: Int
    let lastReadAt: Date?
    let averagePagesPerHour: Double?
    let averageWordsPerMinute: Double?

    // MARK: - Computed Display Properties

    /// Formatted reading time string, or nil if zero reading time.
    var formattedReadingTime: String? {
        ReadingTimeFormatter.formatReadingTime(totalSeconds: totalReadingSeconds)
    }

    /// Formatted speed string, or nil if insufficient data.
    var formattedSpeed: String? {
        ReadingTimeFormatter.formatSpeed(
            averagePagesPerHour: averagePagesPerHour,
            averageWordsPerMinute: averageWordsPerMinute,
            totalReadingSeconds: totalReadingSeconds
        )
    }

    /// Uppercased format badge label (e.g. "EPUB", "PDF", "TXT").
    var formatBadge: String {
        ReadingTimeFormatter.formatBadgeLabel(format: format)
    }

    /// SF Symbol name for the book's format.
    var formatIcon: String {
        switch format.lowercased() {
        case "epub": return "book.fill"
        case "pdf": return "doc.fill"
        case "txt": return "doc.text.fill"
        case "md": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }
}
