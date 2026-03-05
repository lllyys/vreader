// Purpose: Tests for format-specific locator factory helpers.

import Testing
import Foundation
@testable import vreader

@Suite("LocatorFactory")
struct LocatorFactoryTests {

    // MARK: - Test Fixtures

    private static let epubFingerprint = DocumentFingerprint(
        contentSHA256: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
        fileByteCount: 102_400,
        format: .epub
    )

    private static let pdfFingerprint = DocumentFingerprint(
        contentSHA256: "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3",
        fileByteCount: 204_800,
        format: .pdf
    )

    private static let txtFingerprint = DocumentFingerprint(
        contentSHA256: "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
        fileByteCount: 512,
        format: .txt
    )

    // MARK: - EPUB Factory

    @Test func epubCreatesValidLocator() {
        let locator = LocatorFactory.epub(
            fingerprint: Self.epubFingerprint,
            href: "chapter1.xhtml",
            progression: 0.25,
            totalProgression: 0.1,
            cfi: "/6/4[chap01]!/4/2/1:0"
        )

        #expect(locator != nil)
        #expect(locator?.href == "chapter1.xhtml")
        #expect(locator?.progression == 0.25)
        #expect(locator?.totalProgression == 0.1)
        #expect(locator?.cfi == "/6/4[chap01]!/4/2/1:0")
        #expect(locator?.bookFingerprint == Self.epubFingerprint)
    }

    @Test func epubWithQuoteFields() {
        let locator = LocatorFactory.epub(
            fingerprint: Self.epubFingerprint,
            href: "chapter2.xhtml",
            progression: 0.5,
            textQuote: "Hello world",
            textContextBefore: "prefix ",
            textContextAfter: " suffix"
        )

        #expect(locator != nil)
        #expect(locator?.textQuote == "Hello world")
        #expect(locator?.textContextBefore == "prefix ")
        #expect(locator?.textContextAfter == " suffix")
    }

    @Test func epubReturnsNilForNonFiniteProgression() {
        let locator = LocatorFactory.epub(
            fingerprint: Self.epubFingerprint,
            href: "chapter1.xhtml",
            progression: .infinity
        )

        #expect(locator == nil)
    }

    @Test func epubReturnsNilForNaNProgression() {
        let locator = LocatorFactory.epub(
            fingerprint: Self.epubFingerprint,
            href: "chapter1.xhtml",
            progression: .nan
        )

        #expect(locator == nil)
    }

    // MARK: - PDF Factory

    @Test func pdfCreatesValidLocator() {
        let locator = LocatorFactory.pdf(
            fingerprint: Self.pdfFingerprint,
            page: 42,
            totalProgression: 0.35
        )

        #expect(locator != nil)
        #expect(locator?.page == 42)
        #expect(locator?.totalProgression == 0.35)
        #expect(locator?.bookFingerprint == Self.pdfFingerprint)
    }

    @Test func pdfWithQuoteFields() {
        let locator = LocatorFactory.pdf(
            fingerprint: Self.pdfFingerprint,
            page: 1,
            textQuote: "Some text on the page"
        )

        #expect(locator != nil)
        #expect(locator?.textQuote == "Some text on the page")
    }

    @Test func pdfReturnsNilForNegativePage() {
        let locator = LocatorFactory.pdf(
            fingerprint: Self.pdfFingerprint,
            page: -1
        )

        #expect(locator == nil)
    }

    @Test func pdfPageZeroIsValid() {
        let locator = LocatorFactory.pdf(
            fingerprint: Self.pdfFingerprint,
            page: 0
        )

        #expect(locator != nil)
        #expect(locator?.page == 0)
    }

    // MARK: - TXT Position Factory

    @Test func txtPositionWithoutSourceText() {
        let locator = LocatorFactory.txtPosition(
            fingerprint: Self.txtFingerprint,
            charOffsetUTF16: 100,
            totalProgression: 0.2
        )

        #expect(locator != nil)
        #expect(locator?.charOffsetUTF16 == 100)
        #expect(locator?.totalProgression == 0.2)
        #expect(locator?.textQuote == nil)
        #expect(locator?.textContextBefore == nil)
        #expect(locator?.textContextAfter == nil)
    }

