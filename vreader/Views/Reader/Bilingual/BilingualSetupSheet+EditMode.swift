// Purpose: Feature #99 WI-2 — the setup sheet's EDIT-frame surfaces
// (design §#1640 `BSSettingsSheet`): the mode-derived title / CTA /
// dirty computations (exposed as testable computed properties), the
// leading Cancel button, the book-context strip, and the cached-
// languages caption. Split from BilingualSetupSheet.swift for the
// ~300-line file budget (rule 50 §9).
//
// @coordinates-with: BilingualSetupSheet.swift,
//   BilingualSettingsEditModel.swift, BilingualCostStrip.swift,
//   dev-docs/plans/20260611-feature-99-translation-settings-reentry.md

import SwiftUI

extension BilingualSetupSheet {

    // MARK: - Mode-derived surfaces (testing seam)

    /// Whether the edit frame is active.
    var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// "Bilingual mode" (first enable) / "Translation settings" (edit).
    var displayTitle: String {
        isEditMode ? "Translation settings" : "Bilingual mode"
    }

    /// The edit frame shows a leading Cancel text button; first-enable
    /// keeps only the default circular close.
    var showsCancelButton: Bool { isEditMode }

    /// "Bilingual mode is on · {book title}" — nil in first-enable mode.
    /// The combined-string testing surface; the view renders the title
    /// as a separate italic-serif run (design `BSSettingsSheet`).
    var contextStripText: String? {
        guard let editBookTitle else { return nil }
        guard !editBookTitle.isEmpty else { return "Bilingual mode is on" }
        return "Bilingual mode is on \u{B7} \(editBookTitle)"
    }

    /// The edit frame's book title — nil in first-enable mode.
    var editBookTitle: String? {
        guard case .edit(let bookTitle) = mode else { return nil }
        return bookTitle
    }

    /// The dirty kind for the current draft (edit mode only — `.none`
    /// in first-enable, whose CTA is constant).
    var editDirtyKind: BilingualSettingsEditModel.DirtyKind {
        guard isEditMode,
              let currentLanguageKey, let currentGranularity else { return .none }
        return BilingualSettingsEditModel.dirtyKind(
            currentLanguage: currentLanguageKey,
            currentGranularity: currentGranularity,
            draft: state,
            cachedLanguages: cachedLanguages
        )
    }

    /// The footer CTA label for the active frame.
    var resolvedCTALabel: String {
        guard isEditMode else { return Self.primaryCTALabel }
        return BilingualSettingsEditModel.ctaLabel(
            dirty: editDirtyKind, draftLanguageDisplay: draftLanguageDisplay)
    }

    /// Accent CTA: always in first-enable; dirty-only in edit.
    var ctaUsesAccentFill: Bool {
        guard isEditMode else { return true }
        return BilingualSettingsEditModel.ctaIsAccent(dirty: editDirtyKind)
    }

    /// The language-slot cost strip kind (under the grid), edit only.
    var languageStripKind: BilingualSettingsEditModel.StripKind? {
        guard isEditMode else { return nil }
        return BilingualSettingsEditModel.languageStripKind(dirty: editDirtyKind)
    }

    /// The granularity-slot cost strip kind, edit only.
    var granularityStripKind: BilingualSettingsEditModel.StripKind? {
        guard isEditMode else { return nil }
        return BilingualSettingsEditModel.granularityStripKind(dirty: editDirtyKind)
    }

    /// Whether a language tile carries the green cached tick (edit only).
    func showsCachedBadge(forLanguageKey key: String) -> Bool {
        isEditMode && cachedLanguages.contains(key)
    }

    /// The "Already translated — switching back is instant" caption —
    /// shown when at least one tile carries a badge.
    var showsCachedCaption: Bool {
        guard isEditMode else { return false }
        return BilingualSetupSheetState.availableLanguages
            .contains { cachedLanguages.contains($0.key) }
    }

    /// The draft language's display name (registry-resolved).
    var draftLanguageDisplay: String {
        BilingualLanguage.findOrDefault(key: state.languageKey).key
    }

    // MARK: - Edit-frame views

    /// Leading Cancel text button (design `BSSettingsSheet` leading slot).
    @ViewBuilder
    var cancelButton: some View {
        if showsCancelButton {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color(theme.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bilingualSettingsCancel")
        }
    }

    /// The book-context strip — "Bilingual mode is on · *{title}*".
    /// Only the TITLE run is italic serif (Gate-4 r1 Medium — the
    /// design italicises the book title, not the whole line).
    @ViewBuilder
    var editContextStrip: some View {
        if let title = editBookTitle {
            HStack(spacing: 8) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(theme.subColor))
                (Text(title.isEmpty
                        ? "Bilingual mode is on" : "Bilingual mode is on \u{B7} ")
                    .font(.system(size: 11.5))
                    + Text(title)
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 11.5)))
                    .italic())
                    .foregroundStyle(Color(theme.subColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityIdentifier("bilingualSettingsContextStrip")
        }
    }

    /// The cached-languages caption under the grid (green dot + sub).
    var editCachedCaption: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(theme.isDark
                    ? Color(red: 0.247, green: 0.416, blue: 0.345)
                    : Color(red: 0.227, green: 0.416, blue: 0.353))
                .frame(width: 11, height: 11)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .heavy))
                        .foregroundStyle(.white)
                )
            Text("Already translated \u{2014} switching back is instant")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(theme.subColor))
        }
        .accessibilityIdentifier("bilingualSettingsCachedCaption")
    }
}
