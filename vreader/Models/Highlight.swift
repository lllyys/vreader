// Purpose: User-created text highlight spanning a range in a book.
// Uses Locator with charRangeStartUTF16/charRangeEndUTF16 for TXT,
// or href+CFI for EPUB. Optionally carries an AnnotationAnchor for
// format-specific precise range restoration (SchemaV2).
//
// Key decisions:
// - anchorData is stored as raw Data? to avoid SwiftData Codable enum decode
//   crashes on legacy rows that lack the column. The computed `anchor` property
//   decodes with try?, returning nil on failure (corrupted or missing data).
//
// @coordinates-with: AnnotationAnchor.swift, HighlightRecord.swift,
//   PersistenceActor+Highlights.swift

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

    /// Raw JSON bytes for the format-specific anchor.
    /// SwiftData stores/reads this as a simple Data? column, avoiding Codable
    /// enum decode crashes on legacy rows. Use the computed `anchor` property
    /// for typed access.
    var anchorData: Data?

    /// The highlighted text content.
    var selectedText: String

    /// User-chosen color name or hex.
    var color: String

    var note: String?
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Anchor

    /// Decoded anchor from `anchorData`. Returns nil when data is missing,
    /// empty, or corrupted — never crashes.
    @Transient var anchor: AnnotationAnchor? {
        guard let data = anchorData, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(AnnotationAnchor.self, from: data)
    }

    // MARK: - Explicit Sync

    /// Updates the locator and syncs the derived profileKey.
    /// Use this instead of setting `locator` directly, because
    /// SwiftData @Model classes do not reliably fire `didSet` observers.
    func updateLocator(_ newLocator: Locator) {
        locator = newLocator
        profileKey = "\(newLocator.bookFingerprint.canonicalKey):\(newLocator.canonicalHash)"
    }

    /// Feature #109 migration helper: repair the stored locator (null non-finite
    /// fields) and recompute the derived `profileKey` under the current (NFC)
    /// canonicalization. No-op for finite + NFC/ASCII rows.
    func recomputeKey() {
        locator = locator.repairedForCanonicalization()
        profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
    }

    /// Updates the anchor for precise range restoration.
    /// Encodes the anchor to JSON bytes for safe SwiftData storage.
    func updateAnchor(_ newAnchor: AnnotationAnchor?) {
        if let newAnchor {
            anchorData = try? JSONEncoder().encode(newAnchor)
        } else {
            anchorData = nil
        }
        updatedAt = Date()
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
        anchor: AnnotationAnchor? = nil,
        createdAt: Date = Date()
    ) {
        self.highlightId = highlightId
        self.profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        self.locator = locator
        if let anchor {
            self.anchorData = try? JSONEncoder().encode(anchor)
        } else {
            self.anchorData = nil
        }
        self.selectedText = selectedText
        self.color = color
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
