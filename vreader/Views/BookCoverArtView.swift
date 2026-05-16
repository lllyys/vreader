// Purpose: Shared cover-art view for the Library grid card + list row
// (feature #60 visual identity v2). Renders a custom cover image when
// one exists, otherwise a generative typographic cover (feature #60
// WI-10), and overlays the design's physical-book treatment: spine
// shadow, page-edge highlight, hairline border, drop shadow.
//
// Key decisions:
// - **Fixed 2:3 aspect ratio.** `Color.clear` drives layout so every
//   card in a LazyVGrid row gets an identical height regardless of the
//   underlying image dimensions. Image lives in `.overlay`, never in
//   `.background`, so it never participates in sizing. `.clipped()`
//   trims any scaledToFill overflow.
// - **No-image fallback is a generative cover** (feature #60 WI-10).
//   When `image` is nil, `GenerativeCoverView` renders a typographic
//   cover whose style + palette are deterministically derived from the
//   book's `fingerprintKey` — so a given book always shows the same
//   cover. This replaces the old plain format-colored placeholder.
// - **Spine + page-edge accents** are gradient strips per the design
//   `BookCover` component — left spine darkens, right edge has a thin
//   page highlight. They sit inside the clip so they curve with the
//   corner radius.
// - **Corner radius is a parameter** — the grid card uses 4pt, the
//   list-row thumbnail uses 3pt (per design `vreader-library.jsx`).
//
// @coordinates-with: BookCardView.swift, BookRowView.swift,
//   LibraryContinueCard.swift, LibraryCardTokens.swift,
//   GenerativeCoverView.swift, GenerativeCoverStyle.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-cover.jsx`

import SwiftUI

/// Cover-art view: a custom image, or a generative typographic cover
/// fallback, with the feature-#60 spine / page-edge / border / shadow
/// treatment.
struct BookCoverArtView: View {
    let image: UIImage?
    /// The book's stable identity — drives the deterministic generative
    /// cover style + palette when no image exists (feature #60 WI-10).
    let fingerprintKey: String
    /// Book title shown on the generative cover.
    let title: String
    /// Book author shown on the generative cover (nil when unknown).
    let author: String?
    var cornerRadius: CGFloat = LibraryCardTokens.cardCoverCornerRadius

    /// Whether the cover renders the generative typographic fallback
    /// rather than a custom image. `true` exactly when no image exists.
    /// Static so the WI-10 contract tests can pin the decision policy
    /// without a SwiftUI render.
    static func usesGenerativeFallback(hasImage: Bool) -> Bool {
        !hasImage
    }

    /// The generative cover style this book resolves to — exposed so
    /// the WI-10 contract tests can pin the per-book derivation.
    var generativeStyleForTesting: GenerativeCoverStyle {
        GenerativeCoverStyle.style(forFingerprintKey: fingerprintKey)
    }

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
                        generativeCover
                    }
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

    // MARK: - Generative cover fallback (feature #60 WI-10)

    /// The generative typographic cover shown when no custom image
    /// exists. Style + palette are deterministically derived from the
    /// book's `fingerprintKey`, so a given book always renders the
    /// same cover across launches.
    private var generativeCover: some View {
        let style = GenerativeCoverStyle.style(forFingerprintKey: fingerprintKey)
        let palette = GenerativeCoverPalette.palette(
            forFingerprintKey: fingerprintKey
        )
        return GenerativeCoverView(
            title: title,
            author: author,
            style: style,
            palette: palette
        )
    }

    // MARK: - Physical-book accents (per design BookCover)

    /// Left-edge spine shadow — a gradient that darkens toward the
    /// binding so the cover reads as a physical book object.
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
