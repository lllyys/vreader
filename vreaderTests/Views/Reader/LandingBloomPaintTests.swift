// Feature #74 WI-1: the pure paint-parameter math for the highlight-landing
// "locate bloom" — washAlpha lerps from the persisted resting fill
// (HighlightPaintColor.fillAlpha) to the 0.86 peak; ring/glow scale with
// intensity; glow alpha differs by theme family (design §3/§6). Plus the
// replace-don't-stack suppression decision (the landing wash replaces the
// equal-range persisted fill rather than stacking on it).

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("LandingBloomPaint (Feature #74 WI-1)")
struct LandingBloomPaintTests {

    private func approx(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

    /// At rest the wash alpha equals the persisted fill alpha (so resting ==
    /// persisted source), and ring/glow are zero.
    @Test func paint_atRestIntensity_matchesPersistedSourceAlpha() {
        let p = LandingBloomPaint(intensity: 0, family: .light)
        #expect(approx(p.washAlpha, HighlightPaintColor.fillAlpha))
        #expect(p.ringWidth == 0)
        #expect(p.glowRadius == 0)
        #expect(p.glowAlpha == 0)
    }

    /// At peak the wash lifts to 0.86, the ring is 1.6, the glow radius 16.
    @Test func paint_atPeakIntensity_liftsWashAndRingAndGlow() {
        let p = LandingBloomPaint(intensity: 1, family: .light)
        #expect(approx(p.washAlpha, 0.86))
        #expect(approx(p.ringWidth, 1.6))
        #expect(approx(p.glowRadius, 16))
    }

    /// Mid intensity lerps linearly — washAlpha == (fillAlpha + 0.86) / 2.
    @Test func paint_midIntensity_lerpsLinearly() {
        let p = LandingBloomPaint(intensity: 0.5, family: .light)
        #expect(approx(p.washAlpha, (HighlightPaintColor.fillAlpha + 0.86) / 2))
        #expect(approx(p.ringWidth, 0.8))
        #expect(approx(p.glowRadius, 8))
    }

    /// Glow alpha is 0.55 (light) / 0.85 (dark) at peak, scaled by intensity.
    @Test func paint_glowAlpha_lightVsDarkFamily() {
        #expect(approx(LandingBloomPaint(intensity: 1, family: .light).glowAlpha, 0.55))
        #expect(approx(LandingBloomPaint(intensity: 1, family: .dark).glowAlpha, 0.85))
        #expect(approx(LandingBloomPaint(intensity: 0.5, family: .dark).glowAlpha, 0.425))
    }

    /// Intensity is clamped to [0, 1].
    @Test func paint_intensity_clampedToUnitRange() {
        #expect(LandingBloomPaint(intensity: -1, family: .light)
                == LandingBloomPaint(intensity: 0, family: .light))
        #expect(LandingBloomPaint(intensity: 5, family: .light)
                == LandingBloomPaint(intensity: 1, family: .light))
    }

    /// The landing wash replaces the persisted fill ONLY for an exactly-equal
    /// range (the feature's case), so the two washes never stack and darken.
    @Test func suppressesPersisted_whenLandingRangeEqualsPersisted() {
        let r = NSRange(location: 10, length: 20)
        #expect(LandingBloomPaint.suppressesPersisted(persistedRange: r, landingRange: r))
        #expect(!LandingBloomPaint.suppressesPersisted(
            persistedRange: r, landingRange: NSRange(location: 10, length: 19)))
        #expect(!LandingBloomPaint.suppressesPersisted(
            persistedRange: r, landingRange: NSRange(location: 11, length: 20)))
    }
}

/// Gate-4 MED: the render-layer contract on the real `HighlightableTextView` /
/// `HighlightingLayoutManager` — `setLandingHighlight` stores the layer on the
/// layout manager (so `drawBackground` can paint it) and `clearLandingHighlight`
/// tears it down. Proves the WI-1 code path, not just the pure math.
@Suite("HighlightableTextView landing layer (Feature #74 WI-1)")
@MainActor
struct HighlightableTextViewLandingTests {

    @Test func setLandingHighlight_storesOnLayoutManager() {
        let tv = HighlightableTextView()
        let lm = tv.layoutManager as? HighlightingLayoutManager
        #expect(lm != nil)
        tv.setLandingHighlight(
            range: NSRange(location: 5, length: 10),
            colorName: "green", intensity: 0.7, family: .dark
        )
        #expect(lm?.landingHighlight?.range == NSRange(location: 5, length: 10))
        #expect(lm?.landingHighlight?.colorName == "green")
        #expect(lm?.landingHighlight?.intensity == 0.7)
        #expect(lm?.landingHighlight?.family == .dark)
    }

    @Test func clearLandingHighlight_tearsDownLayer() {
        let tv = HighlightableTextView()
        let lm = tv.layoutManager as? HighlightingLayoutManager
        tv.setLandingHighlight(
            range: NSRange(location: 0, length: 4),
            colorName: "yellow", intensity: 1, family: .light
        )
        #expect(lm?.landingHighlight != nil)
        tv.clearLandingHighlight()
        #expect(lm?.landingHighlight == nil)
    }

    /// WI-1 is dormant: a fresh view has no landing layer until a caller sets it
    /// (no trigger ships in WI-1).
    @Test func freshView_hasNoLandingLayer() {
        let tv = HighlightableTextView()
        let lm = tv.layoutManager as? HighlightingLayoutManager
        #expect(lm?.landingHighlight == nil)
    }
}
#endif
