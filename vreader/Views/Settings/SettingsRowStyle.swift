// Purpose: Feature #67 — the design's `Row`, factored as a reusable
// SwiftUI view so every Settings-sheet row renders one shape: a 30pt
// rounded colored-icon tile, a 15pt title, an optional 11pt detail
// subline, an optional trailing value string, and an optional chevron.
//
// Pinned to the committed design bundle at
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`
// (`SettingsSheet`'s `Row`).
//
// Key decisions:
// - **Pure presentation.** The row fetches no data — its inputs are
//   passed in. WI-3's `SettingsHeaderViewModel` / WI-4's `SettingsView`
//   own the data; this view only draws.
// - **Generic `Trailing` slot.** The common case is a value string +
//   chevron; the generic slot lets a row carry an arbitrary trailing
//   view (a `Toggle` for the AI group's rows in WI-5). A
//   `where Trailing == EmptyView` convenience init covers the
//   value-string-only case so callers don't write an empty closure.
// - **No row divider.** The design's `Row` draws its own
//   `borderBottom`; in a SwiftUI `Form` the enclosing `Section`
//   provides the separators, so the row itself stays divider-free —
//   WI-4's mount controls separator visibility.
// - **`isDestructive` drives the title color** to the design's danger
//   red (`#c44`); `resolvedTitleColorForTesting` exposes the resolved
//   color so the composition test can assert it without a render path.
//
// @coordinates-with: SettingsRowPalette.swift, SettingsView.swift,
//   AISettingsSection.swift, ReaderThemeV2.swift,
//   SettingsIconRowTests.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import SwiftUI

/// Non-generic color constants for `SettingsIconRow`. Kept off the
/// generic `SettingsIconRow` type so callers and tests reference the
/// danger color without binding the `Trailing` parameter.
enum SettingsRowColors {
    /// The design's danger color for a destructive row's title (`#c44`).
    static let destructiveTitle = Color(
        .sRGB, red: 0xc4 / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0
    )
}

/// Layout metrics for `SettingsIconRow`, pinned to the design `Row`
/// (`vreader-panels.jsx` `SettingsSheet`). Off the generic type so the
/// composition test can assert them without binding `Trailing`.
///
/// Horizontal row padding (`14px` in the design) is intentionally NOT
/// here — `SettingsIconRow` renders inside a `Form` `Section`, and the
/// horizontal inset is supplied by WI-4's `.listRowInsets` so it is not
/// double-applied. These metrics are the row's own intrinsic contract.
enum SettingsRowMetrics {
    /// The icon tile's edge length — the design's 30pt rounded square.
    static let iconTileSize: CGFloat = 30
    /// The icon tile's corner radius — design `borderRadius: 8`.
    static let iconTileCornerRadius: CGFloat = 8
    /// The icon glyph point size — design `size={17}`.
    static let iconGlyphSize: CGFloat = 17
    /// Spacing between the tile and the title block — design `gap: 12`.
    static let tileToTitleSpacing: CGFloat = 12
    /// Vertical row padding — design `Row` `padding: '12px ...'`.
    static let verticalPadding: CGFloat = 12
    /// Spacing between the title and its detail subline — design
    /// `marginTop: 1`.
    static let titleToDetailSpacing: CGFloat = 1
    /// Gap before the chevron after a trailing value — design
    /// `marginRight: 4`.
    static let trailingValueGap: CGFloat = 4
    /// Title font size — design `fontSize: 15`.
    static let titleFontSize: CGFloat = 15
    /// Detail-subline font size — design `fontSize: 11`.
    static let detailFontSize: CGFloat = 11
    /// Trailing-value font size — design `fontSize: 14`.
    static let trailingValueFontSize: CGFloat = 14
    /// Chevron point size — design `Icons.Chevron size={13}`.
    static let chevronSize: CGFloat = 13
}

/// The design's 30pt colored-icon settings row.
struct SettingsIconRow<Trailing: View>: View {

    private let theme: ReaderThemeV2
    private let icon: Image
    private let iconBackground: Color
    private let title: String
    private let detail: String?
    private let trailingValue: String?
    private let showsChevron: Bool
    private let isDestructive: Bool
    private let trailing: Trailing

