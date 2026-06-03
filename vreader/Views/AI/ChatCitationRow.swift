// Purpose: The "Drew on" provenance row under an AI Chat reply (Feature #86 WI-6,
// design #1455). A small uppercase "Drew on" label followed by chips naming what
// the answer read. A whole-book span that reached PAST the reader is an amber
// `· ahead` spoiler chip; everything else is a neutral chip (a note chip carries a
// note glyph).
//
// @coordinates-with: ChatCitation.swift, AIChatMessageRow.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/chat-context-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

struct ChatCitationRow: View {
    let citations: [ChatCitation]
    let theme: ReaderThemeV2

    static let identifier = "chatCitationRow"

    var body: some View {
        FlowRow(spacing: 6) {
            Text("Drew on")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Color(theme.subColor))
            ForEach(citations) { citation in
                chip(citation)
            }
        }
        .accessibilityIdentifier(Self.identifier)
        .accessibilityElement(children: .combine)
        // Gate-4 WI-6: announce the spoiler ("ahead") state to VoiceOver, not just
        // the label — otherwise a spoiler chip sounds the same as a safe one.
        .accessibilityLabel("Drew on: " + citations.map {
            $0.aheadOfReader ? "\($0.label), ahead" : $0.label
        }.joined(separator: ", "))
    }

    @ViewBuilder
    private func chip(_ citation: ChatCitation) -> some View {
        let ahead = citation.aheadOfReader
        HStack(spacing: 4) {
            if citation.sourceKind == .note {
                Image(systemName: "note.text").font(.system(size: 10))
            }
            if ahead {
                Image(systemName: "info.circle").font(.system(size: 10, weight: .semibold))
            }
            Text(ahead ? "\(citation.label) · ahead" : citation.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color(ahead ? amberInk : theme.subColor))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(ahead ? amberWash : neutralWash)))
        .overlay(
            Capsule().stroke(Color(ahead ? amberBorder : .clear), lineWidth: 0.5)
        )
    }

    // Amber spoiler treatment.
    private var amberInk: UIColor {
        theme.isDark ? UIColor(red: 0xe8/255, green: 0xb4/255, blue: 0x65/255, alpha: 1)
                     : UIColor(red: 0x9a/255, green: 0x6a/255, blue: 0x1f/255, alpha: 1)
    }
    private var amberWash: UIColor { UIColor(red: 180/255, green: 120/255, blue: 40/255, alpha: 0.13) }
    private var amberBorder: UIColor {
        theme.isDark ? UIColor(red: 232/255, green: 180/255, blue: 101/255, alpha: 0.4)
                     : UIColor(red: 154/255, green: 106/255, blue: 31/255, alpha: 0.3)
    }
    private var neutralWash: UIColor {
        theme.isDark ? UIColor(white: 1, alpha: 0.06) : UIColor(white: 0, alpha: 0.05)
    }
}

/// A minimal wrapping HStack (chips flow to the next line). Sufficient for the
/// short "Drew on" rows; avoids a heavier layout dependency.
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
#endif
