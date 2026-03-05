// Purpose: Free-form user annotation attached to a location in a book.

import Foundation
import SwiftData

@Model
final class AnnotationNote {
    @Attribute(.unique) var annotationId: UUID

    /// Primitive sync key.
    var profileKey: String

    /// Mutate via `updateLocator(_:)` — SwiftData `didSet` is unreliable.
    var locator: Locator
    var content: String
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
        annotationId: UUID = UUID(),
        locator: Locator,
        content: String,
        createdAt: Date = Date()
    ) {
        self.annotationId = annotationId
        self.profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        self.locator = locator
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
