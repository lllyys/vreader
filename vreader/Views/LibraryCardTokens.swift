// Purpose: Feature #60 visual-identity v2 — Library-screen design tokens
// for the grid card (`BookCardView`), the list row (`BookRowView`), and
// the Library container shell (`LibraryView` re-skin, WI-9).
//
// The Library is always presented in the warm-paper light palette in
// the committed design bundle (it is not theme-switchable like the
// reader). `ReaderThemeV2` covers the *reader* surfaces; its `.paper`
// stop (`#f4eee0` bg) differs from the Library shell (`#f7f4ee`), so
// the Library carries its own small token surface here rather than
// borrowing reader tokens that would render the wrong shade.
//
// Token values are pinned to the committed design bundle at
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`
// (`GridView`, `ListView`) and `vreader-cover.jsx` (`BookCover`).
//
// Key decisions:
// - **Layout constants are CGFloat statics, not magic numbers.** The
//   card/row views and their contract tests both read these, so the
//   design spec has one home.
// - **Colors built from integer RGB triples** (mirrors
//   `ReaderThemeV2.hex(_:_:_:)`) — keeps the design hex readable in
//   source without a string-parsing dependency, and lets the type
//   compile without importing the WI-7 `Color(hexString:)` helper.
// - **`accent` reuses `AccentColor.light`'s oxblood** (`#8c2f2f`) so
//   the Library badge accent stays coherent with the rest of the
//   feature-#60 chrome rather than drifting to a Library-local hue.
//   `accent` is also the swept-arc colour of the list-row progress
//   ring.
// - **List-container tokens** (`listCardBackground`, `listRowDivider`,
//   `listCardCornerRadius`) are pinned in the WI-8 token pass but
//   consumed by the WI-9 Library-container re-skin. The design file
//   is shared, so the spec lives in one home rather than splitting
//   the same `vreader-library.jsx` constants across two PRs.
//
// @coordinates-with: BookCardView.swift, BookRowView.swift,
//   AccentColor.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`

import SwiftUI

/// Design tokens for the Library grid card + list row (feature #60 WI-8).
/// Pure namespace — static members only, no instances.
enum LibraryCardTokens {

    // MARK: - Palette (warm-paper light, per design `vreader-library.jsx`)

    /// Primary text — book titles, the `#1d1a14` near-black ink.
    static let ink = rgb(0x1d, 0x1a, 0x14)

    /// Secondary text — authors, metadata, the `#7a6a4a` warm taupe.
    static let subText = rgb(0x7a, 0x6a, 0x4a)

    /// Format-chip fill — `rgba(60,40,20,0.08)` warm wash on paper.
    static let chipBackground = rgb(0x3c, 0x28, 0x14, alpha: 0.08)

    /// List-card surface — the rows sit on a `#ffffff` rounded card.
    static let listCardBackground = Color.white

    /// Hairline between list rows — `rgba(60,40,20,0.08)`, drawn 0.5pt.
    static let listRowDivider = rgb(0x3c, 0x28, 0x14, alpha: 0.08)

    /// Restrained oxblood accent — reused from `AccentColor.light`
    /// (`#8c2f2f`) so Library badges match the feature-#60 chrome.
    static let accent = Self.color(fromHex: AccentColor.light.hex)

    /// Cover hairline border — keeps light-edged covers delineated
    /// against the warm-paper grid (carries bug #107's intent forward).
    static let coverBorder = rgb(0x3c, 0x28, 0x14, alpha: 0.14)

    /// Finished-state green — `#3a6a5a`. The grid-card finished
    /// checkmark glyph and the list-row "Finished" label both use it.
    static let finished = rgb(0x3a, 0x6a, 0x5a)

    /// In-cover progress-strip track — `rgba(255,255,255,0.2)`. Sits
    /// on the cover art, so it is white-on-image, not on paper.
    static let coverProgressTrack = Color.white.opacity(0.2)

    /// In-cover progress-strip fill — `rgba(255,255,255,0.9)`.
    static let coverProgressFill = Color.white.opacity(0.9)

    /// Finished-checkmark disc fill — `rgba(255,255,255,0.95)`.
    static let coverFinishedBadgeFill = Color.white.opacity(0.95)

    /// List-row progress-ring track — `rgba(60,40,20,0.12)` warm wash.
    /// The ring's swept arc uses `accent` (oxblood).
    static let progressRingTrack = rgb(0x3c, 0x28, 0x14, alpha: 0.12)

    // MARK: - Container shell palette (feature #60 WI-9)

