// Purpose: User-created text highlight spanning a range in a book.
// Uses Locator with charRangeStartUTF16/charRangeEndUTF16 for TXT,
// or href+CFI for EPUB.

import Foundation
import SwiftData

@Model
final class Highlight {
    @Attribute(.unique) var highlightId: UUID

    /// Primitive sync key.
    private(set) var profileKey: String

    /// Locator marking the highlight range start (and range via charRange fields).
    /// Mutate via `updateLocator(_:)` — SwiftData `didSet` is unreliable.
    private(set) var locator: Locator

    /// The highlighted text content.
    var selectedText: String

    /// User-chosen color name or hex.
    var color: String

    var note: String?
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Explicit Sync

    /// Updates the locator and syncs the derived profileKey.
    /// Use this instead of setting `locator` directly, because
    /// SwiftData @Model classes do not reliably fire `didSet` observers.
    func updateLocator(_ newLocator: Locator) {
        locator = newLocator
        profileKey = "\(newLocator.bookFingerprint.canonicalKey):\(newLocator.canonicalHash)"
    }

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
