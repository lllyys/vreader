// Purpose: Custom accent-track slider row for the Reader Settings panel
// (feature #66 WI-1). Replaces the native `Slider` in the panel's
// font-size and line-spacing sections with the design bundle's
// `SliderRow` (`dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`):
// a 14 pt-radius tinted container holding a leading glyph, a 4 pt
// accent-filled track with a 22 pt white thumb, and a trailing glyph.
//
// Key decisions:
// - `CGFloat`-native API. The real bindings (`TypographySettings.fontSize`
//   / `lineSpacing`) are `CGFloat`; a `Double` round-trip would be lossy
//   ceremony (feature #66 Gate-2 round-1 finding 3).
// - Accessibility: the custom track has no innate adjustable semantics,
//   so the row is backed by `.accessibilityRepresentation { Slider(...) }`
//   — VoiceOver / Switch Control / Voice Control see a genuine native
//   slider (label, value, increment/decrement). The container also keeps
//   a 44 pt minimum hit target (feature #66 Gate-2 round-1 finding 4).
// - Continuous binding updates during drag — no debounce — so the live
//   reader preview tracks the thumb exactly as the native `Slider` did
//   (feature #66 plan risk 2).
// - Theme-tinted: the track / fill / glyphs read the active
//   `ReaderThemeV2` so contrast holds across all 5 sheet surfaces
//   (feature #66 plan risk 3).
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift,
//   vreader/Models/TypographySettings.swift, vreader/Models/ReaderThemeV2.swift

import SwiftUI

/// A custom accent-track slider row mirroring the design's `SliderRow`.
struct SettingsSliderRow: View {

    /// A leading / trailing slider affordance — the design draws either a
    /// typeface `Aa` letter (font-size row) or an SF Symbol (line-spacing
    /// row). Pure value type so the row's affordances are testable.
    enum Glyph: Equatable {
        /// A text glyph at a point size — the design's `Aa` size letters.
        case text(String, size: CGFloat)
        /// An SF Symbol glyph — the line-spacing row's leading/trailing icons.
        case symbol(String)
    }

    /// The bound value — continuously updated during drag.
    @Binding var value: CGFloat
    /// The legal value range (e.g. `TypographySettings.fontSizeRange`).
    let range: ClosedRange<CGFloat>
    /// The quantization step (1 pt for font size, 0.1× for line spacing).
    let step: CGFloat
    /// The leading affordance, shown left of the track.
    let leading: Glyph
    /// The trailing affordance, shown right of the track.
    let trailing: Glyph
    /// VoiceOver label for the slider (e.g. "Font size").
    let accessibilityLabel: String
    /// The active reader theme — drives track / fill / glyph contrast.
    var theme: ReaderThemeV2 = .default

    init(
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        leading: Glyph,
        trailing: Glyph,
        accessibilityLabel: String,
        theme: ReaderThemeV2 = .default
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.leading = leading
        self.trailing = trailing
        self.accessibilityLabel = accessibilityLabel
        self.theme = theme
    }

    // MARK: - Pure value math (testable)

    /// Maps `value` onto a 0...1 track fraction, clamped so the thumb
    /// never escapes the track. A degenerate (single-point) range pins
    /// the fraction to 0 — no divide-by-zero.
    static func progress(for value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let raw = (value - range.lowerBound) / span
        return min(max(raw, 0), 1)
    }

    /// Snaps an arbitrary value to the nearest `step` within `range`.
    static func quantize(
        _ value: CGFloat, in range: ClosedRange<CGFloat>, step: CGFloat
    ) -> CGFloat {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }
        let steps = ((clamped - range.lowerBound) / step).rounded()
        let snapped = range.lowerBound + steps * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    /// Maps a 0...1 track fraction back to a quantized in-range value —
    /// the inverse of `progress`. An over-drag past the track edge still
    /// resolves in-range.
    static func value(
        atFraction fraction: CGFloat, in range: ClosedRange<CGFloat>, step: CGFloat
    ) -> CGFloat {
        let clampedFraction = min(max(fraction, 0), 1)
        let span = range.upperBound - range.lowerBound
        let raw = range.lowerBound + clampedFraction * span
        return quantize(raw, in: range, step: step)
    }

    // MARK: - Layout constants

    /// Horizontal padding inside the row container (design's `14`).
    static let horizontalPadding: CGFloat = 14
    /// Spacing between glyph columns and the track (design's `gap: 12`).
    static let columnSpacing: CGFloat = 12
    /// Leading glyph column width (design's `width: 24`).
    static let leadingGlyphWidth: CGFloat = 24
    /// Trailing glyph column width (design's `width: 28`).
    static let trailingGlyphWidth: CGFloat = 28

