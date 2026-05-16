// Purpose: Shared cover-art view for the Library grid card + list row
// (feature #60 visual identity v2). Renders a custom cover image when
// one exists, otherwise a format-colored placeholder, and overlays the
// design's physical-book treatment: spine shadow, page-edge highlight,
// hairline border, drop shadow.
//
// Key decisions:
// - **Fixed 2:3 aspect ratio.** `Color.clear` drives layout so every
//   card in a LazyVGrid row gets an identical height regardless of the
//   underlying image dimensions. Image lives in `.overlay`, never in
//   `.background`, so it never participates in sizing. `.clipped()`
//   trims any scaledToFill overflow.
// - **Spine + page-edge accents** are gradient strips per the design
//   `BookCover` component — left spine darkens, right edge has a thin
//   page highlight. They sit inside the clip so they curve with the
//   corner radius.
// - **Corner radius is a parameter** — the grid card uses 4pt, the
//   list-row thumbnail uses 3pt (per design `vreader-library.jsx`).
//
// @coordinates-with: BookCardView.swift, BookRowView.swift,
//   LibraryCardTokens.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-cover.jsx`

import SwiftUI

/// Cover-art view: custom image or format-colored placeholder, with the
/// feature-#60 spine / page-edge / border / shadow treatment.
struct BookCoverArtView: View {
    let image: UIImage?
    let coverColor: Color
    let formatIcon: String
    let formatBadge: String
    var cornerRadius: CGFloat = LibraryCardTokens.cardCoverCornerRadius

    var body: some View {
        Color(white: 0.92)
            .aspectRatio(LibraryCardTokens.coverAspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        coverColor
                    }
                }
            }
            .overlay {
                if image == nil {
                    placeholderGlyph
                }
            }
            .overlay { spineShadow }
            .overlay { pageEdge }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                // Bug #107: a subtle hairline keeps light-edged covers
                // delineated against the warm-paper library background.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LibraryCardTokens.coverBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }

    // MARK: - Placeholder

    /// Format glyph + uppercase badge shown when no custom cover exists.
    private var placeholderGlyph: some View {
        VStack(spacing: 4) {
            Image(systemName: formatIcon)
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.8))
            Text(formatBadge)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - Physical-book accents (per design BookCover)

    /// Left-edge spine shadow — a gradient that darkens toward the
    /// binding so a flat color placeholder reads as a book object.
    private var spineShadow: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.25), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 6)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    /// Right-edge page highlight — a thin strip suggesting cut pages.
    private var pageEdge: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.black.opacity(0.12), .white.opacity(0.18)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 2)
        }
        .allowsHitTesting(false)
    }
}
