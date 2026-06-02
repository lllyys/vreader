// Purpose: Feature #65 WI-3 — the re-skinned Translate tab body.
// Hosts the v2 target-language pill rail and the stacked translation
// result card. Replaces the pre-v2 native menu `Picker` +
// `.borderedProminent` "Translate" button + plain-text `BilingualView`.
//
// Mirrors `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`
// — `TranslateView`.
//
// Key decisions:
// - Uses `AITranslationViewModel` for state management.
// - The `TranslateLanguageRail`'s `onSelect` calls
//   `viewModel.translate(...)` DIRECTLY on every pill tap — the design
//   has no separate Translate button, and a re-tap of the
//   default-preselected language must still request it (Gate-2
//   finding #3). No `.onChange`.
// - `AITranslationViewModel.translate` cancels an in-flight predecessor,
//   so rapid pill taps don't race.
// - Shows a v2-tokened loading state while translating.
// - Shows a v2-tokened error with a retry on failure.
// - On completion, renders `TranslationResultCard` (the design's
//   stacked original + accent-tinted translation cards).
//
// @coordinates-with: AITranslationViewModel.swift,
//   TranslateLanguageRail.swift, TranslationResultCard.swift,
//   ReaderThemeV2.swift, AIReaderPanel.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// The re-skinned Translate tab body — language pill rail + result card.
struct TranslationPanel: View {

    /// The translation view model.
    @Bindable var viewModel: AITranslationViewModel

    /// The current locator for context extraction.
    let locator: Locator

    /// The text content to translate.
    let textContent: String

    /// The book format.
    let format: BookFormat

    /// Visual-identity-v2 theme tokens for the panel surface + ink.
    /// Defaults to `.paper` so existing callers / previews that omit it
    /// keep working (the change is additive).
    var theme: ReaderThemeV2 = .paper

    var body: some View {
        VStack(spacing: 0) {
            TranslateLanguageRail(
                languages: viewModel.supportedLanguages,
                selected: viewModel.targetLanguage,
                theme: theme,
                onSelect: requestTranslation
            )

            Color(theme.ruleColor).frame(height: 0.5)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(theme.paperColor))
        .accessibilityIdentifier("translationPanel")
    }

    // MARK: - Body state

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingView
        } else if let error = viewModel.errorMessage {
            errorView(message: error)
        } else if let translated = viewModel.translatedText {
            TranslationResultCard(
                originalText: viewModel.originalText,
                translatedText: translated,
                targetLanguage: viewModel.targetLanguage,
                theme: theme
            )
        } else {
            idleView
        }
    }

    // MARK: - Translation request

    /// Fires a translation for the tapped language. Wired to every pill
    /// of the rail — including a re-tap of the already-selected
    /// language — so the default-preselected language is requestable
    /// on first open (Gate-2 finding #3).
    ///
    /// The tapped `language` is passed straight through to
    /// `translate(...)` rather than staged via `viewModel.targetLanguage`
    /// first: the request's language is captured in this closure, so a
    /// rapid follow-up tap cannot retarget an already-spawned request
    /// (Gate-4 finding #1).
    private func requestTranslation(_ language: String) {
        // Bug #314: when the Translate tab was opened from a text SELECTION,
        // translate that selection (`viewModel.originalText`) verbatim — NOT the
        // auto-extracted book-context `textContent`. A cold open (no selection)
        // falls back to `textContent` + the `.section` context window.
        let isSelection = viewModel.hasExplicitSelection
        let text = isSelection ? viewModel.originalText : textContent
        Task {
            await viewModel.translate(
                originalText: text,
                locator: locator,
                format: format,
                targetLanguage: language,
                isExplicitSelection: isSelection
            )
        }
    }

    // MARK: - States

    @ViewBuilder
    private var idleView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "character.book.closed")
                .font(.system(size: 36))
                .foregroundStyle(Color(theme.subColor))
                .accessibilityHidden(true)

            Text("Tap a language to translate this passage")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 15)))
                .foregroundStyle(Color(theme.subColor))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("translationIdle")
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 14) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(Color(theme.accentColor))

            Text("Translating\u{2026}")
                .font(.system(size: 13))
                .foregroundStyle(Color(theme.subColor))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("translationLoading")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color(theme.accentColor))
                .accessibilityHidden(true)

            Text(message)
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 15)))
                .foregroundStyle(Color(theme.subColor))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                requestTranslation(viewModel.targetLanguage)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(theme.accentColor))
            .accessibilityIdentifier("translationRetryButton")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("translationError")
    }
}
#endif
