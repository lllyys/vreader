// Purpose: Feature #99 WI-1 — the pure edit-mode decision seam for the
// edit-framed translation-settings sheet (design §#1640 `BSSettingsSheet`).
// All CTA / cost-strip / banner rules live here so the SwiftUI sheet and
// the six host confirm-routers stay wiring.
//
// Key decisions:
// - A LANGUAGE change dominates the dirty kind; the cache decides
//   new-vs-cached. A cached-language pick that ALSO changes granularity
//   is `.newLanguage` — re-translation is owed anyway, so the CTA is the
//   accent "Apply · re-translate as you read" (design CTA table).
// - The cost strip has TWO render slots mirroring the design jsx: the
//   language strip under the language grid (new/cached kinds) and the
//   granularity strip under the segmented control (granularity-only).
// - The re-translate banner shows only for `.newLanguage` (the design
//   note's confirmed state).
//
// @coordinates-with: BilingualSetupSheet.swift, BilingualCostStrip.swift,
//   ChapterTranslationStore.swift,
//   dev-docs/plans/20260611-feature-99-translation-settings-reentry.md

import Foundation

/// The pure decision rules for the edit-framed translation-settings sheet.
enum BilingualSettingsEditModel {

    /// What the draft changes relative to the book's current settings.
    enum DirtyKind: Equatable, Sendable {
        /// Nothing changed — quiet "Done", no strips, no banner.
        case none
        /// The draft language has no cached rows (or a cached language
        /// combined with a granularity change — re-translation owed).
        case newLanguage
        /// The draft language was translated before at any granularity —
        /// switching is instant.
        case cachedLanguage
        /// Only the granularity changed.
        case granularityOnly
    }

    /// The cost-strip variants (rendered by `BilingualCostStrip`).
    enum StripKind: Equatable, Sendable {
        case newLanguage
        case cachedLanguage
        case granularityOnly
    }

    /// Resolves the dirty kind. Language change dominates; the cache set
    /// (from `ChapterTranslationStore.cachedLanguages`) decides whether a
    /// changed language is a paid re-translate or an instant switch.
    /// Both language keys are canonicalised through the registry
    /// (Gate-4 r1 Medium): a stale persisted `currentLanguage` no longer
    /// in `BilingualLanguage.all` resolves the same way the sheet's
    /// `normalised()` draft does, so an untouched sheet stays `.none`.
    static func dirtyKind(
        currentLanguage: String,
        currentGranularity: TranslationGranularity,
        draft: BilingualSetupSheetState,
        cachedLanguages: Set<String>
    ) -> DirtyKind {
        let canonicalCurrent = BilingualLanguage.findOrDefault(key: currentLanguage).key
        let canonicalDraft = BilingualLanguage.findOrDefault(key: draft.languageKey).key
        let languageChanged = canonicalDraft != canonicalCurrent
        let granularityChanged = draft.granularity != currentGranularity
        if languageChanged {
            if cachedLanguages.contains(canonicalDraft) && !granularityChanged {
                return .cachedLanguage
            }
            return .newLanguage
        }
        if granularityChanged { return .granularityOnly }
        return .none
    }

    /// The footer CTA label (design CTA table).
    static func ctaLabel(dirty: DirtyKind, draftLanguageDisplay: String) -> String {
        switch dirty {
        case .none:           return "Done"
        case .cachedLanguage: return "Switch to \(draftLanguageDisplay)"
        case .newLanguage, .granularityOnly:
            return "Apply \u{B7} re-translate as you read"
        }
    }

    /// Accent fill for any dirty state; quiet fill for "Done".
    static func ctaIsAccent(dirty: DirtyKind) -> Bool {
        dirty != .none
    }

    /// The strip under the LANGUAGE grid — language kinds only.
    static func languageStripKind(dirty: DirtyKind) -> StripKind? {
        switch dirty {
        case .newLanguage:    return .newLanguage
        case .cachedLanguage: return .cachedLanguage
        case .granularityOnly, .none: return nil
        }
    }

    /// The strip under the GRANULARITY control — granularity-only.
    static func granularityStripKind(dirty: DirtyKind) -> StripKind? {
        dirty == .granularityOnly ? .granularityOnly : nil
    }

    /// The floating "Re-translating in {lang}…" banner shows only when a
    /// genuinely new language was applied (the design's confirmed state).
    static func shouldShowRetranslateBanner(dirty: DirtyKind) -> Bool {
        dirty == .newLanguage
    }
}
