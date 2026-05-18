// Purpose: Feature #65 WI-3 — the re-skinned Translate result card.
// Replaces the plain-text `BilingualView` (system-font side-by-side /
// stacked panels) with the design's stacked cards: an "Original" card
// with a serif body, and an accent-tinted translation card labelled
// with the target language.
//
// Mirrors `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`
// — `TranslateView`'s original + translation cards.
//
// Scope reconciliation (plan §2.2):
// - The design draws a "Speak" button on the accent translation card.
//   Wiring TTS to speak an arbitrary translated string in an arbitrary
//   language is a non-trivial integration, not a re-skin — the **Speak
//   button is OMITTED**; the card's public surface carries no `onSpeak`.
// - The design draws a "Notes on the translation" card. The translation
//   contract returns a single string; a notes field is a second AI
//   output — the **Notes card is OMITTED**.
// - The design labels the original card "English (Original)". The source
//   language is unknown in production (the translation contract carries
//   no source-language field), so the label ships as the honest
//   "Original" — matching the predecessor `BilingualView`'s label.
//
// @coordinates-with: TranslationPanel.swift, ReaderThemeV2.swift,
//   ReaderTypography.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// The stacked original + accent-tinted translation cards — design
/// `vreader-panels.jsx` `TranslateView`. The design's "Speak" button
/// and "Notes on the translation" card are omitted (plan §2.2).
struct TranslationResultCard: View {

    /// The original source text rendered in the upper card.
    let originalText: String

    /// The translated text rendered in the accent-tinted lower card.
    let translatedText: String

    /// The target-language label drawn on the accent translation card
    /// (e.g. "Chinese"). Also selects the serif stack — a CJK target
    /// renders the translation with a CJK serif face.
    let targetLanguage: String

    /// Visual-identity-v2 theme tokens for the card surfaces + ink.
    let theme: ReaderThemeV2

    /// The original card's section label. The committed design labels
    /// this card "English (Original)", but the translation contract
    /// carries no source-language field — the source language is
    /// genuinely unknown — so the honest label is "Original" (file
    /// header / plan §2.2). Exposed `static` so a re-skin regressing it
    /// back to a hardcoded source language is unit-catchable.
    static let originalCardLabel = "Original"

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                originalCard
                translationCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .accessibilityIdentifier("translationResultCard")
    }

    // MARK: - Original card

    /// The "Original" card — design's neutral-surface, hairline-bordered
    /// card with an uppercase sub label and a serif body.
    private var originalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(Self.originalCardLabel, color: Color(theme.subColor))
            Text(originalText)
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 15)))
                .lineSpacing(4)
                .foregroundStyle(Color(theme.inkColor))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(originalCardFillColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(theme.ruleColor), lineWidth: 0.5)
        )
        .accessibilityIdentifier("translationOriginalCard")
    }

    // MARK: - Translation card

    /// The accent-tinted translation card — design's gradient-filled,
    /// accent-bordered card labelled with the target language. The
    /// design's "Speak" button is omitted (plan §2.2).
    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(targetLanguage, color: Color(theme.accentColor))
            Text(translatedText)
                .font(Font(ReaderTypography.body(for: Self.translationFontFamily(for: targetLanguage), size: 16)))
                .lineSpacing(5)
                .foregroundStyle(Color(theme.inkColor))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(theme.accentColor.withAlphaComponent(0.10)),
                            Color(theme.accentColor.withAlphaComponent(0.05)),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(theme.accentColor.withAlphaComponent(0.33)), lineWidth: 0.5)
        )
        .accessibilityIdentifier("translationTranslatedCard")
    }

    // MARK: - Parts

    /// The design's uppercase tracked section label.
    private func sectionLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Typography

    /// CJK target languages (Chinese / Japanese / Korean) render the
    /// translation with a CJK serif stack; everything else uses the
    /// Latin serif — design `TranslateView`'s per-language font switch.
    /// `.system` is the registry's CJK-capable fallback (the bundled
    /// CJK serif binary is deferred — see `ReaderTypography`).
    ///
    /// Exposed `static` so the per-language font switch is unit-pinnable
    /// without a SwiftUI render pass (the `TranslateLanguageRail.tapAction`
    /// precedent).
    static func translationFontFamily(for targetLanguage: String) -> ReaderFontFamily {
        switch targetLanguage {
        case "Chinese", "Japanese", "Korean", "中文", "日本語", "한국어":
            return .system
        default:
            return .sourceSerif4
        }
    }

    // MARK: - Palette

    /// The original card's surface — design `TranslateView`: white over a
    /// light theme, a faint white wash over a dark theme.
    private var originalCardFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.04)
            : UIColor.white
    }
}
#endif
