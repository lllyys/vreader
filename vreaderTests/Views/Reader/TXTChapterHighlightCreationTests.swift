// Purpose: Tests for Feature #48 WI-3 — chapter-local → global locator translation in
// TXTReaderContainerView's locatorFactory closure.
//
// Verifies that in chapter mode, the locatorFactory translates chapter-local selection
// offsets to global UTF-16 offsets via LocatorFactory.txtChapterRange.

import Testing
import Foundation
@testable import vreader

@Suite("TXTReaderContainerView - WI-3 creation translation")
@MainActor
struct TXTChapterHighlightCreationTests {

    private static let fingerprint = DocumentFingerprint(
        contentSHA256: "d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5",
        fileByteCount: 2048,
        format: .txt
    )

    // Chapter text: "hello world selected word goodbye" — 34 UTF-16 code units
    // "selected w" starts at local offset 12 (after "hello world "), length 10
    // Positions 12-21 (0-based, 10 chars): s,e,l,e,c,t,e,d,' ',w = "selected w"
    private static let chapterText = "hello world selected word goodbye"
    private static let localStart = 12
    private static let localEnd = 22  // exclusive, covers 10 chars "selected w"

    @Test func chapterModeLocatorIsGlobal_highlightPath() {
        // Chapter 1: globalStart=1000, text = chapterText
        // local [12,22) → globals [1012, 1022), quote = "selected wo"
        let locator = TXTReaderContainerView.makeLocatorForTXT(
            fingerprint: Self.fingerprint,
            localStart: Self.localStart,
            localEnd: Self.localEnd,
            chapterText: Self.chapterText,
            chapterGlobalStart: 1000,
            isChapterMode: true
        )
        #expect(locator != nil)
        #expect(locator?.charRangeStartUTF16 == 1012)
        #expect(locator?.charRangeEndUTF16 == 1022)
        #expect(locator?.textQuote == "selected w")
    }

    @Test func continuousModeLocatorIsPassthrough() {
        // In continuous mode (no chapter), offsets are global directly.
        // makeLocatorForTXT with isChapterMode=false + no chapter args
        // should produce same result as LocatorFactory.txtRange.
        let locator = TXTReaderContainerView.makeLocatorForTXT(
            fingerprint: Self.fingerprint,
            localStart: 12,
            localEnd: 22,
            chapterText: nil,
            chapterGlobalStart: 0,
            isChapterMode: false
        )
        let expected = LocatorFactory.txtRange(
            fingerprint: Self.fingerprint,
            charRangeStartUTF16: 12,
            charRangeEndUTF16: 22
        )
        #expect(locator?.charRangeStartUTF16 == expected?.charRangeStartUTF16)
        #expect(locator?.charRangeEndUTF16 == expected?.charRangeEndUTF16)
    }

    @Test func chapterModeLocatorIsGlobal_addNotePath() {
        // Verifies the same seam covers the Add Note path — the locatorFactory closure
        // is shared between highlight-requested and add-note-save paths.
        // Chapter 0: globalStart=0 → offsets are identity (no translation).
        let locator = TXTReaderContainerView.makeLocatorForTXT(
            fingerprint: Self.fingerprint,
            localStart: 5,
            localEnd: 10,
            chapterText: Self.chapterText,
            chapterGlobalStart: 0,
            isChapterMode: true
        )
        #expect(locator?.charRangeStartUTF16 == 5)
        #expect(locator?.charRangeEndUTF16 == 10)
    }
}
