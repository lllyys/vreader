// Purpose: Feature #56 WI-9 — one cell in the
// `BilingualSetupSheet`'s 3-column target-language grid. Extracted
// into its own file so the per-cell highlight + script-aware font
// choice stay clear (and the parent setup sheet, with its sibling
// `+Sections.swift` extension, stays under the ~300-line per-file
// budget).
//
// Design source:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`
//   — `BilingualSetupSheet`'s `BILINGUAL_LANGS.map(...)` button.
//   - Active cell: accent-tinted background, inset 1.5pt accent stroke,
//     accent-filled glyph chip, white glyph.
//   - Inactive cell: theme-paper surface (or dark surface in dark
//     themes), 0.5pt rule stroke, dimmed glyph chip.
//
// @coordinates-with: BilingualSetupSheet.swift, BilingualLanguage.swift,
//   ReaderThemeV2.swift

import SwiftUI

/// One language-picker cell rendered inside the setup sheet's grid.
struct BilingualLanguagePickerCell: View {

    /// Theme tokens for the active book.
    let theme: ReaderThemeV2

    /// The language this cell offers.
    let language: BilingualLanguage

    /// Whether the cell renders the selected styling.
    let isSelected: Bool

    /// Tap handler — host stores the new selection.
    let onTap: () -> Void

    /// Feature #99 (edit frame): the green "translated before" tick
    /// badge at the cell's top-right (design `BSLangTile` `cached`).
    /// Default off — first-enable renders unchanged.
    var showsCachedBadge: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                glyphChip
                Text(language.key)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color(theme.inkColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(cellBackground)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if showsCachedBadge { cachedBadge }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.cellAccessibilityIdentifier(for: language.key))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(showsCachedBadge ? "translated before" : "")
    }

    /// The 15pt green tick disc with a 2pt surface ring (design
    /// `BSLangTile` `cached` badge).
    private var cachedBadge: some View {
        Circle()
            .fill(theme.isDark
                ? Color(red: 0.247, green: 0.416, blue: 0.345)
                : Color(red: 0.227, green: 0.416, blue: 0.353))
            .frame(width: 15, height: 15)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.white)
            )
            .overlay(
                Circle().strokeBorder(Color(theme.sheetSurfaceColor), lineWidth: 2)
            )
            .offset(x: 4, y: -4)
    }

    /// Per-cell glyph chip — accent-filled when selected, dimmed when
    /// not.
    private var glyphChip: some View {
        Text(language.glyph)
            .font(.system(size: glyphFontSize, weight: .bold, design: glyphFontDesign))
            .foregroundStyle(isSelected ? Color.white : Color(theme.inkColor))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(
                    isSelected
                        ? Color(theme.accentColor)
                        : (theme.isDark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06))
                )
            )
    }

    @ViewBuilder
    private var cellBackground: some View {
        let accent = Color(theme.accentColor)
        let outline = Color(theme.ruleColor)
        RoundedRectangle(cornerRadius: 12)
            .fill(
                isSelected
                    ? accent.opacity(theme.isDark ? 0.15 : 0.08)
                    : (theme.isDark
                        ? Color.white.opacity(0.04)
                        : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? accent : outline,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
    }

    /// Glyph font size — CJK glyphs need a touch more weight than the
    /// Latin two-letter codes per design (`fontSize: 13 / 11`).
    private var glyphFontSize: CGFloat {
        switch language.script {
        case .cjk: return 13
        default:   return 11
        }
    }

    /// Serif design for non-Latin glyphs; default for Latin codes.
    private var glyphFontDesign: Font.Design {
        switch language.script {
        case .cjk, .rtl, .cyrillic: return .serif
        case .latin:                return .default
        }
    }

    /// Stable accessibility identifier — XCUITest pins per-cell taps
    /// by language key.
    static func cellAccessibilityIdentifier(for key: String) -> String {
        "bilingualLanguageCell_\(key)"
    }
}
