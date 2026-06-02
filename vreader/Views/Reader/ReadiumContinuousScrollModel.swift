// Purpose: Feature #83 WI-2 — the pure boundary-decision logic for Readium
// cross-chapter continuous scroll. Given the scroll geometry the WI-1 spike
// proved observable (`window.scrollY` == `scrollingElement.scrollTop`,
// `scrollHeight`, `innerHeight`) + the drag direction + the layout, decide
// whether to auto-advance to the next resource, retreat to the previous, or do
// nothing. Pure + value-typed → unit-tested without a render path.
//
// The signal shape mirrors what the boundary observer posts (Gate-2 audit):
// `(scrollY, scrollHeight, innerHeight, dragDelta, layout)`. `dragDelta > 0`
// means the finger moved UP (a scroll-DOWN intent); `< 0` means DOWN (scroll-up
// intent).
//
// @coordinates-with: ReadiumEPUBHost+ContinuousScroll.swift (the observer/wiring),
//   ReadiumEPUBHost+Navigation.swift (goForward/goBackward),
//   dev-docs/plans/20260602-feature-83-readium-continuous-scroll.md (WI-2)

import Foundation

/// The scroll geometry reported by the boundary observer.
struct ReadiumScrollGeometry: Equatable, Sendable {
    let scrollY: Double
    let scrollHeight: Double
    let innerHeight: Double
}

/// The decision the boundary signal resolves to.
enum ReadiumScrollBoundaryDecision: Equatable, Sendable {
    case advance   // at the bottom + dragging further down → goForward
    case retreat   // at the top + dragging further up → goBackward
    case none
}

enum ReadiumContinuousScrollModel {

    /// Px tolerance for "at the edge" (rounding + sub-pixel layout).
    static let edgeEpsilon: Double = 4
    /// Minimum finger travel to count as a deliberate boundary drag (vs a tap
    /// jitter).
    static let minDragDelta: Double = 10

    /// Resolve a boundary-drag signal. Only acts in `.scroll` layout.
    /// - `dragDelta` > 0: finger up → scroll-down intent (advance at bottom).
    /// - `dragDelta` < 0: finger down → scroll-up intent (retreat at top).
    static func decide(
        geometry g: ReadiumScrollGeometry,
        dragDelta: Double,
        layout: EPUBLayoutPreference
    ) -> ReadiumScrollBoundaryDecision {
        guard layout == .scroll else { return .none }
        guard abs(dragDelta) >= minDragDelta else { return .none }
        guard g.innerHeight > 0, g.scrollHeight > 0 else { return .none }

        let atBottom = (g.scrollY + g.innerHeight) >= (g.scrollHeight - edgeEpsilon)
        let atTop = g.scrollY <= edgeEpsilon

        if dragDelta > 0 && atBottom { return .advance }
        if dragDelta < 0 && atTop { return .retreat }
        return .none
    }
}
