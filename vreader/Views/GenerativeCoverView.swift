// Purpose: Feature #60 visual-identity v2 (WI-10) — the generative
// typographic book-cover view. Rendered by `BookCoverArtView` when a
// book has no embedded / custom cover image, replacing the old plain
// format-colored placeholder.
//
// Layout is pinned to the committed design bundle
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-cover.jsx`
// (`CoverArt`) — five style families: classic / modern / animal /
// editorial / minimal. Each family is a distinct typographic
// composition of the book's title + author over a palette-coloured
// background.
//
// Key decisions:
// - **Style + palette are inputs, not derived here.** The deterministic
//   `fingerprintKey → (style, palette)` policy lives in
//   `GenerativeCoverStyle` / `GenerativeCoverPalette`; this view is
//   purely presentational so the policy stays unit-testable without a
//   render path.
// - **Metrics scale with the cover width** (matching the design's
//   `w * 0.13` title size etc.) so the same view renders correctly at
//   the grid-card, list-row, and continue-rail sizes.
// - **The spine / page-edge / shadow chrome stays in `BookCoverArtView`** —
//   this view fills the cover's interior only.
//
// @coordinates-with: BookCoverArtView.swift, GenerativeCoverStyle.swift,
//   ReaderTypography.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-cover.jsx`

import SwiftUI

/// Generative typographic cover interior — one of the design's five
/// `CoverArt` style families. Sized to fill its container.
struct GenerativeCoverView: View {
    let title: String
    let author: String?
    let style: GenerativeCoverStyle
    let palette: GenerativeCoverPalette

    var body: some View {
        GeometryReader { geo in
            let metrics = CoverMetrics(width: geo.size.width)
            ZStack {
                Color(rgb: palette.background)
                styleContent(metrics: metrics)
            }
        }
    }

    // MARK: - Per-style content

    @ViewBuilder
    private func styleContent(metrics: CoverMetrics) -> some View {
        switch style {
        case .classic:    classicArt(metrics)
        case .modern:     modernArt(metrics)
        case .animal:     animalArt(metrics)
        case .editorial:  editorialArt(metrics)
        case .minimal:    minimalArt(metrics)
        }
    }

    // MARK: - Classic

    /// Italic serif title at the top, a half-width accent rule, and an
    /// uppercase author at the bottom — `vreader-cover.jsx` `classic`.
    private func classicArt(_ m: CoverMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(titleFont(m.titleSize))
                .fontWeight(.semibold)
                .italic()
                .foregroundStyle(Color(rgb: palette.ink))
                .lineLimit(4)
            Spacer(minLength: 0)
            Rectangle()
                .fill(Color(rgb: palette.accent).opacity(0.7))
                .frame(width: m.contentWidth * 0.5, height: 1)
                .padding(.vertical, 4)
            Spacer(minLength: 0)
            authorText(uppercase: true, size: m.authorSize, tracking: 0.4)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(m.padding)
    }

    // MARK: - Modern

