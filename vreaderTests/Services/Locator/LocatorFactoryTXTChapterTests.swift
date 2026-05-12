// Purpose: Tests for LocatorFactory.txtChapterRange — chapter-local → global locator creation.

import Testing
import Foundation
@testable import vreader

@Suite("LocatorFactory.txtChapterRange")
struct LocatorFactoryTXTChapterTests {

    private static let fingerprint = DocumentFingerprint(
        contentSHA256: "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
        fileByteCount: 512,
        format: .txt
    )

    // "abcdefghij" — 10 ASCII characters, 10 UTF-16 code units
    private static let chapterText = "abcdefghij"

    @Test func txtChapterRange_extractsQuoteFromChapterText() {
        // local [3,7) → "defg", globalStart=1000 → globals [1003, 1007)
        let locator = LocatorFactory.txtChapterRange(
            fingerprint: Self.fingerprint,
            chapterLocalStart: 3,
            chapterLocalEnd: 7,
            chapterText: Self.chapterText,
            chapterGlobalStart: 1000
        )
        #expect(locator != nil)
        #expect(locator?.charRangeStartUTF16 == 1003)
        #expect(locator?.charRangeEndUTF16 == 1007)
        #expect(locator?.textQuote == "defg")
    }

    @Test func txtChapterRange_handlesInvertedRange() {
        // inverted local [5,3) → nil
        let locator = LocatorFactory.txtChapterRange(
            fingerprint: Self.fingerprint,
            chapterLocalStart: 5,
            chapterLocalEnd: 3,
            chapterText: Self.chapterText,
            chapterGlobalStart: 1000
        )
        #expect(locator == nil)
    }

    @Test func txtChapterRange_zeroGlobalStartIsIdentity() {
        // globalStart=0 → offsets equal chapter-local offsets (same as txtRange)
        let locator = LocatorFactory.txtChapterRange(
            fingerprint: Self.fingerprint,
            chapterLocalStart: 2,
            chapterLocalEnd: 5,
            chapterText: Self.chapterText,
            chapterGlobalStart: 0
        )
        let txtLocator = LocatorFactory.txtRange(
            fingerprint: Self.fingerprint,
            charRangeStartUTF16: 2,
            charRangeEndUTF16: 5,
            sourceText: Self.chapterText
        )
        #expect(locator?.charRangeStartUTF16 == txtLocator?.charRangeStartUTF16)
        #expect(locator?.charRangeEndUTF16 == txtLocator?.charRangeEndUTF16)
        #expect(locator?.textQuote == txtLocator?.textQuote)
    }

    @Test func txtChapterRange_rejectsNegativeStart() {
        let locator = LocatorFactory.txtChapterRange(
            fingerprint: Self.fingerprint,
            chapterLocalStart: -1,
            chapterLocalEnd: 5,
            chapterText: Self.chapterText,
            chapterGlobalStart: 1000
        )
        #expect(locator == nil)
    }

    @Test func txtChapterRange_rejectsEndBeyondChapterText() {
        // chapterText has 10 UTF-16 units; end=11 exceeds it
        let locator = LocatorFactory.txtChapterRange(
            fingerprint: Self.fingerprint,
            chapterLocalStart: 0,
            chapterLocalEnd: 11,
            chapterText: Self.chapterText,
            chapterGlobalStart: 1000
        )
        #expect(locator == nil)
    }
}
