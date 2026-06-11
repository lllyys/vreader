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

/// Which frame the setup sheet renders (feature #99).
enum BilingualSetupSheetMode: Equatable, Sendable {
    /// The original first-enable frame — "Bilingual mode" title,
    /// preview section, constant CTA. The default; pre-#99 callers
    /// render byte-identical.
    case firstEnable
    /// The edit frame (design §#1640 `BSSettingsSheet`) — "Translation
    /// settings" title, leading Cancel, book-context strip, cached
    /// badges, cost strips, dirty-driven CTA.
    case edit(bookTitle: String)
}

/// First-enable bilingual setup half-sheet — target language,
/// granularity, AI provider chip. Feature #99 adds the edit frame
/// (`BilingualSetupSheetMode.edit`) for post-setup re-entry.
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

    /// Bug #344 (design #1646 S-C): whether this book's format can honor
    /// sentence granularity. When false, the Sentence segment renders at
    /// 45% opacity, ignores taps, and an info footnote explains why —
    /// the control dims rather than silently forcing `.paragraph`.
    var sentenceGranularityAvailable: Bool = true

    /// Feature #99: which frame to render. Defaults to the original
    /// first-enable frame — existing callers are unchanged.
    var mode: BilingualSetupSheetMode = .firstEnable

    /// Feature #99 (edit frame): languages with ≥1 cached row for this
    /// book (`ChapterTranslationStore.cachedLanguages`) — drives the
    /// tick badges, the caption, and the cached-vs-new dirty kind.
    var cachedLanguages: Set<String> = []

    /// Feature #99 (edit frame): the book's CURRENT persisted language /
    /// granularity — the dirty baseline. nil in first-enable mode.
    var currentLanguageKey: String? = nil
    var currentGranularity: TranslationGranularity? = nil

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
            title: displayTitle,
            onClose: onCancel,
            leading: { cancelButton },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Feature #99: the edit frame swaps the preview
                        // for the book-context strip (design BSSettingsSheet).
                        if isEditMode {
                            editContextStrip
                        } else {
                            previewSection
                        }
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
                        onTap: { state.languageKey = lang.key },
                        showsCachedBadge: showsCachedBadge(forLanguageKey: lang.key)
                    )
                }
            }
            // Feature #99 (edit frame): the cached caption + the
            // language-slot cost strip live tight under the grid.
            if showsCachedCaption {
                editCachedCaption
            }
            if let kind = languageStripKind {
                BilingualCostStrip(
                    theme: theme, kind: kind,
                    languageDisplay: draftLanguageDisplay)
            }
        }
    }

    // MARK: - Granularity

    var granularitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BilingualSectionLabel(theme: theme, text: "Granularity")
            HStack(spacing: 0) {
                ForEach(BilingualSetupSheetState.availableGranularities, id: \.self) { option in
                    Button(action: {
                        guard isGranularitySelectable(option) else { return }
                        state.granularity = option
                    }) {
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
                        // Design #1646 S-C: the unavailable segment dims to
                        // 45% — visible, not selectable.
                        .opacity(isGranularitySelectable(option) ? 1.0 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isGranularitySelectable(option))
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
            if !sentenceGranularityAvailable {
                // Design #1646 S-C: the info footnote under the control.
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(theme.subColor))
                    Text("Sentence mode isn\u{2019}t available for this book\u{2019}s format yet.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(theme.subColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("bilingualGranularityUnavailableFootnote")
            }
            // Feature #99 (edit frame): the granularity-slot cost strip.
            if let kind = granularityStripKind {
                BilingualCostStrip(
                    theme: theme, kind: kind,
                    languageDisplay: draftLanguageDisplay)
            }
        }
    }

    /// Bug #344: a granularity option is selectable unless it is `.sentence`
    /// on a format that can't hold the sentence-level inject contract.
    func isGranularitySelectable(_ option: TranslationGranularity) -> Bool {
        option != .sentence || sentenceGranularityAvailable
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
        // Feature #99: the edit frame's CTA is dirty-driven — quiet
        // "Done" when nothing changed, accent otherwise; first-enable
        // keeps the constant accent CTA.
        Button(action: onConfirm) {
            Text(resolvedCTALabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ctaUsesAccentFill ? Color.white : Color(theme.inkColor))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(
                        ctaUsesAccentFill
                            ? Color(theme.accentColor)
                            : (theme.isDark
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.06))
                    )
                )
                .shadow(
                    color: ctaUsesAccentFill
                        ? Color(theme.accentColor).opacity(0.33)
                        : Color.clear,
                    radius: 6, x: 0, y: 4
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityIdentifier("bilingualSetupConfirm")
    }
}
