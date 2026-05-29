// Purpose: Tests for `HighlightHitTolerance` (Bug #287 / GH #1268) — the
// cross-format pure helper that expands each highlight's glyph/annotation
// extent toward Apple's 44pt minimum touch target so a near-miss tap still
// resolves to the highlight (and is absorbed) instead of falling through to
// the page-turn / chrome-toggle router.
//
// Covers: exact-on-glyph hit, within-slop hit, beyond-slop miss, the 44pt
// boundary, slop never expanding an already-tall extent (no "sticky"
// page-turn capture), nearest-center tiebreak for overlapping highlights,
// per-rect slop, and empty input.
//
// @coordinates-with: HighlightHitTolerance.swift, PDFHighlightTapResolver.swift,
//   TXTTextViewBridgeCoordinator.swift, TXTChunkedReaderBridge.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("HighlightHitTolerance — 44pt minimum touch target (Bug #287)")
struct HighlightHitToleranceTests {

    private let id1 = UUID()
    private let id2 = UUID()

    // MARK: - slop(forExtentDimension:)

    @Test
    func slop_thinLine_expandsTowardMinimumTarget() {
        // A 17pt line is below the 44pt HIG minimum: slop per side is
        // (44 - 17) / 2 = 13.5pt, so the effective touch height is ~44pt.
        let slop = HighlightHitTolerance.slop(forExtentDimension: 17)
        #expect(abs(slop - 13.5) < 0.001)
    }

    @Test
    func slop_extentAlreadyAtMinimum_isZero() {
        // A 44pt extent already meets the target — no expansion, so legit
        // page-turn zones adjacent to a tall highlight are not captured.
        #expect(HighlightHitTolerance.slop(forExtentDimension: 44) == 0)
    }

    @Test
    func slop_extentLargerThanMinimum_isZero() {
        // Never negative: a tall block highlight gets zero slop.
        #expect(HighlightHitTolerance.slop(forExtentDimension: 120) == 0)
    }

    @Test
    func minimumTouchTarget_isAppleHIGValue() {
        #expect(HighlightHitTolerance.minimumTouchTarget == 44)
    }

    // MARK: - nearestHit(point:candidates:)

    @Test
    func nearestHit_pointExactlyOnGlyph_returnsThatID() {
        let rect = CGRect(x: 50, y: 100, width: 200, height: 17)
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 100, y: 108),  // inside the un-expanded rect
            candidates: [(id1, rect)]
        )
        #expect(result == id1)
    }

    @Test
    func nearestHit_pointWithinSlop_resolvesAndAbsorbs() {
        // A 17pt line at y∈[100,117]. Slop is 13.5pt, so the expanded
        // vertical band is [86.5, 130.5]. A tap at y=125 is OUTSIDE the
        // glyph but inside the slop band → must resolve (and the caller
        // absorbs the tap rather than turning the page).
        let rect = CGRect(x: 50, y: 100, width: 200, height: 17)
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 100, y: 125),
            candidates: [(id1, rect)]
        )
        #expect(result == id1)
    }

    @Test
    func nearestHit_pointBeyondSlop_missesSoCallerRoutesToPageTurn() {
        // Same 17pt line; expanded band tops out at y=130.5. A tap at
        // y=140 is beyond the slop → miss, so the caller falls through to
        // the page-turn / chrome router.
        let rect = CGRect(x: 50, y: 100, width: 200, height: 17)
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 100, y: 140),
            candidates: [(id1, rect)]
        )
        #expect(result == nil)
    }

    @Test
    func nearestHit_atExactSlopBoundary_isInclusive() {
        // Boundary: the bottom edge of the expanded band (130.5) is a hit.
        let rect = CGRect(x: 50, y: 100, width: 200, height: 17)
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 100, y: 130.5),
            candidates: [(id1, rect)]
        )
        #expect(result == id1)
    }

    @Test
    func nearestHit_tallExtent_noSlopSoAdjacentTapMisses() {
        // A 60pt block highlight gets zero slop. A tap 5pt below it must
        // MISS so the page-turn still works just outside a tall highlight.
        let rect = CGRect(x: 50, y: 100, width: 200, height: 60)  // [100,160]
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 100, y: 162),
            candidates: [(id1, rect)]
        )
        #expect(result == nil)
    }

    @Test
    func nearestHit_overlappingExpandedBands_picksNearestCenter() {
        // Two thin highlights whose slop bands both cover the tap point.
        // id1 centered at y=108.5, id2 centered at y=140.5. A tap at
        // y=125 is nearer id2's... no — |125-108.5|=16.5, |125-140.5|=15.5,
        // so id2 is nearer. Deterministic nearest-center tiebreak.
        let rect1 = CGRect(x: 50, y: 100, width: 200, height: 17)  // center 108.5
        let rect2 = CGRect(x: 50, y: 132, width: 200, height: 17)  // center 140.5
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 100, y: 125),
            candidates: [(id1, rect1), (id2, rect2)]
        )
        #expect(result == id2)
    }

    @Test
    func nearestHit_horizontalSlopAlsoApplied() {
        // A narrow 10pt-wide highlight gets horizontal slop too — a tap
        // just left of it within the band still resolves.
        let rect = CGRect(x: 100, y: 100, width: 10, height: 17)
        // width 10 → horizontal slop (44-10)/2 = 17; band x∈[83,127].
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 90, y: 108),
            candidates: [(id1, rect)]
        )
        #expect(result == id1)
    }

    @Test
    func nearestHit_emptyCandidates_returnsNil() {
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 100, y: 100),
            candidates: []
        )
        #expect(result == nil)
    }

    @Test
    func nearestHit_zeroAreaRect_isNotInflatedIntoTouchTarget() {
        // Bug #287 audit (L1): a zero-area candidate rect must be skipped, not
        // inflated into a full 44x44 tappable region.
        let zero = CGRect(x: 100, y: 100, width: 0, height: 0)
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 110, y: 110),  // inside a hypothetical 44x44 band
            candidates: [(id1, zero)]
        )
        #expect(result == nil)
    }

    @Test
    func nearestHit_zeroHeightRect_isSkipped() {
        // A degenerate line with width but zero height must not become a
        // 44pt-tall band.
        let line = CGRect(x: 50, y: 100, width: 200, height: 0)
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 100, y: 115),
            candidates: [(id1, line)]
        )
        #expect(result == nil)
    }

    @Test
    func nearestHit_pointFarFromEverything_returnsNil() {
        let rect = CGRect(x: 50, y: 100, width: 200, height: 17)
        let result = HighlightHitTolerance.nearestHit(
            point: CGPoint(x: 500, y: 500),
            candidates: [(id1, rect)]
        )
        #expect(result == nil)
    }
}
#endif
