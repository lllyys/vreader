// Purpose: Bug #260 / GH #1130 — pure label formatting for the
// AZW3/MOBI bottom-chrome scrubber's two end-aligned position labels.
// Foliate relocate carries `tocLabel`, `sectionIndex`, `sectionTotal`,
// and the reading `fraction`; this maps them to the leading + trailing
// label strings the shared `ReaderBottomChrome` renders. Extracted as a
// pure static so the formatting + the edge cases (no TOC label, sparse
// metadata, single-section book) are unit-testable without a SwiftUI
// render path.
//
// @coordinates-with: FoliateBilingualContainerView+BottomChrome.swift,
//   ReaderBottomChrome.swift, FoliateBottomChromeWiringTests.swift

import Foundation

/// Builds the two bottom-chrome position labels for AZW3/MOBI.
enum FoliateBottomChromeLabels {

    /// The resolved (leading, trailing) labels for the scrubber.
    struct Labels: Equatable {
        let leading: String
        let trailing: String
    }

    /// - leading: the current chapter title (`tocLabel`) when present
    ///   and non-blank, otherwise the reading percentage (e.g. "45%").
    /// - trailing: "Chapter X of Y" derived from `sectionIndex` (0-based
    ///   → 1-based) and `sectionTotal`, or empty when section metadata
    ///   is missing / a single-section book (no useful position).
    static func make(
        tocLabel: String?,
        sectionIndex: Int?,
        sectionTotal: Int?,
        fraction: Double
    ) -> Labels {
        let percent = percentLabel(fraction)
        let trimmedTOC = tocLabel?.trimmingCharacters(in: .whitespacesAndNewlines)

        let leading: String
        if let toc = trimmedTOC, !toc.isEmpty {
            leading = toc
        } else {
            leading = percent
        }

        let trailing = sectionPositionLabel(
            sectionIndex: sectionIndex,
            sectionTotal: sectionTotal
        )
        return Labels(leading: leading, trailing: trailing)
    }

    /// "NN%" from a 0...1 fraction, clamped + rounded.
    static func percentLabel(_ fraction: Double) -> String {
        let clamped = fraction.isNaN ? 0 : min(1.0, max(0.0, fraction))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// "Chapter X of Y" (1-based) or empty when there is no meaningful
    /// multi-section position (missing total, total ≤ 1, or a negative
    /// index).
    static func sectionPositionLabel(sectionIndex: Int?, sectionTotal: Int?) -> String {
        guard let total = sectionTotal, total > 1,
              let index = sectionIndex, index >= 0 else {
            return ""
        }
        // Clamp the 1-based position into 1...total so a relocate that
        // briefly reports an out-of-range index never prints "Chapter
        // 13 of 12".
        let position = min(total, index + 1)
        return "Chapter \(position) of \(total)"
    }
}
