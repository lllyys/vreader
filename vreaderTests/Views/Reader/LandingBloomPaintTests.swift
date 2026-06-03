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

/// Feature #74 WI-2: the bloom intensity curve (design §3 motion / §5 reduce-motion).
@Suite("LandingBloomCurve (Feature #74 WI-2)")
struct LandingBloomCurveTests {

    @Test func intensity_rest_isZero() {
        #expect(LandingBloomCurve.intensity(elapsedMs: 0, reduceMotion: false) == 0)
    }

    @Test func intensity_duringHold_isPeak() {
        #expect(LandingBloomCurve.intensity(elapsedMs: 250, reduceMotion: false) == 1)
    }

    @Test func intensity_decaysMonotonicallyAfterHold() {
        let a = LandingBloomCurve.intensity(elapsedMs: 500, reduceMotion: false)
        let b = LandingBloomCurve.intensity(elapsedMs: 900, reduceMotion: false)
        #expect(a > b)
        #expect(b > 0)
    }

    @Test func intensity_atEnd_isZero_andComplete() {
        #expect(LandingBloomCurve.intensity(elapsedMs: 1500, reduceMotion: false) == 0)
        #expect(LandingBloomCurve.isComplete(elapsedMs: 1500, reduceMotion: false))
        #expect(!LandingBloomCurve.isComplete(elapsedMs: 1400, reduceMotion: false))
    }

    @Test func reduceMotion_jumpsToPeak_holdsThenFades() {
        #expect(LandingBloomCurve.intensity(elapsedMs: 0, reduceMotion: true) == 1)
        #expect(LandingBloomCurve.intensity(elapsedMs: 1200, reduceMotion: true) == 1)
        #expect(LandingBloomCurve.intensity(elapsedMs: 1360, reduceMotion: true) > 0)
        #expect(LandingBloomCurve.intensity(elapsedMs: 1520, reduceMotion: true) == 0)
    }
}

/// Feature #74 WI-2: the navigate-from-list trigger + theme-family resolution +
/// the reduce-motion glow suppression.
@Suite("LandingBloom trigger + family (Feature #74 WI-2)")
@MainActor
struct LandingBloomTriggerTests {

    @Test func landingTrigger_firesOnlyForAPersistedRangeMatch() {
        let h = PaintedHighlight(range: NSRange(location: 10, length: 5), colorName: "green")
        // Exact match (a list tap on the saved highlight) → bloom with its color.
        #expect(TXTTextViewBridge.landingTrigger(
            highlightRange: NSRange(location: 10, length: 5), persisted: [h])?.colorName == "green")
        // A search hit (range matches no persisted highlight) → no bloom.
        #expect(TXTTextViewBridge.landingTrigger(
            highlightRange: NSRange(location: 11, length: 5), persisted: [h]) == nil)
        // No nav range → no bloom.
        #expect(TXTTextViewBridge.landingTrigger(highlightRange: nil, persisted: [h]) == nil)
    }

    @Test func bloomThemeFamily_byBackgroundLuminance() {
        #expect(TXTTextViewBridge.bloomThemeFamily(for: .white) == .light)
        #expect(TXTTextViewBridge.bloomThemeFamily(for: .black) == .dark)
    }

    @Test func paint_reduceMotion_suppressesGlowKeepsRing() {
        let p = LandingBloomPaint(intensity: 1, family: .dark, reduceMotion: true)
        #expect(p.glowRadius == 0)
        #expect(p.glowAlpha == 0)
        #expect(approxCG(p.ringWidth, 1.6))
        #expect(p.ringAlpha == 1)
        #expect(approxCG(p.washAlpha, 0.86))
    }

    /// §5 fidelity (Gate-4 Medium): under reduce-motion the ring fades by OPACITY
    /// (ringAlpha), NOT by shrinking — its WIDTH stays fixed at 1.6 while active,
    /// so nothing translates/scales. Contrast: motion shrinks the ring width.
    @Test func paint_reduceMotion_ringFadesByOpacityNotWidth() {
        let fading = LandingBloomPaint(intensity: 0.5, family: .dark, reduceMotion: true)
        #expect(approxCG(fading.ringWidth, 1.6))   // fixed geometry
        #expect(approxCG(fading.ringAlpha, 0.5))   // fades by opacity
        #expect(fading.glowRadius == 0)
        // Motion (contrast): the ring width shrinks with intensity, alpha stays 1.
        let motion = LandingBloomPaint(intensity: 0.5, family: .dark, reduceMotion: false)
        #expect(approxCG(motion.ringWidth, 0.8))
        #expect(motion.ringAlpha == 1)
    }

    /// Gate-4 round-2: the coordinator's `cancelLandingBloom` cancels BOTH the
    /// pending (delayed work item) AND the active (layer on the text view) bloom —
    /// the contract the interruptibility paths (user tap/scroll, superseding nav,
    /// highlight-hit tap) rely on.
    @Test func coordinator_cancelLandingBloom_cancelsPendingAndActive() {
        let coord = TXTTextViewBridge.Coordinator(delegate: nil, config: TXTViewConfig())
        let tv = HighlightableTextView()
        coord.activeTextView = tv
        // Active bloom: a landing layer is on the text view.
        tv.setLandingHighlight(
            range: NSRange(location: 0, length: 4), colorName: "yellow",
            intensity: 0.5, family: .light
        )
        let lm = tv.layoutManager as? HighlightingLayoutManager
        #expect(lm?.landingHighlight != nil)
        // Pending bloom: a scheduled work item.
        let work = DispatchWorkItem {}
        coord.pendingBloom = work

        coord.cancelLandingBloom()

        #expect(coord.pendingBloom == nil)   // pending dropped
        #expect(work.isCancelled)            // …and cancelled
        #expect(lm?.landingHighlight == nil) // active torn down
    }

    private func approxCG(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }
}
#endif
