// Purpose: Tests for FoliateScrolledWindowMath — the pure windowing math for
// the Feature #73 Foliate scrolled continuous surface. Covers window
// computation (clamping at both ends, K>total, K=1, empty), offset/section
// mapping (boundaries, out-of-range, empty), the Gate-2 C1 intra-section
// fraction contract, and evict adjustment.

import Testing
import Foundation
@testable import vreader

@Suite("FoliateScrolledWindowMath")
struct FoliateScrolledWindowMathTests {

    // MARK: - window

    @Test("window centers on current with K=3 in the middle")
    func windowMiddle() {
        #expect(FoliateScrolledWindowMath.window(current: 4, total: 10, k: 3) == 3...5)
    }

    @Test("window clamps + shifts inward at the start, preserving size")
    func windowAtStart() {
        #expect(FoliateScrolledWindowMath.window(current: 0, total: 10, k: 3) == 0...2)
        #expect(FoliateScrolledWindowMath.window(current: 1, total: 10, k: 3) == 0...2)
    }

    @Test("window clamps + shifts inward at the end, preserving size")
    func windowAtEnd() {
        #expect(FoliateScrolledWindowMath.window(current: 9, total: 10, k: 3) == 7...9)
        #expect(FoliateScrolledWindowMath.window(current: 8, total: 10, k: 3) == 7...9)
    }

    @Test("window clamps size to total when K exceeds total")
    func windowKExceedsTotal() {
        #expect(FoliateScrolledWindowMath.window(current: 1, total: 2, k: 5) == 0...1)
        #expect(FoliateScrolledWindowMath.window(current: 0, total: 1, k: 3) == 0...0)
    }

    @Test("window K=1 is just current")
    func windowK1() {
        #expect(FoliateScrolledWindowMath.window(current: 5, total: 10, k: 1) == 5...5)
    }

    @Test("window nil for empty book or non-positive K")
    func windowDegenerate() {
        #expect(FoliateScrolledWindowMath.window(current: 0, total: 0, k: 3) == nil)
        #expect(FoliateScrolledWindowMath.window(current: 0, total: 5, k: 0) == nil)
    }

    @Test("window clamps an out-of-range current")
    func windowCurrentOutOfRange() {
        #expect(FoliateScrolledWindowMath.window(current: 99, total: 10, k: 3) == 7...9)
        #expect(FoliateScrolledWindowMath.window(current: -5, total: 10, k: 3) == 0...2)
    }

    // MARK: - offsetOfSection

    @Test("offsetOfSection sums the sizes before the index")
    func offsetOfSection() {
        let sizes = [100.0, 200.0, 300.0]
        #expect(FoliateScrolledWindowMath.offsetOfSection(0, mountedSizes: sizes) == 0)
        #expect(FoliateScrolledWindowMath.offsetOfSection(1, mountedSizes: sizes) == 100)
        #expect(FoliateScrolledWindowMath.offsetOfSection(2, mountedSizes: sizes) == 300)
        #expect(FoliateScrolledWindowMath.offsetOfSection(3, mountedSizes: sizes) == 600) // == total
    }

    @Test("offsetOfSection handles empty + clamps")
    func offsetOfSectionEdges() {
        #expect(FoliateScrolledWindowMath.offsetOfSection(0, mountedSizes: []) == 0)
        #expect(FoliateScrolledWindowMath.offsetOfSection(-1, mountedSizes: [10, 20]) == 0)
        #expect(FoliateScrolledWindowMath.offsetOfSection(99, mountedSizes: [10, 20]) == 30)
    }

    // MARK: - sectionAtOffset

    @Test("sectionAtOffset maps offsets to sections; boundary belongs to later")
    func sectionAtOffset() {
        let sizes = [100.0, 200.0, 300.0]
        #expect(FoliateScrolledWindowMath.sectionAtOffset(0, mountedSizes: sizes) == 0)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(50, mountedSizes: sizes) == 0)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(100, mountedSizes: sizes) == 1) // boundary → later
        #expect(FoliateScrolledWindowMath.sectionAtOffset(250, mountedSizes: sizes) == 1)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(300, mountedSizes: sizes) == 2)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(9999, mountedSizes: sizes) == 2) // beyond end → last
    }

    @Test("sectionAtOffset handles empty + negative")
    func sectionAtOffsetEdges() {
        #expect(FoliateScrolledWindowMath.sectionAtOffset(50, mountedSizes: []) == 0)
        #expect(FoliateScrolledWindowMath.sectionAtOffset(-10, mountedSizes: [100]) == 0)
    }

    // MARK: - intraSectionFraction (Gate-2 C1 contract)