    @Test func txtPositionWithSourceTextExtractsQuoteAndContext() {
        let source = "The quick brown fox jumps over the lazy dog near the riverbank on a sunny afternoon day"
        // UTF-16 offset 10 = start of "brown"
        let offset = 10
        let locator = LocatorFactory.txtPosition(
            fingerprint: Self.txtFingerprint,
            charOffsetUTF16: offset,
            sourceText: source
        )

        #expect(locator != nil)
        #expect(locator?.textQuote != nil)
        // Quote should start at offset 10
        #expect(locator?.textQuote?.hasPrefix("brown") == true)
        // Should have context before (chars before offset)
        #expect(locator?.textContextBefore != nil)
        #expect(locator?.textContextBefore == "The quick ")
    }

    @Test func txtPositionAtOffsetZero() {
        let source = "Hello world, this is a test string for context extraction."
        let locator = LocatorFactory.txtPosition(
            fingerprint: Self.txtFingerprint,
            charOffsetUTF16: 0,
            sourceText: source
        )

        #expect(locator != nil)
        #expect(locator?.textQuote != nil)
        // No before context when at start
        #expect(locator?.textContextBefore == nil || locator?.textContextBefore == "")
    }

    @Test func txtPositionAtEndOfText() {
        let source = "Short text"
        let offset = source.utf16.count
        let locator = LocatorFactory.txtPosition(
            fingerprint: Self.txtFingerprint,
            charOffsetUTF16: offset,
            sourceText: source
        )

        #expect(locator != nil)
        // At end, no quote or after context
        #expect(locator?.textQuote == nil || locator?.textQuote == "")
        #expect(locator?.textContextAfter == nil || locator?.textContextAfter == "")
    }

    @Test func txtPositionReturnsNilForNegativeOffset() {
        let locator = LocatorFactory.txtPosition(
            fingerprint: Self.txtFingerprint,
            charOffsetUTF16: -5
        )

        #expect(locator == nil)
    }

    // MARK: - TXT Range Factory

    @Test func txtRangeExtractsSelectedText() {
        let source = "The quick brown fox jumps over the lazy dog"
        // "brown fox" = offset 10 to 19
        let locator = LocatorFactory.txtRange(
            fingerprint: Self.txtFingerprint,
            charRangeStartUTF16: 10,
            charRangeEndUTF16: 19,
            sourceText: source
        )

        #expect(locator != nil)
        #expect(locator?.charRangeStartUTF16 == 10)
        #expect(locator?.charRangeEndUTF16 == 19)
        #expect(locator?.textQuote == "brown fox")
        #expect(locator?.textContextBefore == "The quick ")
        #expect(locator?.textContextAfter == " jumps over the lazy dog")
    }

    @Test func txtRangeWithoutSourceText() {
        let locator = LocatorFactory.txtRange(
            fingerprint: Self.txtFingerprint,
            charRangeStartUTF16: 10,
            charRangeEndUTF16: 20
        )

        #expect(locator != nil)
        #expect(locator?.charRangeStartUTF16 == 10)
        #expect(locator?.charRangeEndUTF16 == 20)
        #expect(locator?.textQuote == nil)
    }

    @Test func txtRangeWithCJKText() {
        // CJK characters are 1 UTF-16 code unit each
        let source = "前面的文字这里是选中的内容后面的文字"
        // "这里是选中的内容" starts at UTF-16 offset 5, length 8
        let locator = LocatorFactory.txtRange(
            fingerprint: Self.txtFingerprint,
            charRangeStartUTF16: 5,
            charRangeEndUTF16: 13,
            sourceText: source
        )

        #expect(locator != nil)
        #expect(locator?.textQuote == "这里是选中的内容")
        #expect(locator?.textContextBefore == "前面的文字")
        #expect(locator?.textContextAfter == "后面的文字")
    }

    @Test func txtRangeWithEmoji() {
        // 😀 is 2 UTF-16 code units (surrogate pair), regular chars are 1
        let source = "Hi😀there"
        // "😀" is at UTF-16 offset 2, occupies 2 code units
        let locator = LocatorFactory.txtRange(
            fingerprint: Self.txtFingerprint,
            charRangeStartUTF16: 2,
            charRangeEndUTF16: 4,
            sourceText: source
        )

        #expect(locator != nil)
        #expect(locator?.textQuote == "😀")
        #expect(locator?.textContextBefore == "Hi")
        #expect(locator?.textContextAfter == "there")
    }

