// Purpose: Tests for Locator canonical hash — determinism, line ending normalization,
// float rounding, canonical JSON structure, and edge cases with special characters.

import Testing
import Foundation
@testable import vreader

@Suite("Locator Canonical Hash")
struct LocatorCanonicalHashTests {

    static let epubFP = DocumentFingerprint(
        contentSHA256: "abc123", fileByteCount: 1024, format: .epub
    )
    static let txtFP = DocumentFingerprint(
        contentSHA256: "ghi789", fileByteCount: 512, format: .txt
    )

    // MARK: - Determinism

    @Test func canonicalHashIsDeterministic() {
        let loc = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let hash1 = loc.canonicalHash
        let hash2 = loc.canonicalHash
        #expect(hash1 == hash2)
        #expect(hash1.count == 64)  // SHA-256 hex = 64 chars
    }

    @Test func canonicalHashDiffersForDifferentLocators() {
        let loc1 = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let loc2 = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch2.xhtml", progression: 0.5, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc1.canonicalHash != loc2.canonicalHash)
    }

    // MARK: - Line Ending Normalization

    @Test func normalizesWindowsLineEndings() {
        let locCRLF = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "line1\r\nline2", textContextBefore: nil, textContextAfter: nil
        )
        let locLF = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "line1\nline2", textContextBefore: nil, textContextAfter: nil
        )
        #expect(locCRLF.canonicalHash == locLF.canonicalHash)
    }

    @Test func normalizesCRLineEndings() {
        let locCR = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "line1\rline2", textContextBefore: nil, textContextAfter: nil
        )
        let locLF = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "line1\nline2", textContextBefore: nil, textContextAfter: nil
        )
        #expect(locCR.canonicalHash == locLF.canonicalHash)
    }

    // MARK: - Float Rounding

    @Test func roundsFloatsTo6Decimals() {
        // Values that differ at the 6th decimal place after rounding.
        // 0.123456x rounds to 0.123456, 0.123457x rounds to 0.123457.
        let loc1 = Locator(
            bookFingerprint: Self.epubFP,
            href: nil, progression: 0.1234561, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let loc2 = Locator(
            bookFingerprint: Self.epubFP,
            href: nil, progression: 0.1234571, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        // Different at 6th decimal — different hashes
        #expect(loc1.canonicalHash != loc2.canonicalHash)
    }

    // MARK: - Canonical JSON Structure

    @Test func canonicalJSONOmitsNilFields() {
        let loc = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let json = loc.canonicalJSON()
        #expect(!json.contains("progression"))
        #expect(!json.contains("cfi"))
        #expect(!json.contains("page"))
        #expect(json.contains("href"))
    }

    @Test func canonicalJSONHasSortedKeys() {
        let loc = Locator(
            bookFingerprint: Self.epubFP,
            href: "ch1.xhtml", progression: 0.5, totalProgression: 0.25,
            cfi: "/6/4", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "test", textContextBefore: nil, textContextAfter: nil
        )
        let json = loc.canonicalJSON()

        if let bfRange = json.range(of: "bookFingerprint"),
           let cfiRange = json.range(of: "\"cfi\""),
           let hrefRange = json.range(of: "\"href\""),
           let progRange = json.range(of: "\"progression\"") {
            #expect(bfRange.lowerBound < cfiRange.lowerBound)
            #expect(cfiRange.lowerBound < hrefRange.lowerBound)
            #expect(hrefRange.lowerBound < progRange.lowerBound)
        } else {
            Issue.record("Expected keys not found in canonical JSON")
        }
    }

    // MARK: - Edge Cases

    @Test func specialCharactersInQuote() throws {
        let loc = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "He said \"hello\" & she said 'goodbye'",
            textContextBefore: "Tab\there",
            textContextAfter: "Backslash\\"
        )
        let data = try JSONEncoder().encode(loc)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded == loc)
        #expect(loc.canonicalHash.count == 64)
    }

    @Test func unicodeQuote() throws {
        let loc = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil, charOffsetUTF16: 0,
            charRangeStartUTF16: 0, charRangeEndUTF16: 4,
            textQuote: "你好世界", textContextBefore: nil, textContextAfter: nil
        )
        let data = try JSONEncoder().encode(loc)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded.textQuote == "你好世界")
    }

    @Test func emptyStrings() throws {
        let loc = Locator(
            bookFingerprint: Self.epubFP,
            href: "", progression: nil, totalProgression: nil,
            cfi: "", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "", textContextBefore: "", textContextAfter: ""
        )
        let data = try JSONEncoder().encode(loc)
        let decoded = try JSONDecoder().decode(Locator.self, from: data)
        #expect(decoded == loc)
    }
}
