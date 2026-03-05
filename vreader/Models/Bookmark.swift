// Purpose: User-created bookmark at a specific location in a book.

import Foundation
import SwiftData

@Model
final class Bookmark {
    @Attribute(.unique) var bookmarkId: UUID

    /// Primitive key for sync: "{bookFingerprintKey}:{locatorHash}"
    var profileKey: String

    /// Mutate via `updateLocator(_:)` — SwiftData `didSet` is unreliable.
    var locator: Locator
    var title: String?
    var createdAt: Date
    var updatedAt: Date

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
        bookmarkId: UUID = UUID(),
        locator: Locator,
        title: String? = nil,
        createdAt: Date = Date()
    ) {
        self.bookmarkId = bookmarkId
        self.profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        self.locator = locator
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