    @Test func txtRangeWithMixedEmojiAndCJK() {
        // 🎉 = 2 UTF-16 code units, 中 = 1 UTF-16 code unit
        let source = "A🎉中B"
        // UTF-16: A(1) 🎉(2) 中(1) B(1) = total 5 code units
        // Select "中" at offset 3, end 4
        let locator = LocatorFactory.txtRange(
            fingerprint: Self.txtFingerprint,
            charRangeStartUTF16: 3,
            charRangeEndUTF16: 4,
            sourceText: source
        )

        #expect(locator != nil)
        #expect(locator?.textQuote == "中")
    }

    @Test func txtRangeReturnsNilForInvertedRange() {
        let locator = LocatorFactory.txtRange(
            fingerprint: Self.txtFingerprint,
            charRangeStartUTF16: 20,
            charRangeEndUTF16: 10
        )

        #expect(locator == nil)
    }

    // MARK: - extractContext

    @Test func extractContextAtMiddle() {
        let source = "abcdefghijklmnopqrstuvwxyz"
        let result = LocatorFactory.extractContext(
            from: source,
            at: 10,
            length: 5,
            windowSize: 3
        )

        #expect(result.quote == "klmno")
        #expect(result.contextBefore == "hij")
        #expect(result.contextAfter == "pqr")
    }

    @Test func extractContextEmptySourceText() {
        let result = LocatorFactory.extractContext(
            from: "",
            at: 0,
            length: 0
        )

        #expect(result.quote == nil || result.quote == "")
        #expect(result.contextBefore == nil || result.contextBefore == "")
        #expect(result.contextAfter == nil || result.contextAfter == "")
    }

    @Test func extractContextOffsetBeyondBounds() {
        let source = "short"
        let result = LocatorFactory.extractContext(
            from: source,
            at: 100,
            length: 5
        )

        // Should clamp — no crash, return nil/empty for out-of-bounds
        #expect(result.quote == nil || result.quote == "")
    }

    @Test func extractContextLengthExceedsBounds() {
        let source = "hello"
        let result = LocatorFactory.extractContext(
            from: source,
            at: 3,
            length: 100
        )

        // Should clamp length to available text
        #expect(result.quote == "lo")
        #expect(result.contextBefore != nil)
    }

    @Test func extractContextZeroLength() {
        let source = "hello world"
        let result = LocatorFactory.extractContext(
            from: source,
            at: 5,
            length: 0,
            windowSize: 3
        )

        // Zero-length selection: no quote, but context still present
        #expect(result.quote == nil || result.quote == "")
        #expect(result.contextBefore == "llo")
        #expect(result.contextAfter == " wo")
    }

    @Test func extractContextWindowClampedAtStart() {
        let source = "hello world"
        let result = LocatorFactory.extractContext(
            from: source,
            at: 2,
            length: 3,
            windowSize: 50
        )

        // Before context can only go back 2 chars
        #expect(result.quote == "llo")
        #expect(result.contextBefore == "he")
    }

    @Test func extractContextWindowClampedAtEnd() {
        let source = "hello world"
        let result = LocatorFactory.extractContext(
            from: source,
            at: 8,
            length: 3,
            windowSize: 50
        )

        // After context can only go forward 0 chars (8+3=11, string length=11)
        #expect(result.quote == "rld")
        #expect(result.contextAfter == nil || result.contextAfter == "")
    }

    // MARK: - Negative windowSize (Issue #13)

    @Test("extractContext: negative windowSize clamped to 0")
    func extractContextNegativeWindowSize() {
        let source = "Hello world"
        let result = LocatorFactory.extractContext(from: source, at: 5, length: 3, windowSize: -10)
        #expect(result.quote == " wo")
        // Negative window clamped to 0 — no context extraction
        #expect(result.contextBefore == nil)
        #expect(result.contextAfter == nil)
    }

    // MARK: - Surrogate pair boundary (Issue #13)

    @Test("TXT position: offset inside surrogate pair snaps to boundary")
    func txtPositionSurrogateBoundary() {
        let fp = Self.txtFingerprint
        // "A😀B" = A(1) + 😀(2 UTF-16) + B(1) = 4 UTF-16 code units
        // Offset 2 is inside the emoji surrogate pair
        let source = "A😀B"
        let locator = LocatorFactory.txtPosition(
            fingerprint: fp,
            charOffsetUTF16: 2,
            sourceText: source
        )
        // Should still produce a valid locator (quote snaps to scalar boundary)
        #expect(locator != nil)
    }
}
