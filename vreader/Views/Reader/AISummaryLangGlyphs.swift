// Purpose: Feature #90 WI-2 — the custom Single / Bilingual segment glyphs for
// `AISummaryLangRow`, transcribed from the committed artboard's `LineGlyph` /
// `StackGlyph` (Gate-4 M2: SF Symbols were a Rule-51 fidelity miss). All strokes
// are authored in the design's 16-unit coordinate space and scaled to the view.
//
// @coordinates-with: AISummaryLangRow.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/bilingual-summarize-artboards.jsx`
//   (`LineGlyph` :85-91, `StackGlyph` :92-101)

#if canImport(UIKit)
import SwiftUI

/// A set of horizontal strokes `(x1, y, x2)` in the design's 16-unit space.
private struct SummaryGlyphLines: Shape {
    /// Each tuple is (startX, y, endX) in 16-unit coordinates.
    let lines: [(CGFloat, CGFloat, CGFloat)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = rect.width / 16
        for (x1, y, x2) in lines {
            path.move(to: CGPoint(x: x1 * scale, y: y * scale))
            path.addLine(to: CGPoint(x: x2 * scale, y: y * scale))
        }
        return path
    }
}

private func summaryGlyphStroke(_ size: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: 1.6 * size / 16, lineCap: .round)
}

/// Design `LineGlyph` — a full line over a shorter one (the "single column").
struct SummaryLineGlyph: View {
    let size: CGFloat
    let color: Color
    var body: some View {
        SummaryGlyphLines(lines: [(3, 6, 13), (3, 10, 10)])
            .stroke(color, style: summaryGlyphStroke(size))
            .frame(width: size, height: size)
    }
}

/// Design `StackGlyph` — two stacked line-pairs, the lower one faded (the
/// bilingual "stacked" treatment).
struct SummaryStackGlyph: View {
    let size: CGFloat
    let color: Color
    var body: some View {
        ZStack {
            SummaryGlyphLines(lines: [(3, 4, 13), (3, 7, 7)])
                .stroke(color, style: summaryGlyphStroke(size))
            SummaryGlyphLines(lines: [(3, 11, 13), (3, 13.5, 7)])
                .stroke(color.opacity(0.55), style: summaryGlyphStroke(size))
        }
        .frame(width: size, height: size)
    }
}
#endif
