// Purpose: User-created text highlight spanning a range in a book.
// Uses Locator with charRangeStartUTF16/charRangeEndUTF16 for TXT,
// or href+CFI for EPUB.

import Foundation
import SwiftData

@Model
final class Highlight {
    @Attribute(.unique) var highlightId: UUID

    /// Primitive sync key.
    var profileKey: String

    /// Locator marking the highlight range start (and range via charRange fields).
    var locator: Locator {
        didSet { profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)" }
    }

    /// The highlighted text content.
    var selectedText: String

    /// User-chosen color name or hex.
    var color: String

    var note: String?
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Relationship

    var book: Book?

    // MARK: - Init

    init(
        highlightId: UUID = UUID(),
        locator: Locator,
        selectedText: String,
        color: String = "yellow",
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.highlightId = highlightId
        self.profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        self.locator = locator
        self.selectedText = selectedText
        self.color = color
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
