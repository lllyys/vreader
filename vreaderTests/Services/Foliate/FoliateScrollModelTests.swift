// Tests for FoliateScrollModel (Feature #76 WI-1): the scrolled-mode scroll
// model derived from a section's computed `writing-mode`. This is the Swift
// source-of-truth the JS `getDirection`/ScrollModel mirrors — `{vertical, rtl}`
// was lossy (vertical-rl vs -lr indistinguishable; the axis sign can't be
// inferred), so the derivation is pinned here and the vendored paginator.js
// builds the same object.

import Testing
@testable import vreader

@Suite("FoliateScrollModel — scrolled-mode axis derivation (Feature #76 WI-1)")
struct FoliateScrollModelTests {

    @Test("horizontal-tb: scrolls vertically (scrollTop/height/top), sign +1")
    func horizontalWriting() {
        let m = FoliateScrollModel.scrolled(writingMode: "horizontal-tb")
        #expect(m.axis == .vertical)
        #expect(m.scrollProp == "scrollTop")
        #expect(m.sizeProp == "height")
        #expect(m.rectStartProp == "top")
        #expect(m.directionSign == 1)
    }

    @Test("vertical-rl: scrolls horizontally (scrollLeft/width/RIGHT), sign −1 (WebKit negative scrollLeft)")
    func verticalRL() {
        let m = FoliateScrollModel.scrolled(writingMode: "vertical-rl")
        #expect(m.axis == .horizontal)
        #expect(m.scrollProp == "scrollLeft")
        #expect(m.sizeProp == "width")
        // Feature #76 WI-3: the logical reading-order start is the section's RIGHT
        // edge (reading starts at the right; scrollLeft 0 there, negative leftward).
        #expect(m.rectStartProp == "right")
        #expect(m.directionSign == -1)
    }

    @Test("vertical-lr: scrolls horizontally, sign +1 (left-to-right column flow)")
    func verticalLR() {
        let m = FoliateScrollModel.scrolled(writingMode: "vertical-lr")
        #expect(m.axis == .horizontal)
        #expect(m.scrollProp == "scrollLeft")
        #expect(m.sizeProp == "width")
        #expect(m.rectStartProp == "left")
        #expect(m.directionSign == 1)
    }

    @Test("unknown / empty writing-mode falls back to the horizontal-tb model (safe default)")
    func unknownFallsBackToHorizontalTB() {
        for raw in ["", "sideways-rl", "garbage", "horizontal-bt"] {
            let m = FoliateScrollModel.scrolled(writingMode: raw)
            #expect(m.axis == .vertical, "\(raw) should default to vertical-scroll")
            #expect(m.scrollProp == "scrollTop")
            #expect(m.directionSign == 1)
        }
    }

    @Test("directionSign feeds the existing logical-offset seam (#1322) consistently")
    func signFeedsLogicalOffset() {
        // vertical-rl: a raw negative scrollLeft becomes a positive logical offset.
        let rl = FoliateScrollModel.scrolled(writingMode: "vertical-rl")
        #expect(FoliateScrolledWindowMath.logicalOffset(rawOffset: -300, sign: rl.directionSign) == 300)
        // horizontal-tb: raw == logical (Feature #73 path byte-unchanged).
        let tb = FoliateScrollModel.scrolled(writingMode: "horizontal-tb")
        #expect(FoliateScrolledWindowMath.logicalOffset(rawOffset: 300, sign: tb.directionSign) == 300)
    }

    @Test("isVertical convenience matches the axis")
    func isVerticalConvenience() {
        #expect(FoliateScrollModel.scrolled(writingMode: "vertical-rl").isVerticalWriting)
        #expect(FoliateScrollModel.scrolled(writingMode: "vertical-lr").isVerticalWriting)
        #expect(!FoliateScrollModel.scrolled(writingMode: "horizontal-tb").isVerticalWriting)
    }
}
