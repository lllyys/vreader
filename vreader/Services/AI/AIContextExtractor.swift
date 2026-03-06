// Purpose: Extracts text around a locator position for AI context.
// Handles different book formats (EPUB, PDF, TXT/MD) with format-specific logic.
//
// Key decisions:
// - Struct-based for Sendable compliance.
// - Target context window is ~500 words (configurable).
// - For TXT/MD: uses charOffsetUTF16 to find center, expands to word boundaries.
// - For PDF: extracts text around the page.
// - For EPUB: uses href to identify the chapter, extracts around progression.
// - Clamps out-of-bounds offsets instead of failing.
// - Returns empty string for empty input (not an error).
//
// @coordinates-with: AIService.swift, Locator.swift

import Foundation

/// Extracts text context around a reading position for AI requests.
struct AIContextExtractor: Sendable {

    /// Target number of characters to extract (approximately 500 words).
    let targetCharacterCount: Int

    init(targetCharacterCount: Int = 2500) {
        self.targetCharacterCount = targetCharacterCount
    }

    /// Extracts context text from the given text units around the locator position.
    ///
    /// - Parameters:
    ///   - locator: The reading position to center context around.
    ///   - textContent: The full text content of the relevant section/chapter/page.
    ///   - format: The book format, determining extraction strategy.
    /// - Returns: Extracted text context, or empty string if no text available.
    func extractContext(
        locator: Locator,
        textContent: String,
        format: BookFormat
    ) -> String {
        guard !textContent.isEmpty else { return "" }

        switch format {
        case .txt, .md:
            return extractByCharOffset(locator: locator, text: textContent)
        case .pdf:
            return extractByPage(text: textContent)
        case .epub:
            return extractByProgression(locator: locator, text: textContent)
        }
    }

    // MARK: - Private

    /// Extracts context around a UTF-16 character offset (TXT/MD).
    private func extractByCharOffset(locator: Locator, text: String) -> String {
        let utf16View = text.utf16
        let totalUTF16 = utf16View.count

        guard totalUTF16 > 0 else { return "" }

        // Determine center offset — clamp to valid range
        let centerUTF16: Int
        if let offset = locator.charOffsetUTF16 {
            centerUTF16 = max(0, min(offset, totalUTF16 - 1))
        } else if let rangeStart = locator.charRangeStartUTF16 {
            centerUTF16 = max(0, min(rangeStart, totalUTF16 - 1))
        } else {
            // No offset info — take from beginning
            centerUTF16 = 0
        }

        // Calculate window in UTF-16 units
        let halfWindow = targetCharacterCount / 2
        let startUTF16 = max(0, centerUTF16 - halfWindow)
        let endUTF16 = min(totalUTF16, centerUTF16 + halfWindow)

        // Convert to String indices
        let startIndex = utf16View.index(utf16View.startIndex, offsetBy: startUTF16)
        let endIndex = utf16View.index(utf16View.startIndex, offsetBy: endUTF16)

        guard let startStringIndex = startIndex.samePosition(in: text),
              let endStringIndex = endIndex.samePosition(in: text) else {
            // Fallback: take prefix
            return String(text.prefix(targetCharacterCount))
        }

        return String(text[startStringIndex..<endStringIndex])
    }

    /// Extracts context from page text (PDF). Takes the full page text up to limit.
    private func extractByPage(text: String) -> String {
        if text.count <= targetCharacterCount {
            return text
        }
        return String(text.prefix(targetCharacterCount))
    }

    /// Extracts context around a progression value (EPUB).
    private func extractByProgression(locator: Locator, text: String) -> String {
        let totalChars = text.count
        guard totalChars > 0 else { return "" }

        let progression = locator.progression ?? 0.0
        let clampedProgression = max(0.0, min(1.0, progression))
        let centerChar = Int(Double(totalChars) * clampedProgression)

        let halfWindow = targetCharacterCount / 2
        let startChar = max(0, centerChar - halfWindow)
        let endChar = min(totalChars, centerChar + halfWindow)

        let startIndex = text.index(text.startIndex, offsetBy: startChar)
        let endIndex = text.index(text.startIndex, offsetBy: endChar)

        return String(text[startIndex..<endIndex])
    }
}
