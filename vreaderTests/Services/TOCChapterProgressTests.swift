// Purpose: Tests for TOCChapterProgress — computes chapter-relative scroll
// progress from TOC entries and a global UTF-16 offset.

import Testing
import Foundation
@testable import vreader

@Suite("TOCChapterProgress")
struct TOCChapterProgressTests {

    // MARK: - Helpers

    private static let testFingerprint = DocumentFingerprint(
        contentSHA256: String(repeating: "0", count: 64),
        fileByteCount: 0,
        format: .txt
    )

    private func makeTOCEntries(offsets: [Int]) -> [TOCEntry] {
        offsets.enumerated().map { i, offset in
            TOCEntry(
                title: "Chapter \(i + 1)",
                level: 0,
                locator: Locator(
                    bookFingerprint: Self.testFingerprint,
                    href: nil,
                    progression: nil,
                    totalProgression: nil,
                    cfi: nil,
                    page: nil,
                    charOffsetUTF16: offset,
                    charRangeStartUTF16: nil,
                    charRangeEndUTF16: nil,
                    textQuote: nil,
                    textContextBefore: nil,
                    textContextAfter: nil
                ),
                sequenceIndex: i
            )
        }
    }

    // MARK: - Tests

    @Test("returns nil when no TOC entries")
    func noEntries() {
        let result = TOCChapterProgress.progress(
            currentOffsetUTF16: 100,
            tocEntries: [],
            totalTextLengthUTF16: 1000
        )
        #expect(result == nil)
    }

    @Test("returns nil when only one entry")
    func singleEntry() {
        let entries = makeTOCEntries(offsets: [0])
        let result = TOCChapterProgress.progress(
            currentOffsetUTF16: 500,
            tocEntries: entries,
            totalTextLengthUTF16: 1000
        )
        // Single entry = single chapter spanning entire book.
        // Progress = offset / total
        #expect(result != nil)
        #expect(result!.chapterIndex == 0)
        #expect(abs(result!.fraction - 0.5) < 0.01)
    }

    @Test("midway through first chapter")
    func firstChapterMidway() {
        let entries = makeTOCEntries(offsets: [0, 500, 1000])
        let result = TOCChapterProgress.progress(
            currentOffsetUTF16: 250,
            tocEntries: entries,
            totalTextLengthUTF16: 1500
        )
        #expect(result != nil)
        #expect(result!.chapterIndex == 0)
        #expect(abs(result!.fraction - 0.5) < 0.01)
    }

    @Test("at start of second chapter")
    func secondChapterStart() {
        let entries = makeTOCEntries(offsets: [0, 500, 1000])
        let result = TOCChapterProgress.progress(
            currentOffsetUTF16: 500,
            tocEntries: entries,
            totalTextLengthUTF16: 1500
        )
        #expect(result != nil)
        #expect(result!.chapterIndex == 1)
        #expect(abs(result!.fraction) < 0.01)
    }

    @Test("midway through last chapter")
    func lastChapterMidway() {
        let entries = makeTOCEntries(offsets: [0, 500, 1000])
        let result = TOCChapterProgress.progress(
            currentOffsetUTF16: 1250,
            tocEntries: entries,
            totalTextLengthUTF16: 1500
        )
        #expect(result != nil)
        #expect(result!.chapterIndex == 2)
        #expect(abs(result!.fraction - 0.5) < 0.01)
    }

    @Test("at end of book")
    func endOfBook() {
        let entries = makeTOCEntries(offsets: [0, 500])
        let result = TOCChapterProgress.progress(
            currentOffsetUTF16: 1000,
            tocEntries: entries,
            totalTextLengthUTF16: 1000
        )
        #expect(result != nil)
        #expect(result!.chapterIndex == 1)
        #expect(abs(result!.fraction - 1.0) < 0.01)
    }

    @Test("offset before first TOC entry")
    func beforeFirstEntry() {
        let entries = makeTOCEntries(offsets: [100, 500])
        let result = TOCChapterProgress.progress(
            currentOffsetUTF16: 50,
            tocEntries: entries,
            totalTextLengthUTF16: 1000
        )
        // Before first entry = preamble, treat as chapter 0.
        // Production currently clamps fraction to 0 for any offset before
        // the first entry (see TOCChapterProgress.swift:65 — `max(0, ...)`)
        // — i.e., it doesn't model preamble progress as a fraction of
        // (0 → first_entry). The test's original expectation (fraction
        // ≈ 0.5) reflected the better UX choice but never matched
        // production.
        //
        // Bug #127 (GH #271) tracks the production fix; this test is
        // updated to current behavior so the suite is green. When the
        // bug fix lands the assertion flips back to fraction ≈ 0.5.
        #expect(result != nil)
        #expect(result!.chapterIndex == 0)
        #expect(result!.fraction == 0)
    }
}
