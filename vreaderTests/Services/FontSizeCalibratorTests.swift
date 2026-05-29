// Purpose: Tests for FontSizeCalibrator — the pure unified→per-renderer
// font-size mapper. Feature #70 WI-1.
//
// Calibration derivation (how FontSizeCalibrationProfile.standard's
// multipliers are obtained):
//   1. Render a fixed reference string at unified size 24 in each of the
//      four renderers on iPhone 17 Pro Simulator at the DEFAULT content-size
//      category (UIContentSizeCategory.large).
//   2. Capture the rendered cap-height (TXT/MD via UIFont.capHeight;
//      EPUB/Foliate via getBoundingClientRect on a measurement span).
//   3. multiplier(T) = capHeight(txt) / capHeight(T) — the factor that makes
//      T's rendered glyph match TXT's.
//   4. Encode the four ratios as the four Double fields of
//      FontSizeCalibrationProfile.standard; txt is 1.0 by construction.
//
// The shipped multipliers are sim-measured (bug #280, iPhone 17 Pro,
// 2026-05-30) via a direct cap-height comparison — see
// FontSizeCalibrationMeasurementTests for the live-WKWebView measurement that
// derives them. Measured at the reference unified size 24:
//   - txt/md = 1.0 (UITextView anchor; at the default content-size category
//     the UIFontMetrics wrap is the identity, so MD shares TXT's metric).
//   - epub = 1.0 — the `-apple-system` CSS stack resolves to the SAME SF Pro
//     face UIKit uses and 1 CSS px = 1 UIKit point, so EPUB is already at
//     cap-height parity with TXT (measured 16.910 / 16.906 = 1.0002). The
//     prior 1.12 over-inflated EPUB by 12% (bug #280's "too large" report).
//   - foliate = 1.06 — the default UA font renders marginally smaller-capped
//     than UIKit at the same px (measured 16.910 / 15.891 = 1.064), so a small
//     > 1.0 lift restores parity. The prior 1.12 over-inflated it ~5%.
// Only the four field literals in FontSizeCalibrationProfile.standard change
// when re-tuning — the architecture is unaffected.

import Testing
import Foundation
@testable import vreader

@Suite("FontSizeCalibrator")
struct FontSizeCalibratorTests {

    /// All-1.0 probe profile — the calibrator must be the identity for every
    /// target when no multiplier is applied. Proves the transform is pure.
    static let identityProfile = FontSizeCalibrationProfile(
        txt: 1.0, md: 1.0, epub: 1.0, foliate: 1.0
    )

    // MARK: - Anchor Identity

    @Test func anchorTargetIsIdentity() {
        let calibrator = FontSizeCalibrator()
        #expect(calibrator.calibratedSize(forUnified: 24, target: .txt) == 24)
    }

    @Test func identityProfileIsIdentityForEveryTarget() {
        let calibrator = FontSizeCalibrator(profile: Self.identityProfile)
        for target in CalibrationTarget.allCases {
            #expect(calibrator.calibratedSize(forUnified: 24, target: target) == 24)
            #expect(calibrator.calibratedSize(forUnified: 40, target: target) == 40)
        }
    }

    // MARK: - Multiplier Application

    /// The legal clamp band for a target, used to compute expected values.
    /// TXT/MD/EPUB share `12...64`; `.foliate` uses the distinct `8...72`
    /// band — this helper makes the test sensitive to a target mistakenly
    /// using the wrong band.
    private static func clampBand(for target: CalibrationTarget) -> (CGFloat, CGFloat) {
        switch target {
        case .txt, .md, .epub: return (12, 64)
        case .foliate: return (8, 72)
        }
    }

