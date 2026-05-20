// Purpose: Feature #56 WI-12 — TXT/MD interlinear builder. Takes the
// source text + per-paragraph UTF-16 ranges + an ordered translation
// segment list (one segment per source paragraph) and produces (a) an
// `NSAttributedString` containing the source paragraphs interleaved
// with synthetic translation runs and (b) a
// `BilingualDisplaySegmentMap` that records the display↔source offset
// mapping for the TXT/MD container's offset-routing.
//
// Used by both `TXTReaderContainerView` and `MDReaderContainerView`.
// The OFF-mode path (`translatedSegments == nil` or empty) returns the
// source text as-is with an identity map, so the TXT/MD container can
// use the same code path regardless of bilingual state.
//
// Key decisions:
// - **Pure function — no I/O, no network, no `@MainActor`.** All
//   inputs are value types; the output is a value type. Exhaustively
//   unit-testable; no fixture book needed.
// - **Synthetic runs carry a decoration attribute key.** The renderer
//   tags every translation run with
//   `BilingualTextRenderer.decorationAttributeKey == true` so a
//   downstream syntax-attribute pass (font scaling, color, leading
//   border) can locate the runs without re-parsing. The decoration
//   attribute is also the seam that lets selection logic in
//   `TXTTextViewBridge` skip synthetic runs without scanning the
//   segment map.
// - **Synthetic-run separator is `"\n"`.** A single newline is enough
//   to put the translation on its own line in `UITextView` without
//   doubling the paragraph break the source already supplies. The
//   rendered string therefore reads:
//
//       <source paragraph 1>\n<translation 1>\n\n<source paragraph 2>\n<translation 2>...
//
//   The leading `\n` of the synthetic run is part of the synthetic
//   `displayRange` so selecting from the end of a source paragraph
//   into the translation does not yield an unexpected source offset.
// - **Partial translation = silent-source-fallback.** When the
//   translation array is shorter than the paragraph array, the prefix
//   gets injected and the tail paragraphs render source-only (no
//   synthetic run, no map entry for a missing translation). This is
//   plan Decision 2's silent fallback.
//
// @coordinates-with: BilingualDisplaySegmentMap.swift,
//   TXTReaderContainerView.swift, MDReaderContainerView.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12)

#if canImport(UIKit)
import Foundation
import UIKit

/// Pure TXT/MD interlinear builder. The output is a value-pair (the
/// rendered `NSAttributedString` + its display↔source map).
enum BilingualTextRenderer {

    /// The custom attribute key applied to every synthetic translation
    /// run in the output `NSAttributedString`. A downstream styling
    /// pass (font scaling, color, indent, leading border) can use
    /// `enumerateAttribute(_:in:options:using:)` against this key to
    /// locate the runs in O(segments); the TXT/MD selection logic can
    /// query the attribute at a tap location to decide whether to
    /// route the hit to a source range or skip it (synthetic runs are
    /// non-selectable per design §2.4).
    static let decorationAttributeKey = NSAttributedString.Key("vreaderBilingualSynthetic")

    /// One render result.
    struct Result {
        /// The rendered display text (source paragraphs interleaved
        /// with synthetic translation runs).
        let attributedString: NSAttributedString

        /// The display↔source offset map. `identity(sourceLength:)`
        /// in OFF mode; an interleaved map in ON mode.
        let segmentMap: BilingualDisplaySegmentMap
    }

