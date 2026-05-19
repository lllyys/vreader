// Purpose: Feature #68 WI-2 — applies the design's chapter-start
// typography (serif in-text heading restyle + accent drop-cap) to a TXT
// chapter's already-built NSAttributedString.
//
// Extracted from TXTAttributedStringBuilder so that file stays under the
// ~300-line budget (rule 50 §9). `TXTAttributedStringBuilder.
// buildChapterStart` is the public entry point and delegates here.
//
// CONTRACT: `decorate` only ever ADDS NSAttributedString attributes —
// the backing string is byte-identical to the input, so every
// offset-based subsystem (positions, highlights, search, TTS) is
// unaffected. No characters are inserted, removed, or case-transformed.
//
// Key decisions:
// - Static, pure functions — no UIKit view dependencies, @Sendable-safe.
// - The drop-cap is an oversized first-character run with a negative
//   baseline offset + `firstLineHeadIndent` (TextKit 1 has no float).
// - Synthetic / "前言" chapters (headingLineLength == 0) get the drop-cap
//   only — no heading restyle, no injected heading.
//
// @coordinates-with: TXTAttributedStringBuilder.swift,
//   ChapterStartTypography.swift

#if canImport(UIKit)
import UIKit

enum TXTChapterStartDecorator {

    /// Returns a copy of `base` with the design's chapter-start
    /// typography applied. `headingLineLength` is the UTF-16 length of
    /// the leading heading line that is ALREADY part of the string
    /// (regex-detected chapters); 0 means no heading line is present
    /// (synthetic / "前言" chapters → drop-cap only).
    static func decorate(
        base: NSAttributedString, text: String, config: TXTViewConfig,
        headingLineLength: Int
    ) -> NSAttributedString {
        guard base.length > 0 else { return base }
        let mutable = NSMutableAttributedString(attributedString: base)
        let nsText = text as NSString

        // A heading length that overruns the body is invalid input and
        // is treated as "no heading" (drop-cap only) — never as "the
        // whole body is a heading". A negative value is likewise 0.
        let headingLen = (headingLineLength > 0 && headingLineLength <= nsText.length)
            ? headingLineLength
            : 0

        applyHeadingRestyle(
            to: mutable, nsText: nsText, headingLength: headingLen, config: config
        )
        applyDropCap(
            to: mutable, nsText: nsText, headingEnd: headingLen, config: config
        )
        return NSAttributedString(attributedString: mutable)
    }

    // MARK: - Private — heading restyle

    /// Restyles the leading heading line (UTF-16 range `0..<headingLength`)
    /// with the design's centered tracked serif typography. No-op when
    /// `headingLength` is 0 (synthetic / "前言" chapters) or the heading
    /// line is entirely whitespace. Characters are never changed.
    private static func applyHeadingRestyle(
        to mutable: NSMutableAttributedString,
        nsText: NSString,
        headingLength: Int,
        config: TXTViewConfig
    ) {
        guard headingLength > 0, headingLength <= mutable.length else { return }
        let headingText = nsText.substring(to: headingLength)
        guard !headingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let baseHeadingFont = ReaderTypography.body(
            for: .sourceSerif4, size: ChapterStartTypography.headingFontSize
        )
        let headingFont = fontWithWeight(
            baseHeadingFont, weight: ChapterStartTypography.headingFontWeight
        )
        let scaled = UIFontMetrics.default.scaledFont(for: headingFont)

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = config.lineSpacing
        style.paragraphSpacing = ChapterStartTypography.headingSpacingAfter
        style.paragraphSpacingBefore = ChapterStartTypography.headingSpacingBefore

        let range = NSRange(location: 0, length: headingLength)
        mutable.addAttributes([
            .font: scaled,
            .foregroundColor: config.chapterHeadingColor,
            .kern: ChapterStartTypography.headingLetterSpacing,
            .paragraphStyle: style,
        ], range: range)
    }

    // MARK: - Private — drop-cap

