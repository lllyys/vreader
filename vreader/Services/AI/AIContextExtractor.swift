// Purpose: Extracts text around a locator position for AI context.
// Handles different book formats (EPUB, PDF, TXT/MD) with format-specific
// logic, and — for the AI Summarize tab — scope-aware extraction
// (Section / Chapter / Book-so-far) bounded by an explicit UTF-16 budget.
//
// Key decisions:
// - Struct-based for Sendable compliance.
// - Target context window is ~500 words (configurable).
// - For TXT/MD: uses charOffsetUTF16 to find center, expands to word boundaries.
// - For PDF: extracts text around the page.
// - For EPUB: uses href to identify the chapter, extracts around progression.
// - Clamps out-of-bounds offsets instead of failing.
// - Returns empty string for empty input (not an error).
// - Scope-aware extraction (feature #69): the legacy
//   extractContext(locator:textContent:format:) is a .section-delegating
//   shim; the scoped entry point adds .chapter / .bookSoFar paths that
//   slice the FULL flattened text by UTF-16 offsets via UTF16TextSlicer
//   (surrogate-pair-safe). The budget is an explicit UTF-16-unit count
//   (maxUTF16) — not an ambiguous "character" count.
// - The scoped TXT helpers resolve the locator's UTF-16 offset with the
//   same `charOffsetUTF16 ?? charRangeStartUTF16` fallback the legacy
//   .section path uses, so all three scopes agree on "where the reader is".
//
// @coordinates-with: AIService.swift, Locator.swift, SummaryScope.swift,
//   ChapterBounds.swift, SummaryScopeResolver.swift, UTF16TextSlicer.swift,
//   AIContextExtracting.swift, AIAssistantViewModel.swift

import Foundation

/// Extracts text context around a reading position for AI requests.
struct AIContextExtractor: Sendable, AIContextExtracting {

    /// Target number of characters to extract (approximately 500 words).
    let targetCharacterCount: Int

    init(targetCharacterCount: Int = 2500) {
        self.targetCharacterCount = targetCharacterCount
    }

    // MARK: - Legacy entry point (.section shim)

    /// Extracts context text from the given text units around the locator.
    ///
    /// Retained for callers that only need the current ~2500-char window
    /// (the Chat tab's section context, etc.). Delegates to the scoped
    /// entry point with `scope: .section`, so behavior is byte-identical
    /// to the pre-feature-#69 implementation.
    ///
    /// - Parameters:
    ///   - locator: The reading position to center context around.
    ///   - textContent: The text content of the relevant section/chapter/page.
    ///   - format: The book format, determining extraction strategy.
    /// - Returns: Extracted text context, or empty string if no text.
    func extractContext(
        locator: Locator,
        textContent: String,
        format: BookFormat
    ) -> String {
        extractContext(
            locator: locator,
            fullText: textContent,
            format: format,
            scope: .section,
            chapterBounds: nil,
            maxUTF16: AIContextBudget.defaultMaxUTF16
        )
    }

    // MARK: - Scoped entry point

    /// Extracts context for an AI summary at the requested scope.
    ///
    /// - `.section` — the existing ~2500-char window around the locator.
    ///   `maxUTF16` is unused for this scope (the window is bounded by
    ///   `targetCharacterCount`); `fullText` may be the full text or a
    ///   section snippet — `.section` re-extracts the same window either
    ///   way, so the legacy snippet callers are unaffected.
    /// - `.chapter` — the UTF-16 sub-sequence `[chapterBounds.start ..<
    ///   chapterBounds.end]` of `fullText`. If that slice exceeds
    ///   `maxUTF16`, a `maxUTF16`-wide window centered on the locator's
    ///   offset (clamped within the chapter) is returned. A `nil`
    ///   `chapterBounds` degrades to `.section`.
    /// - `.bookSoFar` — the prefix `[0 ..< offset]`; if longer than
    ///   `maxUTF16`, the LAST `maxUTF16` units before the offset
    ///   (recency-biased).
    ///
    /// All slicing snaps to Unicode scalar boundaries (`UTF16TextSlicer`)
    /// so a surrogate pair is never bisected.
    ///
    /// - Parameters:
    ///   - locator: The reading position.
    ///   - fullText: The FULL flattened book text (not a snippet) for
    ///     `.chapter` / `.bookSoFar`.
    ///   - format: The book format.
    ///   - scope: How much of the book the summary should cover.
    ///   - chapterBounds: The chapter span for `.chapter`; `nil` degrades
    ///     `.chapter` to `.section`.
    ///   - maxUTF16: The UTF-16-unit budget for `.chapter` / `.bookSoFar`.
    /// - Returns: Extracted text, or `""` if no text is available.
    func extractContext(
        locator: Locator,
        fullText: String,
        format: BookFormat,
        scope: SummaryScope,
        chapterBounds: ChapterBounds?,
        maxUTF16: Int = AIContextBudget.defaultMaxUTF16
    ) -> String {
        guard !fullText.isEmpty else { return "" }

        switch scope {
        case .section:
            return extractSection(locator: locator, text: fullText, format: format)
        case .chapter:
            guard let bounds = chapterBounds else {
                return extractSection(locator: locator, text: fullText, format: format)
            }
            return extractChapter(
                locator: locator, text: fullText,
                bounds: bounds, maxUTF16: maxUTF16
            )
        case .bookSoFar:
            return extractBookSoFar(
                locator: locator, text: fullText, maxUTF16: maxUTF16
            )
        }
    }

