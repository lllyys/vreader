// Purpose: Feature #56 WI-12 — pin the TXT/MD source↔display offset
// map. The map records ordered display ranges each tagged as either
// `.source(sourceRange:)` (a slice of the source text appearing
// verbatim in the display) or `.synthetic` (a translation block
// injected between source paragraphs). The TXT/MD container routes
// every display-offset touchpoint (selection, search/highlight nav,
// persisted-highlight hit-test, TTS highlight + auto-scroll) through
// this map, and offset-routing's correctness gates the rest of the
// bilingual TXT/MD slice.
//
// @coordinates-with: BilingualDisplaySegmentMap.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12)

import Testing
@testable import vreader

@Suite("Feature #56 WI-12 — BilingualDisplaySegmentMap")
struct BilingualDisplaySegmentMapTests {

    // MARK: - identity map (bilingual off)

    @Test("identity map sourceOffset(forDisplayOffset:) is pass-through within bounds")
    func identitySourceOffsetWithinBounds() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        #expect(map.sourceOffset(forDisplayOffset: 0) == 0)
        #expect(map.sourceOffset(forDisplayOffset: 50) == 50)
        #expect(map.sourceOffset(forDisplayOffset: 99) == 99)
    }

    @Test("identity map displayOffset(forSourceOffset:) is pass-through within bounds")
    func identityDisplayOffsetWithinBounds() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        #expect(map.displayOffset(forSourceOffset: 0) == 0)
        #expect(map.displayOffset(forSourceOffset: 50) == 50)
        #expect(map.displayOffset(forSourceOffset: 99) == 99)
    }

    @Test("identity map sourceOffset(forDisplayOffset:) returns nil past display end")
    func identitySourceOffsetPastDisplayEnd() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        // The display end is 100 (the half-open upper bound) — beyond
        // that there is no source location.
        #expect(map.sourceOffset(forDisplayOffset: 100) == nil)
        #expect(map.sourceOffset(forDisplayOffset: 1000) == nil)
    }

    @Test("identity map sourceOffset(forDisplayOffset:) returns nil for negative")
    func identitySourceOffsetNegative() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        #expect(map.sourceOffset(forDisplayOffset: -1) == nil)
    }

    @Test("identity map of zero-length source has empty mapping")
    func identityEmpty() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 0)
        #expect(map.sourceOffset(forDisplayOffset: 0) == nil)
        #expect(map.displayOffset(forSourceOffset: 0) == 0)
    }

    @Test("identity map displayLength == sourceLength")
    func identityDisplayLengthEqualsSource() {
        let map = BilingualDisplaySegmentMap.identity(sourceLength: 100)
        #expect(map.displayLength == 100)
        #expect(map.sourceLength == 100)
    }

    // MARK: - interleaved map (bilingual on)

    /// A two-paragraph source: paragraph A occupies source [0, 10),
    /// paragraph B occupies source [10, 20). Translation A is 5 chars
    /// long; translation B is 7 chars long. The display layout the
    /// renderer produces is:
    ///
    ///   [0, 10)   source paragraph A (10 chars)
    ///   [10, 15)  synthetic translation A (5 chars)
    ///   [15, 25)  source paragraph B (10 chars)
    ///   [25, 32)  synthetic translation B (7 chars)
    ///
    /// `displayLength == 32`, `sourceLength == 20`.
    private static func twoParagraphMap() -> BilingualDisplaySegmentMap {
        BilingualDisplaySegmentMap(
            sourceLength: 20,
            segments: [
                .source(sourceRange: 0..<10, displayRange: 0..<10),
                .synthetic(displayRange: 10..<15),
                .source(sourceRange: 10..<20, displayRange: 15..<25),
                .synthetic(displayRange: 25..<32)
            ]
        )
    }

    @Test("interleaved sourceOffset(forDisplayOffset:) inside paragraph A")
    func interleavedSourceInsideParagraphA() {
        let map = Self.twoParagraphMap()
        #expect(map.sourceOffset(forDisplayOffset: 0) == 0)
        #expect(map.sourceOffset(forDisplayOffset: 5) == 5)
        #expect(map.sourceOffset(forDisplayOffset: 9) == 9)
    }

    @Test("interleaved sourceOffset(forDisplayOffset:) inside synthetic is nil")
    func interleavedSourceInsideSynthetic() {
        let map = Self.twoParagraphMap()
        // Display offsets 10..<15 fall in the synthetic translation
        // run — they have no source position.
        #expect(map.sourceOffset(forDisplayOffset: 10) == nil)
        #expect(map.sourceOffset(forDisplayOffset: 12) == nil)
        #expect(map.sourceOffset(forDisplayOffset: 14) == nil)
    }

    @Test("interleaved sourceOffset(forDisplayOffset:) inside paragraph B is shifted")
    func interleavedSourceInsideParagraphB() {
        let map = Self.twoParagraphMap()
        // Display offset 15 = first char of paragraph B = source 10.
        // Display offset 24 = last char of paragraph B = source 19.
        #expect(map.sourceOffset(forDisplayOffset: 15) == 10)
        #expect(map.sourceOffset(forDisplayOffset: 20) == 15)
        #expect(map.sourceOffset(forDisplayOffset: 24) == 19)
    }

    @Test("interleaved sourceOffset(forDisplayOffset:) inside synthetic-B is nil")
    func interleavedSourceInsideTrailingSynthetic() {
        let map = Self.twoParagraphMap()
        #expect(map.sourceOffset(forDisplayOffset: 25) == nil)
        #expect(map.sourceOffset(forDisplayOffset: 31) == nil)
    }

    @Test("interleaved sourceOffset(forDisplayOffset:) past display end is nil")
    func interleavedSourcePastEnd() {
        let map = Self.twoParagraphMap()
        #expect(map.sourceOffset(forDisplayOffset: 32) == nil)
        #expect(map.sourceOffset(forDisplayOffset: 1000) == nil)
    }

    @Test("interleaved displayOffset(forSourceOffset:) at paragraph A boundaries")
    func interleavedDisplayParagraphA() {
        let map = Self.twoParagraphMap()
        #expect(map.displayOffset(forSourceOffset: 0) == 0)
        #expect(map.displayOffset(forSourceOffset: 5) == 5)
        #expect(map.displayOffset(forSourceOffset: 9) == 9)
    }

    @Test("interleaved displayOffset(forSourceOffset:) at paragraph B boundaries is shifted")
    func interleavedDisplayParagraphB() {
        let map = Self.twoParagraphMap()
        // Source offset 10 lands at the start of paragraph B in display,
        // which is the display offset 15 (past synthetic A).
        #expect(map.displayOffset(forSourceOffset: 10) == 15)
        #expect(map.displayOffset(forSourceOffset: 15) == 20)
        #expect(map.displayOffset(forSourceOffset: 19) == 24)
    }

    @Test("interleaved displayOffset(forSourceOffset:) at source end == past-paragraph-B")
    func interleavedDisplaySourceEnd() {
        let map = Self.twoParagraphMap()
        // Source offset 20 == source end. The renderer convention is
        // that the end maps to the position right after paragraph B
        // ends (display 25) — selection end-points land there.
        #expect(map.displayOffset(forSourceOffset: 20) == 25)
    }

    @Test("interleaved displayLength counts source + synthetic")
    func interleavedDisplayLength() {
        let map = Self.twoParagraphMap()
        #expect(map.displayLength == 32)
        #expect(map.sourceLength == 20)
    }

    @Test("displayOffset(forSourceOffset:) clamps a past-end source offset to display end")
    func displayOffsetPastSourceEndClampsToDisplayEnd() {
        let map = Self.twoParagraphMap()
        #expect(map.displayOffset(forSourceOffset: 1000) == map.displayLength)
    }

    @Test("displayOffset(forSourceOffset:) clamps a negative source offset to 0")
    func displayOffsetNegativeClampsToZero() {
        let map = Self.twoParagraphMap()
        #expect(map.displayOffset(forSourceOffset: -1) == 0)
    }

    // MARK: - round-trip invariant for source positions

    @Test("source→display→source round-trip is identity for every source offset")
    func roundTripSourcePositions() {
        let map = Self.twoParagraphMap()
        for source in 0..<map.sourceLength {
            let display = map.displayOffset(forSourceOffset: source)
            let roundTrip = map.sourceOffset(forDisplayOffset: display)
            #expect(roundTrip == source, "source=\(source) display=\(display) round-trip=\(String(describing: roundTrip))")
        }
    }

    // MARK: - equality + sendable

    @Test("two identity maps over equal lengths are equal")
    func identityEquality() {
        let a = BilingualDisplaySegmentMap.identity(sourceLength: 42)
        let b = BilingualDisplaySegmentMap.identity(sourceLength: 42)
        #expect(a == b)
    }

    @Test("two interleaved maps over equal segments are equal")
    func interleavedEquality() {
        let a = Self.twoParagraphMap()
        let b = Self.twoParagraphMap()
        #expect(a == b)
    }

    // MARK: - single-paragraph + single-source edge cases

    @Test("single source segment with no synthetic = identity-shape map")
    func singleSourceOnly() {
        let map = BilingualDisplaySegmentMap(
            sourceLength: 20,
            segments: [.source(sourceRange: 0..<20, displayRange: 0..<20)]
        )
        #expect(map.displayLength == 20)
        #expect(map.sourceOffset(forDisplayOffset: 10) == 10)
        #expect(map.displayOffset(forSourceOffset: 10) == 10)
    }
}