    /// Applies the accent drop-cap to the first drop-cap-eligible scalar
    /// of the first body paragraph.
    ///
    /// `headingEnd` is the UTF-16 offset just past the leading heading
    /// line (0 for synthetic / "前言" chapters). The actual body
    /// paragraph begins after any blank lines that separate the heading
    /// from the body, so this first skips newlines to find the real body
    /// start. No-op when the body is empty, the first paragraph has no
    /// eligible scalar within a short scan window (R5), or the first
    /// scalar is CJK (R4). Only attributes are added.
    private static func applyDropCap(
        to mutable: NSMutableAttributedString,
        nsText: NSString,
        headingEnd: Int,
        config: TXTViewConfig
    ) {
        guard headingEnd < mutable.length else { return }
        // Skip the newline(s) between the heading line and the body — for
        // a synthetic chapter `headingEnd` is 0 and this is a no-op.
        var bodyStart = headingEnd
        while bodyStart < mutable.length {
            let unit = nsText.character(at: bodyStart)
            if unit == 0x0A || unit == 0x0D {
                bodyStart += 1
            } else {
                break
            }
        }
        guard bodyStart < mutable.length else { return }
        guard let cap = firstDropCapScalar(in: nsText, from: bodyStart)
        else { return }

        let dropCapSize = config.fontSize * ChapterStartTypography.dropCapScale
        let baseDropCapFont = ReaderTypography.body(
            for: .sourceSerif4, size: dropCapSize
        )
        let dropCapFont = fontWithWeight(
            baseDropCapFont, weight: ChapterStartTypography.dropCapFontWeight
        )
        // The oversized capital is dropped onto the body line with a
        // negative baseline offset so its cap-height sits roughly with
        // the line's x-height rather than floating above the line box.
        let baselineDrop = -(dropCapSize - config.fontSize)
            * (1.0 - ChapterStartTypography.dropCapLineHeight)

        // The drop-cap glyph is one Unicode scalar — UTF-16 length 1 for
        // a BMP letter/digit, 2 for a supplementary-plane letter (which
        // `isDropCapEligible` does accept). `firstDropCapScalar` reports
        // the correct span so the whole glyph is styled.
        let capRange = NSRange(location: cap.index, length: cap.utf16Length)
        mutable.addAttributes([
            .font: dropCapFont,
            .foregroundColor: config.accentColor,
            .baselineOffset: baselineDrop,
        ], range: capRange)

        // Indent the first body line so it clears the oversized capital.
        // The advance width is approximated from the drop-cap glyph's
        // bounding size — a true float is not available in TextKit 1.
        let capString = nsText.substring(with: capRange)
        let advance = (capString as NSString).size(
            withAttributes: [.font: dropCapFont]
        ).width
        applyFirstLineIndent(
            to: mutable, nsText: nsText, bodyStart: bodyStart,
            indent: advance, lineSpacing: config.lineSpacing
        )
    }

    /// Returns the first drop-cap-eligible scalar at or after `start` —
    /// its UTF-16 `index` and `utf16Length` (1 for a BMP scalar, 2 for a
    /// supplementary-plane one). Scans only the first body paragraph
    /// (stops at the first newline) and only a short window (handles a
    /// leading opening quote per R5 without enlarging deep into the
    /// paragraph). Returns `nil` when no eligible scalar is found.
    private static func firstDropCapScalar(
        in nsText: NSString, from start: Int
    ) -> (index: Int, utf16Length: Int)? {
        let scanWindow = 8
        var index = start
        var scanned = 0
        while index < nsText.length && scanned < scanWindow {
            let unit = nsText.character(at: index)
            // Stop at a paragraph break — the drop-cap is on the first
            // paragraph only.
            if unit == 0x0A || unit == 0x0D { return nil }

            if UTF16.isLeadSurrogate(unit) {
                // Reconstruct the supplementary-plane scalar from the
                // surrogate pair, then test eligibility against the
                // real scalar (a non-BMP Latin-extended letter is
                // eligible per `isDropCapEligible`).
                let nextIndex = index + 1
                if nextIndex < nsText.length {
                    let trail = nsText.character(at: nextIndex)
                    if UTF16.isTrailSurrogate(trail) {
                        let codePoint = 0x10000
                            + (UInt32(unit) - 0xD800) * 0x400
                            + (UInt32(trail) - 0xDC00)
                        if let scalar = Unicode.Scalar(codePoint),
                           ChapterStartTypography.isDropCapEligible(scalar) {
                            return (index, 2)
                        }
                    }
                }
                index += 2
                scanned += 1
                continue
            }

            if let scalar = Unicode.Scalar(unit),
               ChapterStartTypography.isDropCapEligible(scalar) {
                return (index, 1)
            }
            index += 1
            scanned += 1
        }
        return nil
    }

    /// Sets `firstLineHeadIndent` on the first body paragraph's
    /// paragraph style so the body's first line clears the drop-cap.
    /// Preserves every other paragraph attribute already on the run.
    private static func applyFirstLineIndent(
        to mutable: NSMutableAttributedString,
        nsText: NSString,
        bodyStart: Int,
        indent: CGFloat,
        lineSpacing: CGFloat
    ) {
        guard bodyStart < mutable.length else { return }
        // The first body paragraph runs from bodyStart to the next
        // newline (or end of string).
        let searchRange = NSRange(
            location: bodyStart, length: mutable.length - bodyStart
        )
        let newline = nsText.rangeOfCharacter(
            from: CharacterSet.newlines, range: searchRange
        )
        let paragraphEnd = newline.location == NSNotFound
            ? mutable.length
            : newline.location
        guard paragraphEnd > bodyStart else { return }
        let paragraphRange = NSRange(
            location: bodyStart, length: paragraphEnd - bodyStart
        )

        let existing = mutable.attribute(
            .paragraphStyle, at: bodyStart, effectiveRange: nil
        ) as? NSParagraphStyle
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        if existing == nil { style.lineSpacing = lineSpacing }
        style.firstLineHeadIndent = indent
        mutable.addAttribute(
            .paragraphStyle, value: style, range: paragraphRange
        )
    }

    /// Returns a copy of `font` with the requested weight applied via the
    /// font descriptor's trait dictionary. Falls back to the input font
    /// when the descriptor cannot carry the weight.
    private static func fontWithWeight(
        _ font: UIFont, weight: UIFont.Weight
    ) -> UIFont {
        let descriptor = font.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
#endif
