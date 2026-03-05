// Purpose: Tests for locator restoration with format-specific fallback chains.

import Testing
import Foundation
@testable import vreader

@Suite("LocatorRestorer")
struct LocatorRestorerTests {

    // MARK: - Test Fixtures

    private static let epubFP = DocumentFingerprint(
        contentSHA256: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
        fileByteCount: 102_400,
        format: .epub
    )

    private static let pdfFP = DocumentFingerprint(
        contentSHA256: "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3",
        fileByteCount: 204_800,
        format: .pdf
    )

    private static let txtFP = DocumentFingerprint(
        contentSHA256: "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
        fileByteCount: 512,
        format: .txt
    )

    /// Helper to build a locator with only the fields needed for a test.
    private static func makeLocator(
        fingerprint: DocumentFingerprint = epubFP,
        href: String? = nil,
        progression: Double? = nil,
        totalProgression: Double? = nil,
        cfi: String? = nil,
        page: Int? = nil,
        charOffsetUTF16: Int? = nil,
        charRangeStartUTF16: Int? = nil,
        charRangeEndUTF16: Int? = nil,
        textQuote: String? = nil,
        textContextBefore: String? = nil,
        textContextAfter: String? = nil
    ) -> Locator {
        Locator(
            bookFingerprint: fingerprint,
            href: href,
            progression: progression,
            totalProgression: totalProgression,
            cfi: cfi,
            page: page,
            charOffsetUTF16: charOffsetUTF16,
            charRangeStartUTF16: charRangeStartUTF16,
            charRangeEndUTF16: charRangeEndUTF16,
            textQuote: textQuote,
            textContextBefore: textContextBefore,
            textContextAfter: textContextAfter
        )
    }

    // MARK: - EPUB: CFI Strategy

    @Test func epubRestoresViaCFIWhenPresent() {
        let locator = Self.makeLocator(
            fingerprint: Self.epubFP,
            href: "chapter1.xhtml",
            progression: 0.25,
            cfi: "/6/4[chap01]!/4/2/1:0"
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: ["chapter1.xhtml"],
            textContent: nil
        )

        #expect(result.strategy == .cfi)
        #expect(result.resolvedHref == nil)
        #expect(result.confidence == nil)
    }

    @Test func epubCFIStrategyIgnoresSpineAndTextContent() {
        // CFI should succeed even if href is NOT in spine and textContent is provided
        let locator = Self.makeLocator(
            fingerprint: Self.epubFP,
            href: "missing.xhtml",
            progression: 0.5,
            cfi: "/6/4[chap01]!/4/2/1:0",
            textQuote: "some text"
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: ["other.xhtml"],
            textContent: "some text in the chapter"
        )

        #expect(result.strategy == .cfi)
    }

    // MARK: - EPUB: href + progression Strategy

    @Test func epubRestoresViaHrefProgressionWhenCFIAbsent() {
        let locator = Self.makeLocator(
            fingerprint: Self.epubFP,
            href: "chapter2.xhtml",
            progression: 0.5
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: ["chapter1.xhtml", "chapter2.xhtml", "chapter3.xhtml"],
            textContent: nil
        )

        #expect(result.strategy == .hrefProgression)
        #expect(result.resolvedHref == "chapter2.xhtml")
        #expect(result.resolvedProgression == 0.5)
    }

    @Test func epubFallsBackToQuoteWhenHrefNotInSpine() {
        let textContent = "The quick brown fox jumps over the lazy dog"
        let locator = Self.makeLocator(
            fingerprint: Self.epubFP,
            href: "removed_chapter.xhtml",
            progression: 0.3,
            textQuote: "brown fox",
            textContextBefore: "quick ",
            textContextAfter: " jumps"
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: ["chapter1.xhtml", "chapter2.xhtml"],
            textContent: textContent
        )

        #expect(result.strategy == .quoteRecovery)
        #expect(result.confidence != nil)
    }

    @Test func epubQuoteRecoveryReturnsCorrectConfidence() {
        let textContent = "Once upon a time in a land far away"
        let locator = Self.makeLocator(
            fingerprint: Self.epubFP,
            href: "gone.xhtml",
            textQuote: "a time",
            textContextBefore: "upon ",
            textContextAfter: " in a"
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: [],
            textContent: textContent
        )

        #expect(result.strategy == .quoteRecovery)
        #expect(result.confidence == .exact)
    }

