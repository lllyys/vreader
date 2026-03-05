// Purpose: Metadata extractor for Markdown files. Extracts title from
// first H1 heading, with fallback to filename.
//
// Key decisions:
// - Uses simple regex for H1 detection (no swift-markdown dependency needed).
// - Title truncated to 255 chars for consistency with other extractors.
// - Uses EncodingDetector for multi-encoding support (not just UTF-8).
// - Empty files get "Untitled" as title.
// - Conforms to MetadataExtractor for BookImporter integration.
//
// @coordinates-with: MetadataExtractor.swift, BookImporter.swift, EncodingDetector.swift

import Foundation

/// Maximum title length in characters.
private let mdMaxTitleLength = 255

/// Extracts metadata from Markdown files. Title from first H1, fallback to filename.
struct MDMetadataExtractor: MetadataExtractor {

    func extractMetadata(from fileURL: URL) async throws -> BookMetadata {
        // Try to read file for H1 extraction using encoding detection
        if let data = try? Data(contentsOf: fileURL),
           let result = try? EncodingDetector.detect(data: data) {
            if let h1Title = Self.extractFirstH1(from: result.text) {
                return BookMetadata(
                    title: String(h1Title.prefix(mdMaxTitleLength)),
                    author: nil,
                    coverImagePath: nil
                )
            }
        }
        // Fallback to filename-based title
        return .fromFilename(fileURL)
    }

    /// Extracts the text of the first ATX H1 heading (# Title) from Markdown source.
    ///
    /// Looks for lines starting with "# " (ATX heading level 1).
    /// Returns nil if no H1 is found.
    static func extractFirstH1(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2))
                    .trimmingCharacters(in: .whitespaces)
                    // Remove trailing # markers (e.g., "# Title ###")
                    .replacingOccurrences(
                        of: #"\s*#+\s*$"#,
                        with: "",
                        options: .regularExpression
                    )
                if !title.isEmpty {
                    return title
                }
            }
        }
        return nil
    }
}