    /// Library shell background — the warm paper `#f7f4ee`. A different
    /// shade from `ReaderThemeV2.paper` (`#f4eee0`); the Library is not
    /// theme-switchable, so this is the one Library backdrop.
    static let shellBackground = rgb(0xf7, 0xf4, 0xee)

    /// Nav-bar pill button fill — `rgba(60,40,20,0.06)` warm wash.
    /// Shared by the search-field container and the unselected filter
    /// chip (the design uses the same wash for all three).
    static let navPillBackground = rgb(0x3c, 0x28, 0x14, alpha: 0.06)

    /// Nav-bar icon tint — the design dark brown `#3a2913`.
    static let navIconTint = rgb(0x3a, 0x29, 0x13)

    /// Selected filter-chip fill — the design near-black `#1d1a14`
    /// (identical to `ink`; aliased for call-site clarity).
    static let filterChipSelectedBackground = ink

    /// Unselected filter-chip fill — the warm wash (same as `navPillBackground`).
    static let filterChipBackground = navPillBackground

    /// Selected filter-chip text — the warm-paper shell colour `#f7f4ee`.
    static let filterChipSelectedText = shellBackground

    /// Unselected filter-chip text — the design dark brown `#3a2913`.
    static let filterChipText = navIconTint

    /// Search-field container fill — the warm wash (same as `navPillBackground`).
    static let searchFieldBackground = navPillBackground

    /// "See all" affordance colour on the Continue-reading header —
    /// the design oxblood accent.
    static let seeAllAccent = accent

    // MARK: - Layout constants

    /// Cover corner radius for the grid card. Design `BookCover` is
    /// called with `radius: 4` from `GridView`.
    static let cardCoverCornerRadius: CGFloat = 4

    /// Cover aspect ratio (width ÷ height). Design `BookCover` default
    /// is `110 × 165` → 2:3. The card scales the cover to the grid
    /// cell width; the 2:3 ratio is the load-bearing invariant.
    static let coverAspectRatio: CGFloat = 110.0 / 165.0

    /// Grid card title point size — design `12.5px` Source Serif 4 600.
    static let cardTitleFontSize: CGFloat = 12.5

    /// Grid card author point size — design `10.5px`.
    static let cardAuthorFontSize: CGFloat = 10.5

    /// Vertical spacing between cover / title / author in the card.
    static let cardStackSpacing: CGFloat = 8

    /// List-row cover thumbnail size — design `BookCover` is called
    /// with `width: 44, height: 62, radius: 3` from `ListView`.
    static let rowCoverWidth: CGFloat = 44
    static let rowCoverHeight: CGFloat = 62
    static let rowCoverCornerRadius: CGFloat = 3

    /// List-row horizontal gap between cover and text — design `gap: 12`.
    static let rowContentSpacing: CGFloat = 12

    /// List-row title point size — design `15px` Source Serif 4 600.
    static let rowTitleFontSize: CGFloat = 15

    /// List-row author point size — design `12px`.
    static let rowAuthorFontSize: CGFloat = 12

    /// List-row format-chip point size — design `9.5px` 600 weight.
    static let rowChipFontSize: CGFloat = 9.5

    /// List-card corner radius — design `borderRadius: 20`.
    static let listCardCornerRadius: CGFloat = 20

    /// In-cover progress strip (design `GridView`): a 2.5pt-tall bar
    /// inset 6pt horizontally and 4pt up from the cover's bottom edge,
    /// with a 2pt corner radius.
    static let coverProgressStripHeight: CGFloat = 2.5
    static let coverProgressStripInset: CGFloat = 6
    static let coverProgressStripBottomInset: CGFloat = 4
    static let coverProgressStripCornerRadius: CGFloat = 2

    /// Finished checkmark disc (design `GridView`): an 18pt circle
    /// inset 6pt from the cover's top-trailing corner.
    static let finishedBadgeSize: CGFloat = 18
    static let finishedBadgeInset: CGFloat = 6

    /// List-row progress ring (design `ListView`): a 30pt box holding
    /// a radius-12 circle (24pt drawn diameter → 3pt inset each side)
    /// stroked at 2pt.
    static let progressRingSize: CGFloat = 30
    static let progressRingInset: CGFloat = 3
    static let progressRingLineWidth: CGFloat = 2

    // MARK: - Container shell layout (feature #60 WI-9)

    /// Nav-bar pill button — design `pillBtn`: a 36pt square with an
    /// 18pt radius (a full circle).
    static let navPillSize: CGFloat = 36
    static let navPillCornerRadius: CGFloat = 18

