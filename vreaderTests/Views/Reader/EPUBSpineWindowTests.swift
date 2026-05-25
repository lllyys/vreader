// Purpose: Tests for EPUBSpineWindow — the pure value type modeling the
// contiguous range of EPUB spine items (chapters) currently materialized
// in the continuous-scroll WKWebView document (feature #71, WI-1).
//
// The window has a non-empty invariant (lo <= anchor <= hi, all in
// 0..<spineCount) per Gate-2 round-1 finding [L1]: a spineCount == 0 book
// has NO window (initial(anchor:spineCount:) returns nil); the container
// guards the empty case. Transitions are pure integer-range arithmetic —
// no UIKit, no I/O — so the whole window-management policy is unit-tested
// here before any WKWebView wiring (WI-4+) consumes it.
//
// @coordinates-with: EPUBSpineWindow.swift,
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-1)

import Testing
@testable import vreader

@Suite("EPUBSpineWindow")
struct EPUBSpineWindowTests {

    // MARK: - initial(anchor:spineCount:)

    @Test("empty book (spineCount 0) has no window")
    func initialEmptyBookIsNil() {
        #expect(EPUBSpineWindow.initial(anchor: 0, spineCount: 0) == nil)
    }

    @Test("single-chapter book windows 0...0 with anchor 0")
    func initialSingleChapter() throws {
        let window = try #require(EPUBSpineWindow.initial(anchor: 0, spineCount: 1))
        #expect(window.lo == 0)
        #expect(window.hi == 0)
        #expect(window.anchor == 0)
        #expect(window.canExtendForward == false)
        #expect(window.canExtendBackward == false)
    }

    @Test("multi-chapter book windows anchor...anchor initially")
    func initialMultiChapterIsSingletonAtAnchor() throws {
        let window = try #require(EPUBSpineWindow.initial(anchor: 3, spineCount: 10))
        #expect(window.lo == 3)
        #expect(window.hi == 3)
        #expect(window.anchor == 3)
        #expect(window.canExtendForward == true)
        #expect(window.canExtendBackward == true)
    }

    @Test("out-of-range anchor clamps into 0..<spineCount")
    func initialClampsAnchor() throws {
        let high = try #require(EPUBSpineWindow.initial(anchor: 99, spineCount: 5))
        #expect(high.anchor == 4)
        let low = try #require(EPUBSpineWindow.initial(anchor: -3, spineCount: 5))
        #expect(low.anchor == 0)
    }

    // MARK: - canExtend flags at the book edges

    @Test("anchor at last chapter cannot extend forward")
    func cannotExtendForwardAtLastChapter() throws {
        let window = try #require(EPUBSpineWindow.initial(anchor: 4, spineCount: 5))
        #expect(window.canExtendForward == false)
        #expect(window.canExtendBackward == true)
    }

    @Test("anchor at first chapter cannot extend backward")
    func cannotExtendBackwardAtFirstChapter() throws {
        let window = try #require(EPUBSpineWindow.initial(anchor: 0, spineCount: 5))
        #expect(window.canExtendBackward == false)
        #expect(window.canExtendForward == true)
    }

    // MARK: - extendForward / extendBackward

    @Test("extendForward grows hi by one")
    func extendForwardGrowsHi() throws {
        let window = try #require(EPUBSpineWindow.initial(anchor: 2, spineCount: 10))
        let extended = window.extendForward()
        #expect(extended.lo == 2)
        #expect(extended.hi == 3)
        #expect(extended.anchor == 2)
    }

    @Test("extendBackward grows lo by one")
    func extendBackwardGrowsLo() throws {
        let window = try #require(EPUBSpineWindow.initial(anchor: 5, spineCount: 10))
        let extended = window.extendBackward()
        #expect(extended.lo == 4)
        #expect(extended.hi == 5)
        #expect(extended.anchor == 5)
    }

    @Test("extendForward at the last chapter is a no-op (clamps)")
    func extendForwardClampsAtEnd() throws {
        let window = try #require(EPUBSpineWindow.initial(anchor: 4, spineCount: 5))
        let extended = window.extendForward()
        #expect(extended == window)
    }

    @Test("extendBackward at the first chapter is a no-op (clamps)")
    func extendBackwardClampsAtStart() throws {
        let window = try #require(EPUBSpineWindow.initial(anchor: 0, spineCount: 5))
        let extended = window.extendBackward()
        #expect(extended == window)
    }

