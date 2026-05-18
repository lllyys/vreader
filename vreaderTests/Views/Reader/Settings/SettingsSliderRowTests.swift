// Purpose: Tests for `SettingsSliderRow` — feature #66 WI-1. The custom
// accent-track slider that replaces the native `Slider` in
// `ReaderSettingsPanel`'s font-size and line-spacing sections, matching
// the design bundle's `SliderRow` (`vreader-panels.jsx`).
//
// SwiftUI body rendering is not pixel-tested. The contract under test is
// the slider's pure value math — `progress(for:)`, `quantize(_:)`, and the
// drag-fraction → value mapping — exercised against the real
// `TypographySettings.fontSizeRange` / `lineSpacingRange`, plus the
// `Binding<CGFloat>` round-trip and the `Glyph` leading/trailing model.
//
// @coordinates-with: vreader/Views/Reader/Settings/SettingsSliderRow.swift,
//   vreader/Models/TypographySettings.swift

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("SettingsSliderRow (Feature #66 WI-1)")
struct SettingsSliderRowTests {

    // MARK: - progress(for:)

    /// `progress` maps a value in range onto a 0...1 track fraction.
    @Test func progress_mapsValueToTrackFraction() {
        let range: ClosedRange<CGFloat> = 12...64
        #expect(SettingsSliderRow.progress(for: 12, in: range) == 0)
        #expect(SettingsSliderRow.progress(for: 64, in: range) == 1)
        #expect(abs(SettingsSliderRow.progress(for: 38, in: range) - 0.5) < 0.0001)
    }

    /// A value below / above the range still clamps the fraction to 0...1
    /// so the thumb never escapes the track.
    @Test func progress_clampsOutOfRangeValues() {
        let range: ClosedRange<CGFloat> = 1.0...2.0
        #expect(SettingsSliderRow.progress(for: 0.5, in: range) == 0)
        #expect(SettingsSliderRow.progress(for: 9.0, in: range) == 1)
    }

    /// A degenerate (single-point) range never divides by zero — it pins
    /// the fraction to 0.
    @Test func progress_handlesDegenerateRange() {
        let range: ClosedRange<CGFloat> = 18...18
        #expect(SettingsSliderRow.progress(for: 18, in: range) == 0)
    }

    // MARK: - quantize(_:)

    /// `quantize` snaps an arbitrary value to the nearest step within the
    /// range — the font-size case (step 1 over 12...64).
    @Test func quantize_snapsToFontSizeStep() {
        let range = TypographySettings.fontSizeRange
        #expect(SettingsSliderRow.quantize(18.4, in: range, step: 1) == 18)
        #expect(SettingsSliderRow.quantize(18.6, in: range, step: 1) == 19)
        #expect(SettingsSliderRow.quantize(20.0, in: range, step: 1) == 20)
    }

    /// The line-spacing case — step 0.1 over 1.0...2.0 — snaps fractional
    /// drag positions to the nearest tenth.
    @Test func quantize_snapsToLineSpacingStep() {
        let range = TypographySettings.lineSpacingRange
        #expect(abs(SettingsSliderRow.quantize(1.43, in: range, step: 0.1) - 1.4) < 0.0001)
        #expect(abs(SettingsSliderRow.quantize(1.47, in: range, step: 0.1) - 1.5) < 0.0001)
    }

    /// Quantization clamps to the range bounds — a value past the max
    /// snaps to the max, not beyond.
    @Test func quantize_clampsToRangeBounds() {
        let range = TypographySettings.fontSizeRange
        #expect(SettingsSliderRow.quantize(100, in: range, step: 1) == 64)
        #expect(SettingsSliderRow.quantize(-5, in: range, step: 1) == 12)
    }

    // MARK: - value(atFraction:)

    /// A drag fraction maps back to a quantized value — the inverse of
    /// `progress`. Fraction 0 → range min, 1 → range max.
    @Test func valueAtFraction_mapsTrackPositionToValue() {
        let range = TypographySettings.fontSizeRange
        #expect(SettingsSliderRow.value(atFraction: 0, in: range, step: 1) == 12)
        #expect(SettingsSliderRow.value(atFraction: 1, in: range, step: 1) == 64)
        #expect(SettingsSliderRow.value(atFraction: 0.5, in: range, step: 1) == 38)
    }

    /// A fraction outside 0...1 (an over-drag past the track edge) still
    /// resolves to an in-range, quantized value.
    @Test func valueAtFraction_clampsOverDrag() {
        let range = TypographySettings.lineSpacingRange
        #expect(SettingsSliderRow.value(atFraction: -0.3, in: range, step: 0.1) == range.lowerBound)
        #expect(SettingsSliderRow.value(atFraction: 1.7, in: range, step: 0.1) == range.upperBound)
    }

    // MARK: - Binding round-trip

    /// The slider drives its `Binding<CGFloat>` — a quantized drag result
    /// written through `value(atFraction:)` round-trips into the binding.
    @Test func binding_roundTripsThroughTypographyFontSize() {
        var typography = TypographySettings()
        let binding = Binding<CGFloat>(
            get: { typography.fontSize },
            set: { typography.fontSize = $0 }
        )
        let newValue = SettingsSliderRow.value(
            atFraction: 0.5, in: TypographySettings.fontSizeRange, step: 1
        )
        binding.wrappedValue = newValue
        #expect(typography.fontSize == 38)
    }

