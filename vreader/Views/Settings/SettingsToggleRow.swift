// Purpose: Feature #67 WI-6 — the design's colored-tile toggle row, a
// peer of `SettingsIconRow` whose trailing control is a `PillSwitch`
// instead of a value+chevron. Used for the AI Assistant master gate +
// the Allow-AI-data-sharing consent rows in the Settings AI group.
//
// Pinned to the committed design bundle at
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-toggles.jsx`
// (`SettingsToggleRow`, Variant A).
//
// Key decisions:
// - **Reuses `SettingsRowMetrics`** (from `SettingsRowStyle.swift`) for
//   the 30pt tile + 15pt title vocabulary so the row is a visual peer of
//   `SettingsIconRow` in the same AI group. The detail subline uses the
//   design's own toggle-row spacing (`SettingsToggleRowMetrics`:
//   `marginTop: 2` + `lineHeight: 1.35`), which differs slightly from
//   `SettingsIconRow`'s `marginTop: 1` (the toggle row's design source is
//   `vreader-ai-toggles.jsx`, not `vreader-panels.jsx`).
// - **`Binding<Bool>` trailing `PillSwitch`.** The row owns no state;
//   the on/off comes from the bound value (the view model's
//   `isAIEnabled` / `hasConsent`).
// - **`toggleAccessibilityIdentifier`** is applied to the `PillSwitch`'s
//   underlying `Toggle` (the real actionable control), not the row
//   container — so UI-test identifiers (`aiToggle` / `consentToggle`)
//   land on the element a test actually taps (the feature #60 WI-9
//   wiring-preservation lesson; Codex Gate-4 High finding).
// - Static `*ForTesting` metric mirrors + a `toggleForTesting()` seam
//   let the composition test pin design parity + the binding mutation
//   without a render path (the `SettingsIconRow.resolvedTitleColorForTesting`
//   precedent).
//
// @coordinates-with: SettingsRowStyle.swift, SettingsRowPalette.swift,
//   PillSwitch.swift, AISettingsSection.swift, ReaderThemeV2.swift,
//   SettingsIconRowTests.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-toggles.jsx`

import SwiftUI

/// Detail-subline metrics specific to the design's `SettingsToggleRow`
/// (`vreader-ai-toggles.jsx` `SettingsToggleRow`), which differs from
/// `SettingsIconRow`'s detail spacing.
enum SettingsToggleRowMetrics {
    /// Title→detail spacing — design `marginTop: 2`.
    static let titleToDetailSpacing: CGFloat = 2
    /// Detail subline line spacing — design `lineHeight: 1.35` over an
    /// 11pt font ≈ a ~4pt added leading.
    static let detailLineSpacing: CGFloat = 4
}

/// The design's colored-tile toggle row.
struct SettingsToggleRow: View {

    private let theme: ReaderThemeV2
    private let icon: Image
    private let iconBackground: Color
    private let title: String
    private let detail: String?
    private let toggleAccessibilityIdentifier: String?
    @Binding private var isOn: Bool

    /// - Parameters:
    ///   - theme: the sheet theme (Settings is always `.paper`).
    ///   - icon: the SF Symbol image rendered inside the 30pt tile.
    ///   - iconBackground: the tile fill — a per-row brand color.
    ///   - title: the 15pt row title.
    ///   - detail: an optional 11pt subline under the title.
    ///   - isOn: the bound on/off state driving the trailing `PillSwitch`.
    ///   - toggleAccessibilityIdentifier: applied to the `PillSwitch`'s
    ///     underlying `Toggle` (the actionable control) so UI tests can
    ///     target the switch directly.
    init(
        theme: ReaderThemeV2,
        icon: Image,
        iconBackground: Color,
        title: String,
        detail: String? = nil,
        isOn: Binding<Bool>,
        toggleAccessibilityIdentifier: String? = nil
    ) {
        self.theme = theme
        self.icon = icon
        self.iconBackground = iconBackground
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.toggleAccessibilityIdentifier = toggleAccessibilityIdentifier
    }

    /// Shared-metric mirrors exposed so the composition test can assert
    /// the toggle row reuses `SettingsIconRow`'s tile/title vocabulary
    /// without a render path.
    static var iconTileSizeForTesting: CGFloat { SettingsRowMetrics.iconTileSize }
    static var titleFontSizeForTesting: CGFloat { SettingsRowMetrics.titleFontSize }
    static var detailFontSizeForTesting: CGFloat { SettingsRowMetrics.detailFontSize }

    /// Flips the bound value — exposed so the binding test exercises the
    /// same mutation the `PillSwitch` performs.
    func toggleForTesting() {
        isOn.toggle()
    }

    var body: some View {
        HStack(spacing: SettingsRowMetrics.tileToTitleSpacing) {
            iconTile
            VStack(alignment: .leading, spacing: SettingsToggleRowMetrics.titleToDetailSpacing) {
                Text(title)
                    .font(.system(size: SettingsRowMetrics.titleFontSize))
                    .foregroundStyle(Color(theme.inkColor))
                if let detail {
                    Text(detail)
                        .font(.system(size: SettingsRowMetrics.detailFontSize))
                        .foregroundStyle(Color(theme.subColor))
                        .lineSpacing(SettingsToggleRowMetrics.detailLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            pillSwitch
        }
        .padding(.vertical, SettingsRowMetrics.verticalPadding)
    }

    /// The trailing `PillSwitch`, carrying the caller's toggle
    /// accessibility identifier on the actionable control.
    @ViewBuilder
    private var pillSwitch: some View {
        if let toggleAccessibilityIdentifier {
            PillSwitch(isOn: $isOn, theme: theme)
                .accessibilityIdentifier(toggleAccessibilityIdentifier)
        } else {
            PillSwitch(isOn: $isOn, theme: theme)
        }
    }

    /// The 30pt rounded-square brand-colored icon tile — identical
    /// vocabulary to `SettingsIconRow`'s tile.
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
