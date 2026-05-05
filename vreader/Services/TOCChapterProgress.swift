// Purpose: Computes chapter-relative scroll progress from TOC entries.
// Used when chapter-based indexing fails but TOC regex detection succeeds,
// so the progress bar can show chapter progress in legacy full-text mode.
//
// @coordinates-with: TXTReaderContainerView.swift, TOCProvider.swift,
//   ReadingProgressBar.swift

import Foundation

/// Result of chapter progress computation from TOC entries.
struct TOCChapterProgressResult: Sendable, Equatable {
    /// Zero-based index of the current chapter in the TOC entries array.
    let chapterIndex: Int
    /// Scroll fraction within the current chapter (0.0 to 1.0).
    let fraction: Double
    /// Total number of chapters.
    let totalChapters: Int
}

/// Computes chapter-relative progress from TOC entries + current scroll offset.
enum TOCChapterProgress {

    /// Finds the current chapter and computes scroll fraction within it.
    ///
    /// - Parameters:
    ///   - currentOffsetUTF16: Current global scroll position in UTF-16 units.
    ///   - tocEntries: TOC entries sorted by position (each has locator.charOffsetUTF16).
    ///   - totalTextLengthUTF16: Total text length of the document.
    /// - Returns: Chapter index + fraction, or nil if no TOC entries.
    static func progress(
        currentOffsetUTF16: Int,
        tocEntries: [TOCEntry],
        totalTextLengthUTF16: Int
    ) -> TOCChapterProgressResult? {
        guard !tocEntries.isEmpty, totalTextLengthUTF16 > 0 else { return nil }

        // Extract sorted chapter start offsets from TOC entries.
        let starts = tocEntries.compactMap { $0.locator.charOffsetUTF16 }
        guard !starts.isEmpty else { return nil }

        // Bug #127: preamble (offset before first TOC entry) — Foreword,
        // Preface, etc. — is treated as virtual chapter 0 with proportional
        // fraction `currentOffset / first_entry_offset`. Earlier behavior
        // clamped this region to fraction=0, which made the progress bar
        // appear stuck at "Chapter 1, 0%" until the reader reached the
        // first chapter title. Now the preamble shows real progress.
        if currentOffsetUTF16 < starts[0] {
            let preambleLen = starts[0]
            let fraction = preambleLen > 0
                ? Double(currentOffsetUTF16) / Double(preambleLen)
                : 0
            return TOCChapterProgressResult(
                chapterIndex: 0,
                fraction: max(0, min(1, fraction)),
                totalChapters: starts.count
            )
        }

        // Find which chapter the current offset falls in.
        var chapterIdx = 0
        for (i, start) in starts.enumerated() {
            if currentOffsetUTF16 >= start {
                chapterIdx = i
            } else {
                break
            }
        }

        // Compute chapter boundaries.
        let chapterStart = starts[chapterIdx]
        let chapterEnd = chapterIdx + 1 < starts.count
            ? starts[chapterIdx + 1]
            : totalTextLengthUTF16
        let chapterLen = chapterEnd - chapterStart

        guard chapterLen > 0 else {
            return TOCChapterProgressResult(
                chapterIndex: chapterIdx, fraction: 0, totalChapters: starts.count
            )
        }

        let localOffset = currentOffsetUTF16 - chapterStart
        let fraction = Double(max(0, min(localOffset, chapterLen))) / Double(chapterLen)

        return TOCChapterProgressResult(
            chapterIndex: chapterIdx,
            fraction: fraction,
            totalChapters: starts.count
        )
    }
}
