// Purpose: Chapter-awareness layer over the continuous-scroll TXT surface
// (Bug #180 re-scoped fix). Maps any document-global UTF-16 offset to the
// chapter that contains it, so `currentChapterIdx` can be DERIVED from scroll
// position rather than driving which text is rendered.
//
// Key decisions:
// - Pure value type (Sendable, Equatable) — no @MainActor, fully unit-testable.
// - Built once at open time from the same `TXTChapterIndex` the detector
//   produces; the continuous surface consumes it without re-indexing.
// - `chapterContaining` is a binary search over the chapters' globalStartUTF16
//   values; all lookups clamp into bounds rather than crash.
// - Single source of truth for "which chapter is offset X in".
//
// @coordinates-with: TXTChapterIndex.swift, TXTReaderViewModel.swift,
//   TXTReaderContainerView.swift

import Foundation

/// Maps document-global UTF-16 offsets to chapters over a continuous TXT
/// scroll surface. Bug #180 re-scoped fix.
struct TXTChapterOffsetIndex: Sendable, Equatable {

    /// Chapters in document order. Each carries `globalStartUTF16` and
    /// `textLengthUTF16` (populated by the chapter-index builder).
    let chapters: [TXTChapter]

    /// Total UTF-16 length of the whole book text.
    let totalTextLengthUTF16: Int

    /// Builds the offset index from a fully-populated `TXTChapterIndex`.
    static func build(from index: TXTChapterIndex) -> TXTChapterOffsetIndex {
        TXTChapterOffsetIndex(
            chapters: index.chapters,
            totalTextLengthUTF16: index.totalTextLengthUTF16
        )
    }

    /// Returns the index of the chapter containing the given document-global
    /// UTF-16 offset. Clamps to `[0, count-1]`; returns 0 for an empty index.
    func chapterContaining(_ globalUTF16: Int) -> Int {
        guard !chapters.isEmpty else { return 0 }
        // Binary search for the last chapter whose start <= globalUTF16.
        var lo = 0
        var hi = chapters.count - 1
        // Below the first chapter's start → clamp to 0.
        if globalUTF16 < chapterStart(of: 0) { return 0 }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if chapterStart(of: mid) <= globalUTF16 {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    /// Document-global UTF-16 start offset of the given chapter.
    /// Returns 0 for an out-of-bounds index.
    func globalStart(ofChapter idx: Int) -> Int {
        guard idx >= 0, idx < chapters.count else { return 0 }
        return chapterStart(of: idx)
    }

    /// UTF-16 length of the given chapter. Returns 0 for an out-of-bounds index.
    func chapterLength(_ idx: Int) -> Int {
        guard idx >= 0, idx < chapters.count else { return 0 }
        return max(0, chapters[idx].textLengthUTF16)
    }

    /// For the per-chapter scrubber: the chapter containing `globalUTF16` and
    /// the fraction (0.0–1.0) of progress through that chapter.
    func chapterLocalFraction(globalUTF16: Int) -> (chapterIdx: Int, fraction: Double) {
        let idx = chapterContaining(globalUTF16)
        let start = globalStart(ofChapter: idx)
        let length = chapterLength(idx)
        guard length > 0 else { return (idx, 0.0) }
        let local = min(max(globalUTF16 - start, 0), length)
        return (idx, Double(local) / Double(length))
    }

    // MARK: - Private

    /// Chapter start, treating an unpopulated `globalStartUTF16` (-1) as 0.
    private func chapterStart(of idx: Int) -> Int {
        max(0, chapters[idx].globalStartUTF16)
    }
}
