// Purpose: Table of contents extraction for all supported formats.
// EPUB: from spine items (titles). PDF: from outline tree. TXT/MD: empty.
//
// Key decisions:
// - TOCEntry is a flat list with level for nesting (not a recursive tree).
// - TXT always returns empty (no TOC for plain text).
// - MD returns empty in V1 (heading extraction deferred).
// - PDF traversal walks PDFOutline recursively.
// - Protocol-based for testability.
//
// @coordinates-with: EPUBTypes.swift, LocatorFactory.swift

import Foundation

/// A single entry in a table of contents.
struct TOCEntry: Sendable, Equatable, Identifiable {
    /// Stable ID derived from locator hash + title for deterministic identity across reloads.
    let id: String
    let title: String
    let level: Int
    let locator: Locator

    init(
        title: String,
        level: Int,
        locator: Locator
    ) {
        self.id = "\(locator.canonicalHash):\(title)"
        self.title = title
        self.level = max(0, level)
        self.locator = locator
    }
}

/// Protocol for table of contents extraction.
protocol TOCProviding: Sendable {
    /// Extracts the table of contents for a given book format.
    func tableOfContents(for fingerprint: DocumentFingerprint) async throws -> [TOCEntry]
}
