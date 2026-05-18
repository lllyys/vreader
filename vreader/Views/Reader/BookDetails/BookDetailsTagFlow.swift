// Purpose: Feature #61 WI-3 — a wrapping, center-aligned flow layout
// for the Book Details sheet's collection-tag chips. SwiftUI ships no
// built-in flow layout, and an `HStack` overflows when a book belongs
// to many collections; this `Layout` wraps the chips onto as many
// centered rows as the proposed width needs. Pinned to
// `vreader-book-details.jsx`'s `DetailsStacked` tag row
// (`flexWrap: wrap, justifyContent: center`).
//
// Split into its own file so `BookDetailsSheet.swift` stays under the
// ~300-line guideline (rule 50 §9).
//
// @coordinates-with: BookDetailsSheet.swift

#if canImport(UIKit)
import SwiftUI

/// A flow layout: places subviews left-to-right, wrapping to a new row
/// when the next subview would exceed the proposed width, and centers
/// each row horizontally within the available width.
struct BookDetailsTagFlow: Layout {
    /// Horizontal gap between chips in a row.
    var spacing: CGFloat = 6
    /// Vertical gap between wrapped rows.
    var lineSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        guard !rows.isEmpty else { return .zero }
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(rows.count - 1)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout Void
    ) {
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            // Each chip is clamped to `bounds.width` (see `measure`), so
            // `row.width` never exceeds it — the centering offset stays
            // non-negative and a long chip cannot bleed past the edges.
            var x = bounds.minX + (bounds.width - row.width) / 2
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    // MARK: - Row computation

    /// One placed chip: its subview index and clamped measured size.
    private struct Item {
        let index: Int
        let size: CGSize
    }

    /// One wrapped row: its chips plus the row's measured width/height.
    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Measures a subview against the available width, clamping the
    /// result so a single very long chip (e.g. a long collection name)
    /// cannot exceed `maxWidth` and overflow the centered row. The chip
    /// itself truncates its text to fit (`BookDetailsSheet`'s tag chip
    /// uses `lineLimit(1)`).
    private func measure(
        _ subview: LayoutSubviews.Element, maxWidth: CGFloat
    ) -> CGSize {
        let cap = max(0, maxWidth)
        let size = subview.sizeThatFits(ProposedViewSize(width: cap, height: nil))
        return CGSize(width: min(size.width, cap), height: size.height)
    }

    /// Greedily packs subviews into rows that each fit `maxWidth`.
    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = measure(subviews[index], maxWidth: maxWidth)
            let projected = current.items.isEmpty
                ? size.width
                : current.width + spacing + size.width
            if !current.items.isEmpty && projected > maxWidth {
                rows.append(current)
                current = Row(
                    items: [Item(index: index, size: size)],
                    width: size.width, height: size.height)
            } else {
                current.items.append(Item(index: index, size: size))
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
#endif
