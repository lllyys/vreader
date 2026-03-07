// Purpose: Protocol for format-specific text extraction for search indexing.
// Each format (EPUB, PDF, TXT, MD) implements this to provide text units for FTS5 indexing.
//
// Key decisions:
// - TextUnit is the minimal data needed: sourceUnitId + text.
// - Protocol is async throws for I/O-bound extraction (PDF, file reads).
// - Sendable for safe cross-actor usage.
//
// @coordinates-with SearchIndexStore.swift, PDFTextExtractor.swift, TXTTextExtractor.swift,
//   EPUBTextExtractor.swift, MDTextExtractor.swift

import Foundation

/// A unit of text extracted from a document for search indexing.
struct TextUnit: Sendable, Equatable {
    /// Canonical source unit identifier:
    /// - EPUB: "epub:<href>"
    /// - PDF: "pdf:page:<zero-based-page-index>"
    /// - TXT: "txt:segment:<zero-based-segment-index>"
    /// - MD: "md:segment:<zero-based-segment-index>"
    let sourceUnitId: String

    /// The raw text content of this unit.
    let text: String
}

/// Protocol for extracting text from a document for search indexing.
protocol SearchTextExtractor: Sendable {
    /// Extracts text units from a document at the given URL.
    ///
    /// - Parameters:
    ///   - url: Location of the document file.
    ///   - fingerprint: The document's content fingerprint.
    /// - Returns: Array of text units, one per logical section (page, chapter, segment).
    func extractTextUnits(
        from url: URL,
        fingerprint: DocumentFingerprint
    ) async throws -> [TextUnit]
}