    @Test("intraSectionFraction returns (index, intra) — NOT whole-book")
    func intraSectionFraction() {
        let sizes = [100.0, 200.0, 300.0]
        // start of section 1 → intra 0
        var r = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 100, mountedSizes: sizes)
        #expect(r.index == 1)
        #expect(abs(r.intra - 0) < 1e-9)
        // middle of section 1 (offset 200, section spans 100..300) → intra 0.5
        r = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 200, mountedSizes: sizes)
        #expect(r.index == 1)
        #expect(abs(r.intra - 0.5) < 1e-9)
        // near end of section 2 (offset 590, section spans 300..600) → intra ~0.9667
        r = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 590, mountedSizes: sizes)
        #expect(r.index == 2)
        #expect(abs(r.intra - (290.0 / 300.0)) < 1e-9)
    }

    @Test("intraSectionFraction clamps + handles zero-size + empty")
    func intraSectionFractionEdges() {
        #expect(FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 50, mountedSizes: []).index == 0)
        #expect(FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 50, mountedSizes: []).intra == 0)
        // zero-size section → intra 0, no NaN
        let r = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: 0, mountedSizes: [0, 100])
        #expect(r.index == 0)
        #expect(r.intra == 0)
        // negative offset clamps to (0, 0)
        let n = FoliateScrolledWindowMath.intraSectionFraction(scrollOffset: -10, mountedSizes: [100])
        #expect(n.index == 0)
        #expect(n.intra == 0)
    }

    // MARK: - offsetAdjustmentOnEvict

    @Test("offsetAdjustmentOnEvict sums evicted sizes, ignores negatives")
    func offsetAdjustmentOnEvict() {
        #expect(FoliateScrolledWindowMath.offsetAdjustmentOnEvict(evictedSizesAbove: [100, 200]) == 300)
        #expect(FoliateScrolledWindowMath.offsetAdjustmentOnEvict(evictedSizesAbove: []) == 0)
        #expect(FoliateScrolledWindowMath.offsetAdjustmentOnEvict(evictedSizesAbove: [100, -50]) == 100)
    }

    // MARK: - containerOffset (WI-1b anchor translation)

    @Test("containerOffset adds the mounted section's offset to the in-section rect top")
    func containerOffset() {
        let sizes = [100.0, 200.0, 300.0]
        // a rect at top=0 in section 0 → container offset 0 (no shift for the first)
        #expect(FoliateScrolledWindowMath.containerOffset(rectTopWithinSection: 0, mountedIndex: 0, mountedSizes: sizes) == 0)
        // a rect at top=50 in section 1 (starts at 100) → 150
        #expect(FoliateScrolledWindowMath.containerOffset(rectTopWithinSection: 50, mountedIndex: 1, mountedSizes: sizes) == 150)
        // a rect at top=10 in section 2 (starts at 300) → 310
        #expect(FoliateScrolledWindowMath.containerOffset(rectTopWithinSection: 10, mountedIndex: 2, mountedSizes: sizes) == 310)
    }

    // MARK: - Feature #76 WI-1: logical-offset conversion

    @Test("positive sign is identity (vertical-scroll / LTR — Feature #73 unchanged)")
    func logicalOffset_positiveSign_identity() {
        #expect(FoliateScrolledWindowMath.logicalOffset(rawOffset: 0, sign: 1) == 0)
        #expect(FoliateScrolledWindowMath.logicalOffset(rawOffset: 250, sign: 1) == 250)
        #expect(FoliateScrolledWindowMath.rawOffset(logicalOffset: 250, sign: 1) == 250)
    }

    @Test("negative sign maps RTL/vertical-rl negative scrollLeft to positive logical")
    func logicalOffset_negativeSign_mapsRTL() {
        #expect(FoliateScrolledWindowMath.logicalOffset(rawOffset: 0, sign: -1) == 0)
        #expect(FoliateScrolledWindowMath.logicalOffset(rawOffset: -250, sign: -1) == 250)
        #expect(FoliateScrolledWindowMath.logicalOffset(rawOffset: -1000, sign: -1) == 1000)
    }

    @Test("rawOffset is the inverse of logicalOffset")
    func rawOffset_invertsLogical() {
        for sign in [1, -1] {
            for x in [0.0, 137.0, 999.5] {
                let raw = FoliateScrolledWindowMath.rawOffset(logicalOffset: x, sign: sign)
                #expect(FoliateScrolledWindowMath.logicalOffset(rawOffset: raw, sign: sign) == x)
            }
        }
    }

    @Test("logical offsets feed the existing windowing math unchanged")
    func logicalOffset_feedsSectionMath() {
        // An RTL window scrolled to scrollLeft -150 over sizes [100,200,300]:
        // logical 150 falls in section 1, intra (150-100)/200 = 0.25.
        let sizes = [100.0, 200.0, 300.0]
        let logical = FoliateScrolledWindowMath.logicalOffset(rawOffset: -150, sign: -1)
        let (idx, intra) = FoliateScrolledWindowMath.intraSectionFraction(
            scrollOffset: logical, mountedSizes: sizes)
        #expect(idx == 1)
        #expect(intra == 0.25)
    }
}
