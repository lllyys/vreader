// Purpose: Feature #56 WI-12b — TXT/MD paragraph-range scanner. Splits a
// chapter's source string into UTF-16 ranges of "paragraphs" (one per
// content line, blank-line-separated content lines treated as separate
// paragraphs). Pure UTF-16 arithmetic — feeds `BilingualTextRenderer.render`.
//
// Key decisions:
// - **A paragraph is a maximal run of non-empty content lines.** "Empty"
//   means whitespace-only after normalisation; "non-empty" means at
//   least one non-whitespace character. A consecutive run of non-empty
//   lines fuses into one paragraph, because real-world TXT/MD files
//   wrap a single logical paragraph across multiple lines. The blank
//   line is the paragraph delimiter — never the single newline.
//   *(Updated 2026-05-20: original split-on-every-newline approach was
//   too aggressive; line-wrapped paragraphs were oversegmented. The
//   conservative fusion picks the right granularity for translation.)*
// - **Paragraph ranges are UTF-16, half-open.** Every consumer
//   (`BilingualTextRenderer`, `BilingualDisplaySegmentMap`) uses UTF-16
//   half-open ranges; matching the convention avoids index arithmetic
//   bugs.
// - **Inter-paragraph separators are excluded from ranges.** A
//   `\n` / `\r\n` / `\n\n` between paragraphs is NOT part of either
//   neighbour's range — the renderer emits a `.source` segment for the
//   separator so selection across the gap still maps to a valid source
//   offset.
// - **Leading + trailing whitespace-only lines yield no paragraph.**
//   These are common at chapter boundaries (especially TXT with
//   stripped chapter headings). They become trailing source segments
//   in the renderer's output but produce no synthetic translation run.
// - **Pure function, no I/O.** Implementation is a single pass through
//   the source; complexity is O(N) in UTF-16 length.
//
// @coordinates-with: BilingualTextRenderer.swift,
//   BilingualDisplaySegmentMap.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import Foundation

/// Pure TXT/MD paragraph-range scanner.
enum BilingualParagraphRanges {

    /// Scans the source text into UTF-16 paragraph ranges. Each range
    /// describes one content "paragraph" — a maximal run of non-empty
    /// lines, blank-line-separated from its neighbours. The returned
    /// ranges:
    /// - are in source order,
    /// - are non-overlapping,
    /// - exclude the inter-paragraph blank-line separators,
    /// - exclude leading + trailing blank lines.
    static func scan(sourceText: String) -> [Range<Int>] {
        let ns = sourceText as NSString
        let length = ns.length
        guard length > 0 else { return [] }

        var ranges: [Range<Int>] = []
        var cursor = 0
        var paragraphStart: Int? = nil  // start of the currently-open paragraph
        var paragraphLastNonBlank: Int = 0  // exclusive end (UTF-16 index after the last non-blank char)

        while cursor < length {
            // Find the end of this line (exclusive of the line terminator).
            // A line terminator is "\n", "\r\n", or "\r".
            var lineEnd = cursor
            while lineEnd < length {
                let unit = ns.character(at: lineEnd)
                if unit == 0x0A /* \n */ || unit == 0x0D /* \r */ {
                    break
                }
                lineEnd += 1
            }
            // Determine whether the line has any non-whitespace.
            let lineRange = NSRange(location: cursor, length: lineEnd - cursor)
            let isBlank = lineRange.length == 0 || isLineBlank(ns: ns, range: lineRange)

            if isBlank {
                // Close the open paragraph, if any.
                if let start = paragraphStart {
                    ranges.append(start..<paragraphLastNonBlank)
                    paragraphStart = nil
                }
            } else {
                // Non-empty line — start or extend the open paragraph.
                if paragraphStart == nil {
                    paragraphStart = cursor
                }
                paragraphLastNonBlank = lineEnd
            }

            // Advance past the line terminator (handle "\r\n" as one).
            if lineEnd < length {
                let unit = ns.character(at: lineEnd)
                cursor = lineEnd + 1
                if unit == 0x0D && cursor < length && ns.character(at: cursor) == 0x0A {
                    cursor += 1
                }
            } else {
                cursor = lineEnd
            }
        }

        // Close any final open paragraph.
        if let start = paragraphStart {
            ranges.append(start..<paragraphLastNonBlank)
        }

        return ranges
    }

    /// True when the NSRange contains only whitespace characters.
    private static func isLineBlank(ns: NSString, range: NSRange) -> Bool {
        let whitespaces = CharacterSet.whitespaces
        for offset in 0..<range.length {
            let unit = ns.character(at: range.location + offset)
            guard let scalar = Unicode.Scalar(UInt32(unit)) else { return false }
            if !whitespaces.contains(scalar) { return false }
        }
        return true
    }
}
