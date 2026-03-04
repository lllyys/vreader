// Purpose: User-created bookmark at a specific location in a book.

import Foundation
import SwiftData

@Model
final class Bookmark {
    @Attribute(.unique) var bookmarkId: UUID

    /// Primitive key for sync: "{bookFingerprintKey}:{locatorHash}"
    var profileKey: String

    var locator: Locator {
        didSet { profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)" }
    }
    var title: String?
    var createdAt: Date
    var updatedAt: Date

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
