// Purpose: Feature #56 WI-9 — the setup sheet's value types:
// `BilingualSetupSheetState` (the host-held draft the sheet binds to)
// and `BilingualEngineDescriptor` (the AI-provider display descriptor).
// Split from BilingualSetupSheet.swift for the ~300-line file budget
// (feature #99 WI-2 pushed the sheet over).
//
// @coordinates-with: BilingualSetupSheet.swift, BilingualLanguage.swift,
//   ChapterTranslationService.swift (`TranslationGranularity`)

import Foundation
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
