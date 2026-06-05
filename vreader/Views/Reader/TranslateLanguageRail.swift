// Purpose: Feature #65 WI-3 — the re-skinned Translate target-language
// pill rail. Replaces the native menu `Picker` + a separate
// `.borderedProminent` "Translate" button (the pre-v2
// `TranslationPanel.languageBar`) with the design's horizontally-
// scrolling pill rail.
//
// Mirrors `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`
// — `TranslateView`'s language-pill row.
//
// CRITICAL interaction model (plan §3 + Gate-2 finding #3):
// The design has NO separate Translate button — a pill tap is the only
// way to request a language. A pill tap therefore fires
// `onSelect(language)` on EVERY tap, including a re-tap of the
// already-`selected` language. If a re-tap of the selected pill did
// nothing, the default-preselected `targetLanguage` ("Chinese") would
// be unrequestable on first open. Every pill — selected or not — is
// wired to the same pure `tapAction(for:onSelect:)`; the rail does NOT
// use `.onChange`.
//
// @coordinates-with: TranslationPanel.swift, AITranslationViewModel.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// The target-language pill rail — design `vreader-panels.jsx`
/// `TranslateView`. A pill tap fires `onSelect(language)` on EVERY tap,
/// including a re-tap of the already-selected language (so the
/// default-preselected language is still requestable — Gate-2
/// finding #3).
struct TranslateLanguageRail: View {

    /// The selectable target languages, one pill each, in display order.
    let languages: [String]

    /// The currently-selected language — its pill draws the accent
    /// highlight. May be a value absent from `languages` (no highlight).
    let selected: String

    /// Visual-identity-v2 theme tokens for the pill surfaces + ink.
    let theme: ReaderThemeV2

    /// Runs when a pill is tapped, with the tapped language. Fires on
    /// EVERY tap — including a re-tap of `selected`.
    var onSelect: (String) -> Void

    /// Feature #87 WI-2: true while a translate is in flight. The active
    /// (`selected`) pill then morphs IN PLACE into the Stop affordance (the
    /// design's "the language control doubles as the stop affordance"), and
    /// tapping it runs `onStop` instead of re-requesting that language.
    var isLoading: Bool = false

    /// Runs when the morphed Stop pill is tapped (aborts the in-flight translate).
    var onStop: () -> Void = {}

    // MARK: - Tap behaviour

    /// Builds the tap action for a single pill. Exposed `static` so the
    /// "fire on every tap" behaviour is unit-pinnable without a SwiftUI
    /// render pass (the `AIChatMessageRow.form(for:)` precedent). The
    /// `body` wires EVERY pill — selected or not — to this builder, so
    /// re-tapping the selected language fires `onSelect` exactly as a
    /// fresh selection does.
    static func tapAction(
        for language: String,
        onSelect: @escaping (String) -> Void
    ) -> () -> Void {
        { onSelect(language) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(languages, id: \.self) { language in
                    pill(for: language)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("translateLanguageRail")
    }

    // MARK: - Pill

    /// A single language pill — design `TranslateView`'s pill button.
    /// The selected pill draws an accent fill + white label; every
    /// other pill draws a neutral wash + ink label. Both wire the SAME
    /// `tapAction(for:onSelect:)` so a re-tap of the selected language
    /// still fires `onSelect`.
    private func pill(for language: String) -> some View {
        let isSelected = language == selected
        // Feature #87 WI-2: the active pill becomes the Stop control while loading.
        let isStop = isLoading && isSelected
        return Button(action: isStop ? onStop : Self.tapAction(for: language, onSelect: onSelect)) {
            pillLabel(language: language, isSelected: isSelected, isStop: isStop)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color(pillFillColor(isSelected: isSelected)))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isStop ? "translateStopPill" : "translateLanguagePill-\(language)")
        .accessibilityLabel(isStop ? "Stop" : language)
        .accessibilityAddTraits(isSelected && !isStop ? .isSelected : [])
    }

    /// The pill's content: the language label, or — when this pill is the active
    /// Stop control — a white square + sweeping ring + "Stop" (the Chat stop visual).
    @ViewBuilder
    private func pillLabel(language: String, isSelected: Bool, isStop: Bool) -> some View {
        if isStop {
            HStack(spacing: 5) {
                ZStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.7)
                    Image(systemName: "square.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 14, height: 14)
                Text("Stop")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white)
            }
        } else {
            Text(language)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color(theme.inkColor))
                .lineLimit(1)
        }
    }

    // MARK: - Palette

    /// The pill fill — design `TranslateView`: the accent for the
    /// selected pill, a neutral wash (`rgba(255,255,255,0.06)` dark /
    /// `rgba(0,0,0,0.05)` light) for every other pill.
    private func pillFillColor(isSelected: Bool) -> UIColor {
        if isSelected {
            return theme.accentColor
        }
        return theme.isDark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.05)
    }
}
#endif
