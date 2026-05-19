// Purpose: Resolves the chapter span containing a reading position,
// from a book's TOC entries — the Chapter scope of the AI Summarize
// selector (feature #69).
//
// Key decisions:
// - Pure, no I/O — converts (TOC entries, locator, total UTF-16 length)
//   into a ChapterBounds?.
// - Mirrors TOCChapterProgress's chapter-detection algorithm: a
//   pre-first-entry offset is virtual chapter 0 (the preamble / front
//   matter), spanning [0, firstStart). The final chapter ends at the
//   total text length.
// - Works purely in UTF-16 units (Locator.charOffsetUTF16) — the same
//   coordinate space the TXT TOC entries and AIContextExtractor use.
// - Defensively sorts the chapter-start offsets so an out-of-order TOC
//   still resolves correctly.
// - Returns nil only when no usable chapter offsets exist (empty TOC
//   or every entry's locator lacks charOffsetUTF16) — the caller then
//   degrades Chapter to Section. A short/zero total length is NOT a
//   nil case: anchored TOC offsets still resolve; the final chapter's
//   end is clamped to >= its start (ChapterBounds enforces this), so a
//   degenerate total simply collapses the final chapter to an empty
//   span, which AIContextExtractor handles as "".
//
// @coordinates-with: ChapterBounds.swift, TOCProvider.swift,
//   TOCChapterProgress.swift, AIContextExtractor.swift

import Foundation

/// Resolves the TOC-chapter span containing a reading position.
enum SummaryScopeResolver {

    /// Returns the chapter span containing `locator`.
    ///
    /// The span for an offset BEFORE the first TOC entry is
    /// `[0, firstEntryOffset)` — the book's preamble (front matter
    /// before chapter 1) — mirroring how `TOCChapterProgress` treats a
    /// pre-first-entry offset as virtual chapter 0. The final chapter
    /// ends at `totalTextLengthUTF16`.
    ///
    /// A locator with no `charOffsetUTF16` is treated as offset `0`
    /// (it has no position, so it falls into the preamble span).
    ///
    /// Returns `nil` only when no usable chapter offsets exist:
    /// - the TOC is empty, or
    /// - every entry's locator lacks `charOffsetUTF16` (EPUB-shaped
    ///   TOCs are not char-offset-anchored).
    ///
    /// A short or zero `totalTextLengthUTF16` does NOT yield `nil` —
    /// anchored offsets still resolve; the final chapter's end is
    /// clamped to its start (a zero-length span) by `ChapterBounds`.
    ///
    /// - Parameters:
    ///   - locator: the reading position to locate within the TOC.
    ///   - tocEntries: the book's TOC entries (need not be sorted).
    ///   - totalTextLengthUTF16: total UTF-16 length of the flattened text.
    /// - Returns: the chapter span, or `nil` when Chapter scope cannot
    ///   be resolved (the caller degrades to Section).
    static func chapterBounds(
        for locator: Locator,
        tocEntries: [TOCEntry],
        totalTextLengthUTF16: Int
    ) -> ChapterBounds? {
        guard !tocEntries.isEmpty else { return nil }

        // Extract chapter-start UTF-16 offsets; an EPUB-shaped TOC whose
        // entries carry no charOffsetUTF16 yields an empty list → nil.
        // Defensive sort: an out-of-order TOC still resolves correctly.
        let starts = tocEntries
            .compactMap { $0.locator.charOffsetUTF16 }
            .sorted()
        guard let firstStart = starts.first else { return nil }

        // A locator without an offset has no position — treat as 0.
        let offset = locator.charOffsetUTF16 ?? 0

        // Pre-first-entry offset → the preamble span [0, firstStart).
        if offset < firstStart {
            return ChapterBounds(startUTF16: 0, endUTF16: firstStart)
        }

        // Find the chapter whose [start, nextStart) contains `offset`.
        var chapterIndex = 0
        for (i, start) in starts.enumerated() {
            if offset >= start {
                chapterIndex = i
            } else {
                break
            }
        }

        let chapterStart = starts[chapterIndex]
        // A non-final chapter ends at the next chapter's start. The
        // final chapter ends at the total text length; if that total
        // is short/zero, `ChapterBounds` clamps the end up to the start
        // (an empty final-chapter span), so this is never `nil`.
        let chapterEnd = chapterIndex + 1 < starts.count
            ? starts[chapterIndex + 1]
            : totalTextLengthUTF16

        return ChapterBounds(startUTF16: chapterStart, endUTF16: chapterEnd)
    }
}