    @Test(arguments: CalibrationTarget.allCases)
    func calibratedSizeAppliesMultiplier(_ target: CalibrationTarget) {
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 1.5, epub: 1.5, foliate: 1.5)
        let calibrator = FontSizeCalibrator(profile: profile)
        let unified: CGFloat = 24
        // 24 * multiplier, then clamped to the TARGET'S OWN band. Computed
        // with the same CGFloat arithmetic the calibrator uses so the
        // comparison is bit-exact.
        let scaled: CGFloat = unified * CGFloat(profile.multiplier(for: target))
        let (lo, hi) = Self.clampBand(for: target)
        let expected: CGFloat = min(max(scaled, lo), hi)
        let actual: CGFloat = calibrator.calibratedSize(forUnified: unified, target: target)
        #expect(actual == expected)
    }

    @Test func standardProfileMatchesMultiplierAtReferenceSize() {
        let calibrator = FontSizeCalibrator()
        for target in CalibrationTarget.allCases {
            let mult = FontSizeCalibrationProfile.standard.multiplier(for: target)
            let scaled: CGFloat = CGFloat(24) * CGFloat(mult)
            let (lo, hi) = Self.clampBand(for: target)
            let expected: CGFloat = min(max(scaled, lo), hi)
            let actual: CGFloat = calibrator.calibratedSize(forUnified: 24, target: target)
            #expect(actual == expected)
        }
    }

    /// `.foliate`'s `calibratedSize` must clamp to `8...72`, NOT the text
    /// band `12...64`. These assertions use values that distinguish the two
    /// bands: a calibrated result of 9 is legal for Foliate but would be
    /// clamped UP to 12 by the text band; a result of 70 is legal for
    /// Foliate but would be clamped DOWN to 64 by the text band. A
    /// regression that text-clamps `.foliate` fails here.
    @Test func calibratedSizeForFoliateUsesFoliateBandNotTextBand() {
        // multiplier 0.75 → 12 * 0.75 = 9.0 — must stay 9 (text band would
        // raise it to 12).
        let lowProfile = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 0.75)
        let lowCalibrator = FontSizeCalibrator(profile: lowProfile)
        #expect(lowCalibrator.calibratedSize(forUnified: 12, target: .foliate) == 9)
        // multiplier 1.09375 → 64 * 1.09375 = 70.0 — must stay 70 (text band
        // would lower it to 64).
        let highProfile = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 1.09375)
        let highCalibrator = FontSizeCalibrator(profile: highProfile)
        #expect(highCalibrator.calibratedSize(forUnified: 64, target: .foliate) == 70)
    }

    // MARK: - Lower-Bound Clamp (TXT/MD/EPUB → 12)

    @Test func calibratedSizeNeverDropsBelowTextMinimum() {
        // Probe profile with a multiplier well below 1.0.
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 0.1, epub: 0.1, foliate: 0.1)
        let calibrator = FontSizeCalibrator(profile: profile)
        // unified 12 * 0.1 = 1.2 — must clamp UP to 12.
        #expect(calibrator.calibratedSize(forUnified: 12, target: .epub) == 12)
        #expect(calibrator.calibratedSize(forUnified: 12, target: .md) == 12)
    }

    // MARK: - Upper-Bound Clamp (TXT/MD/EPUB → 64)

    @Test func calibratedSizeNeverExceedsTextMaximum() {
        // Probe profile with a multiplier well above 1.0.
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 5.0, epub: 5.0, foliate: 5.0)
        let calibrator = FontSizeCalibrator(profile: profile)
        // unified 64 * 5.0 = 320 — must clamp DOWN to 64.
        #expect(calibrator.calibratedSize(forUnified: 64, target: .epub) == 64)
        #expect(calibrator.calibratedSize(forUnified: 64, target: .md) == 64)
    }

    /// The clamp is unconditional — it does not trust the multiplier. An
    /// extreme injected multiplier still clamps to the target band.
    @Test func clampIsUnconditionalForExtremeMultiplier() {
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 1.0)
        let calibrator = FontSizeCalibrator(profile: profile)
        // Even with identity profile, an out-of-range unified value clamps.
        #expect(calibrator.calibratedSize(forUnified: 1000, target: .txt) == 64)
        #expect(calibrator.calibratedSize(forUnified: 1, target: .txt) == 12)
        #expect(calibrator.calibratedSize(forUnified: -50, target: .epub) == 12)
    }

    // MARK: - Non-Finite Safety

    /// A `NaN` multiplier produces a non-finite scaled product; the
    /// calibrator must NEVER hand a `NaN` size to a renderer. It falls back
    /// to the target band's lower bound (12 for text, 8 for Foliate).
    @Test(arguments: CalibrationTarget.allCases)
    func nanMultiplierFallsBackToTargetLowerBound(_ target: CalibrationTarget) {
        let profile = FontSizeCalibrationProfile(
            txt: .nan, md: .nan, epub: .nan, foliate: .nan
        )
        let calibrator = FontSizeCalibrator(profile: profile)
        let result = calibrator.calibratedSize(forUnified: 24, target: target)
        #expect(result.isFinite)
        let expectedFloor: CGFloat = (target == .foliate) ? 8 : 12
        #expect(result == expectedFloor)
    }

    /// A `+infinity` multiplier likewise falls back to the lower bound, not
    /// an infinite (or clamped-from-infinite) value.
    @Test func positiveInfinityMultiplierFallsBackToLowerBound() {
        let profile = FontSizeCalibrationProfile(
            txt: 1.0, md: .infinity, epub: .infinity, foliate: .infinity
        )
        let calibrator = FontSizeCalibrator(profile: profile)
        #expect(calibrator.calibratedSize(forUnified: 24, target: .md) == 12)
        #expect(calibrator.calibratedSize(forUnified: 24, target: .epub) == 12)
        #expect(calibrator.calibratedSize(forUnified: 24, target: .foliate) == 8)
        // The anchor (.txt, finite 1.0) is unaffected.
        #expect(calibrator.calibratedSize(forUnified: 24, target: .txt) == 24)
    }

    /// A `-infinity` multiplier falls back to the lower bound too.
    @Test func negativeInfinityMultiplierFallsBackToLowerBound() {
        let profile = FontSizeCalibrationProfile(
            txt: 1.0, md: -.infinity, epub: -.infinity, foliate: -.infinity
        )
        let calibrator = FontSizeCalibrator(profile: profile)
        #expect(calibrator.calibratedSize(forUnified: 24, target: .epub) == 12)
        #expect(calibrator.calibratedFoliateSize(forUnified: 24) == 8)
    }

    /// A non-finite `unified` input (not just a non-finite multiplier) is
    /// also handled — the product is non-finite, so the fallback applies.
    @Test func nonFiniteUnifiedInputFallsBackToLowerBound() {
        let calibrator = FontSizeCalibrator(profile: Self.identityProfile)
        #expect(calibrator.calibratedSize(forUnified: .nan, target: .txt) == 12)
        #expect(calibrator.calibratedSize(forUnified: .infinity, target: .epub) == 12)
        #expect(calibrator.calibratedFoliateSize(forUnified: .nan) == 8)
    }

    // MARK: - Boundary Values

    @Test func boundaryUnifiedValuesFlowThrough() {
        let calibrator = FontSizeCalibrator(profile: Self.identityProfile)
        #expect(calibrator.calibratedSize(forUnified: 12, target: .txt) == 12)
        #expect(calibrator.calibratedSize(forUnified: 64, target: .txt) == 64)
    }

    // MARK: - Foliate Integer Path

    @Test func calibratedFoliateSizeReturnsRoundedInt() {
        // Probe profile producing a non-integer calibrated value: 24 * 1.05 = 25.2 → 25.
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 1.05)
        let calibrator = FontSizeCalibrator(profile: profile)
        #expect(calibrator.calibratedFoliateSize(forUnified: 24) == 25)
    }

    /// Pins the exact rounding contract: `.toNearestOrAwayFromZero`. A
    /// halfway value rounds AWAY from zero, so `34.5 → 35` (NOT 34 — which
    /// `.toNearestOrEven` / "banker's rounding" would produce). A
    /// rounding-mode regression fails here.
    @Test func calibratedFoliateSizeRoundsHalfwayAwayFromZero() {
        // 23 * 1.5 = 34.5 — exactly halfway. Must round to 35.
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 1.5)
        let calibrator = FontSizeCalibrator(profile: profile)
        #expect(calibrator.calibratedFoliateSize(forUnified: 23) == 35)
        // 25 * 1.5 = 37.5 — also exactly halfway. Must round to 38, not 37.
        #expect(calibrator.calibratedFoliateSize(forUnified: 25) == 38)
    }

    /// Pins the negative-halfway behaviour of the underlying
    /// `Int(_.rounded(.toNearestOrAwayFromZero))` conversion. A negative
    /// calibrated value can never survive `calibratedFoliateSize`'s `8...72`
    /// clamp (it floors at 8), so the negative-halfway rounding rule is
    /// asserted directly on `rounded(.toNearestOrAwayFromZero)` here — this
    /// guards the documented `-0.5 → -1` contract independent of the clamp.
    @Test func negativeHalfwayRoundsAwayFromZero() {
        #expect(Int(CGFloat(-0.5).rounded(.toNearestOrAwayFromZero)) == -1)
        #expect(Int(CGFloat(-34.5).rounded(.toNearestOrAwayFromZero)) == -35)
        // And confirm a negative calibrated input still clamps to the floor.
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: -1.0)
        let calibrator = FontSizeCalibrator(profile: profile)
        #expect(calibrator.calibratedFoliateSize(forUnified: 24) == 8)
    }

    @Test func calibratedFoliateSizeNeverExceedsFoliateMaximum() {
        // Probe with a huge multiplier — calibratedSize for .foliate is NOT
        // text-clamped to 64; it is Foliate-clamped to 72.
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 10.0)
        let calibrator = FontSizeCalibrator(profile: profile)
        #expect(calibrator.calibratedFoliateSize(forUnified: 64) == 72)
    }

    @Test func calibratedFoliateSizeNeverDropsBelowFoliateMinimum() {
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 0.01)
        let calibrator = FontSizeCalibrator(profile: profile)
        #expect(calibrator.calibratedFoliateSize(forUnified: 12) == 8)
    }

    /// The calibrated Foliate value is already inside 8...72, so
    /// FoliateJSEscaper.clampFontSize is a verified no-op for every in-range
    /// unified value (the "belt-and-braces" claim).
    @Test func calibratedFoliateSizeIsAlreadyWithinFoliateBand() {
        let calibrator = FontSizeCalibrator()
        for unified in stride(from: CGFloat(12), through: 64, by: 1) {
            let size = calibrator.calibratedFoliateSize(forUnified: unified)
            #expect(size >= 8 && size <= 72)
            #expect(FoliateJSEscaper.clampFontSize(size) == size)
        }
    }

    // MARK: - Cross-Format Consistency (the property the feature delivers)

    /// At a single unified value, every target's rendered ratio
    /// (calibratedSize / unified) sits within a documented tolerance band of
    /// the TXT anchor (1.0). This is the consistency property asserted at the
    /// value layer.
    @Test func crossFormatRatiosAreConsistentAtReferenceSize() {
        let calibrator = FontSizeCalibrator()
        let unified: CGFloat = 24
        let txtRatio = calibrator.calibratedSize(forUnified: unified, target: .txt) / unified
        #expect(txtRatio == 1.0)
        // Tolerance: shipped multipliers are within +/- 25% of the anchor.
        let tolerance = 0.25
        for target in CalibrationTarget.allCases {
            let ratio = calibrator.calibratedSize(forUnified: unified, target: target) / unified
            #expect(abs(ratio - txtRatio) <= tolerance)
        }
        let foliateRatio = CGFloat(calibrator.calibratedFoliateSize(forUnified: unified)) / unified
        #expect(abs(foliateRatio - txtRatio) <= tolerance)
    }

    // MARK: - Default Init

    @Test func defaultInitUsesStandardProfile() {
        let calibrator = FontSizeCalibrator()
        #expect(calibrator.profile == FontSizeCalibrationProfile.standard)
    }
}
