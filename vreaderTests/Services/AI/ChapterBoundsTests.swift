// Purpose: Tests for ChapterBounds — the UTF-16 character span of one
// chapter, used to bound a Chapter-scoped AI summary (feature #69 WI-1).
// Pins value-type equality and field preservation.

import Testing
@testable import vreader

@Suite("ChapterBounds")
struct ChapterBoundsTests {

    // MARK: - Field preservation

    @Test func constructedBoundsPreserveFields() {
        let bounds = ChapterBounds(startUTF16: 120, endUTF16: 4500)
        #expect(bounds.startUTF16 == 120)
        #expect(bounds.endUTF16 == 4500)
    }

    @Test func zeroLengthBoundsArePreserved() {
        let bounds = ChapterBounds(startUTF16: 800, endUTF16: 800)
        #expect(bounds.startUTF16 == 800)
        #expect(bounds.endUTF16 == 800)
    }

    @Test func preambleBoundsStartAtZero() {
        let bounds = ChapterBounds(startUTF16: 0, endUTF16: 312)
        #expect(bounds.startUTF16 == 0)
        #expect(bounds.endUTF16 == 312)
    }

    // MARK: - Span invariant (init clamps invalid input)

    @Test func negativeStartIsClampedToZero() {
        let bounds = ChapterBounds(startUTF16: -50, endUTF16: 400)
        #expect(bounds.startUTF16 == 0)
        #expect(bounds.endUTF16 == 400)
    }

    @Test func endBelowStartIsRaisedToStart() {
        // A reversed span collapses to a zero-length span at the start.
        let bounds = ChapterBounds(startUTF16: 900, endUTF16: 200)
        #expect(bounds.startUTF16 == 900)
        #expect(bounds.endUTF16 == 900)
    }

    @Test func negativeStartWithNegativeEndCollapsesToZero() {
        // start clamps to 0, then end (-10 < 0) is raised to 0.
        let bounds = ChapterBounds(startUTF16: -100, endUTF16: -10)
        #expect(bounds.startUTF16 == 0)
        #expect(bounds.endUTF16 == 0)
    }

    @Test func invariantHoldsAfterClamping() {
        // Whatever the input, end is never below start and start is never negative.
        for (rawStart, rawEnd) in [(-5, -9), (10, 3), (-1, 7), (0, 0), (50, 50)] {
            let bounds = ChapterBounds(startUTF16: rawStart, endUTF16: rawEnd)
            #expect(bounds.startUTF16 >= 0)
            #expect(bounds.endUTF16 >= bounds.startUTF16)
        }
    }

    // MARK: - Equatable

    @Test func equalBoundsCompareEqual() {
        let a = ChapterBounds(startUTF16: 10, endUTF16: 99)
        let b = ChapterBounds(startUTF16: 10, endUTF16: 99)
        #expect(a == b)
    }

    @Test func differentStartCompareUnequal() {
        let a = ChapterBounds(startUTF16: 10, endUTF16: 99)
        let b = ChapterBounds(startUTF16: 11, endUTF16: 99)
        #expect(a != b)
    }

    @Test func differentEndCompareUnequal() {
        let a = ChapterBounds(startUTF16: 10, endUTF16: 99)
        let b = ChapterBounds(startUTF16: 10, endUTF16: 100)
        #expect(a != b)
    }

    // MARK: - Sendable

    @Test func boundsAreSendable() {
        let bounds: any Sendable = ChapterBounds(startUTF16: 0, endUTF16: 1)
        #expect(bounds is ChapterBounds)
    }
}
