// Purpose: Tests for Locator validation — field bounds, NaN rejection, format validation.

import Testing
import Foundation
@testable import vreader

@Suite("Locator Validation")
struct LocatorValidationTests {

    static let fp = DocumentFingerprint(
        contentSHA256: "abc123def456789012345678901234567890123456789012345678901234abcd",
        fileByteCount: 1024,
        format: .epub
    )

    // MARK: - Page Validation

    @Test func negativePageIsInvalid() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: -1,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.validate() == .negativePageIndex)
    }

    @Test func zeroPageIsValid() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: 0,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.validate() == nil)
    }

    // MARK: - UTF-16 Offset Validation

    @Test func negativeUTF16OffsetIsInvalid() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: -1, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.validate() == .negativeUTF16Offset)
    }

    @Test func invertedRangeIsInvalid() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: 200, charRangeEndUTF16: 100,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.validate() == .invertedUTF16Range)
    }

    @Test func equalRangeIsValid() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: 100, charRangeEndUTF16: 100,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.validate() == nil)
    }

    // MARK: - Non-Finite Progression

    @Test func nanProgressionIsInvalid() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: Double.nan, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.validate() == .nonFiniteProgression)
    }

    @Test func infinityTotalProgressionIsInvalid() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: Double.infinity,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(loc.validate() == .nonFiniteProgression)
    }

    // MARK: - NaN/Infinity in Canonical Hash

    @Test func nanProgressionOmittedFromCanonicalJSON() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: Double.nan, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let json = loc.canonicalJSON()
        #expect(!json.contains("progression"))
    }

    @Test func infinityTotalProgressionOmittedFromCanonicalJSON() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: Double.infinity,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let json = loc.canonicalJSON()
        #expect(!json.contains("totalProgression"))
    }

    // MARK: - Validated Factory

    @Test func validatedReturnsNilForInvalidLocator() {
        let result = Locator.validated(
            bookFingerprint: Self.fp, page: -1
        )
        #expect(result == nil)
    }

    @Test func validatedReturnsLocatorForValidInput() {
        let result = Locator.validated(
            bookFingerprint: Self.fp,
            href: "ch1.xhtml", progression: 0.5
        )
        #expect(result != nil)
        #expect(result?.href == "ch1.xhtml")
    }

    // MARK: - Control Character Escaping

    @Test func controlCharactersAreEscapedInCanonicalJSON() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: "text\u{08}with\u{0C}controls",
            textContextBefore: nil, textContextAfter: nil
        )
        let json = loc.canonicalJSON()
        #expect(json.contains("\\u0008"))
        #expect(json.contains("\\u000c"))
    }

    // MARK: - Locale Independence

    @Test func canonicalHashIsDeterministicAcrossInvocations() {
        let loc = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: 0.333333, totalProgression: 0.666666,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        // Call multiple times to verify stability
        let hashes = (0..<10).map { _ in loc.canonicalHash }
        let allSame = hashes.allSatisfy { $0 == hashes[0] }
        #expect(allSame)
    }
}
