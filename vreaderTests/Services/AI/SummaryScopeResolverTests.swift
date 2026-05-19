// Purpose: Tests for SummaryScopeResolver — the pure TOC→ChapterBounds
// resolver behind the Chapter scope of the AI Summarize selector
// (feature #69 WI-2). Mirrors the chapter-detection algorithm of
// TOCChapterProgress: pre-first-entry offset → preamble span
// [0, firstStart); empty / non-anchored TOC → nil.

import Testing
@testable import vreader

@Suite("SummaryScopeResolver")
struct SummaryScopeResolverTests {

    // MARK: - Helpers

    private static let fp = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 4096,
        format: .txt
    )

    /// A TXT locator at a UTF-16 char offset.
    private func locator(at offset: Int?) -> Locator {
        Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: offset,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    /// A TOC entry anchored at a UTF-16 char offset (or nil — EPUB-shaped).
    private func tocEntry(_ title: String, charOffset: Int?) -> TOCEntry {
        TOCEntry(title: title, level: 0, locator: locator(at: charOffset))
    }

    /// A three-chapter TXT TOC: chapters start at 100, 1000, 3000.
    private var threeChapterTOC: [TOCEntry] {
        [
            tocEntry("Chapter 1", charOffset: 100),
            tocEntry("Chapter 2", charOffset: 1000),
            tocEntry("Chapter 3", charOffset: 3000),
        ]
    }

    // MARK: - Locator inside chapter 1

    @Test func offsetInChapterOneResolvesToFirstSpan() {
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 400),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == ChapterBounds(startUTF16: 100, endUTF16: 1000))
    }

    // MARK: - Locator mid-book (chapter 2)

    @Test func offsetMidBookResolvesToMiddleSpan() {
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 2000),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == ChapterBounds(startUTF16: 1000, endUTF16: 3000))
    }

    // MARK: - Locator in the final chapter (end == total)

    @Test func offsetInFinalChapterEndsAtTotalLength() {
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 4200),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == ChapterBounds(startUTF16: 3000, endUTF16: 5000))
    }

    // MARK: - Pre-first-entry offset → preamble span [0, firstStart)

    @Test func offsetBeforeFirstEntryResolvesToPreambleSpan() {
        // Mirrors TOCChapterProgress: front matter before chapter 1
        // is virtual chapter 0, spanning [0, firstStart).
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 40),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == ChapterBounds(startUTF16: 0, endUTF16: 100))
    }

    @Test func offsetZeroResolvesToPreambleSpan() {
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 0),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == ChapterBounds(startUTF16: 0, endUTF16: 100))
    }

    // MARK: - Offset exactly on a chapter boundary

    @Test func offsetExactlyOnBoundaryBelongsToThatChapter() {
        // Offset == chapter-2 start (1000) → resolves to chapter 2.
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 1000),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == ChapterBounds(startUTF16: 1000, endUTF16: 3000))
    }

    @Test func offsetExactlyOnFirstEntryStartIsChapterOne() {
        // Offset == first entry start (100) → chapter 1, not preamble.
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 100),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == ChapterBounds(startUTF16: 100, endUTF16: 1000))
    }

    // MARK: - Single-chapter book

    @Test func singleChapterBookSpansEntryStartToTotal() {
        let toc = [tocEntry("Only Chapter", charOffset: 50)]
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 900),
            tocEntries: toc,
            totalTextLengthUTF16: 2000
        )
        #expect(bounds == ChapterBounds(startUTF16: 50, endUTF16: 2000))
    }

    @Test func singleChapterPreambleSpansZeroToEntryStart() {
        let toc = [tocEntry("Only Chapter", charOffset: 50)]
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 10),
            tocEntries: toc,
            totalTextLengthUTF16: 2000
        )
        #expect(bounds == ChapterBounds(startUTF16: 0, endUTF16: 50))
    }

    // MARK: - Empty TOC → nil

    @Test func emptyTOCReturnsNil() {
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 400),
            tocEntries: [],
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == nil)
    }

    // MARK: - TOC entries with nil charOffsetUTF16 (EPUB-shaped) → nil

    @Test func tocWithNoCharOffsetsReturnsNil() {
        let toc = [
            tocEntry("Chapter 1", charOffset: nil),
            tocEntry("Chapter 2", charOffset: nil),
        ]
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 400),
            tocEntries: toc,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == nil)
    }

    @Test func tocWithSomeCharOffsetsUsesOnlyAnchoredEntries() {
        // Mixed TOC: only the anchored entries (200, 1500) form spans.
        let toc = [
            tocEntry("Anchored A", charOffset: 200),
            tocEntry("Unanchored", charOffset: nil),
            tocEntry("Anchored B", charOffset: 1500),
        ]
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 800),
            tocEntries: toc,
            totalTextLengthUTF16: 4000
        )
        #expect(bounds == ChapterBounds(startUTF16: 200, endUTF16: 1500))
    }

    // MARK: - Locator with nil charOffsetUTF16 → treated as offset 0

    @Test func locatorWithNoOffsetResolvesToPreamble() {
        // A locator lacking charOffsetUTF16 has no position — treat as
        // offset 0, which lands in the preamble span.
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: nil),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == ChapterBounds(startUTF16: 0, endUTF16: 100))
    }

    // MARK: - Short / zero total length is NOT a nil case

    @Test func zeroTotalLengthStillResolvesFromAnchoredTOC() {
        // Plan §2.4: nil is reserved for "no usable chapter offsets".
        // A zero total length with anchored TOC offsets must still
        // resolve — the final chapter collapses to an empty span
        // (ChapterBounds clamps end up to start).
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 4200),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 0
        )
        // Locator 4200 is in the final chapter (start 3000); a zero
        // total collapses [3000, 0] to the zero-length span [3000, 3000].
        #expect(bounds == ChapterBounds(startUTF16: 3000, endUTF16: 3000))
    }

    @Test func shortTotalLengthResolvesNonFinalChapterNormally() {
        // A short total length does not affect non-final chapters —
        // their end comes from the next chapter's start, not the total.
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 400),
            tocEntries: threeChapterTOC,
            totalTextLengthUTF16: 10
        )
        #expect(bounds == ChapterBounds(startUTF16: 100, endUTF16: 1000))
    }

    // MARK: - Surrogate-pair (supplementary-plane) UTF-16 offsets

    @Test func surrogatePairOffsetsLandInExpectedChapter() {
        // The resolver works in UTF-16 units. Derive real offsets from a
        // string containing supplementary-plane characters (emoji are
        // 2 UTF-16 units each) and prove the locator lands in the right
        // chapter span — a genuine UTF-16 test, not hard-coded numbers.
        let emoji = "😀"                        // 1 Character, 2 UTF-16 units
        let chapterOnePrefix = String(repeating: emoji, count: 50)   // 100 UTF-16
        let chapterTwoBody = String(repeating: emoji, count: 80)     // 160 UTF-16
        let fullText = chapterOnePrefix + chapterTwoBody             // 260 UTF-16

        let chTwoStart = chapterOnePrefix.utf16.count                // 100
        let total = fullText.utf16.count                            // 260
        // A reading position 30 emoji into chapter two → 100 + 60 = 160.
        let readingOffset = chTwoStart + String(repeating: emoji, count: 30).utf16.count

        let toc = [
            tocEntry("Chapter One", charOffset: 0),
            tocEntry("Chapter Two", charOffset: chTwoStart),
        ]
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: readingOffset),
            tocEntries: toc,
            totalTextLengthUTF16: total
        )
        #expect(bounds == ChapterBounds(startUTF16: chTwoStart, endUTF16: total))
        // Sanity: the offsets are even (each emoji is a 2-unit surrogate pair).
        #expect(chTwoStart % 2 == 0)
        #expect(readingOffset % 2 == 0)
    }

    // MARK: - Unsorted TOC entries

    @Test func unsortedTOCEntriesAreSortedBeforeResolving() {
        // Entries supplied out of order — resolver sorts the offsets.
        let toc = [
            tocEntry("Chapter 3", charOffset: 3000),
            tocEntry("Chapter 1", charOffset: 100),
            tocEntry("Chapter 2", charOffset: 1000),
        ]
        let bounds = SummaryScopeResolver.chapterBounds(
            for: locator(at: 2000),
            tocEntries: toc,
            totalTextLengthUTF16: 5000
        )
        #expect(bounds == ChapterBounds(startUTF16: 1000, endUTF16: 3000))
    }
}
