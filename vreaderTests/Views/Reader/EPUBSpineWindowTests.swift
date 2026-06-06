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

    // MARK: - evictTrailing(forward:maxSpan:)

    @Test("eviction is a no-op when span is within maxSpan (forward)")
    func evictTrailingNoOpForward() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 5, spineCount: 20))
        window = window.extendForward().extendBackward() // 4...6, anchor 5, span 3
        #expect(window.evictTrailing(forward: true, maxSpan: 3) == window)
    }

    @Test("eviction is a no-op when span is within maxSpan (backward)")
    func evictTrailingNoOpBackward() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 5, spineCount: 20))
        window = window.extendForward().extendBackward() // 4...6
        #expect(window.evictTrailing(forward: false, maxSpan: 3) == window)
    }

    @Test("forward eviction trims the trailing (lo) end, keeping the leading (hi) section")
    func evictTrailingForwardTrimsLo() throws {
        // Window 1...4 anchored at 2 — the Bug #327 lagging-anchor case: the
        // reader is at the window bottom while the topmost-visible section is 2.
        var window = try #require(EPUBSpineWindow.initial(anchor: 2, spineCount: 20))
        window = window.extendBackward()                  // 1...2
            .extendForward().extendForward()              // 1...4, anchor 2
        #expect(window.lo == 1 && window.hi == 4)
        let evicted = window.evictTrailing(forward: true, maxSpan: 3)
        #expect(evicted.lo == 2)        // trailing (lo) trimmed
        #expect(evicted.hi == 4)        // leading (hi) section KEPT — reader can reach it
        #expect(evicted.contains(2))    // anchor stays inside
    }

    @Test("backward eviction trims the trailing (hi) end, keeping the leading (lo) section")
    func evictTrailingBackwardTrimsHi() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 3, spineCount: 20))
        window = window.extendForward()                   // 3...4
            .extendBackward().extendBackward()            // 1...4, anchor 3
        #expect(window.lo == 1 && window.hi == 4)
        let evicted = window.evictTrailing(forward: false, maxSpan: 3)
        #expect(evicted.hi == 3)        // trailing (hi) trimmed
        #expect(evicted.lo == 1)        // leading (lo) section KEPT
        #expect(evicted.contains(3))    // anchor stays inside
    }

    @Test("forward eviction never trims the anchor or ahead — window stays > maxSpan when the anchor lags near lo")
    func evictTrailingForwardKeepsAnchorAndAhead() throws {
        // Anchor 1 == lo, window 1...6 (span 6). Forward eviction can only trim
        // BEHIND the anchor (lo < anchor); lo == anchor, so nothing is trimmed and
        // the window is left LARGER than maxSpan. This is the deadlock-break: the
        // chapters ahead of the reader are never evicted out from under them; the
        // window shrinks to maxSpan naturally as the anchor advances.
        var window = try #require(EPUBSpineWindow.initial(anchor: 1, spineCount: 30))
        for _ in 0..<5 { window = window.extendForward() } // 1...6, anchor 1
        #expect(window.evictTrailing(forward: true, maxSpan: 3) == window)
    }

    @Test("forward eviction trims down to maxSpan once the anchor has advanced")
    func evictTrailingForwardTrimsOnceAnchorAdvanced() throws {
        // Same wide window 1...6 but re-anchored at 4 (reader moved forward). The
        // trailing chapters behind the anchor are now trimmable: [1,6] → [4,6].
        var window = try #require(EPUBSpineWindow.initial(anchor: 1, spineCount: 30))
        for _ in 0..<5 { window = window.extendForward() } // 1...6
        window = window.reanchored(to: 4)
        let evicted = window.evictTrailing(forward: true, maxSpan: 3)
        #expect(evicted.lo == 4 && evicted.hi == 6)
        #expect(evicted.contains(4))
    }

    @Test("backward eviction never trims the anchor or behind when the anchor lags near hi")
    func evictTrailingBackwardKeepsAnchorAndBehind() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 6, spineCount: 30))
        for _ in 0..<5 { window = window.extendBackward() } // 1...6, anchor 6
        #expect(window.evictTrailing(forward: false, maxSpan: 3) == window)
    }

    @Test("maxSpan clamps to ≥ 1 — even then the leading section survives")
    func evictTrailingMaxSpanClampsToOne() throws {
        var window = try #require(EPUBSpineWindow.initial(anchor: 4, spineCount: 10))
        window = window.extendForward().extendBackward() // 3...5, anchor 4
        // forward, maxSpan 0 → cap 1: trim lo while span>1 && lo<anchor: 3→4 →
        // [4,5]. The anchor + the leading section 5 are retained (directional
        // eviction never drops the chapter ahead of the reader).
        let evicted = window.evictTrailing(forward: true, maxSpan: 0)
        #expect(evicted.lo == 4 && evicted.hi == 5)
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

    // MARK: - reanchored (Feature #71 WI-4)

    @Test("reanchored moves the anchor inside the window without changing the range")
    func reanchoredMovesAnchorKeepsRange() throws {
        // Window 0...4 anchored at 0; re-anchor to the reading chapter 3.
        var w = try #require(EPUBSpineWindow.initial(anchor: 0, spineCount: 10))
        for _ in 0..<4 { w = w.extendForward() } // 0...4, anchor 0
        let r = w.reanchored(to: 3)
        #expect(r.lo == 0 && r.hi == 4)        // materialized range unchanged
        #expect(r.anchor == 3)                 // anchor moved
        // Forward eviction now trims behind (toward lo), keeping the reading chapter.
        let evicted = r.evictTrailing(forward: true, maxSpan: 3)
        #expect(evicted.contains(3))
        #expect(evicted.lo > 0)                // far-behind chapters trimmed
    }

    @Test("reanchored clamps an out-of-window anchor into lo...hi")
    func reanchoredClampsOutOfWindow() throws {
        var w = try #require(EPUBSpineWindow.initial(anchor: 2, spineCount: 10))
        w = w.extendForward() // 2...3, anchor 2
        #expect(w.reanchored(to: 9).anchor == 3)   // clamps up to hi
        #expect(w.reanchored(to: 0).anchor == 2)   // clamps down to lo
    }

    @Test("reanchored to the current anchor returns an equal window")
    func reanchoredToSameAnchorIsNoOp() throws {
        let w = try #require(EPUBSpineWindow.initial(anchor: 2, spineCount: 10))
        #expect(w.reanchored(to: 2) == w)
    }
}
