// Purpose: Feature #60 visual-identity v2 (WI-10) — layout metrics +
// the `RGBTriple → Color` bridge for the generative book-cover view.
// Extracted from `GenerativeCoverView` to keep that file under the
// ~300-line guideline.
//
// @coordinates-with: GenerativeCoverView.swift, GenerativeCoverStyle.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-cover.jsx`

import SwiftUI

/// Width-derived layout metrics for `GenerativeCoverView` — mirrors the
/// design `CoverArt`'s `w * 0.13` title / `w * 0.075` author /
/// `w * 0.11` padding scaling so one view renders correctly at every
/// cover size (grid card, list row, continue rail).
struct GenerativeCoverMetrics {
    let titleSize: CGFloat
    let authorSize: CGFloat
    let padding: CGFloat
    let contentWidth: CGFloat

    init(width: CGFloat) {
        let w = width.isFinite && width > 0 ? width : 110
        self.titleSize = max(11, w * 0.13)
        self.authorSize = max(8, w * 0.075)
        self.padding = max(8, w * 0.11)
        self.contentWidth = max(0, w - padding * 2)
    }
}

// MARK: - Color from RGBTriple

extension Color {
    /// Builds a SwiftUI `Color` from a Foundation-only `RGBTriple` in
    /// the sRGB space — the generative-cover palettes store raw RGB so
    /// the model layer compiles without SwiftUI.
    init(rgb triple: RGBTriple) {
        self = Color(
            .sRGB,
            red: Double(triple.red) / 255.0,
            green: Double(triple.green) / 255.0,
            blue: Double(triple.blue) / 255.0
        )
    }
}
