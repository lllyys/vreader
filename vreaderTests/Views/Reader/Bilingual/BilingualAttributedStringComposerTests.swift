// Purpose: Feature #56 WI-12b — pin the TXT/MD interlinear composer that
// preserves the source `NSAttributedString`'s typography while inserting
// synthetic translation runs. Inherits paragraph-style attributes from
// the source so synthetic runs match font/line spacing; tags every
// synthetic run with `BilingualTextRenderer.decorationAttributeKey`.
//
// @coordinates-with: BilingualAttributedStringComposer.swift,
//   BilingualTextRenderer.swift, BilingualDisplaySegmentMap.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("Feature #56 WI-12b — BilingualAttributedStringComposer")
struct BilingualAttributedStringComposerTests {

    @Test("empty translations returns the source attributed string verbatim")
    func emptyTranslations() {
        let source = NSAttributedString(
            string: "Hello\n\nWorld",
            attributes: [.font: UIFont.systemFont(ofSize: 17)]
        )
        let result = BilingualAttributedStringComposer.compose(
            sourceAttributed: source,
            sourceParagraphRanges: [0..<5, 7..<12],
            translatedSegments: []
        )
        #expect(result.attributedString.isEqual(to: source))
        #expect(result.segmentMap == BilingualDisplaySegmentMap.identity(sourceLength: source.length))
    }

    @Test("nil translations returns identity")
    func nilTranslations() {
        let source = NSAttributedString(
            string: "Hello", attributes: [.font: UIFont.systemFont(ofSize: 17)]
        )
        let result = BilingualAttributedStringComposer.compose(
            sourceAttributed: source,
            sourceParagraphRanges: [0..<5],
            translatedSegments: nil
        )
        #expect(result.attributedString.isEqual(to: source))
    }

    @Test("non-empty translations interleaves synthetic runs + tags them with the decoration key")
    func interleavesSyntheticRuns() {
        let source = NSAttributedString(
            string: "Para1\n\nPara2",
            attributes: [.font: UIFont.systemFont(ofSize: 17)]
        )
        let result = BilingualAttributedStringComposer.compose(
            sourceAttributed: source,
            sourceParagraphRanges: [0..<5, 7..<12],
            translatedSegments: ["Trans1", "Trans2"]
        )
        // Display contains both source paragraphs + both translations.
        #expect(result.attributedString.string.contains("Para1"))
        #expect(result.attributedString.string.contains("Para2"))
        #expect(result.attributedString.string.contains("Trans1"))
        #expect(result.attributedString.string.contains("Trans2"))

        // Segment map is non-identity.
        #expect(result.segmentMap.sourceLength == source.length)
        #expect(result.segmentMap.displayLength > source.length)

        // Every synthetic display range is tagged with the decoration key.
        var allSyntheticAreTagged = true
        for segment in result.segmentMap.segments {
            guard case let .synthetic(displayRange) = segment else { continue }
            let nsRange = NSRange(location: displayRange.lowerBound,
                                  length: displayRange.upperBound - displayRange.lowerBound)
            // Look at the first character of the synthetic — its
            // attributes must include the decoration key.
            let attrs = result.attributedString.attributes(at: nsRange.location, effectiveRange: nil)
            if attrs[BilingualTextRenderer.decorationAttributeKey] as? Bool != true {
                allSyntheticAreTagged = false
            }
        }
        #expect(allSyntheticAreTagged)
    }

    @Test("synthetic runs inherit the prior source paragraph's font attribute")
    func syntheticInheritsFont() {
        let customFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let source = NSAttributedString(string: "Para1", attributes: [.font: customFont])
        let result = BilingualAttributedStringComposer.compose(
            sourceAttributed: source,
            sourceParagraphRanges: [0..<5],
            translatedSegments: ["Trans1"]
        )
        // Look at the synthetic display range — find a synthetic segment.
        let syntheticSegment = result.segmentMap.segments.first {
            if case .synthetic = $0 { return true }
            return false
        }
        #expect(syntheticSegment != nil)
        if case .synthetic(let displayRange) = syntheticSegment! {
            // Skip the leading "\n" of the synthetic run (the leader char) —
            // check the first char of the actual translation text.
            let firstSyntheticCharLocation = displayRange.lowerBound + 1
            let attrs = result.attributedString.attributes(
                at: firstSyntheticCharLocation, effectiveRange: nil
            )
            let font = attrs[.font] as? UIFont
            #expect(font == customFont)
        }
    }
}
