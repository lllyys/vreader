// Purpose: Stores the current reading position for a book.
// Uses Locator for universal position representation.

import Foundation
import SwiftData

@Model
final class ReadingPosition {
    /// Locator-based canonical hash for sync key.
    var locatorHash: String

    /// Full locator for the current reading position.
    /// Mutate via `updateLocator(_:)` — SwiftData `didSet` is unreliable.
    var locator: Locator

    /// When the position was last updated.
    var updatedAt: Date

    /// Device that last updated this position.
    var deviceId: String

    // MARK: - Explicit Sync

    /// Updates the locator and syncs the derived locatorHash.
    /// Use this instead of setting `locator` directly, because
    /// SwiftData @Model classes do not reliably fire `didSet` observers.
    func updateLocator(_ newLocator: Locator) {
        locator = newLocator
        locatorHash = newLocator.canonicalHash
    }

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
