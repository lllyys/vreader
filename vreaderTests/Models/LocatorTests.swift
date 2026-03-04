// Purpose: Tests for Locator — format-specific fields, TXT UTF-16 offsets, Codable round-trip.

import Testing
import Foundation
@testable import vreader

@Suite("Locator")
struct LocatorTests {

    static let epubFP = DocumentFingerprint(
        contentSHA256: "abc123", fileByteCount: 1024, format: .epub
    )
    static let pdfFP = DocumentFingerprint(
        contentSHA256: "def456", fileByteCount: 2048, format: .pdf
    )
    static let txtFP = DocumentFingerprint(
        contentSHA256: "ghi789", fileByteCount: 512, format: .txt
    )

    // MARK: - EPUB Locator

    @Test func epubLocatorUsesHrefAndProgression() {
        let loc = Locator(
            bookFingerprint: Self.epubFP,
            href: "chapter1.xhtml", progression: 0.42, totalProgression: 0.15,
            cfi: "/6/4!/4/2:0", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.href == "chapter1.xhtml")
        #expect(loc.progression == 0.42)
        #expect(loc.cfi == "/6/4!/4/2:0")
        #expect(loc.page == nil)
        #expect(loc.charOffsetUTF16 == nil)
    }

    // MARK: - PDF Locator

    @Test func pdfLocatorUsesPage() {
        let loc = Locator(
            bookFingerprint: Self.pdfFP,
            href: nil, progression: nil, totalProgression: 0.05,
            cfi: nil, page: 7,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "Introduction", textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.page == 7)
        #expect(loc.href == nil)
        #expect(loc.cfi == nil)
    }

    // MARK: - TXT Locator with UTF-16 Offsets

    @Test func txtLocatorUsesUTF16Offset() {
        let loc = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 1024,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.charOffsetUTF16 == 1024)
    }

    @Test func txtLocatorRangeFields() {
        let loc = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: 100, charRangeEndUTF16: 200,
            textQuote: "selected text", textContextBefore: "before ", textContextAfter: " after"
        )
        #expect(loc.charRangeStartUTF16 == 100)
        #expect(loc.charRangeEndUTF16 == 200)
    }

    // MARK: - TXT UTF-16 Boundary Edge Cases

    @Test func utf16OffsetAtZero() {
        let loc = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: 0,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.charOffsetUTF16 == 0)
    }

    @Test func utf16RangeStartEqualsEnd() {
        let loc = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: 500, charRangeEndUTF16: 500,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.charRangeStartUTF16 == loc.charRangeEndUTF16)
    }

    @Test func utf16LargeOffset() {
        let loc = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: 2_147_483_647,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.charOffsetUTF16 == 2_147_483_647)
    }

    @Test func utf16SurrogatePairAwareness() {
        let text = "Hello 😀 World"
        #expect(text.utf16.count == 14)  // 6 + 2 + 6

        let loc = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: 6,
            charRangeStartUTF16: 6, charRangeEndUTF16: 8,
            textQuote: "😀", textContextBefore: "Hello ", textContextAfter: " World"
        )
        #expect(loc.charRangeEndUTF16! - loc.charRangeStartUTF16! == 2)
    }

    @Test func utf16CJKCharacters() {
        let text = "你好世界"
        #expect(text.utf16.count == 4)

        let loc = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: 0,
            charRangeStartUTF16: 0, charRangeEndUTF16: 2,
            textQuote: "你好", textContextBefore: nil, textContextAfter: "世界"
        )
        #expect(loc.charRangeEndUTF16 == 2)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let original = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: 0.123456789, totalProgression: 0.5,
            cfi: "/6/4", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "Hello", textContextBefore: "Say ", textContextAfter: " World"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableRoundTripWithAllNilOptionals() throws {
        let original = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableRoundTripWithAllFields() throws {
        let original = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: 0.5, totalProgression: 0.25,
            cfi: "/6/4", page: 3, charOffsetUTF16: 100,
            charRangeStartUTF16: 100, charRangeEndUTF16: 200,
            textQuote: "quote", textContextBefore: "before", textContextAfter: "after"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Hashable

    @Test func equalLocatorsHaveSameHash() {
        let loc1 = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let loc2 = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc1 == loc2)
        #expect(loc1.hashValue == loc2.hashValue)
    }
}