    /// Nav-bar icon point size — design `Icons.* size={19}`.
    static let navIconSize: CGFloat = 19

    /// Gap between the trailing nav-bar pill buttons — design `gap: 8`.
    static let navPillSpacing: CGFloat = 8

    /// Library title point size — design `fontSize: 36` Source Serif 4.
    static let titleFontSize: CGFloat = 36

    /// Section-header point size — `Continue reading` / `All books`
    /// headers, design `fontSize: 18` Source Serif 4.
    static let sectionHeaderFontSize: CGFloat = 18

    /// Subtitle point size — `{N} books · {M} reading`, design `13`.
    static let subtitleFontSize: CGFloat = 13

    /// Filter chip — design: `borderRadius: 100` (a full pill),
    /// `padding: 6px 12px`, `fontSize: 13`.
    static let filterChipCornerRadius: CGFloat = 100
    static let filterChipFontSize: CGFloat = 13
    static let filterChipHorizontalPadding: CGFloat = 12
    static let filterChipVerticalPadding: CGFloat = 6

    /// Gap between filter chips — design `gap: 6`.
    static let filterChipSpacing: CGFloat = 6

    /// Continue-reading card cover — design `ContinueCard`:
    /// `BookCover` at `124 × 186` (a 2:3 portrait), `radius: 5`.
    static let continueCardCoverWidth: CGFloat = 124
    static let continueCardCoverHeight: CGFloat = 186
    static let continueCardCoverCornerRadius: CGFloat = 5

    /// Continue-reading card title point size — design `13.5`.
    static let continueCardTitleFontSize: CGFloat = 13.5

    /// Continue-reading card metadata point size — design `11`.
    static let continueCardMetaFontSize: CGFloat = 11

    /// Gap between cover and the title/meta block in a Continue card —
    /// design `gap: 10`.
    static let continueCardStackSpacing: CGFloat = 10

    /// Gap between Continue-reading cards in the rail — design `gap: 14`.
    static let continueRailSpacing: CGFloat = 14

    /// Search-field container — design: `borderRadius: 12`,
    /// `padding: 10px 14px`, leading-icon gap `8`.
    static let searchFieldCornerRadius: CGFloat = 12
    static let searchFieldHorizontalPadding: CGFloat = 14
    static let searchFieldVerticalPadding: CGFloat = 10
    static let searchFieldIconSpacing: CGFloat = 8

    /// Search-field text point size — design `fontSize: 15`.
    static let searchFieldFontSize: CGFloat = 15

    /// Standard content horizontal inset — the design uses `18` for the
    /// nav bar / chips / search / list card and `22` for the title /
    /// section headers / grid. Both are exposed so each surface reads
    /// its own design value.
    static let shellEdgePadding: CGFloat = 18
    static let shellContentPadding: CGFloat = 22

    /// In-cover progress strip for the Continue card — design
    /// `ContinueCard`: a 2.5pt-tall bar inset 6pt horizontally, 5pt up
    /// from the bottom, 2pt corner radius.
    static let continueCardStripBottomInset: CGFloat = 5

    // MARK: - Serif title font

    /// Source Serif 4 face at the requested size, resolved via the
    /// feature-#60 typography registry (WI-1b bundled the binary).
    /// Falls back to Georgia/serif if the face is unavailable — same
    /// chain `ReaderTypography` documents.
    static func serifTitleFont(size: CGFloat) -> Font {
        Font(ReaderTypography.body(for: .sourceSerif4, size: size))
    }

    // MARK: - Color builders

    /// Builds a SwiftUI `Color` from 8-bit RGB integer triples plus
    /// optional alpha — mirrors `ReaderThemeV2.hex(_:_:_:)` so the
    /// design hex stays readable in source.
    private static func rgb(
        _ r: Int, _ g: Int, _ b: Int, alpha: Double = 1.0
    ) -> Color {
        Color(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: alpha
        )
    }

    /// Parses a `#RRGGBB` hex string into a `Color`. Used only for the
    /// `AccentColor` bridge (its API exposes hex strings, not RGB
    /// triples). Falls back to the design oxblood on malformed input
    /// so the badge always renders.
    private static func color(fromHex hex: String) -> Color {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
            return rgb(0x8c, 0x2f, 0x2f) // design oxblood fallback
        }
        return rgb(
            Int((value >> 16) & 0xff),
            Int((value >> 8) & 0xff),
            Int(value & 0xff)
        )
    }
}
