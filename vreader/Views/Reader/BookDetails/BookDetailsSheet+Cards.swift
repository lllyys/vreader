// Purpose: Card rendering helpers extracted from `BookDetailsSheet.swift`
// to keep that file under the rule-50 ~300-line guideline (feature #56
// WI-14's `translateBookViewModel` + `translateBookTextProvider` props
// pushed it over). The metadata card, actions card, and section
// scaffolding are pure presentation — no state of their own — so they
// move as-is without behavior change.
//
// @coordinates-with: BookDetailsSheet.swift, BookDetailsMetadataRow.swift,
//   BookDetailsActionRow.swift, TranslateBookActionRow.swift,
//   ReaderThemeV2.swift

#if canImport(UIKit)
import SwiftUI

extension BookDetailsSheet {

    // MARK: - Cards

    /// The Metadata card body — rows separated by hairline dividers.
    @ViewBuilder
    var metadataCard: some View {
        let rows = metadataRows
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            BookDetailsMetadataRow(model: row, theme: theme, onAccessory: {
                if let accessory = row.accessory { handleAccessory(accessory) }
            })
            if index < rows.count - 1 {
                rowDivider
            }
        }
    }

    /// The Actions card body — rows separated by hairline dividers.
    /// The `.translateBook` row is rendered through `TranslateBookActionRow`
    /// (status-aware icon + sublabel) rather than the generic
    /// `BookDetailsActionRow` — the design specifies a richer state per
    /// progress phase.
    @ViewBuilder
    var actionCard: some View {
        let rows = actionRows
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            if row.kind == .translateBook, let vm = translateBookViewModel {
                TranslateBookActionRow(
                    progress: vm.progress,
                    targetLanguageLabel: translateBookTargetLanguage,
                    theme: theme,
                    onTap: { handleAction(.translateBook) })
            } else {
                BookDetailsActionRow(model: row, theme: theme, onTap: {
                    handleAction(row.kind)
                })
            }
            if index < rows.count - 1 {
                rowDivider
            }
        }
    }

    // MARK: - Section scaffolding

    /// A labelled section: an uppercase tracked label above a rounded
    /// card. Mirrors the design's `SectionLabel` + 14pt-radius card.
    @ViewBuilder
    func section(
        label: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color(theme.subColor))
            VStack(spacing: 0) { content() }
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Hairline row divider — design's `0.5px solid t.rule` borderBottom.
    var rowDivider: some View {
        Color(theme.ruleColor).frame(height: 0.5)
    }

    /// Card surface fill — design `t.isDark ? rgba(255,255,255,0.04) : #fff`.
    var cardBackground: Color {
        theme.isDark ? Color.white.opacity(0.04) : Color.white
    }
}
#endif