    /// Writing through the binding respects `TypographySettings`'
    /// own clamping — an out-of-range write lands clamped, never invalid.
    @Test func binding_respectsTypographyClamping() {
        var typography = TypographySettings()
        let binding = Binding<CGFloat>(
            get: { typography.lineSpacing },
            set: { typography.lineSpacing = $0 }
        )
        binding.wrappedValue = 9.0
        #expect(typography.lineSpacing == TypographySettings.lineSpacingRange.upperBound)
    }

    // MARK: - Glyph model

    /// The leading/trailing `Glyph` cases cover the design's slider
    /// affordances: the `Aa` size letters and the SF Symbol icons.
    @Test func glyph_exposesDesignAffordances() {
        let small = SettingsSliderRow.Glyph.text("A", size: 13)
        let large = SettingsSliderRow.Glyph.text("A", size: 22)
        let icon = SettingsSliderRow.Glyph.symbol("text.alignleft")
        #expect(small != large)
        #expect(small != icon)
    }

    // MARK: - Construction

    /// The `CGFloat`-native initializer accepts the real typography
    /// bindings, ranges, and steps without a `Double` round-trip
    /// (round-1 audit finding 3).
    @Test @MainActor func init_acceptsCGFloatTypographyBindings() {
        let store = ReaderSettingsStore(defaults: Self.isolatedDefaults())
        let row = SettingsSliderRow(
            value: Binding(
                get: { store.typography.fontSize },
                set: { store.typography.fontSize = $0 }
            ),
            range: TypographySettings.fontSizeRange,
            step: 1,
            leading: .text("A", size: 13),
            trailing: .text("A", size: 22),
            accessibilityLabel: "Font size"
        )
        #expect(row.accessibilityLabel == "Font size")
        #expect(row.range == TypographySettings.fontSizeRange)
        #expect(row.step == 1)
    }

    // MARK: - Full-row hit geometry (Gate-4 round-1 Medium fix)

    /// The track width subtracts both paddings, both glyph columns, and
    /// both inter-column gaps from the full row width.
    @Test func trackWidth_subtractsPaddingAndGlyphColumns() {
        // 2*14 padding + 24 + 28 glyphs + 2*12 gaps = 104 consumed.
        #expect(SettingsSliderRow.trackWidth(forRowWidth: 304) == 200)
        #expect(SettingsSliderRow.trackWidth(forRowWidth: 104) == 0)
    }

    /// A row narrower than the chrome never yields a negative track
    /// width — it pins to zero.
    @Test func trackWidth_neverNegativeForTooNarrowRow() {
        #expect(SettingsSliderRow.trackWidth(forRowWidth: 40) == 0)
        #expect(SettingsSliderRow.trackWidth(forRowWidth: 0) == 0)
    }

    /// The track origin is left padding + leading glyph + one gap.
    @Test func trackOriginX_isPaddingPlusLeadingGlyphPlusGap() {
        // 14 padding + 24 leading glyph + 12 gap = 50.
        #expect(SettingsSliderRow.trackOriginX == 50)
    }

    /// A touch in the FULL ROW maps to a track fraction — the whole
    /// 44 pt row is a live hit target, not just the 24 pt track
    /// (Gate-4 round-1 Medium finding). Row width 304 → track 200 wide,
    /// origin at x=50.
    @Test func trackFraction_mapsFullRowTouchToTrackFraction() {
        // x = trackOriginX → fraction 0 (left track edge).
        #expect(SettingsSliderRow.trackFraction(forRowX: 50, rowWidth: 304) == 0)
        // x = trackOriginX + trackWidth → fraction 1 (right track edge).
        #expect(SettingsSliderRow.trackFraction(forRowX: 250, rowWidth: 304) == 1)
        // x = track midpoint → fraction 0.5.
        #expect(abs(SettingsSliderRow.trackFraction(forRowX: 150, rowWidth: 304) - 0.5) < 0.0001)
    }

    /// A touch landing in the leading-glyph zone (left of the track)
    /// clamps to fraction 0; a touch in the trailing-glyph zone clamps
    /// to 1 — so a tap anywhere on the row produces an in-range value.
    @Test func trackFraction_clampsGlyphZoneTouchesToTrackEdges() {
        // x in the leading glyph / left padding (< trackOriginX) → 0.
        #expect(SettingsSliderRow.trackFraction(forRowX: 10, rowWidth: 304) == 0)
        #expect(SettingsSliderRow.trackFraction(forRowX: 0, rowWidth: 304) == 0)
        // x in the trailing glyph / right padding (> track end) → 1.
        #expect(SettingsSliderRow.trackFraction(forRowX: 300, rowWidth: 304) == 1)
    }

    /// A full-row touch resolves through `value(atFraction:)` to a
    /// quantized in-range value — the end-to-end drag path.
    @Test func trackFraction_endToEndResolvesQuantizedValue() {
        let range = TypographySettings.fontSizeRange
        let fraction = SettingsSliderRow.trackFraction(forRowX: 150, rowWidth: 304)
        let value = SettingsSliderRow.value(atFraction: fraction, in: range, step: 1)
        #expect(value == 38) // midpoint of 12...64
    }

    // MARK: - Helpers

    private static func isolatedDefaults() -> UserDefaults {
        let suite = "SettingsSliderRowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
