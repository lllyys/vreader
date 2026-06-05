// Purpose: Feature #90 WI-2 — the Summarize tab's language popover, presented
// from `AISummaryLangRow`'s language pill. Lists `BilingualLanguage.all` in a
// 2-column grid; tapping a language selects it and dismisses.
//
// Mirrors the committed design `bilingual-summarize-artboards.jsx` `LangPopover`
// (`:183-211`): a titled card ("Summary language" + the hint "The summary is
// written in this language."), a 2-column grid where each cell is a 20×20 glyph
// square + the language `key` name, the active cell accent-tinted with an inset
// accent border, and a footer ("Translation uses your configured AI provider.
// Long summaries may take a few seconds.").
//
// `BilingualLanguage.all` is the language authority (the bilingual surface's
// registry — Gate-2 M1), NOT Translate's in-memory string list.
//
// @coordinates-with: AISummaryLangRow.swift, AISummaryTabView.swift,
//   BilingualLanguage.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/bilingual-summarize-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// The Summarize tab's language-list popover — design `LangPopover`.
struct AISummaryLangPopover: View {

    /// The currently-selected language (its cell renders accent-tinted).
    let selectedLanguage: BilingualLanguage

    /// Visual-identity-v2 theme tokens.
    let theme: ReaderThemeV2

    /// Invoked when a language cell is tapped — passes the chosen language.
    let onSelect: (BilingualLanguage) -> Void

    /// The accessibility identifier for a language cell.
    static func rowIdentifier(_ language: BilingualLanguage) -> String {
        "summaryLang-\(language.key)"
    }

    private let columns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(BilingualLanguage.all, id: \.self) { language in
                    cell(for: language)
                }
            }
            .padding(10)
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color(cardFillColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(theme.ruleColor), lineWidth: 0.5)
        )
        .frame(maxWidth: 290)
        .accessibilityIdentifier("summaryLangPopover")
    }

    // MARK: - Header / footer

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Summary language")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color(theme.inkColor))
            Text("The summary is written in this language.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(theme.subColor))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(theme.subColor))
            Text("Translation uses your configured AI provider. Long summaries may take a few seconds.")
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 2)
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(for language: BilingualLanguage) -> some View {
        let isActive = language == selectedLanguage
        Button { onSelect(language) } label: {
            HStack(spacing: 8) {
                AISummaryLangGlyphSquare(
                    glyph: language.glyph,
                    script: language.script,
                    size: 20,
                    corner: 5,
                    background: isActive
                        ? Color(theme.accentColor)
                        : Color(neutralGlyphFill),
                    foreground: isActive ? .white : Color(theme.inkColor)
                )
                Text(language.key)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(Color(theme.inkColor))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color(cellFillColor(isActive: isActive)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isActive ? Color(theme.accentColor) : Color(theme.ruleColor),
                        lineWidth: isActive ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.rowIdentifier(language))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Theme washes

    /// The popover card background — an opaque panel over the sheet.
    private var cardFillColor: UIColor {
        theme.isDark
            ? UIColor(red: 0x24 / 255, green: 0x20 / 255, blue: 0x1d / 255, alpha: 1)
            : .white
    }

    /// The neutral glyph-square wash for an inactive cell (design dark
    /// `rgba(255,255,255,0.08)` / light `rgba(0,0,0,0.06)`).
    private var neutralGlyphFill: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.06)
    }

    /// The cell background — accent-tinted when active, a faint wash otherwise
    /// (design active `accent14`/`accent26`, inactive `rgba(...,0.02/0.04)`).
    private func cellFillColor(isActive: Bool) -> UIColor {
        if isActive {
            return theme.accentColor.withAlphaComponent(theme.isDark ? 0.15 : 0.08)
        }
        return theme.isDark
            ? UIColor.white.withAlphaComponent(0.04)
            : UIColor.black.withAlphaComponent(0.02)
    }
}
#endif
