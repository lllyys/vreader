// Purpose: Feature #56 WI-12b — pin the TXT/MD offset router. Every
// display offset the TXT/MD container exposes to a downstream consumer
// (UITextView selection, highlight range, search-nav scroll, TTS
// auto-scroll) is routed through `BilingualOffsetRouter`. When the
// segment map is identity (bilingual off), every routed offset is the
// same offset — byte-identical pass-through that gates R-TXT-offsets.
//
// @coordinates-with: BilingualOffsetRouter.swift,
//   BilingualDisplaySegmentMap.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #56 WI-12b — BilingualOffsetRouter")
struct BilingualOffsetRouterTests {

    // MARK: - identity map: byte-identical pass-through

    @Test("identity map: sourceToDisplay is identity")
    func identitySourceToDisplay() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        for source in [0, 5, 25, 50, 75, 99] {
            #expect(BilingualOffsetRouter.displayOffset(forSourceOffset: source, map: map) == source)
        }
    }

    @Test("identity map: displayToSource is identity")
    func identityDisplayToSource() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        for display in [0, 5, 25, 50, 75, 99] {
            #expect(BilingualOffsetRouter.sourceOffset(forDisplayOffset: display, map: map) == display)
        }
    }

    @Test("identity map: range round-trip")
    func identityRangeRoundTrip() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        let source = 10..<25
        let display = BilingualOffsetRouter.displayRange(forSourceRange: source, map: map)
        #expect(display == NSRange(location: 10, length: 15))
    }

    @Test("identity map: NSRange round-trip")
    func identityNSRangeRoundTrip() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        let source = NSRange(location: 10, length: 15)
        let display = BilingualOffsetRouter.displayNSRange(forSourceNSRange: source, map: map)
        #expect(display == source)
    }

    // MARK: - non-identity map: synthetic-skip semantics

    @Test("synthetic range: displayToSource returns nil for synthetic offset")
    func syntheticSkip() {
        // Source: "AAA" (0..<3); synthetic "[T]" at display 3..<6; "BBB" at display 6..<9 source 3..<6.
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        // Source offsets pass straight through.
        #expect(BilingualOffsetRouter.sourceOffset(forDisplayOffset: 0, map: map) == 0)
        #expect(BilingualOffsetRouter.sourceOffset(forDisplayOffset: 2, map: map) == 2)
        // Inside the synthetic — nil.
        #expect(BilingualOffsetRouter.sourceOffset(forDisplayOffset: 4, map: map) == nil)
        // After the synthetic — shifted source.
        #expect(BilingualOffsetRouter.sourceOffset(forDisplayOffset: 6, map: map) == 3)
        #expect(BilingualOffsetRouter.sourceOffset(forDisplayOffset: 8, map: map) == 5)
    }

    @Test("source range: shifts past intervening synthetic")
    func sourceRangeShiftsPastSynthetic() {
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6),
            .source(sourceRange: 3..<6, displayRange: 6..<9)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 6, segments: segments)
        // A range entirely inside the first source segment is identity.
        let display0 = BilingualOffsetRouter.displayRange(forSourceRange: 0..<3, map: map)
        #expect(display0 == NSRange(location: 0, length: 3))
        // A range entirely inside the second source segment is shifted +3.
        let display1 = BilingualOffsetRouter.displayRange(forSourceRange: 3..<6, map: map)
        #expect(display1 == NSRange(location: 6, length: 3))
    }

    @Test("empty source range: empty display range")
    func emptySourceRange() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        let display = BilingualOffsetRouter.displayRange(forSourceRange: 50..<50, map: map)
        #expect(display.length == 0)
    }

    // MARK: - helpers

    @Test("isSynthetic: returns true inside synthetic ranges")
    func isSyntheticInsideSynthetic() {
        let segments: [BilingualDisplaySegmentMap.Segment] = [
            .source(sourceRange: 0..<3, displayRange: 0..<3),
            .synthetic(displayRange: 3..<6)
        ]
        let map = BilingualDisplaySegmentMap(sourceLength: 3, segments: segments)
        #expect(BilingualOffsetRouter.isSynthetic(displayOffset: 4, map: map))
        #expect(!BilingualOffsetRouter.isSynthetic(displayOffset: 1, map: map))
    }
}
