// Purpose: Records how and when a book was imported into the library.
// Includes optional security-scoped bookmark data for file access.

import Foundation

/// Provenance metadata for an imported book.
struct ImportProvenance: Codable, Hashable, Sendable {
    /// How the book was imported.
    let source: ImportSource

    /// When the import occurred.
    let importedAt: Date

    /// Optional security-scoped bookmark for re-accessing the original file.
    /// NOTE: Contains file access metadata. V2 should encrypt at rest via keychain-backed key
    /// if store is synced or accessible outside sandbox.
    let originalURLBookmarkData: Data?

    /// Feature #42 Phase 2 (WI-4b): the original Kindle extension (`azw3`/`mobi`/
    /// `prc`/`azw`) when this book was produced by convert-on-import; nil
    /// otherwise. **Best-effort, non-load-bearing** (WI-4 design decision #5):
    /// the converted EPUB is a self-describing first-class EPUB, so nothing in
    /// correctness/rendering/backup/restore depends on this — it is observability
    /// only, and its loss on restore/dedupe-replace is acceptable.
    let convertedFromKindleExtension: String?

    /// The `MobiEPUBConverter.version` that produced the converted EPUB; nil for
    /// non-converted books. Best-effort (see `convertedFromKindleExtension`).
    let converterVersion: Int?

    /// Optional fields default to nil so existing call sites are unchanged and
    /// pre-v3 persisted/backup payloads (which lack the new keys) decode cleanly
    /// — Swift's synthesized `Codable` uses `decodeIfPresent` for Optionals, so
    /// a missing key → nil (round-3 audit Medium: backward-compatible decode).
    init(
        source: ImportSource,
        importedAt: Date,
        originalURLBookmarkData: Data?,
        convertedFromKindleExtension: String? = nil,
        converterVersion: Int? = nil
    ) {
        self.source = source
        self.importedAt = importedAt
        self.originalURLBookmarkData = originalURLBookmarkData
        self.convertedFromKindleExtension = convertedFromKindleExtension
        self.converterVersion = converterVersion
    }
}