    /// Build a `Result` for the given source + translation inputs.
    ///
    /// - Parameters:
    ///   - sourceText: the source text (paragraph contents + their
    ///     surrounding whitespace, as the TXT/MD reader stores it).
    ///   - sourceParagraphRanges: UTF-16 ranges of each paragraph in
    ///     `sourceText`. Synthetic runs are injected after each range;
    ///     intervening text (paragraph separators) becomes its own
    ///     `.source` segment so selection across the separator yields
    ///     a valid source offset.
    ///   - translatedSegments: ordered translated strings, one per
    ///     paragraph in `sourceParagraphRanges`. `nil` or empty
    ///     suppresses the interleave and the result is the source +
    ///     identity map (the bilingual-off path).
    static func render(
        sourceText: String,
        sourceParagraphRanges: [Range<Int>],
        translatedSegments: [String]?
    ) -> Result {
        let sourceLengthUTF16 = sourceText.utf16.count

        // Off-mode shortcut: nil or empty translations → identity.
        guard let translations = translatedSegments, !translations.isEmpty,
              !sourceParagraphRanges.isEmpty else {
            return Result(
                attributedString: NSAttributedString(string: sourceText),
                segmentMap: BilingualDisplaySegmentMap.identity(sourceLength: sourceLengthUTF16)
            )
        }

        let sourceNS = sourceText as NSString
        let result = NSMutableAttributedString()
        var segments: [BilingualDisplaySegmentMap.Segment] = []
        // Tracks the source UTF-16 cursor as we walk paragraphs in
        // order, so the inter-paragraph text (separators) becomes its
        // own `.source` segment with the correct source range.
        var sourceCursor = 0
        var displayCursor = 0

        for (index, paragraphRange) in sourceParagraphRanges.enumerated() {
            // Inter-paragraph text (everything from the previous
            // paragraph end to this paragraph start) — emit a `.source`
            // segment so selection across the separator still maps to
            // a valid source offset.
            if paragraphRange.lowerBound > sourceCursor {
                let preLength = paragraphRange.lowerBound - sourceCursor
                let preText = sourceNS.substring(
                    with: NSRange(location: sourceCursor, length: preLength)
                )
                result.append(NSAttributedString(string: preText))
                segments.append(.source(
                    sourceRange: sourceCursor..<paragraphRange.lowerBound,
                    displayRange: displayCursor..<(displayCursor + preLength)
                ))
                displayCursor += preLength
                sourceCursor = paragraphRange.lowerBound
            }

            // The paragraph itself — a `.source` segment.
            let paragraphLength = paragraphRange.upperBound - paragraphRange.lowerBound
            if paragraphLength > 0 {
                let paragraphText = sourceNS.substring(
                    with: NSRange(location: paragraphRange.lowerBound, length: paragraphLength)
                )
                result.append(NSAttributedString(string: paragraphText))
                segments.append(.source(
                    sourceRange: paragraphRange.lowerBound..<paragraphRange.upperBound,
                    displayRange: displayCursor..<(displayCursor + paragraphLength)
                ))
                displayCursor += paragraphLength
                sourceCursor = paragraphRange.upperBound
            }

            // The synthetic translation run for this paragraph, if a
            // translation is available. The leading "\n" separates the
            // translation from the source line in `UITextView` without
            // doubling the paragraph's own break that may follow in
            // the source's inter-paragraph segment.
            if index < translations.count {
                let translationText = translations[index]
                guard !translationText.isEmpty else { continue }
                let syntheticRun = "\n" + translationText
                let syntheticAttrString = NSAttributedString(
                    string: syntheticRun,
                    attributes: [decorationAttributeKey: true]
                )
                result.append(syntheticAttrString)
                let syntheticLength = (syntheticRun as NSString).length
                segments.append(.synthetic(
                    displayRange: displayCursor..<(displayCursor + syntheticLength)
                ))
                displayCursor += syntheticLength
            }
        }

        // Any source text after the last paragraph (trailing whitespace,
        // chapter footer text) — emit as a final `.source` segment so
        // hit tests in that region map back to the source.
        if sourceCursor < sourceLengthUTF16 {
            let tailLength = sourceLengthUTF16 - sourceCursor
            let tailText = sourceNS.substring(
                with: NSRange(location: sourceCursor, length: tailLength)
            )
            result.append(NSAttributedString(string: tailText))
            segments.append(.source(
                sourceRange: sourceCursor..<sourceLengthUTF16,
                displayRange: displayCursor..<(displayCursor + tailLength)
            ))
            displayCursor += tailLength
            sourceCursor = sourceLengthUTF16
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
