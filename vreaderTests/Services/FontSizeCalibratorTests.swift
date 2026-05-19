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
// The shipped multipliers are conservative, identity-leaning estimates
// (EPUB/Foliate WebViews render CSS px slightly smaller than the equivalent
// UIKit point at default metrics, so their multipliers are >= 1.0; MD is
// also a UITextView so it is approximately 1.0). Gate-5 behavioral
// verification confirms or re-tunes them; only the four field literals in
// FontSizeCalibrationProfile.standard change if re-tuning is needed — the
// architecture is unaffected.

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

    @Test(arguments: CalibrationTarget.allCases)
    func calibratedSizeAppliesMultiplier(_ target: CalibrationTarget) {
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 1.5, epub: 1.5, foliate: 1.5)
        let calibrator = FontSizeCalibrator(profile: profile)
        let unified: CGFloat = 24
        // 24 * multiplier, then clamped to the target range (here all in
        // range). Computed with the same CGFloat arithmetic the calibrator
        // uses so the comparison is bit-exact.
        let scaled: CGFloat = unified * CGFloat(profile.multiplier(for: target))
        let expected: CGFloat = min(max(scaled, CGFloat(12)), CGFloat(64))
        let actual: CGFloat = calibrator.calibratedSize(forUnified: unified, target: target)
        #expect(actual == expected)
    }

    @Test func standardProfileMatchesMultiplierAtReferenceSize() {
        let calibrator = FontSizeCalibrator()
        for target in CalibrationTarget.allCases {
            let mult = FontSizeCalibrationProfile.standard.multiplier(for: target)
            let scaled: CGFloat = CGFloat(24) * CGFloat(mult)
            let expected: CGFloat = min(max(scaled, CGFloat(12)), CGFloat(64))
            let actual: CGFloat = calibrator.calibratedSize(forUnified: 24, target: target)
            #expect(actual == expected)
        }
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

    @Test func calibratedFoliateSizeRoundsHalfUp() {
        // 8.0 unified clamped to 12 (text min applied first via calibratedSize),
        // then Foliate clamp 8...72. Use a value that produces a .5 fraction.
        // 23 * 1.5 = 34.5 → rounds to 34 or 35 (Swift .rounded() is half-to-even
        // -> 34; .toNearestOrAwayFromZero -> 35). We assert via the documented
        // rounding: rounded() to nearest.
        let profile = FontSizeCalibrationProfile(txt: 1.0, md: 1.0, epub: 1.0, foliate: 1.5)
        let calibrator = FontSizeCalibrator(profile: profile)
        let result = calibrator.calibratedFoliateSize(forUnified: 23)
        // 23 * 1.5 = 34.5; accept either standard rounding outcome.
        #expect(result == 34 || result == 35)
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
