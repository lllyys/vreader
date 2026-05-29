// Purpose: Cross-format pure hit-test tolerance for tap-on-highlight
// (Bug #287 / GH #1268). The native reader bridges (TXT/MD via
// `TextHighlightHitTester` + the bridge coordinators, PDF via
// `PDFHighlightTapResolver`) previously hit-tested a tap against the EXACT
// glyph/annotation extent of a highlight — a ~17-22pt line, well below
// Apple's 44pt HIG minimum touch target. A near-miss tap fell through to
// the page-turn / chrome-toggle router instead of opening the highlight
// popover, making tap-to-edit unreliable.
//
// This helper expands each highlight's bounding rect toward the 44pt
// minimum and answers "which highlight (if any) does this point hit,
// accounting for slop?". The slop is bounded and is ZERO for an extent
// that already meets the minimum, so a tall block highlight does not
// become "sticky" and capture legitimate page-turn taps just outside it.
// On overlapping expanded bands the nearest-center candidate wins, giving
// a deterministic tiebreak.
//
// Kept pure (no UIKit view dependency) so it is fully unit-testable and
// reusable by every native format. EPUB/Foliate apply the analogous
// tolerance in their own (web-rendered) hit paths; see EPUBHighlightJS.swift.
//
// @coordinates-with: TextHighlightHitTester.swift,
//   TXTTextViewBridgeCoordinator.swift, TXTChunkedReaderBridge.swift,
//   PDFHighlightTapResolver.swift, PDFViewBridge.swift

#if canImport(UIKit)
import Foundation
import CoreGraphics

enum HighlightHitTolerance {
    /// Apple Human Interface Guidelines minimum touch-target dimension.
    static let minimumTouchTarget: CGFloat = 44

    /// Per-side slop for an extent of `dimension` points: enough to reach
    /// `minimumTouchTarget` total when split across both sides, clamped at
    /// zero (an extent already at/above the minimum gets no expansion).
    static func slop(forExtentDimension dimension: CGFloat) -> CGFloat {
        let deficit = minimumTouchTarget - dimension
        guard deficit > 0 else { return 0 }
        return deficit / 2
    }

    /// Returns the id of the candidate whose slop-expanded rect contains
    /// `point`, choosing the candidate whose center is nearest `point` when
    /// several expanded rects overlap. Each rect is expanded independently
    /// by its own width/height-derived slop, so a tall rect is not
    /// over-expanded. Returns nil when no expanded rect contains the point
    /// (caller then routes the tap to the page-turn / chrome path).
    static func nearestHit(
        point: CGPoint,
        candidates: [(id: UUID, rect: CGRect)]
    ) -> UUID? {
        var bestID: UUID?
        var bestDistanceSquared = CGFloat.greatestFiniteMagnitude
        for candidate in candidates {
            let rect = candidate.rect
            // Skip zero/negative-area rects: a malformed zero-area rect would
            // otherwise be inflated into a full 44x44 tappable region.
            guard rect.width > 0, rect.height > 0 else { continue }
            let expanded = rect.insetBy(
                dx: -slop(forExtentDimension: rect.width),
                dy: -slop(forExtentDimension: rect.height)
            )
            // Inclusive containment on all four edges. `CGRect.contains` is
            // upper-exclusive on the max edge, which would drop a tap landing
            // exactly on the bottom/right of the expanded band — the precise
            // near-miss case this tolerance exists to catch.
            guard point.x >= expanded.minX, point.x <= expanded.maxX,
                  point.y >= expanded.minY, point.y <= expanded.maxY
            else { continue }
            let cx = rect.midX
            let cy = rect.midY
            let dx = point.x - cx
            let dy = point.y - cy
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                bestID = candidate.id
            }
        }
        return bestID
    }
}
#endif
