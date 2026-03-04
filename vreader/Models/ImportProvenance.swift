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
}
