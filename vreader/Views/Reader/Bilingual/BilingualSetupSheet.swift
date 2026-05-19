// Purpose: Feature #56 WI-9 — the first-enable bilingual setup
// half-sheet. Shown the first time the More-menu Bilingual toggle
// flips ON for a book (and reachable later from the row's
// "Tap to change" detail per design §2.2). Picks target language,
// segmentation granularity, and surfaces the AI provider chip.
//
// Design source:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`
//   — `BilingualSetupSheet` (~27–155 in the JSX).
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/feature-60-followups.md`
//   §2.2.
//
// Key decisions:
// - **Bindings out, not VM-in.** The sheet takes a `Binding` for the
//   shared `BilingualSetupSheetState` (language + granularity) so the
//   host owns the source of truth and can persist via the bilingual
//   view model. The same sheet shape serves both first-enable (the
//   "Turn on bilingual mode" CTA confirms + dismisses) and later
//   preferences edit (no CTA, dismiss is automatic).
// - **No direct AI dependency.** The sheet receives `aiConfigured`
//   as input and exposes an `onOpenSettings` callback. Wiring to
//   `ProviderProfileStore` lives at the host (WI-10..13 — different
//   per format), exactly like the More-menu row pattern.
// - **Shares `ReaderSheetChrome`** (feature #60 WI-10) for the sheet
//   surface + title bar. The design's `Sheet` wrapper maps cleanly
//   onto it; doubling the implementation would risk drift.
// - **9-language grid uses a 3-column adaptive layout** matching the
//   JSX's `gridTemplateColumns: repeat(3, 1fr)`. Each cell is a
//   `BilingualLanguagePickerCell` (its own helper view) so the per-
//   cell highlight + script-aware font choice stay readable.
//
// @coordinates-with: BilingualLanguage.swift, ReaderSheetChrome.swift,
//   ReaderThemeV2.swift, ChapterTranslationService.swift
//   (`TranslationGranularity`), BilingualReadingViewModel.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`

import SwiftUI

/// Shared state for the bilingual setup sheet — held by the host
/// (the per-format reader container, WI-10..13) and bound to the
/// view model on confirm. A pure value type so the sheet can stay
/// stateless and testable.
struct BilingualSetupSheetState: Equatable, Sendable {

    /// One of `BilingualLanguage.all`'s `key` values.
    var languageKey: String

    /// Segmentation granularity — paragraph (default) or sentence.
    var granularity: TranslationGranularity

    /// Default state per design §2.2 — Chinese + paragraph.
    static let defaultValue = BilingualSetupSheetState(
        languageKey: "Chinese",
        granularity: .paragraph
    )

    /// Languages the picker offers. Pinned to `BilingualLanguage.all`
    /// so any registry edit flows through to the sheet automatically.
    static var availableLanguages: [BilingualLanguage] { BilingualLanguage.all }

    /// Granularity options in design order (paragraph then sentence).
    static let availableGranularities: [TranslationGranularity] = [.paragraph, .sentence]
}

/// First-enable bilingual setup half-sheet — target language,
/// granularity, AI provider chip.
struct BilingualSetupSheet: View {

    /// Visual-identity-v2 theme tokens for the active book.
    let theme: ReaderThemeV2

    /// Mutable state — written by user taps, observed by the host on
    /// confirm.
    @Binding var state: BilingualSetupSheetState

    /// True when an AI provider profile is configured. Drives the
    /// engine strip's visual + the engine button label.
    let aiConfigured: Bool

    /// Tap on the "Turn on bilingual mode" CTA — host should persist
    /// the chosen settings and dismiss.
    let onConfirm: () -> Void

    /// Tap on the engine "Set up" / "Change…" button — host should
    /// route to AI Settings.
    let onOpenSettings: () -> Void

    /// Sheet accessibility identifier for XCUITest + verify-cron.
    static let accessibilityIdentifier = "bilingualSetupSheet"

    /// Primary CTA label — pinned by tests.
    static func ctaLabel(aiConfigured: Bool) -> String {
        aiConfigured ? "Turn on bilingual mode" : "Turn on bilingual mode"
    }

