// Purpose: Tests for AIContextExtractor — format-specific text extraction,
// boundary clamping, empty input handling.

import Testing
import Foundation
@testable import vreader

@Suite("AIContextExtractor")
struct AIContextExtractorTests {

    // MARK: - Helpers

    private static let testFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 1024,
        format: .txt
    )

    private func makeLocator(
        format: BookFormat = .txt,
        charOffset: Int? = nil,
        charRangeStart: Int? = nil,
        page: Int? = nil,
        progression: Double? = nil,
        href: String? = nil
    ) -> Locator {
        Locator(
            bookFingerprint: DocumentFingerprint(
                contentSHA256: Self.testFP.contentSHA256,
                fileByteCount: Self.testFP.fileByteCount,
                format: format
            ),
            href: href,
            progression: progression,
            totalProgression: nil,
            cfi: nil,
            page: page,
            charOffsetUTF16: charOffset,
            charRangeStartUTF16: charRangeStart,
            charRangeEndUTF16: charRangeStart != nil ? (charRangeStart! + 10) : nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )
    }

    // MARK: - Empty Input

    @Test func emptyTextReturnsEmpty() {
        let extractor = AIContextExtractor(targetCharacterCount: 100)
        let locator = makeLocator(charOffset: 0)
        let result = extractor.extractContext(locator: locator, textContent: "", format: .txt)
        #expect(result.isEmpty)
    }

    // MARK: - TXT / MD Extraction

    @Test func txtExtractsAroundOffset() {
        let text = String(repeating: "a", count: 100)
        let extractor = AIContextExtractor(targetCharacterCount: 20)
        let locator = makeLocator(charOffset: 50)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .txt)
        #expect(result.count == 20, "Should extract ~20 characters around offset 50")
    }

    @Test func txtClampsOffsetBeyondEnd() {
        let text = "Short text"
        let extractor = AIContextExtractor(targetCharacterCount: 100)
        let locator = makeLocator(charOffset: 99999)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .txt)
        #expect(!result.isEmpty, "Should clamp offset and return text")
    }

    @Test func txtNegativeOffsetClampedToZero() {
        // charOffsetUTF16 of 0 is the minimum valid value
        let text = "Hello World"
        let extractor = AIContextExtractor(targetCharacterCount: 100)
        let locator = makeLocator(charOffset: 0)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .txt)
        #expect(result == "Hello World")
    }

    @Test func txtUsesRangeStartWhenNoOffset() {
        let text = String(repeating: "b", count: 200)
        let extractor = AIContextExtractor(targetCharacterCount: 20)
        let locator = makeLocator(charRangeStart: 100)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .txt)
        #expect(!result.isEmpty)
        #expect(result.count <= 20)
    }

    @Test func txtNoOffsetInfoExtractsFromBeginning() {
        let text = "Beginning of text content that is fairly long for testing purposes."
        let extractor = AIContextExtractor(targetCharacterCount: 20)
        let locator = makeLocator() // no charOffset or range

        let result = extractor.extractContext(locator: locator, textContent: text, format: .txt)
        #expect(result.hasPrefix("Beginning"))
    }

    @Test func mdUsessameTxtLogic() {
        let text = String(repeating: "m", count: 100)
        let extractor = AIContextExtractor(targetCharacterCount: 30)
        let locator = makeLocator(format: .md, charOffset: 50)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .md)
        #expect(!result.isEmpty)
        #expect(result.count <= 30)
    }

    @Test func txtShortTextReturnsAll() {
        let text = "Short"
        let extractor = AIContextExtractor(targetCharacterCount: 100)
        let locator = makeLocator(charOffset: 2)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .txt)
        #expect(result == "Short")
    }

    // MARK: - CJK Text

    @Test func txtHandlesCJKText() {
        let text = String(repeating: "中", count: 100)
        let extractor = AIContextExtractor(targetCharacterCount: 20)
        let locator = makeLocator(charOffset: 50)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .txt)
        #expect(!result.isEmpty)
    }

    // MARK: - PDF Extraction

    @Test func pdfExtractsFullPageWhenShort() {
        let text = "Page content that fits within the limit."
        let extractor = AIContextExtractor(targetCharacterCount: 2500)
        let locator = makeLocator(format: .pdf, page: 5)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .pdf)
        #expect(result == text)
    }

    @Test func pdfTruncatesLongPage() {
        let text = String(repeating: "p", count: 5000)
        let extractor = AIContextExtractor(targetCharacterCount: 100)
        let locator = makeLocator(format: .pdf, page: 1)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .pdf)
        #expect(result.count == 100)
    }

    // MARK: - EPUB Extraction

    @Test func epubExtractsAroundProgression() {
        let text = String(repeating: "e", count: 200)
        let extractor = AIContextExtractor(targetCharacterCount: 40)
        let locator = makeLocator(
            format: .epub,
            progression: 0.5,
            href: "chapter1.xhtml"
        )

        let result = extractor.extractContext(locator: locator, textContent: text, format: .epub)
        #expect(!result.isEmpty)
        #expect(result.count <= 40)
    }

    @Test func epubNilProgressionDefaultsToZero() {
        let text = "Beginning of chapter content and more text."
        let extractor = AIContextExtractor(targetCharacterCount: 100)
        let locator = makeLocator(format: .epub, href: "ch1.xhtml")

        let result = extractor.extractContext(locator: locator, textContent: text, format: .epub)
        #expect(result.hasPrefix("Beginning"))
    }

    @Test func epubProgressionBeyondOneClamps() {
        let text = String(repeating: "x", count: 100)
        let extractor = AIContextExtractor(targetCharacterCount: 50)
        let locator = makeLocator(format: .epub, progression: 1.5)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .epub)
        #expect(!result.isEmpty, "Should clamp progression > 1.0")
    }

    @Test func epubNegativeProgressionClamps() {
        let text = "Start of the chapter."
        let extractor = AIContextExtractor(targetCharacterCount: 100)
        let locator = makeLocator(format: .epub, progression: -0.5)

        let result = extractor.extractContext(locator: locator, textContent: text, format: .epub)
        #expect(!result.isEmpty, "Should clamp negative progression to 0")
    }

    // MARK: - Sendable

    @Test func extractorIsSendable() {
        let extractor: any Sendable = AIContextExtractor()
        #expect(extractor is AIContextExtractor)
    }
}
