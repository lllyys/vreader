// Purpose: Feature #68 WI-3 — applies the design's chapter-start
// typography (leading-heading restyle + accent drop-cap) to the
// NSAttributedString produced by `MDAttributedStringRenderer.render`.
//
// A new file because `MDAttributedStringRenderer.swift` is already 457
// lines, well over the ~300-line budget (rule 50 §9), and the decorator
// must stay independently testable.
//
// CONTRACT: `decorate` only ever ADDS NSAttributedString attributes —
// `decorate(...).string == attributed.string` and the UTF-16 length is
// unchanged, so every offset-based subsystem (search, highlights,
// position) is unaffected. No characters are inserted, removed, or
// case-transformed.
//
// MD scope (feature #68 v2): only the document's LEADING heading is
// restyled — `headings.first`, and only when its `charOffsetUTF16 == 0`.
// Post-thematic-break heading styling is out of scope (`MDHeading` does
// not encode break adjacency). The drop-cap goes on the first PLAIN body
// paragraph — list / code-block / blockquote first blocks are skipped.
// Locating that paragraph + its eligible initial is delegated to
// `MDChapterStartScanner`.
//
// @coordinates-with: MDChapterStartScanner.swift,
//   MDAttributedStringRenderer.swift, MDTypes.swift,
//   ChapterStartTypography.swift, MDReaderViewModel.swift

#if canImport(UIKit)
import UIKit

enum MDChapterStartDecorator {

    /// Returns a copy of `attributed` with chapter-start typography
    /// applied: the leading heading restyled (only when it is the
    /// document's first block, `charOffsetUTF16 == 0`) and a drop-cap on
    /// the first plain body paragraph. No-op when the document is empty
    /// or has no plain body paragraph. `config` carries the colors.
    static func decorate(
        _ attributed: NSAttributedString,
        headings: [MDHeading],
        config: MDRenderConfig
    ) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let nsText = attributed.string as NSString

        let leadingHeading = leadingHeadingRange(
            headings: headings, nsText: nsText
        )
        if let headingRange = leadingHeading {
            applyHeadingRestyle(to: mutable, range: headingRange, config: config)
        }
        // Every heading's start offset — the drop-cap scan must skip
        // heading blocks (a heading is rendered as plain bold text with
        // no distinctive run attribute, so offset matching is the
        // reliable exclusion).
        let headingOffsets = Set(headings.map { $0.charOffsetUTF16 })
        applyDropCap(
            to: mutable, nsText: nsText,
            afterHeading: leadingHeading,
            headingOffsets: headingOffsets, config: config
        )
        return NSAttributedString(attributedString: mutable)
    }

    // MARK: - Private — leading heading

    /// The UTF-16 range of the document's leading heading line — non-nil
    /// only when `headings.first` exists AND sits at offset 0 (it is the
    /// document's first block). The range covers the heading text but not
    /// the trailing newline.
    private static func leadingHeadingRange(
        headings: [MDHeading], nsText: NSString
    ) -> NSRange? {
        guard let first = headings.first, first.charOffsetUTF16 == 0 else {
            return nil
        }
        // The renderer materializes a heading as `headingText + "\n"`.
        // The heading line runs from offset 0 to the first newline.
        let newline = nsText.rangeOfCharacter(from: CharacterSet.newlines)
        let end = newline.location == NSNotFound ? nsText.length : newline.location
        guard end > 0 else { return nil }
        return NSRange(location: 0, length: end)
    }

    /// Restyles `range` with the design's centered tracked serif
    /// chapter-heading typography. Characters are never changed.
    private static func applyHeadingRestyle(
        to mutable: NSMutableAttributedString,
        range: NSRange,
        config: MDRenderConfig
    ) {
        guard range.location + range.length <= mutable.length else { return }
        let baseFont = ReaderTypography.body(
            for: .sourceSerif4, size: ChapterStartTypography.headingFontSize
        )
        let headingFont = fontWithWeight(
            baseFont, weight: ChapterStartTypography.headingFontWeight
        )
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacing = ChapterStartTypography.headingSpacingAfter
        style.paragraphSpacingBefore = ChapterStartTypography.headingSpacingBefore

        mutable.addAttributes([
            .font: headingFont,
            .foregroundColor: config.chapterHeadingColor,
            .kern: ChapterStartTypography.headingLetterSpacing,
            .paragraphStyle: style,
        ], range: range)
    }

    // MARK: - Private — drop-cap

    /// Applies the accent drop-cap to the first drop-cap-eligible scalar
    /// of the first PLAIN body paragraph after the leading heading (or
    /// from offset 0 when there is no leading heading). Skips heading,
    /// list, code-block and blockquote blocks. No-op when no plain
    /// paragraph with an eligible initial is found.
    private static func applyDropCap(
        to mutable: NSMutableAttributedString,
        nsText: NSString,
        afterHeading: NSRange?,
        headingOffsets: Set<Int>,
        config: MDRenderConfig
    ) {
        // Start scanning after the leading heading line (+ its newline),
        // else at offset 0.
        var paragraphStart = 0
        if let h = afterHeading {
            paragraphStart = min(h.location + h.length + 1, mutable.length)
        }

        guard let cap = MDChapterStartScanner.firstPlainParagraphDropCap(
            in: mutable, nsText: nsText, from: paragraphStart,
            headingOffsets: headingOffsets
        ) else { return }

        let dropCapSize = config.fontSize * ChapterStartTypography.dropCapScale
        let baseDropCapFont = ReaderTypography.body(
            for: .sourceSerif4, size: dropCapSize
        )
        let dropCapFont = fontWithWeight(
            baseDropCapFont, weight: ChapterStartTypography.dropCapFontWeight
        )
        let baselineDrop = -(dropCapSize - config.fontSize)
            * (1.0 - ChapterStartTypography.dropCapLineHeight)

        let capRange = NSRange(location: cap.index, length: cap.utf16Length)
        mutable.addAttributes([
            .font: dropCapFont,
            .foregroundColor: config.accentColor,
            .baselineOffset: baselineDrop,
        ], range: capRange)

        let capString = nsText.substring(with: capRange)
        let advance = (capString as NSString).size(
            withAttributes: [.font: dropCapFont]
        ).width
        applyFirstLineIndent(
            to: mutable, nsText: nsText,
            paragraphStart: cap.paragraphStart, indent: advance
        )
    }

    /// Sets `firstLineHeadIndent` on the drop-cap paragraph's paragraph
    /// style so the body's first line clears the oversized capital.
    /// Preserves every other paragraph attribute on the run.
    private static func applyFirstLineIndent(
        to mutable: NSMutableAttributedString,
        nsText: NSString,
        paragraphStart: Int,
        indent: CGFloat
    ) {
        guard paragraphStart < mutable.length else { return }
        let lineEnd = MDChapterStartScanner.lineEndOffset(
            in: nsText, from: paragraphStart
        )
        guard lineEnd > paragraphStart else { return }
        let range = NSRange(
            location: paragraphStart, length: lineEnd - paragraphStart
        )
        let existing = mutable.attribute(
            .paragraphStyle, at: paragraphStart, effectiveRange: nil
        ) as? NSParagraphStyle
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        mutable.addAttribute(.paragraphStyle, value: style, range: range)
    }

    /// Returns a copy of `font` with the requested weight via the font
    /// descriptor's trait dictionary. Falls back to the input font when
    /// the descriptor cannot carry the weight.
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
