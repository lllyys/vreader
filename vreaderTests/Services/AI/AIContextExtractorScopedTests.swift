// Purpose: Tests for AIContextExtractor's scope-aware extraction
// (feature #69 WI-3) — the .section / .chapter / .bookSoFar paths,
// the explicit UTF-16 budget, and surrogate-pair-safe slicing.
// The legacy extractContext(locator:textContent:format:) is a
// .section-delegating shim; this suite proves it stays byte-identical.

import Testing
import Foundation
@testable import vreader

@Suite("AIContextExtractor scoped extraction")
struct AIContextExtractorScopedTests {

    // MARK: - Helpers

    private static let fp = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 8192,
        format: .txt
    )

    private func locator(at offset: Int?) -> Locator {
        Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: offset,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - .section: new path == legacy path (byte-identical)

    @Test func sectionScopeMatchesLegacyEntryPoint() {
        let text = String(repeating: "abcdefghij", count: 500)  // 5000 chars
        let extractor = AIContextExtractor()
        let loc = locator(at: 2500)

        let legacy = extractor.extractContext(
            locator: loc, textContent: text, format: .txt
        )
        let scoped = extractor.extractContext(
            locator: loc, fullText: text, format: .txt,
            scope: .section, chapterBounds: nil, maxUTF16: 12_000
        )
        #expect(scoped == legacy)
        #expect(!scoped.isEmpty)
    }

    @Test func legacyEntryPointStillWorksUnchanged() {
        let text = "Hello World"
        let extractor = AIContextExtractor(targetCharacterCount: 100)
        let result = extractor.extractContext(
            locator: locator(at: 0), textContent: text, format: .txt
        )
        #expect(result == "Hello World")
    }

    // MARK: - .chapter: slices to bounds

    @Test func chapterScopeSlicesToBounds() {
        // 3000 chars; chapter span [1000, 2000) → exactly that slice.
        let text = String(repeating: "x", count: 1000)
            + String(repeating: "y", count: 1000)
            + String(repeating: "z", count: 1000)
        let extractor = AIContextExtractor()
        let bounds = ChapterBounds(startUTF16: 1000, endUTF16: 2000)

        let result = extractor.extractContext(
            locator: locator(at: 1500), fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 12_000
        )
        #expect(result == String(repeating: "y", count: 1000))
    }

    // MARK: - .chapter over maxUTF16: centered window within the chapter

    @Test func chapterScopeOverBudgetTakesCenteredWindow() {
        // Chapter [1000, 2000); maxUTF16 200; locator at 1500. Window
        // centered on the locator → [1400, 1600). Marker segments prove
        // the EXACT slice, not just the length.
        let text = String(repeating: "H", count: 1000)   // [0,1000)
            + String(repeating: "L", count: 400)         // [1000,1400)
            + String(repeating: "M", count: 200)         // [1400,1600) ← window
            + String(repeating: "R", count: 400)         // [1600,2000)
            + String(repeating: "T", count: 1000)        // [2000,3000)
        let extractor = AIContextExtractor()
        let bounds = ChapterBounds(startUTF16: 1000, endUTF16: 2000)

        let result = extractor.extractContext(
            locator: locator(at: 1500), fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 200
        )
        #expect(result == String(repeating: "M", count: 200))
    }

    @Test func chapterScopeOverBudgetWindowStaysInsideChapter() {
        // Locator near the chapter start; the centered window must clamp
        // to the chapter's left edge — [800, 1000), NOT spill before 800.
        let text = String(repeating: "B", count: 800)    // [0,800)
            + String(repeating: "W", count: 200)         // [800,1000) ← window
            + String(repeating: "R", count: 1000)        // [1000,2000)
        let extractor = AIContextExtractor()
        let bounds = ChapterBounds(startUTF16: 800, endUTF16: 1800)

        let result = extractor.extractContext(
            locator: locator(at: 820), fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 200
        )
        // Window clamps to the chapter's left edge: exactly the "W" run.
        #expect(result == String(repeating: "W", count: 200))
    }

    @Test func chapterScopeOverBudgetWindowClampsToRightEdge() {
        // Locator near the chapter end; the window must clamp to the
        // chapter's right edge — [1600, 1800), NOT spill past 1800.
        let text = String(repeating: "B", count: 1600)   // [0,1600)
            + String(repeating: "W", count: 200)         // [1600,1800) ← window
            + String(repeating: "A", count: 200)         // [1800,2000)
        let extractor = AIContextExtractor()
        let bounds = ChapterBounds(startUTF16: 800, endUTF16: 1800)

        let result = extractor.extractContext(
            locator: locator(at: 1790), fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 200
        )
        #expect(result == String(repeating: "W", count: 200))
    }

    // MARK: - .chapter with nil bounds degrades to .section

    @Test func chapterScopeWithNilBoundsDegradesToSection() {
        let text = String(repeating: "abcdefghij", count: 500)
        let extractor = AIContextExtractor()
        let loc = locator(at: 2500)

        let chapterNil = extractor.extractContext(
            locator: loc, fullText: text, format: .txt,
            scope: .chapter, chapterBounds: nil, maxUTF16: 12_000
        )
        let section = extractor.extractContext(
            locator: loc, fullText: text, format: .txt,
            scope: .section, chapterBounds: nil, maxUTF16: 12_000
        )
        #expect(chapterNil == section)
    }

    // MARK: - .bookSoFar: short prefix

    @Test func bookSoFarShortPrefixTakesStartToOffset() {
        let text = String(repeating: "p", count: 5000)
        let extractor = AIContextExtractor()
        // Offset 800, budget 12000 → prefix [0, 800).
        let result = extractor.extractContext(
            locator: locator(at: 800), fullText: text, format: .txt,
            scope: .bookSoFar, chapterBounds: nil, maxUTF16: 12_000
        )
        #expect(result.utf16.count == 800)
        #expect(result == String(repeating: "p", count: 800))
    }

    // MARK: - .bookSoFar over budget: last maxUTF16 units before the offset

    @Test func bookSoFarOverBudgetTakesLastBudgetUnits() {
        // Distinct halves so we can prove the recency bias.
        let head = String(repeating: "H", count: 3000)
        let tail = String(repeating: "T", count: 3000)
        let text = head + tail   // offset 6000 worth
        let extractor = AIContextExtractor()

        // Locator at 6000 (end), budget 1000 → last 1000 units = all "T".
        let result = extractor.extractContext(
            locator: locator(at: 6000), fullText: text, format: .txt,
            scope: .bookSoFar, chapterBounds: nil, maxUTF16: 1000
        )
        #expect(result.utf16.count == 1000)
        #expect(result == String(repeating: "T", count: 1000))
    }

    // MARK: - Empty fullText

    @Test func emptyFullTextReturnsEmptyForEveryScope() {
        let extractor = AIContextExtractor()
        for scope in SummaryScope.allCases {
            let result = extractor.extractContext(
                locator: locator(at: 0), fullText: "", format: .txt,
                scope: scope,
                chapterBounds: ChapterBounds(startUTF16: 0, endUTF16: 0),
                maxUTF16: 12_000
            )
            #expect(result.isEmpty, "scope \(scope) on empty text → \"\"")
        }
    }

    // MARK: - Locator offset 0

    @Test func bookSoFarAtOffsetZeroReturnsEmpty() {
        let text = String(repeating: "a", count: 1000)
        let extractor = AIContextExtractor()
        // Prefix [0, 0) is empty.
        let result = extractor.extractContext(
            locator: locator(at: 0), fullText: text, format: .txt,
            scope: .bookSoFar, chapterBounds: nil, maxUTF16: 12_000
        )
        #expect(result.isEmpty)
    }

    // MARK: - Locator offset past utf16.count → clamp

    @Test func bookSoFarOffsetPastEndClampsToFullText() {
        let text = String(repeating: "a", count: 500)
        let extractor = AIContextExtractor()
        // Offset 99999 clamps to 500 → prefix is the whole text.
        let result = extractor.extractContext(
            locator: locator(at: 99_999), fullText: text, format: .txt,
            scope: .bookSoFar, chapterBounds: nil, maxUTF16: 12_000
        )
        #expect(result == text)
    }

    @Test func chapterBoundsBeyondTextAreClamped() {
        // Bounds end past the text length → slice clamps to the text end.
        let text = String(repeating: "a", count: 500)
        let extractor = AIContextExtractor()
        let bounds = ChapterBounds(startUTF16: 100, endUTF16: 99_999)

        let result = extractor.extractContext(
            locator: locator(at: 200), fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 12_000
        )
        #expect(result == String(repeating: "a", count: 400))  // [100, 500)
    }

    // MARK: - Zero-length chapter

    @Test func zeroLengthChapterReturnsEmpty() {
        let text = String(repeating: "a", count: 1000)
        let extractor = AIContextExtractor()
        let bounds = ChapterBounds(startUTF16: 400, endUTF16: 400)

        let result = extractor.extractContext(
            locator: locator(at: 400), fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 12_000
        )
        #expect(result.isEmpty)
    }

    // MARK: - CJK / surrogate-pair text — no split surrogate at boundaries

    @Test func chapterScopeDoesNotSplitSurrogatePairs() {
        // Emoji are 2-UTF-16-unit surrogate pairs. A chapter slice whose
        // bounds fall ON a pair boundary must yield valid scalars.
        let emoji = "😀"
        let text = String(repeating: emoji, count: 200)  // 400 UTF-16 units
        let extractor = AIContextExtractor()
        // [100, 300) — both bounds land between two emoji (even offsets).
        let bounds = ChapterBounds(startUTF16: 100, endUTF16: 300)

        let result = extractor.extractContext(
            locator: locator(at: 200), fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 12_000
        )
        // 200 UTF-16 units = 100 emoji, every scalar intact.
        #expect(result.utf16.count == 200)
        #expect(result == String(repeating: emoji, count: 100))
        #expect(result.unicodeScalars.allSatisfy { $0 != "\u{FFFD}" })
    }

    @Test func bookSoFarOverBudgetDoesNotSplitSurrogatePairs() {
        // Over-budget last-N truncation on emoji text: if maxUTF16 is odd
        // it would bisect a surrogate pair — the extractor must not
        // produce a replacement char / lone surrogate.
        let emoji = "🎉"
        let text = String(repeating: emoji, count: 300)  // 600 UTF-16 units
        let extractor = AIContextExtractor()
        // Offset 600 (end), odd budget 201 → must round to a safe boundary.
        let result = extractor.extractContext(
            locator: locator(at: 600), fullText: text, format: .txt,
            scope: .bookSoFar, chapterBounds: nil, maxUTF16: 201
        )
        // No replacement char; result is a whole number of emoji.
        #expect(result.unicodeScalars.allSatisfy { $0 != "\u{FFFD}" })
        #expect(result.utf16.count % 2 == 0)
        #expect(result.utf16.count <= 201)
    }

    @Test func chapterScopeOverBudgetCJKWindowIsValid() {
        let cjk = "中"  // 1 UTF-16 unit
        let text = String(repeating: cjk, count: 2000)
        let extractor = AIContextExtractor()
        let bounds = ChapterBounds(startUTF16: 0, endUTF16: 1500)

        let result = extractor.extractContext(
            locator: locator(at: 700), fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 300
        )
        #expect(result.utf16.count == 300)
        #expect(result.unicodeScalars.allSatisfy { $0 != "\u{FFFD}" })
    }

    @Test func chapterScopeOddBoundsOnSurrogateTextSnapToScalars() {
        // Chapter bounds that land mid-surrogate-pair (odd offsets on
        // emoji text). The slice must snap to scalar boundaries: start
        // snaps UP, end snaps DOWN — yielding a whole number of emoji,
        // no replacement char, length never exceeding the requested span.
        let emoji = "🍎"                          // 2 UTF-16 units
        let text = String(repeating: emoji, count: 200)  // 400 UTF-16 units
        let extractor = AIContextExtractor()
        // Odd bounds [101, 299) bisect pairs at both ends.
        let bounds = ChapterBounds(startUTF16: 101, endUTF16: 299)

        let result = extractor.extractContext(
            locator: locator(at: 200), fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 12_000
        )
        // start 101 snaps up to 102, end 299 snaps down to 298 → [102,298)
        // = 196 UTF-16 units = 98 whole emoji.
        #expect(result == String(repeating: emoji, count: 98))
        #expect(result.unicodeScalars.allSatisfy { $0 != "\u{FFFD}" })
        #expect(result.utf16.count <= 299 - 101)
    }

    // MARK: - Regression: locator with charRangeStartUTF16 but no charOffsetUTF16

    @Test func bookSoFarUsesRangeStartWhenNoCharOffset() {
        // A selection-anchored locator carries charRangeStartUTF16 but
        // no charOffsetUTF16. The scoped path must resolve the offset
        // via the same fallback the legacy .section path uses — so
        // bookSoFar takes [0, rangeStart), not the whole text.
        let text = String(repeating: "z", count: 5000)
        let extractor = AIContextExtractor()
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: 1200, charRangeEndUTF16: 1210,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let result = extractor.extractContext(
            locator: loc, fullText: text, format: .txt,
            scope: .bookSoFar, chapterBounds: nil, maxUTF16: 12_000
        )
        #expect(result.utf16.count == 1200)
    }

    @Test func chapterUsesRangeStartWhenNoCharOffsetForCenteredWindow() {
        // Same fallback for the over-budget chapter window: the centered
        // window must center on charRangeStartUTF16 when charOffsetUTF16
        // is nil.
        let text = String(repeating: "H", count: 1400)   // [0,1400)
            + String(repeating: "M", count: 200)         // [1400,1600) ← window
            + String(repeating: "R", count: 1400)        // [1600,3000)
        let extractor = AIContextExtractor()
        let bounds = ChapterBounds(startUTF16: 1000, endUTF16: 2000)
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: 1500, charRangeEndUTF16: 1510,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let result = extractor.extractContext(
            locator: loc, fullText: text, format: .txt,
            scope: .chapter, chapterBounds: bounds, maxUTF16: 200
        )
        #expect(result == String(repeating: "M", count: 200))
    }

    // MARK: - Protocol conformance + AIContextBudget

    @Test func extractorConformsToProtocol() {
        let extractor: any AIContextExtracting = AIContextExtractor()
        let result = extractor.extractContext(
            locator: locator(at: 0), fullText: "hello", format: .txt,
            scope: .section, chapterBounds: nil, maxUTF16: 100
        )
        #expect(!result.isEmpty)
    }

    @Test func protocolConvenienceOverloadSuppliesDefaultBudget() {
        // The 5-arg protocol-extension overload supplies
        // AIContextBudget.defaultMaxUTF16.
        let extractor: any AIContextExtracting = AIContextExtractor()
        let result = extractor.extractContext(
            locator: locator(at: 0), fullText: "hello world", format: .txt,
            scope: .section, chapterBounds: nil
        )
        #expect(!result.isEmpty)
    }

    @Test func defaultBudgetIsPositive() {
        #expect(AIContextBudget.defaultMaxUTF16 > 0)
    }

    // MARK: - Non-summarize formats still use .section via the legacy shim

    @Test func epubLegacyShimUnchanged() {
        // .section on EPUB delegates to the progression path — the
        // legacy 3-arg entry point must behave exactly as before #69.
        let text = String(repeating: "e", count: 200)
        let extractor = AIContextExtractor(targetCharacterCount: 40)
        let loc = Locator(
            bookFingerprint: DocumentFingerprint(
                contentSHA256: Self.fp.contentSHA256,
                fileByteCount: Self.fp.fileByteCount, format: .epub
            ),
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let legacy = extractor.extractContext(
            locator: loc, textContent: text, format: .epub
        )
        let scoped = extractor.extractContext(
            locator: loc, fullText: text, format: .epub,
            scope: .section, chapterBounds: nil, maxUTF16: 12_000
        )
        #expect(scoped == legacy)
    }
}
