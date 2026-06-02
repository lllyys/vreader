// Purpose: Feature #83 WI-2 — pin the boundary-decision logic for Readium
// cross-chapter continuous scroll. The geometry shape is what the WI-1 spike
// proved observable on device (window.scrollY / scrollHeight / innerHeight).
//
// @coordinates-with: vreader/Views/Reader/ReadiumContinuousScrollModel.swift

import Testing
@testable import vreader

@Suite("Feature #83 — ReadiumContinuousScrollModel")
struct ReadiumContinuousScrollModelTests {

    private func geo(_ y: Double, _ h: Double = 4680, _ inner: Double = 874) -> ReadiumScrollGeometry {
        ReadiumScrollGeometry(scrollY: y, scrollHeight: h, innerHeight: inner)
    }

    @Test func atBottom_dragDown_advances() {
        // bottom = scrollHeight - innerHeight = 4680 - 874 = 3806
        let d = ReadiumContinuousScrollModel.decide(geometry: geo(3806), dragDelta: 30, layout: .scroll)
        #expect(d == .advance)
    }

    @Test func atTop_dragUp_retreats() {
        let d = ReadiumContinuousScrollModel.decide(geometry: geo(0), dragDelta: -30, layout: .scroll)
        #expect(d == .retreat)
    }

    @Test func midResource_none() {
        let d = ReadiumContinuousScrollModel.decide(geometry: geo(1908), dragDelta: 30, layout: .scroll)
        #expect(d == .none)
    }

    @Test func atBottom_dragUp_wrongDirection_none() {
        // At the bottom but dragging DOWN (scroll-up intent) → not an advance.
        let d = ReadiumContinuousScrollModel.decide(geometry: geo(3806), dragDelta: -30, layout: .scroll)
        #expect(d == .none)
    }

    @Test func atTop_dragDown_wrongDirection_none() {
        let d = ReadiumContinuousScrollModel.decide(geometry: geo(0), dragDelta: 30, layout: .scroll)
        #expect(d == .none)
    }

    @Test func smallDrag_none() {
        let d = ReadiumContinuousScrollModel.decide(geometry: geo(3806), dragDelta: 4, layout: .scroll)
        #expect(d == .none)
    }

    @Test func pagedLayout_none() {
        let d = ReadiumContinuousScrollModel.decide(geometry: geo(3806), dragDelta: 30, layout: .paged)
        #expect(d == .none)
    }

    @Test func edgeTolerance_nearBottom_advances() {
        // 3 px short of the exact bottom is within edgeEpsilon (4).
        let d = ReadiumContinuousScrollModel.decide(geometry: geo(3803), dragDelta: 30, layout: .scroll)
        #expect(d == .advance)
    }

    @Test func zeroGeometry_none() {
        let d = ReadiumContinuousScrollModel.decide(
            geometry: ReadiumScrollGeometry(scrollY: 0, scrollHeight: 0, innerHeight: 0),
            dragDelta: 30, layout: .scroll)
        #expect(d == .none)
    }
}