    /// Heavy Inter title top-left, a short accent tick + author at the
    /// bottom-left — `vreader-cover.jsx` `modern`.
    private func modernArt(_ m: CoverMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(titleFont(m.titleSize * 1.1))
                .fontWeight(.heavy)
                .foregroundStyle(Color(rgb: palette.ink))
                .lineLimit(4)
                .padding(.top, m.padding * 0.5)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Color(rgb: palette.accent))
                    .frame(width: 24, height: 2)
                authorText(uppercase: false, size: m.authorSize, tracking: 0)
                    .fontWeight(.medium)
                    .opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(m.padding)
    }

    // MARK: - Animal

    /// Serif title, an abstract block in the middle, author at the
    /// bottom — `vreader-cover.jsx` `animal` (O'Reilly-style).
    private func animalArt(_ m: CoverMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(titleFont(m.titleSize * 0.95))
                .fontWeight(.bold)
                .foregroundStyle(Color(rgb: palette.ink))
                .lineLimit(3)
            abstractBlock(m)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(m.padding * 0.5)
            authorText(uppercase: false, size: m.authorSize, tracking: 0)
                .fontWeight(.medium)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(m.padding)
    }

    /// The design's abstract animal-silhouette panel — a faint inked
    /// box with a centered glyph (`vreader-cover.jsx` draws an animal
    /// SVG; an SF Symbol stands in for the silhouette here, kept inside
    /// the framed box exactly as the design's `<svg>` is).
    private func abstractBlock(_ m: CoverMetrics) -> some View {
        ZStack {
            Rectangle().fill(Color(rgb: palette.ink).opacity(0.08))
            Rectangle().stroke(Color(rgb: palette.ink).opacity(0.15), lineWidth: 1)
            Image(systemName: "pawprint.fill")
                .font(.system(size: m.titleSize * 1.6))
                .foregroundStyle(Color(rgb: palette.ink).opacity(0.85))
        }
    }

    // MARK: - Editorial

    /// Uppercase accent author label at the top, a large serif title
    /// on a 40% baseline, a hairline + year footer —
    /// `vreader-cover.jsx` `editorial`.
    private func editorialArt(_ m: CoverMetrics) -> some View {
        ZStack {
            VStack {
                Text(authorSurname.uppercased())
                    .font(.system(size: m.authorSize * 0.85))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundStyle(Color(rgb: palette.accent))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color(rgb: palette.ink).opacity(0.5))
                        .frame(width: 16, height: 1)
                    Text(footerLabel)
                        .font(.system(size: m.authorSize * 0.85))
                        .tracking(0.6)
                        .foregroundStyle(Color(rgb: palette.ink).opacity(0.7))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Title centred on the design's 40% vertical baseline.
            VStack {
                Spacer(minLength: 0).frame(maxHeight: .infinity)
                Text(title)
                    .font(titleFont(m.titleSize * 1.2))
                    .fontWeight(.bold)
                    .foregroundStyle(Color(rgb: palette.ink))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0).frame(maxHeight: .infinity)
                Spacer(minLength: 0).frame(maxHeight: .infinity)
            }
        }
        .padding(m.padding)
    }

    // MARK: - Minimal

    /// A centred mark glyph, the serif title, and the sans author —
    /// all centre-aligned — `vreader-cover.jsx` `minimal`.
    private func minimalArt(_ m: CoverMetrics) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color(rgb: palette.accent), lineWidth: 1.5)
                    .frame(width: 28, height: 28)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(rgb: palette.accent))
                    .frame(width: 16, height: 16)
            }
            .padding(.bottom, 4)
            Text(title)
                .font(titleFont(m.titleSize))
                .fontWeight(.semibold)
                .foregroundStyle(Color(rgb: palette.ink))
                .multilineTextAlignment(.center)
                .lineLimit(4)
            authorText(uppercase: false, size: m.authorSize, tracking: 0.3)
                .multilineTextAlignment(.center)
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(m.padding)
    }

    // MARK: - Shared text builders

    /// Title typeface — Source Serif 4 or Inter per the style, resolved
    /// through `ReaderTypography` (so it picks up the WI-1b bundled
    /// faces or their documented fallback).
    private func titleFont(_ size: CGFloat) -> Font {
        Font(ReaderTypography.body(for: style.titleFontFamily, size: size))
    }

    /// The author line — empty (rendered as a zero-height spacer) when
    /// the book carries no author so the composition still balances.
    @ViewBuilder
    private func authorText(
        uppercase: Bool, size: CGFloat, tracking: CGFloat
    ) -> some View {
        if let author, !author.isEmpty {
            Text(uppercase ? author.uppercased() : author)
                .font(.system(size: size))
                .tracking(tracking)
                .foregroundStyle(Color(rgb: palette.ink))
                .lineLimit(2)
        } else {
            // No author: keep the slot but render nothing.
            Color.clear.frame(height: 0)
        }
    }

    /// The author's surname (last whitespace-delimited token) for the
    /// editorial style's top label. Falls back to the whole author, or
    /// "—" when there is no author.
    private var authorSurname: String {
        guard let author, !author.isEmpty else { return "—" }
        return author.split(separator: " ").last.map(String.init) ?? author
    }

    /// The editorial style's footer label — the design draws the
    /// publication year there. `LibraryBookItem` carries no year, so
    /// the footer falls back to the author's surname (a stable,
    /// book-specific token) rather than inventing a year.
    private var footerLabel: String { authorSurname }
}

// MARK: - Cover metrics

/// Width-derived layout metrics — mirrors the design `CoverArt`'s
/// `w * 0.13` title / `w * 0.075` author / `w * 0.11` padding scaling
/// so one view renders correctly at every cover size.
private struct CoverMetrics {
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
    /// the sRGB space.
    init(rgb triple: RGBTriple) {
        self = Color(
            .sRGB,
            red: Double(triple.red) / 255.0,
            green: Double(triple.green) / 255.0,
            blue: Double(triple.blue) / 255.0
        )
    }
}
