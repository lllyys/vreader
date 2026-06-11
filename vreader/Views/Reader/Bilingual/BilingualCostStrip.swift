// Purpose: Feature #99 WI-2 — the edit-frame cost strip (design §#1640
// `BSCostStrip`): new-language (accent-tinted, sparkle), cached-language
// (neutral, check) and granularity (neutral, check) variants, rendered
// in the sheet's two strip slots per `BilingualSettingsEditModel`.
//
// Adaptation (plan Known limitations): the mock's "≈ $0.31" clause is
// sample data needing a per-model price table that doesn't exist — the
// new-language sub keeps the behavioral copy only.
//
// @coordinates-with: BilingualSetupSheet+EditMode.swift,
//   BilingualSettingsEditModel.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual-suite.jsx`

import SwiftUI

/// The edit-frame cost strip. Copy is pinned by tests.
struct BilingualCostStrip: View {

    let theme: ReaderThemeV2
    let kind: BilingualSettingsEditModel.StripKind
    /// The draft language's display name (used by the new-language head).
    let languageDisplay: String

    /// The strip's headline, per kind (design copy).
    static func head(
        for kind: BilingualSettingsEditModel.StripKind, languageDisplay: String
    ) -> String {
        switch kind {
        case .newLanguage:     return "\(languageDisplay) is new for this book"
        case .cachedLanguage:  return "Cached \u{2014} switches instantly"
        case .granularityOnly: return "Granularity change re-translates"
        }
    }

    /// The strip's sub line, per kind (design copy; the new-language
    /// cost clause is dropped — see the file header).
    static func sub(for kind: BilingualSettingsEditModel.StripKind) -> String {
        switch kind {
        case .newLanguage:
            return "Pages re-translate as you read."
        case .cachedLanguage:
            return "This language was translated before. Nothing is re-paid."
        case .granularityOnly:
            return "Cached rows are per-granularity \u{B7} starts from this page."
        }
    }

    private var isAccented: Bool { kind == .newLanguage }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Group {
                if isAccented {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color(theme.accentColor))
                } else {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color(theme.subColor))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.head(for: kind, languageDisplay: languageDisplay))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isAccented
                        ? Color(theme.accentColor) : Color(theme.inkColor))
                Text(Self.sub(for: kind))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(theme.subColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isAccented
                    ? Color(theme.accentColor).opacity(0.07)
                    : (theme.isDark
                        ? Color.white.opacity(0.04)
                        : Color.black.opacity(0.03)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isAccented
                        ? Color(theme.accentColor).opacity(0.27)
                        : Color(theme.ruleColor),
                    lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bilingualCostStrip")
    }
}
