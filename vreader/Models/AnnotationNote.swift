// Purpose: Free-form user annotation attached to a location in a book.

import Foundation
import SwiftData

@Model
final class AnnotationNote {
    @Attribute(.unique) var annotationId: UUID

    /// Primitive sync key.
    var profileKey: String

    var locator: Locator {
        didSet { profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)" }
    }
    var content: String
    var createdAt: Date
    var updatedAt: Date

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
