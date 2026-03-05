// Purpose: End-to-end integration tests for locator generation → persistence → restoration.
// Validates the full cycle across EPUB, PDF, and TXT formats including edge cases.
//
// @coordinates-with LocatorFactory.swift, LocatorRestorer.swift, QuoteRecovery.swift

import Testing
import Foundation
@testable import vreader

@Suite("Locator Integration")
struct LocatorIntegrationTests {

    // MARK: - Shared Fingerprints

    private static let epubFP = DocumentFingerprint(
        contentSHA256: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
        fileByteCount: 524_288,
        format: .epub
    )

    private static let pdfFP = DocumentFingerprint(
        contentSHA256: "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3",
        fileByteCount: 1_048_576,
        format: .pdf
    )

    private static let txtFP = DocumentFingerprint(
        contentSHA256: "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
        fileByteCount: 8_192,
        format: .txt
    )

    // MARK: - JSON Round-trip Helper

    /// Encode → decode a locator through JSON, simulating persistence.
    private func roundTrip(_ locator: Locator) throws -> Locator {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(locator)
        return try JSONDecoder().decode(Locator.self, from: data)
    }

    // MARK: - EPUB Integration Tests

    @Test("EPUB: simple chapter navigation via hrefProgression")
    func epubSimpleChapterNavigation() throws {
        // 1. Create locator at chapter3.xhtml, progression 0.5
        let locator = try #require(LocatorFactory.epub(
            fingerprint: Self.epubFP,
            href: "chapter3.xhtml",
            progression: 0.5,
            totalProgression: 0.35
        ))

        // 2. Persist and restore
        let restored = try roundTrip(locator)

        // 3. Restore with matching spine
        let spine = ["chapter1.xhtml", "chapter2.xhtml", "chapter3.xhtml", "chapter4.xhtml"]
        let result = LocatorRestorer.restoreEPUB(
            locator: restored,
            spineHrefs: spine,
            textContent: nil
        )

        // 4. Expect hrefProgression strategy
        #expect(result.strategy == .hrefProgression)
        #expect(result.resolvedHref == "chapter3.xhtml")
        #expect(result.resolvedProgression == 0.5)
    }

    @Test("EPUB: CFI-based restoration takes priority")
    func epubCFIRestoration() throws {
        let cfi = "/6/4[chap03]!/4/2/1:42"

        // 1. Create locator with CFI
        let locator = try #require(LocatorFactory.epub(
            fingerprint: Self.epubFP,
            href: "chapter3.xhtml",
            progression: 0.5,
            totalProgression: 0.35,
            cfi: cfi
        ))

        // 2. Persist and restore
        let restored = try roundTrip(locator)

        // 3. Restore — CFI should take priority
        let spine = ["chapter1.xhtml", "chapter2.xhtml", "chapter3.xhtml"]
        let result = LocatorRestorer.restoreEPUB(
            locator: restored,
            spineHrefs: spine,
            textContent: nil
        )

        #expect(result.strategy == .cfi)
        // CFI is a pass-through — actual resolution is Readium's job.
        // The restorer confirms the CFI exists but doesn't resolve href/progression.
    }

    @Test("EPUB: changed spine falls back to quote recovery")
    func epubChangedSpineFallsBackToQuote() throws {
        let quoteText = "It was the best of times, it was the worst of times"
        let contextBefore = "opening paragraph. "
        let contextAfter = ", it was the age of wisdom"

        // 1. Create locator with href NOT in new spine, but with quote
        let locator = try #require(LocatorFactory.epub(
            fingerprint: Self.epubFP,
            href: "old-chapter3.xhtml",
            progression: 0.5,
            totalProgression: 0.35,
            textQuote: quoteText,
            textContextBefore: contextBefore,
            textContextAfter: contextAfter
        ))

        // 2. Persist and restore
        let restored = try roundTrip(locator)

        // 3. Restore with new spine that does NOT contain old-chapter3.xhtml
        let newSpine = ["intro.xhtml", "part1.xhtml", "part2.xhtml"]
        let fullText = "This is the opening paragraph. It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness."

        let result = LocatorRestorer.restoreEPUB(
            locator: restored,
            spineHrefs: newSpine,
            textContent: fullText
        )

        // Should fall back to quote recovery
        #expect(result.strategy == .quoteRecovery)
        #expect(result.confidence != nil)
        #expect(result.resolvedUTF16Offset != nil)
    }

    // MARK: - PDF Integration Tests

    @Test("PDF: page index restoration")
    func pdfPageRestore() throws {
        // 1. Create locator at page 42
        let locator = try #require(LocatorFactory.pdf(
            fingerprint: Self.pdfFP,
            page: 42,
            totalProgression: 0.42
        ))

        // 2. Persist and restore
        let restored = try roundTrip(locator)

        // 3. Restore with 100 total pages
        let result = LocatorRestorer.restorePDF(
            locator: restored,
            totalPages: 100,
            pageText: nil
        )

        #expect(result.strategy == .pageIndex)
        #expect(result.resolvedPage == 42)
    }

    @Test("PDF: out-of-range page falls back to quote recovery")
    func pdfOutOfRangeFallsBackToQuote() throws {
        let quoteText = "thermodynamic equilibrium"
        let contextBefore = "concept of "
        let contextAfter = " is fundamental"

        // 1. Create locator at page 150 with quote
        let locator = try #require(LocatorFactory.pdf(
            fingerprint: Self.pdfFP,
            page: 150,
            totalProgression: 0.95,
            textQuote: quoteText,
            textContextBefore: contextBefore,
            textContextAfter: contextAfter
        ))

        // 2. Persist and restore
        let restored = try roundTrip(locator)

        // 3. Restore — book now only has 100 pages
        let pageText = "The concept of thermodynamic equilibrium is fundamental to understanding heat transfer in closed systems."

        let result = LocatorRestorer.restorePDF(
            locator: restored,
            totalPages: 100,
            pageText: pageText
        )

        // Page 150 > totalPages 100, should fall back to quote
        #expect(result.strategy == .quoteRecovery)
        #expect(result.confidence != nil)
        #expect(result.resolvedUTF16Offset != nil)
    }

    // MARK: - TXT Integration Tests

    @Test("TXT: offset restoration with quote verification")
    func txtOffsetRestoreWithVerification() throws {
        let sourceText = "The quick brown fox jumps over the lazy dog near the riverbank on a sunny afternoon day."

        // 1. Create locator at offset 10 (start of "brown") with auto-extracted quote
        let offset = 10
        let locator = try #require(LocatorFactory.txtPosition(
            fingerprint: Self.txtFP,
            charOffsetUTF16: offset,
            totalProgression: Double(offset) / Double(sourceText.utf16.count),
            sourceText: sourceText
        ))

        // Verify factory extracted quote and context
        #expect(locator.textQuote != nil)

        // 2. Persist and restore
        let restored = try roundTrip(locator)

        // 3. Restore with same text
        let result = LocatorRestorer.restoreTXT(
            locator: restored,
            currentText: sourceText
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == offset)

        // 4. Verify the quote at restored offset matches
        if let resolvedOffset = result.resolvedUTF16Offset, let quote = restored.textQuote {
            let utf16 = sourceText.utf16
            let startIdx = utf16.index(utf16.startIndex, offsetBy: resolvedOffset)
            let endIdx = utf16.index(startIdx, offsetBy: min(quote.utf16.count, utf16.count - resolvedOffset))
            let textAtOffset = String(utf16[startIdx..<endIdx])
            #expect(textAtOffset == quote)
        }
    }

    @Test("TXT: offset beyond text length falls back to quote recovery")
    func txtOffsetAfterTextChangeFallsBack() throws {
        let originalText = "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau"

        // 1. Create locator pointing near end of text (offset 80)
        let offset = 80
        let locator = try #require(LocatorFactory.txtPosition(
            fingerprint: Self.txtFP,
            charOffsetUTF16: offset,
            totalProgression: Double(offset) / Double(originalText.utf16.count),
            sourceText: originalText
        ))

        #expect(locator.textQuote != nil)

        // 2. Persist and restore
        let restored = try roundTrip(locator)

        // 3. Truncated text — offset 80 is now beyond text length
        let truncatedText = "Alpha beta gamma delta epsilon zeta eta theta"

        // 4. Restore with truncated text — offset exceeds length, falls back
        let result = LocatorRestorer.restoreTXT(
            locator: restored,
            currentText: truncatedText
        )

        // Offset 80 > truncatedText.utf16.count, so falls back to quote recovery.
        // Quote from original text likely absent in truncated text → failed or quoteRecovery.
        #expect(result.strategy == .failed || result.strategy == .quoteRecovery)
    }

    @Test("TXT: quote recovery finds text after content shift")
    func txtQuoteRecoveryAfterContentShift() throws {
        let originalText = "Alpha beta gamma delta epsilon"

        // Create locator at "gamma" (offset 11) with auto-extracted quote
        let locator = try #require(LocatorFactory.txtPosition(
            fingerprint: Self.txtFP,
            charOffsetUTF16: 11,
            sourceText: originalText
        ))

        let extractedQuote = try #require(locator.textQuote)

        // Build a new locator with an invalid offset but same quote
        // Simulate: offset is now beyond text (e.g., text was restructured)
        let staleLocator = Locator(
            bookFingerprint: Self.txtFP,
            href: nil, progression: nil, totalProgression: nil,
            cfi: nil, page: nil,
            charOffsetUTF16: 9999,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: extractedQuote,
            textContextBefore: locator.textContextBefore,
            textContextAfter: locator.textContextAfter
        )

        // Restore with same text — offset 9999 exceeds, falls back to quote
        let result = LocatorRestorer.restoreTXT(
            locator: staleLocator,
            currentText: originalText
        )

        #expect(result.strategy == .quoteRecovery)
        #expect(result.resolvedUTF16Offset != nil)
        #expect(result.confidence != nil)
    }

    // MARK: - Edge Cases

    @Test("TXT: CJK round-trip preserves UTF-16 offsets")
    func txtCJKRoundTrip() throws {
        // Each CJK character = 1 UTF-16 code unit
        let sourceText = "这是一段中文文本用于测试定位器在中日韩文字环境下的正确性和稳定性"

        // Point at "测试" (offset 10)
        let offset = 10
        let locator = try #require(LocatorFactory.txtPosition(
            fingerprint: Self.txtFP,
            charOffsetUTF16: offset,
            sourceText: sourceText
        ))

        // Persist and restore
        let restored = try roundTrip(locator)

        // Restore
        let result = LocatorRestorer.restoreTXT(
            locator: restored,
            currentText: sourceText
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == offset)

        // Verify text at offset
        if let resolvedOffset = result.resolvedUTF16Offset {
            let utf16 = sourceText.utf16
            let idx = utf16.index(utf16.startIndex, offsetBy: resolvedOffset)
            let endIdx = utf16.index(idx, offsetBy: min(2, utf16.count - resolvedOffset))
            let text = String(utf16[idx..<endIdx])
            #expect(text == "测试")
        }
    }

    @Test("TXT: emoji round-trip handles surrogate pairs")
    func txtEmojiRoundTrip() throws {
        // 😀 = 2 UTF-16 code units (surrogate pair)
        // 🎉 = 2 UTF-16 code units
        let sourceText = "Hello 😀 world 🎉 end"
        // UTF-16 layout: H(1) e(1) l(1) l(1) o(1) (1) 😀(2) (1) w(1) o(1) r(1) l(1) d(1) (1) 🎉(2) (1) e(1) n(1) d(1)
        // Offset of "world": 6 (Hello ) + 2 (😀) + 1 ( ) = 9

        let offset = 9  // start of "world"
        let locator = try #require(LocatorFactory.txtPosition(
            fingerprint: Self.txtFP,
            charOffsetUTF16: offset,
            sourceText: sourceText
        ))

        // Persist and restore
        let restored = try roundTrip(locator)

        let result = LocatorRestorer.restoreTXT(
            locator: restored,
            currentText: sourceText
        )

        #expect(result.strategy == .utf16Offset)
        #expect(result.resolvedUTF16Offset == offset)

        // Verify the text at the offset starts with "world"
        if let resolvedOffset = result.resolvedUTF16Offset {
            let utf16 = sourceText.utf16
            let idx = utf16.index(utf16.startIndex, offsetBy: resolvedOffset)
            let endIdx = utf16.index(idx, offsetBy: min(5, utf16.count - resolvedOffset))
            let text = String(utf16[idx..<endIdx])
            #expect(text == "world")
        }
    }

    @Test("Locator Codable round-trip through JSON persistence")
    func locatorCodableRoundTrip() throws {
        // Create a fully-populated EPUB locator
        let locator = try #require(LocatorFactory.epub(
            fingerprint: Self.epubFP,
            href: "chapter5.xhtml",
            progression: 0.75,
            totalProgression: 0.60,
            cfi: "/6/10[chap05]!/4/2/1:100",
            textQuote: "To be or not to be",
            textContextBefore: "famous soliloquy: ",
            textContextAfter: ", that is the question"
        ))

        // 1. Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let jsonData = try encoder.encode(locator)
        let jsonString = try #require(String(data: jsonData, encoding: .utf8))

        // Verify JSON is valid and contains expected fields
        #expect(jsonString.contains("chapter5.xhtml"))
        #expect(jsonString.contains("To be or not to be"))
        #expect(jsonString.contains("chap05"))

        // 2. Decode back
        let decoded = try JSONDecoder().decode(Locator.self, from: jsonData)

        // 3. All fields must match
        #expect(decoded.bookFingerprint == locator.bookFingerprint)
        #expect(decoded.href == locator.href)
        #expect(decoded.progression == locator.progression)
        #expect(decoded.totalProgression == locator.totalProgression)
        #expect(decoded.cfi == locator.cfi)
        #expect(decoded.textQuote == locator.textQuote)
        #expect(decoded.textContextBefore == locator.textContextBefore)
        #expect(decoded.textContextAfter == locator.textContextAfter)

        // 4. Canonical hashes must be identical
        #expect(decoded.canonicalHash == locator.canonicalHash)

        // 5. Restore the decoded locator — should work identically
        let spine = ["chapter1.xhtml", "chapter3.xhtml", "chapter5.xhtml"]
        let result = LocatorRestorer.restoreEPUB(
            locator: decoded,
            spineHrefs: spine,
            textContent: nil
        )

        #expect(result.strategy == .cfi)
    }
}
