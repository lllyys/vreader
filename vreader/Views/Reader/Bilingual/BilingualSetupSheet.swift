// Purpose: Feature #56 WI-9 — the first-enable bilingual setup
// half-sheet (design §2.2). Picks target language, granularity, and
// surfaces the AI provider chip.
//
// Key decisions:
// - **`onCancel` and `onConfirm` are distinct.** Close button
//   dismisses without persisting; primary CTA confirms + persists.
// - **No direct AI dependency.** Host produces a
//   `BilingualEngineDescriptor` (configured? + provider name +
//   subtitle); the sheet renders it verbatim, with the configured-
//   state title carrying the host-supplied provider name.
// - **Language normalisation** through `BilingualLanguage.findOrDefault`
//   on appear — a persisted key not in the current registry
//   canonicalises to the first registered entry so the picker grid
//   always paints a selection.
// - **Sections split across `+Sections.swift`** to stay under the
//   ~300-line per-file budget (rule 50 §9). This file owns grid +
//   granularity + CTA + state types; engine strip + preview live in
//   the sibling.
//
// @coordinates-with: BilingualLanguage.swift, ReaderSheetChrome.swift,
//   ReaderThemeV2.swift, ChapterTranslationService.swift
//   (`TranslationGranularity`), BilingualReadingViewModel.swift,
//   BilingualSetupSheet+Sections.swift,
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

    /// Returns a copy with the language key canonicalised through the
    /// registry (`BilingualLanguage.findOrDefault`). A persisted key
    /// that's no longer in `BilingualLanguage.all` is rewritten to
    /// the registry's first entry — same fallback the pill uses, so
    /// the picker always paints a selection.
    func normalised() -> BilingualSetupSheetState {
        let resolvedKey = BilingualLanguage.findOrDefault(key: languageKey).key
        return BilingualSetupSheetState(
            languageKey: resolvedKey,
            granularity: granularity
        )
    }
}

/// AI provider descriptor the host passes into the setup sheet. The
/// sheet renders the descriptor's display surface verbatim; the host
/// resolves the provider name + subtitle from `ProviderProfileStore`.
struct BilingualEngineDescriptor: Equatable, Sendable {

    /// Whether an AI provider profile is configured. Drives the
    /// engine strip's visual + the engine button label.
    let configured: Bool

    /// Provider display name (e.g. `"Claude"`). Optional — `nil`
    /// degrades to a generic "AI provider configured" title.
    let providerName: String?

    /// Subtitle shown under the title. Optional — `nil` degrades to
    /// the design's generic copy.
    let subtitle: String?

    /// Display title — provider name when configured + supplied,
    /// otherwise a generic title.
    var displayTitle: String {
        if configured {
            if let name = providerName, !name.isEmpty {
                return name
            }
            return "AI provider configured"
        }
        return "No AI provider configured"
    }

    /// Display subtitle — host-supplied when configured + supplied,
    /// otherwise the design's generic copy.
    var displaySubtitle: String {
        if let subtitle, !subtitle.isEmpty {
            return subtitle
        }
        if configured {
            return "Translations cached per paragraph, one page ahead."
        }
        return "Bilingual mode needs an AI provider to translate."
    }
}

/// First-enable bilingual setup half-sheet — target language,
/// granularity, AI provider chip.
struct BilingualSetupSheet: View {

    /// Visual-identity-v2 theme tokens for the active book.
    let theme: ReaderThemeV2

    /// Mutable state — written by user taps, observed by the host on
    /// confirm.
    @Binding var state: BilingualSetupSheetState

    /// AI provider descriptor — produced by the host. Drives the
    /// engine-strip title, subtitle, button label.
    let engineDescriptor: BilingualEngineDescriptor

    /// Tap on the primary CTA — host should persist the chosen
    /// settings and dismiss.
    let onConfirm: () -> Void

    /// Tap on the close button — host should dismiss WITHOUT
    /// persisting. The host's `.sheet(..., onDismiss:)` composition
    /// should also route swipe-to-dismiss to the same closure so
    /// every dismissal path is covered (the close button alone is
    /// what this view wires); the WI-10..15 composition sites are
    /// the right place to assert that on-dismiss contract.
    let onCancel: () -> Void

    /// Tap on the engine "Set up" / "Change…" button — host should
    /// route to AI Settings.
    let onOpenSettings: () -> Void

    /// Sheet accessibility identifier for XCUITest + verify-cron.
    static let accessibilityIdentifier = "bilingualSetupSheet"

    /// Primary CTA label — pinned by tests. Per design §2.2 this is
    /// a constant string; the AI gating is surfaced by the engine
    /// strip, not by branching the CTA copy.
    static let primaryCTALabel = "Turn on bilingual mode"

    /// Engine strip button label — branches on the AI-configured
    /// state.
    static func engineButtonLabel(aiConfigured: Bool) -> String {
        aiConfigured ? "Change\u{2026}" : "Set up"
    }

    var body: some View {
        ReaderSheetChrome(
            theme: theme,
            title: "Bilingual mode",
            onClose: onCancel,
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        previewSection
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
        .onAppear {
            // Canonicalise the language key on appear — a stale key
            // from an older release otherwise leaves the picker grid
            // with no selection painted.
            state = state.normalised()
        }
    }

    // MARK: - Target language

    var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualSectionLabel(theme: theme, text: "Target language")
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

    var granularitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualSectionLabel(theme: theme, text: "Granularity")
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

    // MARK: - CTA

    var cta: some View {
        Button(action: onConfirm) {
            Text(Self.primaryCTALabel)
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
}

// MARK: - Granularity labels

extension TranslationGranularity {

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
