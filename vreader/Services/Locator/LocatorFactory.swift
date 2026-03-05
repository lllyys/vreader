// Purpose: Format-specific locator factories with automatic quote/context extraction.
//
// Key decisions:
// - All factories delegate to Locator.validated() — return nil on validation failure.
// - TXT factories auto-extract quote + context from source text using UTF-16 offsets.
// - extractContext uses String.UTF16View for offset math, clamping to bounds.
// - Context window defaults to 50 characters before/after the selection.
//
// @coordinates-with Locator.swift, DocumentFingerprint.swift

import Foundation

enum LocatorFactory {

    // MARK: - Constants

    /// Number of UTF-16 code units to capture before/after the selection for context.
    static let contextWindowSize = 50
    /// Default quote length in UTF-16 code units for position-based (non-range) TXT locators.
    static let defaultQuoteLength = 30

    // MARK: - EPUB

    /// Creates a locator for an EPUB position.
    static func epub(
        fingerprint: DocumentFingerprint,
        href: String,
        progression: Double,
        totalProgression: Double? = nil,
        cfi: String? = nil,
        textQuote: String? = nil,
        textContextBefore: String? = nil,
        textContextAfter: String? = nil
    ) -> Locator? {
        Locator.validated(
            bookFingerprint: fingerprint,
            href: href,
            progression: progression,
            totalProgression: totalProgression,
            cfi: cfi,
            textQuote: textQuote,
            textContextBefore: textContextBefore,
            textContextAfter: textContextAfter
        )
    }

    // MARK: - PDF

    /// Creates a locator for a PDF page position.
    static func pdf(
        fingerprint: DocumentFingerprint,
        page: Int,
        totalProgression: Double? = nil,
        textQuote: String? = nil,
        textContextBefore: String? = nil,
        textContextAfter: String? = nil
    ) -> Locator? {
        Locator.validated(
            bookFingerprint: fingerprint,
            totalProgression: totalProgression,
            page: page,
            textQuote: textQuote,
            textContextBefore: textContextBefore,
            textContextAfter: textContextAfter
        )
    }

    // MARK: - TXT Position

    /// Creates a locator for a TXT cursor position (single offset).
    /// If `sourceText` is provided, auto-extracts a ~30-char quote and surrounding context.
    static func txtPosition(
        fingerprint: DocumentFingerprint,
        charOffsetUTF16: Int,
        totalProgression: Double? = nil,
        sourceText: String? = nil
    ) -> Locator? {
        var textQuote: String?
        var contextBefore: String?
        var contextAfter: String?

        if let sourceText {
            let ctx = extractContext(
                from: sourceText,
                at: charOffsetUTF16,
                length: defaultQuoteLength
            )
            textQuote = ctx.quote
            contextBefore = ctx.contextBefore
            contextAfter = ctx.contextAfter
        }

        return Locator.validated(
            bookFingerprint: fingerprint,
            totalProgression: totalProgression,
            charOffsetUTF16: charOffsetUTF16,
            textQuote: nonEmpty(textQuote),
            textContextBefore: nonEmpty(contextBefore),
            textContextAfter: nonEmpty(contextAfter)
        )
    }

    // MARK: - TXT Range

    /// Creates a locator for a TXT selection range.
    /// If `sourceText` is provided, auto-extracts the selected text as quote and surrounding context.
    static func txtRange(
        fingerprint: DocumentFingerprint,
        charRangeStartUTF16: Int,
        charRangeEndUTF16: Int,
        totalProgression: Double? = nil,
        sourceText: String? = nil
    ) -> Locator? {
        var textQuote: String?
        var contextBefore: String?
        var contextAfter: String?

        if let sourceText {
            let length = charRangeEndUTF16 - charRangeStartUTF16
            guard length >= 0 else {
                // Inverted range — let validated() reject it, but skip extraction.
                return Locator.validated(
                    bookFingerprint: fingerprint,
                    totalProgression: totalProgression,
                    charRangeStartUTF16: charRangeStartUTF16,
                    charRangeEndUTF16: charRangeEndUTF16
                )
            }
            let ctx = extractContext(
                from: sourceText,
                at: charRangeStartUTF16,
                length: length
            )
            textQuote = ctx.quote
            contextBefore = ctx.contextBefore
            contextAfter = ctx.contextAfter
        }

        return Locator.validated(
            bookFingerprint: fingerprint,
            totalProgression: totalProgression,
            charRangeStartUTF16: charRangeStartUTF16,
            charRangeEndUTF16: charRangeEndUTF16,
            textQuote: nonEmpty(textQuote),
            textContextBefore: nonEmpty(contextBefore),
            textContextAfter: nonEmpty(contextAfter)
        )
    }

