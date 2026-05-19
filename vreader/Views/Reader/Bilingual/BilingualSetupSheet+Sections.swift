// Purpose: Feature #56 WI-9 — engine strip, preview strip, and the
// section label helper for `BilingualSetupSheet`. Split out so the
// parent file stays under the ~300-line per-file budget (rule 50 §9).
//
// Design source:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`
//   — `BilingualSetupSheet`'s "Translation engine" strip + the
//     `BilingualPreview` sample row (~157–193 in the JSX).
//
// @coordinates-with: BilingualSetupSheet.swift, BilingualLanguage.swift,
//   ReaderThemeV2.swift

import SwiftUI

extension BilingualSetupSheet {

    // MARK: - Preview strip

    /// Sample paragraph + translation row mirroring the design's
    /// `BilingualPreview`. Re-rendered when the user picks a new
    /// target language so the preview tracks the choice.
    var previewSection: some View {
        BilingualSetupPreview(theme: theme, languageKey: state.languageKey)
    }

    // MARK: - Engine strip

    var engineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BilingualSectionLabel(theme: theme, text: "Translation engine")
            HStack(spacing: 12) {
                engineAvatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(engineDescriptor.displayTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color(theme.inkColor))
                    Text(engineDescriptor.displaySubtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(theme.subColor))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onOpenSettings) {
                    Text(Self.engineButtonLabel(aiConfigured: engineDescriptor.configured))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(engineDescriptor.configured ? Color(theme.inkColor) : Color.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                engineDescriptor.configured
                                    ? (theme.isDark
                                        ? Color.white.opacity(0.08)
                                        : Color.black.opacity(0.06))
                                    : Color(theme.accentColor)
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bilingualEngineButton")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(engineStripBackground)
        }
    }

    private var engineAvatar: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(engineDescriptor.configured ? Color.white : Color(theme.subColor))
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(
                    engineDescriptor.configured
                        ? AnyShapeStyle(LinearGradient(
                            colors: [
                                Color(theme.accentColor),
                                Color(theme.accentColor).opacity(0.67),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.black.opacity(0.08))
                )
            )
    }

    @ViewBuilder
    private var engineStripBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                engineDescriptor.configured
                    ? Color(theme.ruleColor)
                    : Color(theme.accentColor).opacity(0.33),
                lineWidth: 0.5
            )
            .background(
                RoundedRectangle(cornerRadius: 12).fill(
                    engineDescriptor.configured
                        ? (theme.isDark
                            ? Color.white.opacity(0.04)
                            : Color.white)
                        : Color(theme.accentColor).opacity(0.06)
                )
            )
    }
}

// MARK: - Section label helper

/// Small-caps section label drawn above each setup-sheet section,
/// matching the design's `SectionLabel` in `vreader-bilingual.jsx`.
struct BilingualSectionLabel: View {
    let theme: ReaderThemeV2
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Color(theme.subColor))
    }
}

// MARK: - Preview strip

/// Sample English source + per-language translation pair used as the
/// design's `BilingualPreview` row. Strings mirror the JSX bundle's
/// sample so the SwiftUI preview matches the documented visual.
struct BilingualSetupPreview: View {

    let theme: ReaderThemeV2
    let languageKey: String

    /// English source — `vreader-bilingual.jsx` Pride-and-Prejudice
    /// opening line.
    private static let englishSource = "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife."

    /// Per-language translations — pinned to the design bundle's
    /// `BilingualPreview.samples`. A language not in this map (a
    /// future addition that landed before the design strings catch
    /// up) falls back to the Chinese sample.
    private static let translations: [String: String] = [
        "Chinese":  "凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。",
        "Japanese": "相当な財産を持っている独身の男性は妻を欲しがっているに違いない、というのは世間一般に認められた真理である。",
        "Korean":   "재산이 많은 독신 남성에게 아내가 필요하다는 것은 누구나 인정하는 진리이다.",
        "Spanish":  "Es una verdad universalmente reconocida que un hombre soltero en posesión de una buena fortuna necesita una esposa.",
        "French":   "C'est une vérité universellement reconnue qu'un homme célibataire possédant une bonne fortune doit avoir besoin d'une épouse.",
        "German":   "Es ist eine allgemein anerkannte Wahrheit, dass ein lediger Mann im Besitz eines schönen Vermögens nach einer Frau verlangen muss.",
        "Italian":  "È una verità universalmente riconosciuta che uno scapolo in possesso di un buon patrimonio debba volere una moglie.",
        "Arabic":   "إنها حقيقة معترف بها عالميًا أن الرجل الأعزب الذي يملك ثروة جيدة لا بد أن يكون بحاجة إلى زوجة.",
        "Russian":  "Общеизвестно, что холостой мужчина, обладающий приличным состоянием, должен иметь желание жениться.",
    ]

    var body: some View {
        let resolved = BilingualLanguage.findOrDefault(key: languageKey)
        let sample = Self.translations[resolved.key] ?? Self.translations["Chinese"] ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.englishSource)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Color(theme.inkColor))
                .lineSpacing(2)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(theme.accentColor).opacity(0.55))
                    .frame(width: 2)
                Text(sample)
                    .font(.system(size: 13, design: resolved.script == .latin ? .default : .serif))
                    .foregroundStyle(Color(theme.subColor))
                    .lineSpacing(3)
                    .multilineTextAlignment(resolved.script == .rtl ? .trailing : .leading)
                    .environment(\.layoutDirection, resolved.script == .rtl ? .rightToLeft : .leftToRight)
                    .padding(.leading, 12)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.isDark ? Color.white.opacity(0.04) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(theme.ruleColor), lineWidth: 0.5)
                )
        )
        .accessibilityIdentifier("bilingualSetupPreview")
    }
}