    /// The track's x-origin within a full-row width — left padding +
    /// leading glyph column + one inter-column gap.
    static var trackOriginX: CGFloat {
        horizontalPadding + leadingGlyphWidth + columnSpacing
    }

    /// The track's drawn width for a given full-row width — the row
    /// width minus both paddings, both glyph columns, and both gaps.
    /// Never negative (a too-narrow row pins the track to zero width).
    static func trackWidth(forRowWidth rowWidth: CGFloat) -> CGFloat {
        let consumed = 2 * horizontalPadding
            + leadingGlyphWidth + trailingGlyphWidth
            + 2 * columnSpacing
        return max(0, rowWidth - consumed)
    }

    /// Maps an x-position measured in the FULL ROW's coordinate space to
    /// a 0...1 track fraction. A touch landing in the leading-glyph zone
    /// resolves to 0, the trailing zone to 1 — so the entire 44 pt row
    /// is a live hit target, not just the 24 pt-tall track (feature #66
    /// Gate-4 round-1 Medium finding).
    static func trackFraction(forRowX rowX: CGFloat, rowWidth: CGFloat) -> CGFloat {
        let width = trackWidth(forRowWidth: rowWidth)
        guard width > 0 else { return 0 }
        let local = rowX - trackOriginX
        return min(max(local / width, 0), 1)
    }

    // MARK: - Body

    /// The row's fixed content height — the design's 24 pt track plus
    /// 12 pt vertical padding top and bottom (`12 + 24 + 12`). Definite
    /// so the body's `GeometryReader` lays out inside a `List` row
    /// (a bare `GeometryReader` has no intrinsic height and would
    /// collapse). Comfortably exceeds the 44 pt accessibility minimum.
    static let rowHeight: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let rowWidth = geo.size.width
            HStack(spacing: Self.columnSpacing) {
                glyphView(leading)
                    .frame(width: Self.leadingGlyphWidth)
                track(rowWidth: rowWidth)
                glyphView(trailing)
                    .frame(width: Self.trailingGlyphWidth)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 12)
            .frame(width: rowWidth, height: geo.size.height)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(containerFill)
            )
            // The drag gesture spans the WHOLE row — `contentShape` makes
            // the padded container (and the glyph columns) hittable, so
            // the advertised 44 pt target is real, not just the track.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard rowWidth > 0 else { return }
                        let fraction = SettingsSliderRow.trackFraction(
                            forRowX: drag.location.x, rowWidth: rowWidth
                        )
                        let newValue = SettingsSliderRow.value(
                            atFraction: fraction, in: range, step: step
                        )
                        if newValue != value { value = newValue }
                    }
            )
        }
        .frame(height: Self.rowHeight)
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { value },
                    set: { value = SettingsSliderRow.quantize($0, in: range, step: step) }
                ),
                in: range,
                step: step
            )
            .accessibilityLabel(accessibilityLabel)
        }
    }

    /// The 4 pt accent-filled track with the 22 pt white thumb. The
    /// track is purely visual — the drag gesture lives on the outer
    /// row so the full 44 pt height is interactive.
    private func track(rowWidth: CGFloat) -> some View {
        let trackWidth = Self.trackWidth(forRowWidth: rowWidth)
        let fraction = SettingsSliderRow.progress(for: value, in: range)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(trackColor)
                .frame(height: 4)
            Capsule()
                .fill(Color(theme.accentColor))
                .frame(width: max(0, trackWidth * fraction), height: 4)
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .offset(x: max(0, min(trackWidth, trackWidth * fraction)) - 11)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
    }

    @ViewBuilder
    private func glyphView(_ glyph: Glyph) -> some View {
        switch glyph {
        case let .text(string, size):
            Text(string)
                .font(.system(size: size, design: .serif))
                .foregroundStyle(Color(theme.subColor))
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(theme.subColor))
        }
    }

    /// The container's subtle fill — the design's
    /// `t.isDark ? rgba(255,255,255,0.05) : rgba(0,0,0,0.04)`.
    private var containerFill: Color {
        theme.isDark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.04)
    }

    /// The unfilled track color — the per-theme `sliderTrack` token (Bug #285 /
    /// #1273). The old inline `isDark ? white@0.1 : black@0.1` was a cold
    /// pure-black smudge over the cream panel (~1.25:1); `sliderTrack` is each
    /// theme's `ink` at the design-specified weight (light family @22% → ~1.6:1).
    private var trackColor: Color {
        Color(theme.sliderTrack)
    }
}
