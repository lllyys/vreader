// Purpose: Feature #68 WI-3 — locates the chapter-start drop-cap target
// inside the MD renderer's NSAttributedString: scans paragraph-by-
// paragraph for the first PLAIN body paragraph (skipping heading, list,
// code-block and blockquote blocks) and returns its first drop-cap-
// eligible scalar.
//
// Split out of `MDChapterStartDecorator` so each file stays under the
// ~300-line budget (rule 50 §9). The decorator owns "apply the
// typography"; this scanner owns "find where the drop-cap goes".
//
// Block-type detection is purely attribute-based — it reads the run
// attributes the MD renderer applies to each block type
// (`MDAttributedStringRenderer`) rather than re-parsing Markdown.
//
// @coordinates-with: MDChapterStartDecorator.swift,
//   MDAttributedStringRenderer.swift, ChapterStartTypography.swift

#if canImport(UIKit)
import UIKit

enum MDChapterStartScanner {

    /// A located drop-cap target: the eligible scalar's UTF-16 `index`
    /// and `utf16Length` (1 for a BMP scalar, 2 for a supplementary-plane
    /// one), plus the `paragraphStart` of the containing paragraph.
    struct DropCapTarget {
        let index: Int
        let utf16Length: Int
        let paragraphStart: Int
    }

    /// Scans paragraph-by-paragraph from `start`, returns the drop-cap
    /// target for the first PLAIN paragraph with a drop-cap-eligible
    /// initial. Returns `nil` when no such paragraph is found within a
    /// bounded scan (the drop-cap target is near the chapter start).
    ///
    /// `headingOffsets` is the set of `MDHeading.charOffsetUTF16` values
    /// — a heading block is rendered as plain bold text (no distinctive
    /// run attribute), so a paragraph whose start matches a heading
    /// offset is excluded explicitly. Without this a document like
    /// `# H1\n\n## H2\n\nBody` would mis-drop-cap the `## H2` line.
    static func firstPlainParagraphDropCap(
        in mutable: NSMutableAttributedString,
        nsText: NSString,
        from start: Int,
        headingOffsets: Set<Int>
    ) -> DropCapTarget? {
        var paragraphStart = start
        var paragraphsScanned = 0
        let maxParagraphs = 24
        while paragraphStart < mutable.length && paragraphsScanned < maxParagraphs {
            let lineEnd = lineEndOffset(in: nsText, from: paragraphStart)
            let lineLength = lineEnd - paragraphStart
            if lineLength > 0,
               !headingOffsets.contains(paragraphStart),
               isPlainParagraph(in: mutable, paragraphStart: paragraphStart),
               let cap = firstDropCapScalar(
                   in: nsText, from: paragraphStart, limit: lineEnd
               ) {
                return DropCapTarget(
                    index: cap.index, utf16Length: cap.utf16Length,
                    paragraphStart: paragraphStart
                )
            }
            paragraphStart = min(lineEnd + 1, mutable.length)
            paragraphsScanned += 1
        }
        return nil
    }

    /// The UTF-16 offset of the first newline at or after `from`, or the
    /// string length when there is no further newline.
    static func lineEndOffset(in nsText: NSString, from: Int) -> Int {
        guard from < nsText.length else { return nsText.length }
        let searchRange = NSRange(location: from, length: nsText.length - from)
        let newline = nsText.rangeOfCharacter(
            from: CharacterSet.newlines, range: searchRange
        )
        return newline.location == NSNotFound ? nsText.length : newline.location
    }

    // MARK: - Private — block classification

    /// True when the paragraph beginning at `paragraphStart` is a plain
    /// body paragraph — NOT a heading, list item, code block, or
    /// blockquote. Determined from the run attributes the MD renderer
    /// applies to each block type.
    private static func isPlainParagraph(
        in mutable: NSMutableAttributedString,
        paragraphStart: Int
    ) -> Bool {
        guard paragraphStart < mutable.length else { return false }
        let attrs = mutable.attributes(at: paragraphStart, effectiveRange: nil)

        // Code block — monospaced font and/or a background color.
        if attrs[.backgroundColor] != nil { return false }
        if let font = attrs[.font] as? UIFont,
           font.fontName.lowercased().contains("mono")
            || font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) {
            return false
        }
        // Blockquote — paragraph style with a head indent.
        if let style = attrs[.paragraphStyle] as? NSParagraphStyle,
           style.headIndent > 0 || style.firstLineHeadIndent > 0 {
            return false
        }
        // List item — the renderer prefixes a bullet or ordered marker.
        return !looksLikeListItem(in: mutable, paragraphStart: paragraphStart)
    }

    /// True when the paragraph text begins with this renderer's list
    /// prefix: optional leading tabs then a "\u{2022} " bullet, or an
    /// ordered marker — a digit run followed by "." or ")" then " ".
    ///
    /// The MD renderer's ordered-list prefix is `<numberStr> ` where
    /// `numberStr` keeps the trailing `.`/`)` punctuation (verified at
    /// `MDAttributedStringRenderer.parseOrderedListItem`), so the
    /// rendered text begins with e.g. "1. " — digits, then `.`/`)`,
    /// then a single space. This matches the renderer's own
    /// ordered-list regex, so detection here is consistent with it.
    private static func looksLikeListItem(
        in mutable: NSMutableAttributedString,
        paragraphStart: Int
    ) -> Bool {
        let ns = mutable.string as NSString
        var i = paragraphStart
        // Skip leading tabs (nested-list indent).
        while i < ns.length && ns.character(at: i) == 0x09 { i += 1 }
        guard i < ns.length else { return false }
        let unit = ns.character(at: i)
        // Unordered bullet "\u{2022} ".
        if unit == 0x2022 { return true }
        // Ordered marker: digits, then "." (0x2E) or ")" (0x29), then " ".
        if unit >= 0x30 && unit <= 0x39 {
            var j = i
            while j < ns.length, ns.character(at: j) >= 0x30, ns.character(at: j) <= 0x39 {
                j += 1
            }
            if j > i, j + 1 < ns.length {
                let punct = ns.character(at: j)
                let space = ns.character(at: j + 1)
                if (punct == 0x2E || punct == 0x29) && space == 0x20 {
                    return true
                }
            }
        }
        return false
    }

    /// Returns the first drop-cap-eligible scalar at or after `start`,
    /// scanning only up to `limit` (the paragraph's line end) and only a
    /// short window (handles a leading opening quote per R5). Surrogate
    /// pairs are reconstructed so a supplementary-plane letter is matched
    /// and its full UTF-16 span (length 2) is reported.
    private static func firstDropCapScalar(
        in nsText: NSString, from start: Int, limit: Int
    ) -> (index: Int, utf16Length: Int)? {
        let scanWindow = 8
        var index = start
        var scanned = 0
        while index < limit && scanned < scanWindow {
            let unit = nsText.character(at: index)
            if UTF16.isLeadSurrogate(unit) {
                let nextIndex = index + 1
                if nextIndex < limit {
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
}
#endif