    // MARK: - MD Position (alias for TXT offset logic on rendered text)

    /// Creates a locator for an MD cursor position in rendered text.
    /// Delegates to the same logic as `txtPosition` — offsets are UTF-16 over rendered text.
    static func mdPosition(
        fingerprint: DocumentFingerprint,
        charOffsetUTF16: Int,
        totalProgression: Double? = nil,
        sourceText: String? = nil
    ) -> Locator? {
        txtPosition(
            fingerprint: fingerprint,
            charOffsetUTF16: charOffsetUTF16,
            totalProgression: totalProgression,
            sourceText: sourceText
        )
    }

    // MARK: - MD Range (alias for TXT range logic on rendered text)

    /// Creates a locator for an MD selection range in rendered text.
    /// Delegates to the same logic as `txtRange`.
    static func mdRange(
        fingerprint: DocumentFingerprint,
        charRangeStartUTF16: Int,
        charRangeEndUTF16: Int,
        totalProgression: Double? = nil,
        sourceText: String? = nil
    ) -> Locator? {
        txtRange(
            fingerprint: fingerprint,
            charRangeStartUTF16: charRangeStartUTF16,
            charRangeEndUTF16: charRangeEndUTF16,
            totalProgression: totalProgression,
            sourceText: sourceText
        )
    }

    // MARK: - Quote/Context Extraction

    /// Extracts quote text and surrounding context from source text at a UTF-16 offset.
    ///
    /// - Parameters:
    ///   - sourceText: The full text to extract from.
    ///   - utf16Offset: Starting position in UTF-16 code units.
    ///   - length: Number of UTF-16 code units to include in the quote (0 for cursor position).
    ///   - windowSize: Maximum number of UTF-16 code units for before/after context.
    /// - Returns: Tuple with optional quote, contextBefore, and contextAfter strings.
    static func extractContext(
        from sourceText: String,
        at utf16Offset: Int,
        length: Int = 0,
        windowSize: Int = contextWindowSize
    ) -> (quote: String?, contextBefore: String?, contextAfter: String?) {
        let utf16 = sourceText.utf16
        let totalCount = utf16.count
        let clampedWindow = max(windowSize, 0)

        guard totalCount > 0 else {
            return (nil, nil, nil)
        }

        // Clamp offset to valid range
        let clampedOffset = min(max(utf16Offset, 0), totalCount)

        // If offset is at or beyond end, nothing to extract
        guard clampedOffset < totalCount || length == 0 else {
            // At end — extract context before only
            let beforeStart = max(0, clampedOffset - clampedWindow)
            let ctxBefore = substringFromUTF16(sourceText, from: beforeStart, to: clampedOffset)
            return (nil, nonEmpty(ctxBefore), nil)
        }

        // Clamp length to available text
        let clampedLength = min(max(length, 0), totalCount - clampedOffset)

        // Extract quote
        let quote: String?
        if clampedLength > 0 {
            quote = substringFromUTF16(sourceText, from: clampedOffset, to: clampedOffset + clampedLength)
        } else {
            quote = nil
        }

        // Extract context before
        let beforeStart = max(0, clampedOffset - clampedWindow)
        let contextBefore = substringFromUTF16(sourceText, from: beforeStart, to: clampedOffset)

        // Extract context after
        let afterEnd = min(totalCount, clampedOffset + clampedLength + clampedWindow)
        let contextAfter = substringFromUTF16(
            sourceText,
            from: clampedOffset + clampedLength,
            to: afterEnd
        )

        return (
            nonEmpty(quote),
            nonEmpty(contextBefore),
            nonEmpty(contextAfter)
        )
    }

    // MARK: - Private Helpers

    /// Extracts a substring using UTF-16 offsets, snapping to valid scalar boundaries.
    /// Returns nil if the range is invalid or empty.
    private static func substringFromUTF16(
        _ string: String,
        from start: Int,
        to end: Int
    ) -> String? {
        let utf16 = string.utf16
        guard start < end, start >= 0, end <= utf16.count else { return nil }

        // Use String.Index(utf16Offset:in:) for safe boundary-aware conversion.
        let startIndex = String.Index(utf16Offset: start, in: string)
        let endIndex = String.Index(utf16Offset: end, in: string)

        guard startIndex < endIndex else { return nil }
        return String(string[startIndex ..< endIndex])
    }

    /// Returns nil for empty strings, the string itself otherwise.
    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