    /// Designated init.
    /// - Parameters:
    ///   - theme: the sheet theme (Settings is always `.paper`, but the
    ///     row is theme-input for future-proofing).
    ///   - icon: the SF Symbol image rendered inside the tile.
    ///   - iconBackground: the tile fill — a per-row brand color.
    ///   - title: the 15pt row title.
    ///   - detail: an optional 11pt subline under the title.
    ///   - trailingValue: an optional value string before the chevron.
    ///   - showsChevron: whether the disclosure chevron is drawn.
    ///   - isDestructive: renders the title in the danger color.
    ///   - trailing: an arbitrary trailing view (e.g. a `Toggle`).
    init(
        theme: ReaderThemeV2,
        icon: Image,
        iconBackground: Color,
        title: String,
        detail: String? = nil,
        trailingValue: String? = nil,
        showsChevron: Bool = true,
        isDestructive: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.theme = theme
        self.icon = icon
        self.iconBackground = iconBackground
        self.title = title
        self.detail = detail
        self.trailingValue = trailingValue
        self.showsChevron = showsChevron
        self.isDestructive = isDestructive
        self.trailing = trailing()
    }

    /// The title color the row will render — danger red when
    /// destructive, otherwise the theme ink. Exposed for the
    /// composition test (the `ReaderSettingsPanel` `*ForTesting`
    /// precedent).
    var resolvedTitleColorForTesting: Color {
        isDestructive ? SettingsRowColors.destructiveTitle : Color(theme.inkColor)
    }

    var body: some View {
        HStack(spacing: SettingsRowMetrics.tileToTitleSpacing) {
            iconTile
            VStack(alignment: .leading, spacing: SettingsRowMetrics.titleToDetailSpacing) {
                Text(title)
                    .font(.system(size: SettingsRowMetrics.titleFontSize))
                    .foregroundStyle(resolvedTitleColorForTesting)
                if let detail {
                    Text(detail)
                        .font(.system(size: SettingsRowMetrics.detailFontSize))
                        .foregroundStyle(Color(theme.subColor))
                }
            }
            Spacer(minLength: 8)
            trailing
            if let trailingValue {
                Text(trailingValue)
                    .font(.system(size: SettingsRowMetrics.trailingValueFontSize))
                    .foregroundStyle(Color(theme.subColor))
                    // Design `Row`: `marginRight: 4` between the value
                    // and the chevron.
                    .padding(.trailing, showsChevron ? SettingsRowMetrics.trailingValueGap : 0)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: SettingsRowMetrics.chevronSize, weight: .semibold))
                    .foregroundStyle(Color(theme.subColor))
            }
        }
        // Design `Row` `padding: '12px 14px'` — the 12pt vertical is the
        // row's own contract; the 14pt horizontal is supplied by WI-4's
        // `.listRowInsets` so it is not double-applied inside the `Form`.
        .padding(.vertical, SettingsRowMetrics.verticalPadding)
    }

    /// The 30pt rounded-square brand-colored icon tile.
    private var iconTile: some View {
        RoundedRectangle(cornerRadius: SettingsRowMetrics.iconTileCornerRadius, style: .continuous)
            .fill(iconBackground)
            .frame(width: SettingsRowMetrics.iconTileSize, height: SettingsRowMetrics.iconTileSize)
            .overlay {
                icon
                    .font(.system(size: SettingsRowMetrics.iconGlyphSize, weight: .regular))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - Convenience init (value-string-only rows)

extension SettingsIconRow where Trailing == EmptyView {

    /// Convenience init for the common row — a value string + chevron,
    /// no custom trailing view.
    init(
        theme: ReaderThemeV2,
        icon: Image,
        iconBackground: Color,
        title: String,
        detail: String? = nil,
        trailingValue: String? = nil,
        showsChevron: Bool = true,
        isDestructive: Bool = false
    ) {
        self.init(
            theme: theme,
            icon: icon,
            iconBackground: iconBackground,
            title: title,
            detail: detail,
            trailingValue: trailingValue,
            showsChevron: showsChevron,
            isDestructive: isDestructive,
            trailing: { EmptyView() }
        )
    }
}
