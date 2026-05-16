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
            let metrics = GenerativeCoverMetrics(width: geo.size.width)
            ZStack {
                Color(rgb: palette.background)
                styleContent(metrics: metrics)
            }
        }
    }

    // MARK: - Per-style content

    @ViewBuilder
    private func styleContent(metrics: GenerativeCoverMetrics) -> some View {
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
    private func classicArt(_ m: GenerativeCoverMetrics) -> some View {
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
            // Design `classic` author: uppercase Source Serif 4.
            authorText(
                family: .sourceSerif4,
                uppercase: true,
                size: m.authorSize,
                tracking: 0.4
            )
            .opacity(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(m.padding)
    }

    // MARK: - Modern

    /// Heavy Inter title top-left, a short accent tick + author at the
    /// bottom-left — `vreader-cover.jsx` `modern`.
    private func modernArt(_ m: GenerativeCoverMetrics) -> some View {
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
                // Design `modern` author: Inter medium.
                authorText(
                    family: .inter,
                    uppercase: false,
                    size: m.authorSize,
                    tracking: 0
                )
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
    private func animalArt(_ m: GenerativeCoverMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(titleFont(m.titleSize * 0.95))
                .fontWeight(.bold)
                .foregroundStyle(Color(rgb: palette.ink))
                .lineLimit(3)
            abstractBlock(m)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(m.padding * 0.5)
            // Design `animal` author: Inter medium.
            authorText(
                family: .inter,
                uppercase: false,
                size: m.authorSize,
                tracking: 0
            )
            .fontWeight(.medium)
            .opacity(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(m.padding)
    }

    /// The design's abstract block panel — the design `animal` branch
    /// draws a framed `rgba(0,0,0,0.08)` box. The design's specific
    /// animal SVG is not a reusable asset and is per-book in the real
    /// design system; the generative fallback keeps the design's framed
    /// abstract box with a neutral geometric mark (an ` AbstractMark`
    /// derived from the palette) rather than a misleading specific
    /// animal glyph.
    private func abstractBlock(_ m: GenerativeCoverMetrics) -> some View {
        ZStack {
            Rectangle().fill(Color(rgb: palette.ink).opacity(0.08))
            Rectangle().stroke(Color(rgb: palette.ink).opacity(0.15), lineWidth: 1)
            // A neutral abstract diamond mark — no specific subject.
            Rectangle()
                .fill(Color(rgb: palette.ink).opacity(0.5))
                .frame(width: m.titleSize * 1.1, height: m.titleSize * 1.1)
                .rotationEffect(.degrees(45))
        }
    }

    // MARK: - Editorial

    /// Uppercase accent author label at the top and a large serif title
    /// on a 40% baseline — `vreader-cover.jsx` `editorial`. The design
    /// draws a hairline + `book.year` footer; `LibraryBookItem` carries
    /// no year, so the footer is omitted rather than inventing a
    /// stand-in value (a self-designed substitution would violate
    /// rule 51).
    private func editorialArt(_ m: GenerativeCoverMetrics) -> some View {
        ZStack {
            VStack {
                // Design `editorial` author label: uppercase Inter.
                Text(authorSurname.uppercased())
                    .font(font(.inter, m.authorSize * 0.85))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundStyle(Color(rgb: palette.accent))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
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
    private func minimalArt(_ m: GenerativeCoverMetrics) -> some View {
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
            // Design `minimal` author: Inter.
            authorText(
                family: .inter,
                uppercase: false,
                size: m.authorSize,
                tracking: 0.3
            )
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

    /// A typeface resolved through `ReaderTypography` for the given
    /// family — used for the author / footer text so the generative
    /// cover honours the design's per-style Source Serif 4 / Inter
    /// pairings rather than the platform system font.
    private func font(_ family: ReaderFontFamily, _ size: CGFloat) -> Font {
        Font(ReaderTypography.body(for: family, size: size))
    }

    /// The author line in the given typeface — empty (a zero-height
    /// spacer) when the book carries no author so the composition still
    /// balances. `family` matches the design's per-style author face
    /// (`vreader-cover.jsx`).
    @ViewBuilder
    private func authorText(
        family: ReaderFontFamily,
        uppercase: Bool,
        size: CGFloat,
        tracking: CGFloat
    ) -> some View {
        if let author, !author.isEmpty {
            Text(uppercase ? author.uppercased() : author)
                .font(font(family, size))
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
}
