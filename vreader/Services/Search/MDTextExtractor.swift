// Purpose: Extracts plain text from Markdown files for search indexing.
// Strips markdown syntax to produce clean text for FTS5 indexing.
//
// Key decisions:
// - Strips common markdown syntax (headings, emphasis, links, images, code).
// - Reuses paragraph-based segmentation like TXTTextExtractor for offset tracking.
// - sourceUnitId uses "md:segment:<N>" convention for SearchHitToLocatorResolver.
// - Markdown stripping happens before segmentation so offsets align with stripped text.
//
// @coordinates-with SearchTextExtractor.swift, SearchHitToLocatorResolver.swift

import Foundation

/// Result of MD text extraction, including segment base offsets for locator resolution.
struct MDExtractionResult: Sendable {
    let textUnits: [TextUnit]
    /// Maps segment index -> cumulative UTF-16 offset in the stripped text.
    let segmentBaseOffsets: [Int: Int]
}

/// Extracts searchable text from Markdown files.
struct MDTextExtractor: SearchTextExtractor {

    func extractTextUnits(
        from url: URL,
        fingerprint: DocumentFingerprint
    ) async throws -> [TextUnit] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else {
            let result = try EncodingDetector.detect(data: data)
            text = result.text
        }
        return extractWithOffsets(from: text).textUnits
    }

    /// Loads a file with encoding detection and extracts text units with offsets.
    /// Handles UTF-8, UTF-16 (with BOM), and falls back to EncodingDetector.
    func extractWithOffsets(from url: URL) async throws -> MDExtractionResult {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else {
            let result = try EncodingDetector.detect(data: data)
            text = result.text
        }
        return extractWithOffsets(from: text)
    }

    /// Creates text units from already-decoded markdown text with segment base offsets.
    func extractWithOffsets(from markdown: String) -> MDExtractionResult {
        let stripped = Self.stripMarkdown(markdown)
        guard !stripped.isEmpty else {
            return MDExtractionResult(textUnits: [], segmentBaseOffsets: [:])
        }
        let segmented = segmentText(stripped)
        return segmented
    }

    // MARK: - Markdown Stripping

    /// Strips markdown syntax, producing plain text suitable for search indexing.
    static func stripMarkdown(_ markdown: String) -> String {
        guard !markdown.isEmpty else { return "" }

        var text = markdown

        // Remove fenced code blocks (``` ... ```) — remove entire block
        text = text.replacingOccurrences(
            of: "```[^\\n]*\\n[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )

        // Remove horizontal rules (---, ***, ___)
        text = text.replacingOccurrences(
            of: "(?m)^[\\s]*[-*_]{3,}[\\s]*$",
            with: "",
            options: .regularExpression
        )

        // Remove images ![alt](url) — drop entirely
        text = text.replacingOccurrences(
            of: "!\\[[^\\]]*\\]\\([^)]*\\)",
            with: "",
            options: .regularExpression
        )

        // Convert links [text](url) → text
        text = text.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]*\\)",
            with: "$1",
            options: .regularExpression
        )

        // Strip heading markers (# ... ######)
        text = text.replacingOccurrences(
            of: "(?m)^#{1,6}\\s+",
            with: "",
            options: .regularExpression
        )

        // Strip bold/italic (*** ** * ___ __ _)
        // Handle *** first, then **, then *
        text = text.replacingOccurrences(
            of: "\\*{3}([^*]+)\\*{3}",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "\\*{2}([^*]+)\\*{2}",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "(?<![\\w*])\\*([^*]+)\\*(?![\\w*])",
            with: "$1",
            options: .regularExpression
        )
        // Underscore variants
        text = text.replacingOccurrences(
            of: "_{3}([^_]+)_{3}",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "_{2}([^_]+)_{2}",
            with: "$1",
            options: .regularExpression
        )

        // Strip inline code `code`
        text = text.replacingOccurrences(
            of: "`([^`]+)`",
            with: "$1",
            options: .regularExpression
        )

        // Strip blockquote markers
        text = text.replacingOccurrences(
            of: "(?m)^>\\s?",
            with: "",
            options: .regularExpression
        )

        // Strip unordered list markers (-, *, +)
        text = text.replacingOccurrences(
            of: "(?m)^\\s*[-*+]\\s+",
            with: "",
            options: .regularExpression
        )

        // Strip ordered list markers (1. 2. etc.)
        text = text.replacingOccurrences(
            of: "(?m)^\\s*\\d+\\.\\s+",
            with: "",
            options: .regularExpression
        )

        // Collapse multiple blank lines
        text = text.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Segmentation

    /// Splits stripped text into paragraph segments with UTF-16 offset tracking.
    private func segmentText(_ text: String) -> MDExtractionResult {
        guard !text.isEmpty else {
            return MDExtractionResult(textUnits: [], segmentBaseOffsets: [:])
        }

        let separator: String
        let doubleNewlineSegments = text.components(separatedBy: "\n\n")
        let nonEmptyCount = doubleNewlineSegments
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count

        if nonEmptyCount <= 1 && text.count > 500 {
            separator = "\n"
        } else {
            separator = "\n\n"
        }

        var units: [TextUnit] = []
        var baseOffsets: [Int: Int] = [:]
        var segmentIndex = 0
        let parts = text.components(separatedBy: separator)
        var utf16Offset = 0

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let partUTF16Count = part.utf16.count

            if !trimmed.isEmpty {
                baseOffsets[segmentIndex] = utf16Offset
                units.append(TextUnit(
                    sourceUnitId: "md:segment:\(segmentIndex)",
                    text: part
                ))
                segmentIndex += 1
            }

            utf16Offset += partUTF16Count + separator.utf16.count
        }

        return MDExtractionResult(textUnits: units, segmentBaseOffsets: baseOffsets)
    }
}
