// Purpose: Translates highlight ranges between global (DB) and chapter-local
// (display) coordinates. Used at the TXTReaderContainerView boundary to adapt
// persisted highlights for chapter display.
//
// Key decisions:
// - Pure functions (enum namespace) — no state, no MainActor.
// - All offsets are UTF-16 code units matching NSString/UIKit conventions.
// - Highlights spanning chapter boundaries are clipped to the chapter range.
// - Invalid inputs (out-of-bounds index, negative start, zero-length) return
//   empty results rather than crashing.
//
// @coordinates-with: TXTChapter.swift, ReaderNotificationModifier.swift,
//   TXTReaderContainerView.swift

import Foundation

/// Translates highlight ranges between global (DB) and chapter-local (display) coordinates.
/// Used at the TXTReaderContainerView boundary to adapt persisted highlights for chapter display.
enum TXTChapterHighlightHelper {

    /// Filters and translates persisted highlights (global UTF-16) to
    /// chapter-local coordinates. Only returns highlights that fall within
    /// the given chapter; each translated highlight keeps its stored color
    /// (Bug #208).
    static func highlightsForChapter(
        chapterIndex: Int,
        chapters: [TXTChapter],
        persistedGlobalRanges: [PaintedHighlight]
    ) -> [PaintedHighlight] {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return [] }
        let chapter = chapters[chapterIndex]
        guard chapter.globalStartUTF16 >= 0, chapter.textLengthUTF16 > 0 else { return [] }

        let chapterStart = chapter.globalStartUTF16
        let chapterEnd = chapterStart + chapter.textLengthUTF16

        return persistedGlobalRanges.compactMap { painted in
            let rangeStart = painted.range.location
            let rangeEnd = painted.range.location + painted.range.length

            // Skip if entirely outside this chapter
            guard rangeEnd > chapterStart, rangeStart < chapterEnd else { return nil }

            // Clip to chapter boundaries
            let clippedStart = max(rangeStart, chapterStart)
            let clippedEnd = min(rangeEnd, chapterEnd)

            // Translate to chapter-local — color preserved (Bug #208)
            return PaintedHighlight(
                range: NSRange(
                    location: clippedStart - chapterStart,
                    length: clippedEnd - clippedStart
                ),
                colorName: painted.colorName
            )
        }
    }

    /// Translates a chapter-local NSRange (from new highlight creation) to global.
    static func toGlobalRange(
        localRange: NSRange,
        chapterIndex: Int,
        chapters: [TXTChapter]
    ) -> NSRange? {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return nil }
        let chapter = chapters[chapterIndex]
        guard chapter.globalStartUTF16 >= 0 else { return nil }
        return NSRange(
            location: localRange.location + chapter.globalStartUTF16,
            length: localRange.length
        )
    }

    /// Filters and translates a UUID-keyed lookup of global highlight ranges
    /// to chapter-local. Preserves the UUID; clips ranges spanning the chapter
    /// boundary; drops entries entirely outside the chapter. Mirrors
    /// `highlightsForChapter` but carries the highlight ID through so the
    /// bridge's tap-on-highlight hit-test can resolve the right UUID for the
    /// inline edit/delete menu in chapter mode (Bug #202).
    static func lookupForChapter(
        chapterIndex: Int,
        chapters: [TXTChapter],
        globalLookup: [PersistedHighlightLookupEntry]
    ) -> [PersistedHighlightLookupEntry] {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return [] }
        let chapter = chapters[chapterIndex]
        guard chapter.globalStartUTF16 >= 0, chapter.textLengthUTF16 > 0 else { return [] }

        let chapterStart = chapter.globalStartUTF16
        let chapterEnd = chapterStart + chapter.textLengthUTF16

        return globalLookup.compactMap { entry in
            let rangeStart = entry.range.location
            let rangeEnd = entry.range.location + entry.range.length

            // Skip if entirely outside this chapter
            guard rangeEnd > chapterStart, rangeStart < chapterEnd else { return nil }

            // Clip to chapter boundaries
            let clippedStart = max(rangeStart, chapterStart)
            let clippedEnd = min(rangeEnd, chapterEnd)

            return PersistedHighlightLookupEntry(
                id: entry.id,
                range: NSRange(
                    location: clippedStart - chapterStart,
                    length: clippedEnd - clippedStart
                )
            )
        }
    }

    /// Translates a global scroll offset to chapter-local for bridge navigation.
    static func toChapterLocalOffset(
        globalUTF16: Int,
        chapterIndex: Int,
        chapters: [TXTChapter]
    ) -> Int {
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return 0 }
        let chapter = chapters[chapterIndex]
        guard chapter.globalStartUTF16 >= 0 else { return 0 }
        return max(0, globalUTF16 - chapter.globalStartUTF16)
    }
}
