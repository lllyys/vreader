// Purpose: Stores the current reading position for a book.
// Uses Locator for universal position representation.

import Foundation
import SwiftData

@Model
final class ReadingPosition {
    /// Locator-based canonical hash for sync key.
    var locatorHash: String

    /// Full locator for the current reading position.
    var locator: Locator {
        didSet { locatorHash = locator.canonicalHash }
    }

    /// When the position was last updated.
    var updatedAt: Date

    /// Device that last updated this position.
    var deviceId: String

    // MARK: - Relationship

    var book: Book?

    // MARK: - Init

    init(
        locator: Locator,
        updatedAt: Date = Date(),
        deviceId: String = ""
    ) {
        self.locatorHash = locator.canonicalHash
        self.locator = locator
        self.updatedAt = updatedAt
        self.deviceId = deviceId
    }
}
