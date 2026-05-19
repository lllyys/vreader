// Purpose: Tests for ChapterStartTypography — feature #68 design-pinned
// constants + the drop-cap eligibility predicate.
//
// @coordinates-with: ChapterStartTypography.swift

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("ChapterStartTypography")
struct ChapterStartTypographyTests {

    // MARK: - Design-pinned numeric constants

    @Test("dropCapScale equals the design 2.6x multiplier")
    func dropCapScaleIsPinned() {
        #expect(ChapterStartTypography.dropCapScale == 2.6)
    }

    @Test("dropCapLineHeight equals the design 0.85")
    func dropCapLineHeightIsPinned() {
        #expect(ChapterStartTypography.dropCapLineHeight == 0.85)
    }

    @Test("headingFontSize equals the design fixed 13pt")
    func headingFontSizeIsPinned() {
        #expect(ChapterStartTypography.headingFontSize == 13)
    }

    @Test("headingLetterSpacing equals the design 2pt tracking")
    func headingLetterSpacingIsPinned() {
        #expect(ChapterStartTypography.headingLetterSpacing == 2)
    }

    @Test("headingSpacingAfter equals the design 18pt marginBottom")
    func headingSpacingAfterIsPinned() {
        #expect(ChapterStartTypography.headingSpacingAfter == 18)
    }

    @Test("headingSpacingBefore equals the design 8pt marginTop")
    func headingSpacingBeforeIsPinned() {
        #expect(ChapterStartTypography.headingSpacingBefore == 8)
    }

    @Test("headingFontWeight equals .medium (design fontWeight 500)")
    func headingFontWeightIsPinned() {
        #expect(ChapterStartTypography.headingFontWeight == .medium)
    }

    @Test("dropCapFontWeight equals .semibold (design fontWeight 600)")
    func dropCapFontWeightIsPinned() {
        #expect(ChapterStartTypography.dropCapFontWeight == .semibold)
    }

    @Test("dropCapCSSFontSizeEm equals 2.6em")
    func dropCapCSSFontSizeEmIsPinned() {
        #expect(ChapterStartTypography.dropCapCSSFontSizeEm == "2.6em")
    }

    // MARK: - isDropCapEligible

    @Test("isDropCapEligible is true for an uppercase Latin letter")
    func eligibleUppercaseLetter() {
        #expect(ChapterStartTypography.isDropCapEligible(Unicode.Scalar("A")))
    }

    @Test("isDropCapEligible is true for a lowercase Latin letter")
    func eligibleLowercaseLetter() {
        #expect(ChapterStartTypography.isDropCapEligible(Unicode.Scalar("a")))
    }

    @Test("isDropCapEligible is true for an ASCII digit")
    func eligibleDigit() {
        #expect(ChapterStartTypography.isDropCapEligible(Unicode.Scalar("7")))
    }

    @Test("isDropCapEligible is false for a space")
    func ineligibleSpace() {
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(" ")))
    }

    @Test("isDropCapEligible is false for a newline")
    func ineligibleNewline() {
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar("\n")))
    }

    @Test("isDropCapEligible is false for a left double quotation mark")
    func ineligibleLeftDoubleQuote() {
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x201C)!))
    }

    @Test("isDropCapEligible is false for a left single quotation mark")
    func ineligibleLeftSingleQuote() {
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x2018)!))
    }

    @Test("isDropCapEligible is false for a combining grave accent")
    func ineligibleCombiningMark() {
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x0300)!))
    }

    @Test("isDropCapEligible is false for a CJK full stop")
    func ineligibleCJKFullStop() {
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x3002)!))
    }

    @Test("isDropCapEligible is false for a CJK ideograph (R4 — no CJK drop-cap)")
    func ineligibleCJKIdeograph() {
        // U+4E2D 中 — drop-cap is a Latin-typography device; the serif
        // Latin face has no CJK coverage, and a 2.6x ideograph reads wrong.
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x4E2D)!))
    }

    @Test("isDropCapEligible is false for an ASCII punctuation char")
    func ineligibleASCIIPunctuation() {
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(".")))
    }

    // MARK: - isDropCapEligible — non-Latin alphabetic scripts

    @Test("isDropCapEligible is true for a Greek capital letter (plan §4.1 — not Latin-only)")
    func eligibleGreekLetter() {
        // U+03A9 Ω — Greek is alphabetic and renders in the serif fallback;
        // plan Risk R4 excludes only CJK, not Greek/Cyrillic.
        #expect(ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x03A9)!))
    }

    @Test("isDropCapEligible is true for a Cyrillic capital letter (plan §4.1 — not Latin-only)")
    func eligibleCyrillicLetter() {
        // U+0416 Ж — Cyrillic is alphabetic and renders in the serif fallback.
        #expect(ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x0416)!))
    }

    @Test("isDropCapEligible is true for a Latin letter with a diacritic")
    func eligibleLatinDiacritic() {
        // U+00C9 É — a precomposed accented Latin letter.
        #expect(ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x00C9)!))
    }

    // MARK: - isDropCapEligible — CJK scripts (full Unicode range)

    @Test("isDropCapEligible is false for a Hiragana letter")
    func ineligibleHiragana() {
        // U+3042 あ
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x3042)!))
    }

    @Test("isDropCapEligible is false for a Katakana letter")
    func ineligibleKatakana() {
        // U+30AB カ
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x30AB)!))
    }

    @Test("isDropCapEligible is false for a Hangul syllable")
    func ineligibleHangulSyllable() {
        // U+AC00 가
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0xAC00)!))
    }

    @Test("isDropCapEligible is false for a Hangul Compatibility Jamo letter")
    func ineligibleHangulCompatJamo() {
        // U+3131 ㄱ — block boundary the original implementation missed.
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x3131)!))
    }

    @Test("isDropCapEligible is false for a Bopomofo letter")
    func ineligibleBopomofo() {
        // U+3105 ㄅ
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x3105)!))
    }

    @Test("isDropCapEligible is false for a halfwidth Katakana letter")
    func ineligibleHalfwidthKatakana() {
        // U+FF8A ﾊ — block boundary the original implementation missed.
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0xFF8A)!))
    }

    @Test("isDropCapEligible is false for a supplementary-plane Kana Supplement letter")
    func ineligibleKanaSupplement() {
        // U+1B001 — supplementary-plane kana; the exclusion must cover
        // the full Unicode range, not only the BMP base blocks.
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x1B001)!))
    }

    @Test("isDropCapEligible is false for a supplementary-plane CJK Extension B ideograph")
    func ineligibleSupplementaryIdeograph() {
        // U+20000 — CJK Unified Ideographs Extension B.
        #expect(!ChapterStartTypography.isDropCapEligible(Unicode.Scalar(0x20000)!))
    }
}
