// Purpose: Core book model for the library. Stores metadata, fingerprint, and import provenance.
//
// Key decisions:
// - fingerprintKey is the canonical primitive sync key (@Attribute(.unique)).
// - SwiftData cannot enforce uniqueness on Codable structs, so fingerprint
//   is stored both as a Codable struct (for domain logic) and as a primitive key.
// - totalWordCount, totalPageCount, totalTextLengthUTF16 are indexing-produced metadata,
//   populated asynchronously after import.
// - format and fileByteCount are stored separately for indexing but derived from
//   fingerprint at init time. They must not be mutated independently.
// - coverImagePath stores a file path reference instead of inline blob data
//   to avoid memory/store pressure with large images.

import Foundation
import SwiftData

@Model
final class Book {
    // MARK: - Identity

    /// Primitive unique key derived from DocumentFingerprint.canonicalKey.
    /// Format: "{format}:{contentSHA256}:{fileByteCount}"
    @Attribute(.unique) var fingerprintKey: String

    /// Full fingerprint for domain logic.
    var fingerprint: DocumentFingerprint {
        didSet { syncDerivedFields() }
    }

    // MARK: - Metadata

    var title: String
    var author: String?

    /// Relative path to cover image in app sandbox. Nil if no cover.
    var coverImagePath: String?

    /// BookFormat.rawValue — derived from fingerprint, stored for query indexing.
    private(set) var format: String

    /// Derived from fingerprint — stored for query indexing.
    private(set) var fileByteCount: Int64

    // MARK: - Import Provenance

    var provenance: ImportProvenance

    // MARK: - Library State

    var addedAt: Date
    var lastOpenedAt: Date?
    var isFavorite: Bool
    var tags: [String]

    // MARK: - Indexing-Produced Metadata

    /// Total word count, populated by background indexer after import.
    var totalWordCount: Int?

    /// Total page count (meaningful for PDF; estimated for reflowable).
    var totalPageCount: Int?

    /// Total text length in UTF-16 code units (canonical for TXT offset calculations).
    var totalTextLengthUTF16: Int?

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade) var readingPosition: ReadingPosition?
    @Relationship(deleteRule: .cascade) var bookmarks: [Bookmark]
    @Relationship(deleteRule: .cascade) var highlights: [Highlight]
    @Relationship(deleteRule: .cascade) var annotations: [AnnotationNote]

    // MARK: - Init

    init(
        fingerprint: DocumentFingerprint,
        title: String,
        author: String? = nil,
        coverImagePath: String? = nil,
        provenance: ImportProvenance,
        addedAt: Date = Date(),
        isFavorite: Bool = false,
        tags: [String] = []
    ) {
        self.fingerprintKey = fingerprint.canonicalKey
        self.fingerprint = fingerprint
        self.title = title
        self.author = author
        self.coverImagePath = coverImagePath
        self.format = fingerprint.format.rawValue
        self.fileByteCount = fingerprint.fileByteCount
        self.provenance = provenance
        self.addedAt = addedAt
        self.isFavorite = isFavorite
        self.tags = tags
        self.bookmarks = []
        self.highlights = []
        self.annotations = []
    }

    // MARK: - Private

    private func syncDerivedFields() {
        fingerprintKey = fingerprint.canonicalKey
        format = fingerprint.format.rawValue
        fileByteCount = fingerprint.fileByteCount
    }
}
