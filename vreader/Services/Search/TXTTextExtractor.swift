// Purpose: Extracts text from TXT files for search indexing.
// Splits text into paragraph-based segments for snippet granularity.
//
// Key decisions:
// - Segments are paragraphs separated by double newlines (or single for short texts).
// - Each segment becomes a TextUnit with sourceUnitId "txt:segment:<N>".
// - Empty segments are filtered out to avoid indexing noise.
// - Segment text is NOT trimmed to preserve UTF-16 offset alignment with original text.
// - Also computes cumulative UTF-16 base offsets for locator resolution.
//
// @coordinates-with SearchTextExtractor.swift, TXTServiceProtocol.swift

import Foundation

/// Result of TXT text extraction, including segment base offsets for locator resolution.
struct TXTExtractionResult: Sendable {
    let textUnits: [TextUnit]
    /// Maps segment index → cumulative UTF-16 offset in the original text.
    let segmentBaseOffsets: [Int: Int]
}

/// Extracts text from TXT files for search indexing.
struct TXTTextExtractor: SearchTextExtractor {

    func extractTextUnits(
        from url: URL,
        fingerprint: DocumentFingerprint
    ) async throws -> [TextUnit] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TXTTextExtractorError.decodingFailed(url.lastPathComponent)
        }
        return segmentText(text).textUnits
    }

    /// Creates text units from already-decoded text with segment base offsets.
    /// Useful when the text is already loaded (e.g., from TXTServiceProtocol).
    func extractWithOffsets(from text: String) -> TXTExtractionResult {
        segmentText(text)
    }

    /// Splits text into paragraph segments, tracking original byte offsets.
    private func segmentText(_ text: String) -> TXTExtractionResult {
        guard !text.isEmpty else {
            return TXTExtractionResult(textUnits: [], segmentBaseOffsets: [:])
        }

        let separator: String
        // Split on double newlines (paragraph boundaries)
        let doubleNewlineSegments = text.components(separatedBy: "\n\n")
        let nonEmptyDoubleCount = doubleNewlineSegments.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count

        if nonEmptyDoubleCount <= 1 && text.count > 500 {
            separator = "\n"
        } else {
            separator = "\n\n"
        }

        // Walk the original text to find segment boundaries and track offsets
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
                    sourceUnitId: "txt:segment:\(segmentIndex)",
                    text: part
                ))
                segmentIndex += 1
            }

            // Advance past this part + the separator
            utf16Offset += partUTF16Count + separator.utf16.count
        }

        return TXTExtractionResult(textUnits: units, segmentBaseOffsets: baseOffsets)
    }
}

/// Errors during TXT text extraction.
enum TXTTextExtractorError: Error, Sendable {
    case decodingFailed(String)
}
