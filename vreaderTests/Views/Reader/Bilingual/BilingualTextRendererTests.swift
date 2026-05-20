// Purpose: Feature #56 WI-12 — pin the TXT/MD interlinear builder
// `BilingualTextRenderer`. Two-argument signature: source `String` +
// `[String]` translated segments + the paragraph boundary array. The
// builder produces an `NSAttributedString` interleaving each source
// paragraph with its synthetic translation run, and a
// `BilingualDisplaySegmentMap` that pins every display↔source offset
// mapping. The OFF-mode path returns the source as-is with an identity
// map so the TXT/MD container can use the same code path regardless
// of bilingual state.
//
// @coordinates-with: BilingualTextRenderer.swift,
//   BilingualDisplaySegmentMap.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #56 WI-12 — BilingualTextRenderer")
struct BilingualTextRendererTests {

    // MARK: - bilingual off

    @Test("off-mode returns source string identity map")
    func offModeIdentity() {
        let source = "Hello world\n\nSecond paragraph"
        let result = BilingualTextRenderer.render(
            sourceText: source,
            sourceParagraphRanges: [],
            translatedSegments: nil
        )
        #expect(result.attributedString.string == source)
        #expect(result.segmentMap == BilingualDisplaySegmentMap.identity(sourceLength: source.utf16.count))
    }

    @Test("off-mode with empty source returns identity over zero length")
    func offModeEmptySource() {
        let result = BilingualTextRenderer.render(
            sourceText: "",
            sourceParagraphRanges: [],
            translatedSegments: nil
        )
        #expect(result.attributedString.string == "")
        #expect(result.segmentMap.sourceLength == 0)
        #expect(result.segmentMap.displayLength == 0)
    }

    // MARK: - bilingual on, single paragraph

    @Test("single-paragraph render interleaves one translation after the paragraph")
    func singleParagraphInterleave() {
        let source = "Hello world"
        // The single paragraph covers the whole source.
        let ranges = [0..<source.utf16.count]
        let result = BilingualTextRenderer.render(
            sourceText: source,
            sourceParagraphRanges: ranges,
            translatedSegments: ["Bonjour le monde"]
        )
        // The display string must contain the source AND the translation.
        let display = result.attributedString.string
        #expect(display.contains("Hello world"))
        #expect(display.contains("Bonjour le monde"))
        // The map's source length matches the input.
        #expect(result.segmentMap.sourceLength == source.utf16.count)
        // displayLength must equal the rendered string's UTF-16 length.
        #expect(result.segmentMap.displayLength == display.utf16.count)
    }

    // MARK: - bilingual on, two paragraphs

    @Test("two-paragraph render interleaves both translations and round-trips offsets")
    func twoParagraphRoundTrip() {
        let p1 = "First paragraph here."
        let p2 = "Second paragraph follows."
        let separator = "\n\n"
        let source = p1 + separator + p2
        let p1Range = 0..<p1.utf16.count
        let p2Start = (p1 + separator).utf16.count
        let p2Range = p2Start..<source.utf16.count
        let result = BilingualTextRenderer.render(
            sourceText: source,
            sourceParagraphRanges: [p1Range, p2Range],
            translatedSegments: ["译文一", "译文二"]
        )
        let display = result.attributedString.string
        #expect(display.contains(p1))
        #expect(display.contains(p2))
        #expect(display.contains("译文一"))
        #expect(display.contains("译文二"))
        // Every source offset round-trips through the map.
        for sourceOffset in 0..<result.segmentMap.sourceLength {
            let displayOffset = result.segmentMap.displayOffset(forSourceOffset: sourceOffset)
            let roundTrip = result.segmentMap.sourceOffset(forDisplayOffset: displayOffset)
            #expect(roundTrip == sourceOffset)
        }
    }

    // MARK: - source-only fallback