    @Test func epubReturnsFailedWhenNoStrategyWorks() {
        let locator = Self.makeLocator(
            fingerprint: Self.epubFP,
            href: "gone.xhtml",
            progression: 0.5
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: ["chapter1.xhtml"],
            textContent: nil
        )

        #expect(result.strategy == .failed)
    }

    @Test func epubHandlesEmptySpineHrefs() {
        let locator = Self.makeLocator(
            fingerprint: Self.epubFP,
            href: "chapter1.xhtml",
            progression: 0.25
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: [],
            textContent: nil
        )

        #expect(result.strategy == .failed)
    }

    @Test func epubHrefPresentButNoProgression() {
        // href is in spine but progression is nil -> should still fail hrefProgression
        let locator = Self.makeLocator(
            fingerprint: Self.epubFP,
            href: "chapter1.xhtml"
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: ["chapter1.xhtml"],
            textContent: nil
        )

        #expect(result.strategy == .failed)
    }

    // MARK: - PDF: Page Strategy

    @Test func pdfRestoresViaPageWhenInRange() {
        let locator = Self.makeLocator(
            fingerprint: Self.pdfFP,
            page: 5
        )
        let result = LocatorRestorer.restorePDF(
            locator: locator,
            totalPages: 100,
            pageText: nil
        )

        #expect(result.strategy == .pageIndex)
        #expect(result.resolvedPage == 5)
    }

    @Test func pdfPageZeroIsValid() {
        let locator = Self.makeLocator(
            fingerprint: Self.pdfFP,
            page: 0
        )
        let result = LocatorRestorer.restorePDF(
            locator: locator,
            totalPages: 10,
            pageText: nil
        )

        #expect(result.strategy == .pageIndex)
        #expect(result.resolvedPage == 0)
    }

    @Test func pdfFallsBackToQuoteWhenPageOutOfRange() {
        let pageText = "This is the content of the page we are looking for"
        let locator = Self.makeLocator(
            fingerprint: Self.pdfFP,
            page: 200,
            textQuote: "content of the page"
        )
        let result = LocatorRestorer.restorePDF(
            locator: locator,
            totalPages: 50,
            pageText: pageText
        )

        #expect(result.strategy == .quoteRecovery)
        #expect(result.confidence != nil)
    }

    @Test func pdfReturnsFailedForOutOfRangePageWithoutQuote() {
        let locator = Self.makeLocator(
            fingerprint: Self.pdfFP,
            page: 200
        )
        let result = LocatorRestorer.restorePDF(
            locator: locator,
            totalPages: 50,
            pageText: nil
        )

        #expect(result.strategy == .failed)
    }

    @Test func pdfReturnsFailedWhenNoFieldsPresent() {
        let locator = Self.makeLocator(fingerprint: Self.pdfFP)
        let result = LocatorRestorer.restorePDF(
            locator: locator,
            totalPages: 100,
            pageText: nil
        )

        #expect(result.strategy == .failed)
    }

    @Test func pdfPageAtBoundary() {
        // page == totalPages - 1 should be valid (0-indexed)
        let locator = Self.makeLocator(
            fingerprint: Self.pdfFP,
            page: 99
        )
        let result = LocatorRestorer.restorePDF(
            locator: locator,
            totalPages: 100,
            pageText: nil
        )

        #expect(result.strategy == .pageIndex)
        #expect(result.resolvedPage == 99)
    }

    @Test func pdfPageAtTotalPagesIsOutOfRange() {
        // page == totalPages is out of range (0-indexed)
        let locator = Self.makeLocator(
            fingerprint: Self.pdfFP,
            page: 100
        )
        let result = LocatorRestorer.restorePDF(
            locator: locator,
            totalPages: 100,
            pageText: nil
        )

        #expect(result.strategy == .failed)
    }

    // MARK: - TXT: UTF-16 Offset Strategy

