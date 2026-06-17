// Purpose: Stores the current reading position for a book.
// Uses Locator for universal position representation.
//
// Key decisions:
// - vreaderLocatorData is the SchemaV8 additive optional column holding the
//   JSON-encoded VReaderLocator envelope (Feature #42). Stored as raw Data? to
//   mirror Highlight.anchorData — a SwiftData-safe blob that legacy rows can
//   lack without a decode crash. The legacy `locator` field is kept untouched
//   for back-compat / dual-write during the two-engine era.

import Foundation
import SwiftData

@Model
final class ReadingPosition {
    /// Locator-based canonical hash for sync key.
    private(set) var locatorHash: String

    /// Full locator for the current reading position.
    /// Mutate via `updateLocator(_:)` — SwiftData `didSet` is unreliable.
    private(set) var locator: Locator

    /// Raw JSON bytes of the engine-agnostic `VReaderLocator` envelope (SchemaV8,
    /// Feature #42). Stored as a simple Data? column — like Highlight.anchorData —
    /// so legacy rows that predate the column read back as nil instead of
    /// crashing. Decode with `VReaderLocator` for typed access. nil until a save
    /// populates it (lazy dual-write; the legacy `locator` is always written too).
    var vreaderLocatorData: Data?

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

    /// Feature #109 migration helper: repair the stored locator (null non-finite
    /// fields) and recompute the derived `locatorHash` under the current (NFC)
    /// canonicalization. No-op for finite + NFC/ASCII rows.
    func recomputeKey() {
        locator = locator.repairedForCanonicalization()
        locatorHash = locator.canonicalHash
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