    @Test("repeated extendForward fills toward the last chapter then stops")
    func repeatedExtendForwardFillsToEnd() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 0, spineCount: 3))
        window = window.extendForward() // 0...1
        window = window.extendForward() // 0...2
        window = window.extendForward() // clamp, still 0...2
        #expect(window.lo == 0)
        #expect(window.hi == 2)
        #expect(window.canExtendForward == false)
    }

    // MARK: - contains

    @Test("contains reports membership across lo...hi")
    func containsReportsMembership() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 5, spineCount: 10))
        window = window.extendForward().extendBackward() // 4...6
        #expect(window.contains(4))
        #expect(window.contains(5))
        #expect(window.contains(6))
        #expect(window.contains(3) == false)
        #expect(window.contains(7) == false)
    }

    // MARK: - evictFarFromAnchor(maxSpan:)

    @Test("eviction is a no-op when span is within maxSpan")
    func evictNoOpWithinMaxSpan() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 5, spineCount: 20))
        window = window.extendForward().extendBackward() // 4...6, span 3
        let evicted = window.evictFarFromAnchor(maxSpan: 3)
        #expect(evicted == window)
    }

    @Test("eviction trims the end farther from the anchor first")
    func evictTrimsFarEndFirst() throws {
        // Anchor 6, window 4...8 (span 5). Anchor is 2 from lo, 2 from hi —
        // symmetric. Extend forward once more: 4...9 (span 6), anchor 6 is
        // 2 from lo(4), 3 from hi(9): hi is farther, so eviction trims hi.
        var window = try #require(EPUBSpineWindow.initial(anchor: 6, spineCount: 20))
        window = window.extendBackward().extendBackward() // 4...6
            .extendForward().extendForward().extendForward() // 4...9
        #expect(window.lo == 4 && window.hi == 9) // span 6
        let evicted = window.evictFarFromAnchor(maxSpan: 5)
        #expect(evicted.hi == 8) // far end (hi) trimmed
        #expect(evicted.lo == 4)
        #expect(evicted.contains(6)) // anchor stays inside
    }

    @Test("eviction keeps the anchor inside the window")
    func evictKeepsAnchorInside() throws {
        // Build a wide window anchored near lo so eviction must trim hi
        // repeatedly without ever dropping the anchor.
        var window = try #require(EPUBSpineWindow.initial(anchor: 1, spineCount: 30))
        for _ in 0..<10 { window = window.extendForward() } // 1...11
        let evicted = window.evictFarFromAnchor(maxSpan: 3)
        #expect(evicted.contains(1))
        #expect(evicted.hi - evicted.lo + 1 <= 3)
        #expect(evicted.anchor == 1)
    }

    @Test("eviction trims lo when the anchor sits near hi")
    func evictTrimsLoWhenAnchorNearHi() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 11, spineCount: 30))
        for _ in 0..<10 { window = window.extendBackward() } // 1...11, anchor 11
        let evicted = window.evictFarFromAnchor(maxSpan: 3)
        #expect(evicted.contains(11))
        #expect(evicted.hi == 11)
        #expect(evicted.hi - evicted.lo + 1 <= 3)
    }

    @Test("eviction with maxSpan 1 collapses to the anchor")
    func evictMaxSpanOneCollapsesToAnchor() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 4, spineCount: 10))
        window = window.extendForward().extendBackward() // 3...5
        let evicted = window.evictFarFromAnchor(maxSpan: 1)
        #expect(evicted.lo == 4)
        #expect(evicted.hi == 4)
        #expect(evicted.anchor == 4)
    }

    @Test("symmetric window evicting by one trims hi (ties favor the start)")
    func evictSymmetricTieTrimsHi() throws {
        // Anchor 4, window 3...5 (span 3), anchor equidistant from both ends.
        // Reducing maxSpan to 2 forces exactly one trim; the `>=` tie-break
        // trims hi → 3...4. Pins the tie-break policy so a `>=`→`>` regression
        // is caught (a `>` would trim lo → 4...5 instead).
        var window = try #require(EPUBSpineWindow.initial(anchor: 4, spineCount: 10))
        window = window.extendForward().extendBackward() // 3...5
        let evicted = window.evictFarFromAnchor(maxSpan: 2)
        #expect(evicted.lo == 3)
        #expect(evicted.hi == 4)
        #expect(evicted.anchor == 4)
    }

    // MARK: - Equatable

    @Test("equality is full-state (same lo/hi/anchor and spineCount)")
    func equatable() throws {
        let a = try #require(EPUBSpineWindow.initial(anchor: 2, spineCount: 10)).extendForward()
        let b = try #require(EPUBSpineWindow.initial(anchor: 2, spineCount: 10)).extendForward()
        #expect(a == b)
    }

    @Test("windows with the same visible range but different spineCount are unequal")
    func equatableIncludesSpineCount() throws {
        // spineCount is load-bearing — it changes future canExtendForward /
        // edge-clamp behavior — so two windows with identical lo/hi/anchor
        // but different spineCount are intentionally NOT equal.
        let a = try #require(EPUBSpineWindow.initial(anchor: 2, spineCount: 10))
        let b = try #require(EPUBSpineWindow.initial(anchor: 2, spineCount: 20))
        #expect(a != b)
    }
}
