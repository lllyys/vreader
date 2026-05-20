// Purpose: Feature #56 WI-12b — TXT/MD interlinear composer that takes a
// **typographed** source `NSAttributedString` (with font / line spacing /
// drop-cap / heading-restyle attrs already applied) and interleaves
// synthetic translation runs at paragraph boundaries. Preserves source-
// paragraph typography on the synthetic run so font + line spacing
// remain consistent with the surrounding chapter chrome.
//
// Why a second renderer? `BilingualTextRenderer` accepts a plain `String`
// source and produces a fresh attrString — which would lose the
// chapter-paged TXT path's drop-cap + heading restyle attributes that
// `TXTAttributedStringBuilder.buildChapterStart` applies upstream. The
// composer takes the already-typographed source and only inserts the
// new runs, preserving the rest.
//
// Key decisions:
// - **Inherit the prior source paragraph's attrs onto the synthetic
//   run.** A simple way to keep font + line spacing consistent with
//   the surrounding chapter. The decoration tag (`decorationAttributeKey`)
//   is added on top so downstream callers can locate the runs.
// - **Pure function, no I/O.** `compose(...)` is `static` and
//   synchronous; the input is a value type, the output is a value type.
// - **Off-mode: identity.** `nil` or empty `translatedSegments` returns
//   the source attrString verbatim + identity segment map.
//
// @coordinates-with: BilingualTextRenderer.swift,
//   BilingualDisplaySegmentMap.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

#if canImport(UIKit)
import Foundation
import UIKit

/// Pure TXT/MD interlinear composer that preserves source typography.
enum BilingualAttributedStringComposer {

    /// One compose result.
    struct Result {
        /// The composed display attributed string — source paragraphs
        /// interleaved with synthetic translation runs (decoration-tagged).
        let attributedString: NSAttributedString
        /// The display↔source offset map.
        let segmentMap: BilingualDisplaySegmentMap
    }

    /// Build a composed `(attrString, segmentMap)` from the typographed
    /// source attrString + paragraph ranges + translations.
    ///
    /// - Parameters:
    ///   - sourceAttributed: the chapter's source attrString with
    ///     typography already applied (drop-cap, heading restyle, font,
    ///     line spacing).
    ///   - sourceParagraphRanges: UTF-16 ranges of each paragraph in the
    ///     source string. Synthetic runs go after each.
    ///   - translatedSegments: ordered translation strings (one per
    ///     paragraph). `nil` or empty suppresses the interleave and
    ///     returns the source attrString + identity map.
    static func compose(
        sourceAttributed: NSAttributedString,
        sourceParagraphRanges: [Range<Int>],
        translatedSegments: [String]?
    ) -> Result {
        let sourceLengthUTF16 = sourceAttributed.length

        guard let translations = translatedSegments, !translations.isEmpty,
              !sourceParagraphRanges.isEmpty else {
            return Result(
                attributedString: sourceAttributed,
                segmentMap: BilingualDisplaySegmentMap.identity(sourceLength: sourceLengthUTF16)
            )
        }

        let result = NSMutableAttributedString()
        var segments: [BilingualDisplaySegmentMap.Segment] = []
        var sourceCursor = 0
        var displayCursor = 0

        for (index, paragraphRange) in sourceParagraphRanges.enumerated() {
            // Inter-paragraph text (gap from prior paragraph end to this
            // paragraph start) — emit as a `.source` segment.
            if paragraphRange.lowerBound > sourceCursor {
                let preRange = NSRange(
                    location: sourceCursor,
                    length: paragraphRange.lowerBound - sourceCursor
                )
                let preSubstring = sourceAttributed.attributedSubstring(from: preRange)
                result.append(preSubstring)
                segments.append(.source(
                    sourceRange: sourceCursor..<paragraphRange.lowerBound,
                    displayRange: displayCursor..<(displayCursor + preRange.length)
                ))
                displayCursor += preRange.length
                sourceCursor = paragraphRange.lowerBound
            }

            // The paragraph itself — copy source attrString slice.
            let paragraphLength = paragraphRange.upperBound - paragraphRange.lowerBound
            if paragraphLength > 0 {
                let paraRange = NSRange(
                    location: paragraphRange.lowerBound, length: paragraphLength
                )
                let paraSubstring = sourceAttributed.attributedSubstring(from: paraRange)
                result.append(paraSubstring)
                segments.append(.source(
                    sourceRange: paragraphRange.lowerBound..<paragraphRange.upperBound,
                    displayRange: displayCursor..<(displayCursor + paragraphLength)
                ))
                displayCursor += paragraphLength
                sourceCursor = paragraphRange.upperBound
            }

            // The synthetic translation run for this paragraph.
            if index < translations.count {
                let translationText = translations[index]
                guard !translationText.isEmpty else { continue }
                let syntheticString = "\n" + translationText

                // Inherit the prior source paragraph's attrs (paragraph
                // style, font, line spacing). Fall back to the source's
                // first-character attrs when the paragraph was empty.
                let inheritFrom = max(0, min(sourceLengthUTF16 - 1,
                                              paragraphRange.upperBound - 1))
                var attrs: [NSAttributedString.Key: Any] = sourceLengthUTF16 > 0
                    ? sourceAttributed.attributes(at: inheritFrom, effectiveRange: nil)
                    : [:]
                attrs[BilingualTextRenderer.decorationAttributeKey] = true

                let syntheticAttrString = NSAttributedString(
                    string: syntheticString, attributes: attrs
                )
                result.append(syntheticAttrString)
                let syntheticLength = (syntheticString as NSString).length
                segments.append(.synthetic(
                    displayRange: displayCursor..<(displayCursor + syntheticLength)
                ))
                displayCursor += syntheticLength
            }
        }

        // Any source attrString after the last paragraph (trailing
        // typography, headings stripped) — emit as a final `.source` segment.
        if sourceCursor < sourceLengthUTF16 {
            let tailRange = NSRange(
                location: sourceCursor, length: sourceLengthUTF16 - sourceCursor
            )
            let tailSubstring = sourceAttributed.attributedSubstring(from: tailRange)
            result.append(tailSubstring)
            segments.append(.source(
                sourceRange: sourceCursor..<sourceLengthUTF16,
                displayRange: displayCursor..<(displayCursor + tailRange.length)
            ))
            displayCursor += tailRange.length
        }

        return Result(
            attributedString: result,
            segmentMap: BilingualDisplaySegmentMap(
                sourceLength: sourceLengthUTF16,
                segments: segments
            )
        )
    }
}
#endif
