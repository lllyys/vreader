// Purpose: Feature #68 — design-pinned constants for the reader
// chapter-start typography (serif in-text chapter heading + accent
// drop-cap). A single stateless namespace so all four reader
// renderers (TXT, MD, EPUB, AZW3/MOBI) agree on the numbers and the
// values are unit-testable in one place.
//
// Every numeric value is read directly from the committed design
// bundle `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-reader.jsx` — the cited line numbers are authoritative.
//
// Key decisions:
// - **No service singleton**. Stateless `enum` namespace (static
//   members only) — threadsafe by construction, no allocation, no
//   `@MainActor`.
// - **No case-transform helper**. The design's `textTransform:
//   'uppercase'` is honoured only on the CSS side (EPUB/AZW3 — a real
//   CSS property), never on the native TXT/MD attributed-string path
//   (`NSAttributedString` has no `text-transform`; `String.uppercased()`
//   changes characters and can change UTF-16 length, breaking the
//   offset invariant). v1 keeps native-heading source casing — see
//   the feature plan §3.2 / §8.
// - **CJK ideographs are NOT drop-cap-eligible**. The drop-cap is a
//   Latin-typography device; the serif Latin face has no CJK coverage
//   and a 2.6x ideograph reads wrong (plan Risk R4).
//
// @coordinates-with: TXTAttributedStringBuilder.swift (TXT drop-cap +
//   heading restyle), MDChapterStartDecorator.swift (MD), ReaderThemeV2+
//   EPUBCSS.swift (EPUB CSS), FoliateStyleMapper.swift (AZW3/MOBI CSS).

import Foundation
#if canImport(UIKit)
import UIKit

enum ChapterStartTypography {

    // MARK: - Drop-cap

    /// Drop-cap size multiplier over body font size. Design:
    /// `vreader-reader.jsx:386` (`fontSize: fontSize * 2.6`).
    static let dropCapScale: CGFloat = 2.6

    /// Drop-cap line-height multiplier. Design: `:386` (`lineHeight: 0.85`).
    static let dropCapLineHeight: CGFloat = 0.85

    /// Drop-cap weight. Design: `:388` (`fontWeight: 600`).
    static let dropCapFontWeight: UIFont.Weight = .semibold

    /// CSS `font-size` for the EPUB/Foliate drop-cap `::first-letter`
    /// rule (the CSS path expresses the 2.6x multiplier as an `em`).
    static let dropCapCSSFontSizeEm: String = "2.6em"

    // MARK: - In-text chapter heading

    /// In-text chapter heading fixed point size. Design: `:337`
    /// (`fontSize: 13` — a fixed px, not scaled with body size).
    static let headingFontSize: CGFloat = 13

    /// Heading tracking (letter-spacing) in points. Design: `:337`
    /// (`letterSpacing: 2`).
    static let headingLetterSpacing: CGFloat = 2

    /// Heading space-below in points. Design: `:339` (`marginBottom: 18`).
    static let headingSpacingAfter: CGFloat = 18

    /// Heading space-above in points. Design: `:339` (`marginTop: 8`).
    static let headingSpacingBefore: CGFloat = 8

    /// Heading weight. Design: `:339` (`fontWeight: 500`).
    static let headingFontWeight: UIFont.Weight = .medium

    // MARK: - Drop-cap eligibility

    /// Whether `scalar` is eligible to be a drop-cap initial.
    ///
    /// A drop-cap initial must be an alphabetic letter (Latin, Cyrillic,
    /// Greek and other casing alphabets the serif face can render) or an
    /// ASCII digit. Ineligible:
    /// - whitespace / newlines (nothing to enlarge),
    /// - quotation marks and punctuation (the design enlarges the first
    ///   *letter*, not an opening quote — see plan Risk R5),
    /// - combining marks (a combining mark has no standalone glyph),
    /// - CJK ideographs, kana, and Hangul (Risk R4 — the drop-cap is a
    ///   Latin-typography device; the serif Latin face has no CJK
    ///   coverage and a 2.6x ideograph/syllable reads wrong).
    ///
    /// **Scope note (plan §4.1 / Risk R4):** the plan pins exactly one
    /// script-class exclusion — CJK. It does not restrict the predicate
    /// to Latin-only; Cyrillic / Greek language books should still get a
    /// drop-cap, and Georgia (the bundled-font fallback) renders those
    /// scripts. So the predicate accepts any alphabetic scalar and then
    /// subtracts the CJK ranges below; it does not subtract Cyrillic /
    /// Greek / etc.
    static func isDropCapEligible(_ scalar: Unicode.Scalar) -> Bool {
        // ASCII digit fast-path.
        if scalar.value >= 0x30 && scalar.value <= 0x39 { return true }

        let properties = scalar.properties

        // Combining marks have no standalone glyph to enlarge.
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return false
        default:
            break
        }

        // Must be an alphabetic character (excludes whitespace,
        // punctuation, quotes, symbols, separators).
        guard properties.isAlphabetic else { return false }

        // Exclude every CJK range where a 2.6x serif Latin initial is
        // wrong. `isIdeographic` covers the unified CJK ideograph
        // blocks; `isCJKKanaOrHangul` covers the non-ideographic CJK
        // scripts (kana, Hangul, bopomofo) the Latin drop-cap face
        // cannot render. Both checks together close the full Unicode
        // range, not just the BMP base blocks.
        if properties.isIdeographic { return false }
        if isCJKKanaOrHangul(scalar) { return false }

        return true
    }

    // MARK: - Private

    /// True for Hangul (syllables + every jamo block), the kana scripts
    /// (Hiragana, Katakana + their phonetic-extension / supplement /
    /// halfwidth blocks), and Bopomofo — CJK scripts that are alphabetic
    /// and non-ideographic but still must not receive a Latin-face
    /// drop-cap. Covers the full Unicode range, not only the BMP base
    /// blocks, so a supplementary-plane kana scalar is excluded too.
    private static func isCJKKanaOrHangul(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF,     // Hangul Jamo
             0x3040...0x309F,     // Hiragana
             0x30A0...0x30FF,     // Katakana
             0x3100...0x312F,     // Bopomofo
             0x3130...0x318F,     // Hangul Compatibility Jamo
             0x31A0...0x31BF,     // Bopomofo Extended
             0x31F0...0x31FF,     // Katakana Phonetic Extensions
             0xA960...0xA97F,     // Hangul Jamo Extended-A
             0xAC00...0xD7AF,     // Hangul Syllables
             0xD7B0...0xD7FF,     // Hangul Jamo Extended-B
             0xFF66...0xFFDC,     // Halfwidth Katakana + halfwidth Hangul jamo
             0x1AFF0...0x1AFFF,   // Kana Extended-B
             0x1B000...0x1B0FF,   // Kana Supplement
             0x1B100...0x1B12F,   // Kana Extended-A
             0x1B130...0x1B16F:   // Small Kana Extension
            return true
        default:
            return false
        }
    }
}
#endif
