// Purpose: Pure, stateless mapper that converts the stored unified font-size
// value into a per-renderer concrete value. Feature #70.
//
// Key decisions:
// - No actor isolation, no I/O — a plain Sendable struct. The instance
//   carries the FontSizeCalibrationProfile so tests can inject a probe
//   profile; production code uses the default `.standard` profile.
// - calibratedSize re-clamps the result to the target renderer's own legal
//   range, so a calibrated value can never exceed what the renderer accepts.
//   The clamp is unconditional — it does not trust the multiplier.
// - The clamp ranges are sourced from the EXISTING renderer limits, not
//   invented here: TXT/MD/EPUB use TypographySettings.fontSizeRange (12...64);
//   Foliate uses 8...72 (the band FoliateJSEscaper.clampFontSize enforces).
//
// @coordinates-with: FontSizeCalibration.swift, ReaderSettingsStore.swift,
//   EPUBReaderContainerView.swift, FoliateSpikeView.swift

import Foundation

/// Converts a unified font-size value into a per-renderer concrete value.
struct FontSizeCalibrator: Sendable {

    /// Lower clamp for the text-reflow renderers (TXT/MD/EPUB). Sourced from
    /// `TypographySettings.fontSizeRange.lowerBound`.
    static let textMinimum: CGFloat = 12

    /// Upper clamp for the text-reflow renderers (TXT/MD/EPUB). Sourced from
    /// `TypographySettings.fontSizeRange.upperBound`.
    static let textMaximum: CGFloat = 64

    /// Lower clamp for the Foliate (AZW3/MOBI) renderer. Sourced from the band
    /// `FoliateJSEscaper.clampFontSize` enforces.
    static let foliateMinimum: Int = 8

    /// Upper clamp for the Foliate (AZW3/MOBI) renderer. Sourced from the band
    /// `FoliateJSEscaper.clampFontSize` enforces.
    static let foliateMaximum: Int = 72

    /// The per-target multiplier set this calibrator applies.
    let profile: FontSizeCalibrationProfile

    init(profile: FontSizeCalibrationProfile = .standard) {
        self.profile = profile
    }

    /// Map the stored unified font-size value to a target's concrete value.
    ///
    /// The result is re-clamped to the target's own legal range so a
    /// calibrated value can never exceed what the renderer accepts. For the
    /// `.foliate` target the band is `8...72`; for `.txt` / `.md` / `.epub` it
    /// is `12...64`.
    ///
    /// Non-finite safety: if `unified` or the configured multiplier is `NaN`
    /// or infinite, the scaled product is non-finite and `Swift.min`/`max`
    /// cannot clamp it deterministically. In that case the method falls back
    /// to the target band's lower bound — a readable, in-range value — so the
    /// calibrator NEVER hands a `NaN`/infinite size to a renderer.
    func calibratedSize(
        forUnified unified: CGFloat,
        target: CalibrationTarget
    ) -> CGFloat {
        let lower: CGFloat
        let upper: CGFloat
        switch target {
        case .txt, .md, .epub:
            lower = Self.textMinimum
            upper = Self.textMaximum
        case .foliate:
            lower = CGFloat(Self.foliateMinimum)
            upper = CGFloat(Self.foliateMaximum)
        }
        let scaled = unified * CGFloat(profile.multiplier(for: target))
        guard scaled.isFinite else { return lower }
        return Self.clamp(scaled, lower: lower, upper: upper)
    }

    /// Map the stored unified font-size value to the integer px value Foliate
    /// consumes.
    ///
    /// Rounds the calibrated CGFloat and clamps to Foliate's `8...72` band
    /// BEFORE `FoliateJSEscaper.clampFontSize` ever sees it, so that downstream
    /// clamp is a verified belt-and-braces no-op rather than a silent value
    /// change.
    ///
    /// Rounding rule: `.toNearestOrAwayFromZero` (the default behaviour of
    /// `FloatingPoint.rounded()`, stated explicitly here so the contract is
    /// pinned). A halfway value rounds away from zero — `34.5 → 35`,
    /// `-0.5 → -1` — and the result is then clamped to `8...72`.
    func calibratedFoliateSize(forUnified unified: CGFloat) -> Int {
        let calibrated = calibratedSize(forUnified: unified, target: .foliate)
        let rounded = Int(calibrated.rounded(.toNearestOrAwayFromZero))
        return min(max(rounded, Self.foliateMinimum), Self.foliateMaximum)
    }

    // MARK: - Private

    private static func clamp(
        _ value: CGFloat,
        lower: CGFloat,
        upper: CGFloat
    ) -> CGFloat {
        min(max(value, lower), upper)
    }
}
