// Purpose: Feature #74 WI-1 — pure paint parameters for the highlight-landing
// "locate bloom" (design: dev-docs/designs/vreader-fidelity-v1/project/
// design-notes/reader-highlight-landing.md). Maps a bloom intensity (0 = rest,
// 1 = peak) + the theme family to the wash alpha, ring width, glow radius, and
// glow alpha that `HighlightingLayoutManager` paints for the landing layer, plus
// the pure `suppressesPersisted` decision (the landing wash REPLACES the
// equal-range persisted fill rather than stacking on it and darkening).
//
// Pure + unit-tested; the actual painting + the bloom animation driver live in
// HighlightableTextView.swift (WI-1 render layer) and WI-2 (animation).
//
// @coordinates-with: HighlightableTextView.swift, HighlightPaintColor.swift

#if canImport(UIKit)
import UIKit

/// Light (Paper / Sepia) vs dark (Dark / OLED / Photo) theme family — only the
/// glow alpha differs (design §6: light 0.55, dark 0.85).
enum LandingBloomThemeFamily: Equatable { case light, dark }

/// The wash / ring / glow paint parameters for the locate bloom at a given
/// `intensity`. `intensity 0` is the resting state (== the persisted highlight);
/// `intensity 1` is the bloom peak.
struct LandingBloomPaint: Equatable {

    /// Wash fill alpha — lerps from the persisted resting fill
    /// (`HighlightPaintColor.fillAlpha`) to the bloom peak (0.86).
    let washAlpha: CGFloat
    /// Focus-ring stroke width (pt) — 0 at rest, 1.6 at peak.
    let ringWidth: CGFloat
    /// Glow blur radius (pt) — 0 at rest, 16 at peak.
    let glowRadius: CGFloat
    /// Glow color alpha — 0 at rest; 0.55 (light) / 0.85 (dark) at peak.
    let glowAlpha: CGFloat

    /// Design §3 / §6. `washAlpha` lerps from `HighlightPaintColor.fillAlpha`
    /// (the persisted resting wash, so `intensity 0` matches the persisted
    /// highlight's source alpha) to 0.86 at peak; the ring (1.6 pt), glow radius
    /// (16 pt), and glow alpha (0.55 light / 0.85 dark) scale linearly with
    /// intensity. `intensity` is clamped to `[0, 1]`.
    init(intensity: CGFloat, family: LandingBloomThemeFamily) {
        let i = min(max(intensity, 0), 1)
        let base = HighlightPaintColor.fillAlpha
        washAlpha = base + (0.86 - base) * i
        ringWidth = 1.6 * i
        glowRadius = 16 * i
        glowAlpha = (family == .light ? 0.55 : 0.85) * i
    }

    /// Whether the landing wash REPLACES the persisted fill for `persistedRange`
    /// (the design's single wash value-lift — never two stacked translucent
    /// fills that composite darker). True iff the ranges are equal — the
    /// feature's case (a Notes/Highlights row tap lands on the exact saved
    /// range; the navigation passes the locator's saved char range verbatim).
    static func suppressesPersisted(persistedRange: NSRange, landingRange: NSRange) -> Bool {
        NSEqualRanges(persistedRange, landingRange)
    }
}
#endif
