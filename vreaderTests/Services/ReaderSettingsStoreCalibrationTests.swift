// Purpose: Tests for feature #70 WI-2 — ReaderSettingsStore routes TXT and MD
// per-renderer font size + leading through FontSizeCalibrator. TXT is the
// 1.0 anchor (behavior-preserving); MD is calibrated. The public
// lineSpacingPoints / cjkLetterSpacing properties stay unified-value-based
// (the ReaderSettingsPanel preview reads them unchanged).

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("ReaderSettingsStoreCalibration")
@MainActor
struct ReaderSettingsStoreCalibrationTests {

    private func makeStore() -> ReaderSettingsStore {
        let suite = "ReaderSettingsStoreCalibrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return ReaderSettingsStore(defaults: defaults)
    }

    // MARK: - Calibrator presence

    /// The store exposes a `FontSizeCalibrator` (default profile) — readable
    /// by `EPUBReaderContainerView` / `FoliateSpikeView` in WI-3/WI-4.
    @Test func storeExposesCalibratorWithStandardProfile() {
        let s = makeStore()
        #expect(s.calibrator.profile == FontSizeCalibrationProfile.standard)
    }

    #if canImport(UIKit)

    // MARK: - TXT config routes through the calibrator (.txt anchor)

    /// `txtViewConfig.fontSize` equals the calibrator's `.txt` mapping of the
    /// unified value — i.e. the TXT path is *routed through* the calibrator,
    /// not reading `typography.fontSize` raw.
    @Test func txtViewConfigFontSizeRoutesThroughCalibratorTxtTarget() {
        let s = makeStore()
        s.typography.fontSize = 24
        let expected = s.calibrator.calibratedSize(forUnified: 24, target: .txt)
        #expect(s.txtViewConfig.fontSize == expected)
    }

    /// Because the shipped `.txt` multiplier is `1.0`, routing TXT through the
    /// calibrator is behavior-preserving — `txtViewConfig.fontSize` still
    /// equals the raw unified value. This is the no-regression guard for the
    /// existing TXT appearance.
    @Test func txtViewConfigFontSizeIsBehaviorPreserving() {
        let s = makeStore()
        for unified in [CGFloat(12), 18, 24, 40, 64] {
            s.typography.fontSize = unified
            #expect(s.txtViewConfig.fontSize == unified)
        }
    }

    // MARK: - MD config routes through the calibrator (.md target)

    /// `mdRenderConfig.fontSize` equals the calibrator's `.md` mapping of the
    /// unified value — the MD path is routed through the calibrator.
    @Test func mdRenderConfigFontSizeRoutesThroughCalibratorMdTarget() {
        let s = makeStore()
        s.typography.fontSize = 22
        let expected = s.calibrator.calibratedSize(forUnified: 22, target: .md)
        #expect(s.mdRenderConfig.fontSize == expected)
    }

    // MARK: - Leading: calibrated base, per target

    /// `txtViewConfig.lineSpacing` uses the `.txt`-calibrated base size for
    /// the leading derivation. With `.txt` multiplier `1.0` this is
    /// numerically identical to the public `lineSpacingPoints` — TXT leading
    /// is behavior-preserving.
    @Test func txtViewConfigLineSpacingUsesCalibratedTxtBase() {
        let s = makeStore()
        s.typography.fontSize = 20
        s.typography.lineSpacing = 1.6
        let calibratedBase = s.calibrator.calibratedSize(forUnified: 20, target: .txt)
        let expected = calibratedBase * (1.6 - 1.0)
        #expect(abs(s.txtViewConfig.lineSpacing - expected) < 0.001)
        // And behavior-preserving: equals the public lineSpacingPoints.
        #expect(abs(s.txtViewConfig.lineSpacing - s.lineSpacingPoints) < 0.001)
    }

    /// `mdRenderConfig.lineSpacing` uses the `.md`-calibrated base size for
    /// the leading derivation.
    @Test func mdRenderConfigLineSpacingUsesCalibratedMdBase() {
        let s = makeStore()
        s.typography.fontSize = 20
        s.typography.lineSpacing = 1.6
        let calibratedBase = s.calibrator.calibratedSize(forUnified: 20, target: .md)
        let expected = calibratedBase * (1.6 - 1.0)
        #expect(abs(s.mdRenderConfig.lineSpacing - expected) < 0.001)
    }