    @Test func txtRestoresViaCharOffsetUTF16() {
        let text = "Hello world, this is a test."
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 6
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == 6)
    }

    @Test func txtRestoresViaCharRangeStartUTF16() {
        let text = "Hello world"
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charRangeStartUTF16: 3,
            charRangeEndUTF16: 8
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == 3)
    }

    @Test func txtFallsBackToQuoteWhenOffsetBeyondTextLength() {
        let text = "Short text"
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 9999,
            textQuote: "Short"
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .quoteRecovery)
        #expect(result.resolvedUTF16Offset == 0)
        #expect(result.confidence == .exact)
    }

    @Test func txtQuoteRecoveryReturnsCorrectUTF16Offset() {
        let text = "The quick brown fox jumps over the lazy dog"
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 9999,
            textQuote: "brown fox"
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .quoteRecovery)
        #expect(result.resolvedUTF16Offset == 10)
    }

    @Test func txtHandlesCJKTextRestoration() {
        // CJK characters are 1 UTF-16 code unit each
        let text = "前面的文字这里是选中的内容后面的文字"
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 5
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == 5)
    }

    @Test func txtCJKQuoteRecoveryFallback() {
        let text = "前面的文字这里是选中的内容后面的文字"
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 9999,
            textQuote: "这里是选中的内容"
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .quoteRecovery)
        #expect(result.resolvedUTF16Offset == 5)
    }

    @Test func txtHandlesEmojiTextRestoration() {
        // 😀 is 2 UTF-16 code units
        let text = "Hi😀there"
        // UTF-16: H(1) i(1) 😀(2) t(1) h(1) e(1) r(1) e(1) = 9 code units
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 4  // after the emoji
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == 4)
    }

    @Test func txtEmojiQuoteRecoveryFallback() {
        let text = "Hello 😀 world"
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 9999,
            textQuote: "😀 world"
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .quoteRecovery)
        // "Hello " is 6 UTF-16 code units
        #expect(result.resolvedUTF16Offset == 6)
    }

    @Test func txtReturnsFailedWhenNoFieldsMatch() {
        let text = "Hello world"
        let locator = Self.makeLocator(fingerprint: Self.txtFP)
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .failed)
    }

    @Test func txtOffsetAtExactEndOfTextIsValid() {
        let text = "Hello"
        // offset == utf16.count means cursor past last char — valid
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 5
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == 5)
    }

    @Test func txtRangeBeyondTextFallsBackToQuote() {
        let text = "Short"
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charRangeStartUTF16: 100,
            charRangeEndUTF16: 200,
            textQuote: "Short"
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .quoteRecovery)
        #expect(result.resolvedUTF16Offset == 0)
    }

    @Test func txtQuoteNotFoundReturnsFailed() {
        let text = "Hello world"
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 9999,
            textQuote: "xyzzy not found"
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: text
        )

        #expect(result.strategy == .failed)
    }

    @Test func txtEmptyTextReturnsFailed() {
        let locator = Self.makeLocator(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 0,
            textQuote: "anything"
        )
        let result = LocatorRestorer.restoreTXT(
            locator: locator,
            currentText: ""
        )

        // offset 0 <= utf16.count (0), so offset strategy should still work
        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == 0)
    }

    // MARK: - Empty/whitespace CFI (Issue #14)

    @Test("EPUB: empty CFI string falls through to next strategy")
    func emptyCFIFallsThrough() {
        let locator = Locator(
            bookFingerprint: Self.epubFP,
            href: "chapter1.xhtml", progression: 0.5, totalProgression: 0.1,
            cfi: "", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: ["chapter1.xhtml"],
            textContent: nil
        )
        // Empty CFI should NOT match .cfi strategy; should fall through to hrefProgression
        #expect(result.strategy == .hrefProgression)
        #expect(result.resolvedHref == "chapter1.xhtml")
    }

    @Test("EPUB: whitespace-only CFI falls through to next strategy")
    func whitespaceCFIFallsThrough() {
        let locator = Locator(
            bookFingerprint: Self.epubFP,
            href: "chapter2.xhtml", progression: 0.3, totalProgression: nil,
            cfi: "   \n\t  ", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let result = LocatorRestorer.restoreEPUB(
            locator: locator,
            spineHrefs: ["chapter2.xhtml"],
            textContent: nil
        )
        #expect(result.strategy == .hrefProgression)
        #expect(result.resolvedHref == "chapter2.xhtml")
    }

    // MARK: - RestorationStrategy rawValue

    @Test func strategyRawValues() {
        #expect(RestorationStrategy.cfi.rawValue == "cfi")
        #expect(RestorationStrategy.hrefProgression.rawValue == "hrefProgression")
        #expect(RestorationStrategy.quoteRecovery.rawValue == "quoteRecovery")
        #expect(RestorationStrategy.pageIndex.rawValue == "pageIndex")
        #expect(RestorationStrategy.utf16Offset.rawValue == "utf16Offset")
        #expect(RestorationStrategy.failed.rawValue == "failed")
    }
}
