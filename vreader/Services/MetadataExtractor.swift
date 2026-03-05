// Purpose: Protocol and stub implementations for book metadata extraction.
// Real implementations will come in WI-6 (EPUB/Readium) and WI-7 (PDF/PDFKit).
//
// Key decisions:
// - Protocol-based design allows easy testing with mocks.
// - Stub extractors derive title from filename.
// - TXT metadata uses filename as title, nil author, no cover.
//
// @coordinates-with: BookImporter.swift

import Foundation

/// Maximum title length in characters (shared across all extractors).
private let maxTitleLength = 255

/// Extracted metadata from a book file.
struct BookMetadata: Sendable, Equatable {
    /// Book title (required).
    let title: String

    /// Author name (optional).
    let author: String?

    /// Relative path to extracted cover image (optional).
    let coverImagePath: String?

    /// Creates metadata using filename-derived title (shared default behavior).
    static func fromFilename(_ fileURL: URL, author: String? = nil, coverImagePath: String? = nil) -> BookMetadata {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(maxTitleLength))
        return BookMetadata(title: title, author: author, coverImagePath: coverImagePath)
    }
}

/// Protocol for extracting metadata from book files.
protocol MetadataExtractor: Sendable {
    /// Extracts metadata from the file at the given URL.
    ///
    /// - Parameter fileURL: Path to the imported file in sandbox.
    /// - Returns: Extracted metadata.
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata
}

/// Extracts metadata for TXT files. Title from filename, no author, no cover.
struct TXTMetadataExtractor: MetadataExtractor {
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        .fromFilename(fileURL)
    }
}

/// Stub extractor for EPUB files.
/// TODO(WI-6): Replace with Readium-based extractor that reads OPF metadata
/// (title, author, publisher, cover image). Remove this stub when WI-6 lands.
struct EPUBMetadataExtractor: MetadataExtractor {
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        .fromFilename(fileURL)
    }
}

/// Stub extractor for PDF files.
/// TODO(WI-7): Replace with PDFKit-based extractor that reads PDF document info
/// (title, author, page count). Remove this stub when WI-7 lands.
struct PDFMetadataExtractor: MetadataExtractor {
    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        .fromFilename(fileURL)
    }
}