    @Test("nil translations falls back to identity even with paragraph ranges")
    func nilTranslationsFallback() {
        let source = "A.\n\nB."
        let p1Range = 0..<2
        let p2Range = 4..<6
        let result = BilingualTextRenderer.render(
            sourceText: source,
            sourceParagraphRanges: [p1Range, p2Range],
            translatedSegments: nil
        )
        #expect(result.attributedString.string == source)
        #expect(result.segmentMap == BilingualDisplaySegmentMap.identity(sourceLength: source.utf16.count))
    }

    @Test("empty translations falls back to identity")
    func emptyTranslationsFallback() {
        let source = "A.\n\nB."
        let p1Range = 0..<2
        let p2Range = 4..<6
        let result = BilingualTextRenderer.render(
            sourceText: source,
            sourceParagraphRanges: [p1Range, p2Range],
            translatedSegments: []
        )
        #expect(result.attributedString.string == source)
        #expect(result.segmentMap == BilingualDisplaySegmentMap.identity(sourceLength: source.utf16.count))
    }

    // MARK: - partial-translation prefix (silent-source-fallback)

    @Test("fewer translations than paragraphs only injects the prefix")
    func partialTranslationPrefix() {
        let p1 = "Para one."
        let p2 = "Para two."
        let p3 = "Para three."
        let separator = "\n\n"
        let source = [p1, p2, p3].joined(separator: separator)
        let p1Range = 0..<p1.utf16.count
        let p2Start = (p1 + separator).utf16.count
        let p2Range = p2Start..<(p2Start + p2.utf16.count)
        let p3Start = (p1 + separator + p2 + separator).utf16.count
        let p3Range = p3Start..<source.utf16.count
        let result = BilingualTextRenderer.render(
            sourceText: source,
            sourceParagraphRanges: [p1Range, p2Range, p3Range],
            translatedSegments: ["T1", "T2"]  // only two translations for three paragraphs
        )
        let display = result.attributedString.string
        #expect(display.contains("T1"))
        #expect(display.contains("T2"))
        // The third paragraph stays source-only — there should be no
        // synthetic run injected for it. The simplest pin: the rendered
        // string ends with paragraph three's source, not a translation.
        #expect(display.hasSuffix(p3))
    }

    // MARK: - Unicode / CJK

    @Test("CJK source + translation round-trips UTF-16 offsets")
    func cjkRoundTrip() {
        let source = "你好。"
        let ranges = [0..<source.utf16.count]
        let result = BilingualTextRenderer.render(
            sourceText: source,
            sourceParagraphRanges: ranges,
            translatedSegments: ["Hello."]
        )
        #expect(result.attributedString.string.contains("你好"))
        #expect(result.attributedString.string.contains("Hello"))
        // Round-trip every UTF-16 source unit (CJK chars take 1 UTF-16
        // unit each in the BMP).
        for sourceOffset in 0..<result.segmentMap.sourceLength {
            let displayOffset = result.segmentMap.displayOffset(forSourceOffset: sourceOffset)
            let roundTrip = result.segmentMap.sourceOffset(forDisplayOffset: displayOffset)
            #expect(roundTrip == sourceOffset)
        }
    }

    // MARK: - synthetic-run regions carry a decoration attribute

    @Test("synthetic translation runs carry the bilingual decoration attribute")
    func syntheticRunsCarryDecorationAttribute() {
        let source = "Para A.\n\nPara B."
        let p1Range = 0..<7
        let p2Start = 9
        let p2Range = p2Start..<(p2Start + 7)
        let result = BilingualTextRenderer.render(
            sourceText: source,
            sourceParagraphRanges: [p1Range, p2Range],
            translatedSegments: ["T A", "T B"]
        )
        var syntheticRunCount = 0
        result.attributedString.enumerateAttribute(
            BilingualTextRenderer.decorationAttributeKey,
            in: NSRange(location: 0, length: result.attributedString.length),
            options: []
        ) { value, _, _ in
            if value as? Bool == true { syntheticRunCount += 1 }
        }
        // Two paragraphs → two synthetic runs with the decoration attr.
        #expect(syntheticRunCount == 2)
    }
}
