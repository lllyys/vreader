// Purpose: Feature #99 WI-3 — the value-type render context for the
// More-menu bilingual cluster. Carries the display strings the
// `translationSettings` row's sub-line needs ("Chinese · Paragraph ·
// Claude") so the popover stays presentational (the Gate-2 H2 seam —
// the same row-parameterisation pattern as `BilingualRowState`).
//
// @coordinates-with: ReaderMoreMenuRow.swift, ReaderMorePopover.swift,
//   ReaderContainerView+Sheets.swift,
//   dev-docs/plans/20260611-feature-99-translation-settings-reentry.md

import Foundation

/// Display context for the More-menu bilingual cluster (feature #99).
/// Built by `ReaderContainerView` from its bilingual mirror + the
/// resolved active-provider name.
struct ReaderMoreMenuBilingualContext: Equatable, Sendable {

    /// The target language's display name (registry-resolved).
    let languageDisplay: String

    /// The granularity's display label ("Paragraph" / "Sentence").
    let granularityDisplay: String

    /// The active AI provider's display name, or nil while unresolved /
    /// no profile — the subtitle drops the segment.
    let providerDisplay: String?

    /// "Chinese · Paragraph · Claude" — the provider segment dropped
    /// when nil/empty.
    var settingsSubtitle: String {
        var parts = [languageDisplay, granularityDisplay]
        if let providerDisplay, !providerDisplay.isEmpty {
            parts.append(providerDisplay)
        }
        return parts.joined(separator: " \u{B7} ")
    }
}