    /// Engine strip button label.
    static func engineButtonLabel(aiConfigured: Bool) -> String {
        aiConfigured ? "Change\u{2026}" : "Set up"
    }

    /// Engine strip descriptor — title + subtitle pair.
    static func engineDescriptor(aiConfigured: Bool) -> (title: String, subtitle: String) {
        if aiConfigured {
            return (
                "AI provider configured",
                "Translations cached per paragraph, one page ahead."
            )
        }
        return (
            "No AI provider configured",
            "Bilingual mode needs an AI provider to translate."
        )
    }

    var body: some View {
        ReaderSheetChrome(
            theme: theme,
            title: "Bilingual mode",
            onClose: onConfirm,
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        languageSection
                        granularitySection
                        engineSection
                        cta
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
        )
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    // MARK: - Target language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Target language")
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 3
                ),
                spacing: 8
            ) {
                ForEach(BilingualSetupSheetState.availableLanguages, id: \.key) { lang in
                    BilingualLanguagePickerCell(
                        theme: theme,
                        language: lang,
                        isSelected: lang.key == state.languageKey,
                        onTap: { state.languageKey = lang.key }
                    )
                }
            }
        }
    }

    // MARK: - Granularity

    private var granularitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Granularity")
            HStack(spacing: 0) {
                ForEach(BilingualSetupSheetState.availableGranularities, id: \.self) { option in
                    Button(action: { state.granularity = option }) {
                        VStack(spacing: 2) {
                            Text(option.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(theme.inkColor))
                            Text(option.detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color(theme.subColor))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(granularityCellBackground(selected: state.granularity == option))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bilingualGranularity_\(option.rawValue)")
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(
                    theme.isDark
                        ? Color.white.opacity(0.06)
                        : Color.black.opacity(0.05)
                )
            )
        }
    }

    /// Selected-vs-not surface — segmented control style.
    @ViewBuilder
    private func granularityCellBackground(selected: Bool) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: 10).fill(
                theme.isDark
                    ? Color(red: 0.227, green: 0.208, blue: 0.188)
                    : Color.white
            )
            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
        } else {
            Color.clear
        }
    }

    // MARK: - Engine

    private var engineSection: some View {
        let descriptor = Self.engineDescriptor(aiConfigured: aiConfigured)
        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Translation engine")
            HStack(spacing: 12) {
                engineAvatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(descriptor.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color(theme.inkColor))
                    Text(descriptor.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(theme.subColor))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onOpenSettings) {
                    Text(Self.engineButtonLabel(aiConfigured: aiConfigured))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(aiConfigured ? Color(theme.inkColor) : Color.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                aiConfigured
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
            .foregroundStyle(aiConfigured ? Color.white : Color(theme.subColor))
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(
                    aiConfigured
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
                aiConfigured
                    ? Color(theme.ruleColor)
                    : Color(theme.accentColor).opacity(0.33),
                lineWidth: 0.5
            )
            .background(
                RoundedRectangle(cornerRadius: 12).fill(
                    aiConfigured
                        ? (theme.isDark
                            ? Color.white.opacity(0.04)
                            : Color.white)
                        : Color(theme.accentColor).opacity(0.06)
                )
            )
    }

    // MARK: - CTA

    private var cta: some View {
        Button(action: onConfirm) {
            Text(Self.ctaLabel(aiConfigured: aiConfigured))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Color(theme.accentColor))
                )
                .shadow(
                    color: Color(theme.accentColor).opacity(0.33),
                    radius: 6, x: 0, y: 4
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityIdentifier("bilingualSetupConfirm")
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Color(theme.subColor))
    }
}

// MARK: - Granularity labels

private extension TranslationGranularity {

    /// Display label for the segmented control — design pins these.
    var label: String {
        switch self {
        case .paragraph: return "Paragraph"
        case .sentence:  return "Sentence"
        }
    }

    /// Smaller-text descriptor under the label.
    var detail: String {
        switch self {
        case .paragraph: return "Translate after each ¶"
        case .sentence:  return "Translate after each sentence"
        }
    }
}