    // MARK: - Locator offset resolution

    /// Resolves the locator's UTF-16 offset into `text` for the scoped
    /// TXT paths, using the same `charOffsetUTF16 ?? charRangeStartUTF16`
    /// fallback the legacy `.section` path (`extractByCharOffset`) uses,
    /// then clamps into `[0, utf16.count]`. `fallback` is returned when
    /// the locator carries neither field.
    private func resolvedOffsetUTF16(
        for locator: Locator, in text: String, fallback: Int
    ) -> Int {
        let total = text.utf16.count
        let raw = locator.charOffsetUTF16 ?? locator.charRangeStartUTF16 ?? fallback
        return max(0, min(raw, total))
    }

    // MARK: - Section (existing per-format behavior)

    /// The pre-feature-#69 per-format window extraction.
    private func extractSection(
        locator: Locator, text: String, format: BookFormat
    ) -> String {
        switch format {
        case .txt, .md:
            return extractByCharOffset(locator: locator, text: text)
        case .pdf:
            return extractByPage(text: text)
        case .epub, .azw3:
            return extractByProgression(locator: locator, text: text)
        }
    }

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

    // MARK: - Chapter (feature #69)

    /// Extracts the chapter-bounded slice. If the chapter exceeds
    /// `maxUTF16`, returns a `maxUTF16`-wide window centered on the
    /// locator's offset, clamped within the chapter.
    private func extractChapter(
        locator: Locator, text: String,
        bounds: ChapterBounds, maxUTF16: Int
    ) -> String {
        let totalUTF16 = text.utf16.count
        // Clamp the chapter span into the text.
        let chapStart = max(0, min(bounds.startUTF16, totalUTF16))
        let chapEnd = max(chapStart, min(bounds.endUTF16, totalUTF16))
        let chapterLength = chapEnd - chapStart
        guard chapterLength > 0 else { return "" }

        // Whole chapter fits the budget — return it verbatim.
        if maxUTF16 <= 0 || chapterLength <= maxUTF16 {
            return UTF16TextSlicer.slice(text, fromUTF16: chapStart, toUTF16: chapEnd)
        }

        // Over budget: a maxUTF16-wide window centered on the locator,
        // clamped to stay inside the chapter. The locator offset uses the
        // same fallback as the .section path; default it to the chapter
        // start so a locator with no offset summarizes the chapter's head.
        let center = max(chapStart, min(
            resolvedOffsetUTF16(for: locator, in: text, fallback: chapStart),
            chapEnd
        ))
        let half = maxUTF16 / 2
        var windowStart = max(chapStart, center - half)
        var windowEnd = min(chapEnd, windowStart + maxUTF16)
        // If we hit the chapter's right edge first, pull the start back.
        windowStart = max(chapStart, windowEnd - maxUTF16)
        windowEnd = min(chapEnd, windowStart + maxUTF16)
        return UTF16TextSlicer.slice(text, fromUTF16: windowStart, toUTF16: windowEnd)
    }

    // MARK: - Book so far (feature #69)

    /// Extracts the prefix from the book start up to the locator's
    /// offset. If that prefix exceeds `maxUTF16`, returns the LAST
    /// `maxUTF16` units before the offset (recency-biased — the text
    /// nearest the reading position is the most relevant).
    private func extractBookSoFar(
        locator: Locator, text: String, maxUTF16: Int
    ) -> String {
        let totalUTF16 = text.utf16.count
        // A locator with no offset means "no position" — treat the whole
        // text as read so far (fallback = totalUTF16), matching how the
        // reader's fallback path extracts from the start of the book.
        let offset = resolvedOffsetUTF16(for: locator, in: text, fallback: totalUTF16)
        guard offset > 0 else { return "" }

        // Whole prefix fits the budget.
        if maxUTF16 <= 0 || offset <= maxUTF16 {
            return UTF16TextSlicer.slice(text, fromUTF16: 0, toUTF16: offset)
        }

        // Over budget: the last maxUTF16 units before the offset.
        let start = offset - maxUTF16
        return UTF16TextSlicer.slice(text, fromUTF16: start, toUTF16: offset)
    }
}
