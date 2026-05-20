// Purpose: Feature #56 WI-15 — a minimal SwiftUI `Layout` implementation
// for wrapping a horizontal stack onto multiple rows. Used by
// `ReTranslateModelChips` (in `ReTranslatePickerSheetParts.swift`); a
// future picker section that needs the same shape can reuse it.
//
// SwiftUI does not ship a native flow layout under the minimum iOS target;
// this is the standard `Layout`-protocol implementation.
//
// Extracted from `ReTranslatePickerSheetParts.swift` so neither file
// exceeds the ~300-LoC guidance (rule 50 §9).
//
// @coordinates-with: ReTranslatePickerSheetParts.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-15)

import SwiftUI

/// Minimal flow layout — wraps subviews when they exceed one row's width.
struct ReTranslateFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width + spacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        return CGSize(width: maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: origin, proposal: ProposedViewSize(size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