    // MARK: - CJK letter spacing: calibrated base, per target

    /// `txtViewConfig.letterSpacing` uses the `.txt`-calibrated base when CJK
    /// spacing is on; `0` when off.
    @Test func txtViewConfigLetterSpacingUsesCalibratedTxtBase() {
        let s = makeStore()
        s.typography.fontSize = 30
        s.typography.cjkSpacing = true
        let calibratedBase = s.calibrator.calibratedSize(forUnified: 30, target: .txt)
        #expect(abs(s.txtViewConfig.letterSpacing - calibratedBase * 0.05) < 0.001)
    }

    @Test func txtViewConfigLetterSpacingZeroWhenCJKDisabled() {
        let s = makeStore()
        s.typography.fontSize = 30
        s.typography.cjkSpacing = false
        #expect(s.txtViewConfig.letterSpacing == 0)
    }

    // MARK: - Public properties stay unified-value-based (panel preview guard)

    /// The public `lineSpacingPoints` is NOT changed by WI-2 — it remains the
    /// unified-value formula, which the `ReaderSettingsPanel` preview reads.
    @Test func publicLineSpacingPointsStaysUnifiedValueBased() {
        let s = makeStore()
        s.typography.fontSize = 20
        s.typography.lineSpacing = 1.6
        // unified 20 * (1.6 - 1.0) = 12.0
        #expect(abs(s.lineSpacingPoints - 12.0) < 0.001)
    }

    /// The public `cjkLetterSpacing` is NOT changed by WI-2 — unified-value
    /// formula.
    @Test func publicCJKLetterSpacingStaysUnifiedValueBased() {
        let s = makeStore()
        s.typography.fontSize = 40
        s.typography.cjkSpacing = true
        // unified 40 * 0.05 = 2.0
        #expect(abs(s.cjkLetterSpacing - 2.0) < 0.001)
        s.typography.cjkSpacing = false
        #expect(s.cjkLetterSpacing == 0)
    }

    // MARK: - Re-derivation on typography change

    /// Changing `typography.fontSize` re-derives both configs through the
    /// calibrator (observation still fires; configs are computed).
    @Test func changingFontSizeReDerivesBothConfigs() {
        let s = makeStore()
        s.typography.fontSize = 18
        let txt1 = s.txtViewConfig.fontSize
        let md1 = s.mdRenderConfig.fontSize
        s.typography.fontSize = 48
        #expect(s.txtViewConfig.fontSize != txt1)
        #expect(s.mdRenderConfig.fontSize != md1)
        #expect(s.txtViewConfig.fontSize == s.calibrator.calibratedSize(forUnified: 48, target: .txt))
        #expect(s.mdRenderConfig.fontSize == s.calibrator.calibratedSize(forUnified: 48, target: .md))
    }

    // MARK: - Boundary values flow through clamped

    /// Unified `12` and `64` flow through both configs, calibrated + clamped
    /// to the text band.
    @Test func boundaryUnifiedValuesFlowThroughBothConfigs() {
        let s = makeStore()
        s.typography.fontSize = 12
        #expect(s.txtViewConfig.fontSize == s.calibrator.calibratedSize(forUnified: 12, target: .txt))
        #expect(s.mdRenderConfig.fontSize == s.calibrator.calibratedSize(forUnified: 12, target: .md))
        #expect(s.txtViewConfig.fontSize >= 12 && s.txtViewConfig.fontSize <= 64)
        #expect(s.mdRenderConfig.fontSize >= 12 && s.mdRenderConfig.fontSize <= 64)
        s.typography.fontSize = 64
        #expect(s.txtViewConfig.fontSize == s.calibrator.calibratedSize(forUnified: 64, target: .txt))
        #expect(s.mdRenderConfig.fontSize == s.calibrator.calibratedSize(forUnified: 64, target: .md))
        #expect(s.txtViewConfig.fontSize >= 12 && s.txtViewConfig.fontSize <= 64)
        #expect(s.mdRenderConfig.fontSize >= 12 && s.mdRenderConfig.fontSize <= 64)
    }

    #endif
}
