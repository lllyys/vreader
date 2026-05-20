// Purpose: SwiftUI Form section for AI assistant configuration. Wraps the
// AI Assistant toggle, a navigation link to the provider list, and the
// data-sharing consent toggle.
//
// Feature #50 WI-6a: previously held the single-profile UI (API key
// SecureField, model/baseURL/temperature/maxTokens fields). Those move
// to `AIProviderEditSheet.swift` in WI-6b. WI-6a keeps the section thin
// and delegates the list management to `AIProviderListView`.
//
// Feature #67 WI-5: restyles the AI Provider `NavigationLink` row to
// the design's colored-icon `SettingsIconRow` treatment
// (`SettingsRowPalette.aiProvider`) — the ONLY AI row depicted in the
// committed `vreader-panels.jsx` `SettingsSheet` design. The AI
// Assistant + Data & Privacy toggle rows keep their existing plain-
// `Toggle` chrome because the design bundle does not depict colored-
// icon variants for those rows; per rule 51 we do not invent UI on an
// undesigned surface (a `needs-design` follow-up tracks them).
//
// Key decisions:
// - The section is just a wrapper now (~80 lines). Heavy lifting lives in
//   the new list view and (WI-6b) the editor sheet.
// - The provider list is reachable via a `NavigationLink` from the
//   Settings form. We don't auto-load the list here — `AIProviderListView`
//   calls `viewModel.loadProfiles()` on its own `.task`.
// - The AI toggle and the consent toggle remain sibling rows on the
//   Settings form root; they're global, not per-profile.
// - `rowPaletteKeysForTesting` mirrors `SettingsView.rowPaletteKeysForTesting`
//   so `SheetReSkinSnapshotTests` / `AISettingsSectionRestyleTests`
//   can pin the restyled rows without a render path.
// - The AI Assistant + Data & Privacy `Toggle` rows do NOT get a
//   colored-icon row treatment: the design (`vreader-panels.jsx`
//   line 868-870) shows only the AI provider row. Inventing icons +
//   colors for the two toggles would violate rule 51.
//
// @coordinates-with: AISettingsViewModel.swift, AIProviderListView.swift,
//   SettingsView.swift, SettingsRowStyle.swift, SettingsRowPalette.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import SwiftUI

/// Form section containing AI assistant settings.
struct AISettingsSection: View {
    @Bindable var viewModel: AISettingsViewModel

    /// The sheet theme — Settings is always `.paper`. Held as a
    /// constant so the row carries the same theme `SettingsView` uses;
    /// matches the WI-4 precedent of `SettingsView.paperTheme`.
    private let theme: ReaderThemeV2 = .paper

    var body: some View {
        Section("AI Assistant") {
            Toggle("Enable AI Assistant", isOn: $viewModel.isAIEnabled)
                .accessibilityIdentifier("aiToggle")
        }

        if viewModel.isAIEnabled {
            Section("Providers") {
                NavigationLink {
                    AIProviderListView(viewModel: viewModel)
                } label: {
                    providerRowForTesting
                }
                .accessibilityIdentifier("aiProvidersNavLink")
            }

            Section("Data & Privacy") {
                Toggle("Allow AI data sharing", isOn: $viewModel.hasConsent)
                    .accessibilityIdentifier("consentToggle")
            }
        }
    }

    // MARK: - Restyled provider row (feature #67 WI-5)

    /// The AI Provider row composed from the design palette. Exposed
    /// so the WI-5 composition test can pin the spec without a
    /// render path. The convention mirrors `SettingsView`'s
    /// `profileCardForTesting` testing seam.
    var providerRowForTesting: AISettingsProviderRow {
        AISettingsProviderRow(
            theme: theme,
            spec: SettingsRowPalette.aiProvider,
            title: "AI Providers",
            trailingValue: activeProfileSummary
        )
    }

    /// The palette keys for the rows this section renders, in render
    /// order — exposed for the feature #67 WI-5 composition test.
    /// Returns the AI Provider's palette key only when AI is enabled.
    /// The Enable-AI / Data-&-Privacy `Toggle` rows are not in this
    /// list — they have no palette entry by design (see file header
    /// comment + rule 51).
    var rowPaletteKeysForTesting: [String] {
        guard viewModel.isAIEnabled else { return [] }
        return [SettingsRowPalette.aiProvider.paletteKey]
    }

    /// Summary text shown to the right of the "AI Providers" row.
    /// Reflects the most recently loaded list state — empty before any
    /// load, "None" if loaded but no profile is active, otherwise the
    /// active profile's name.
    private var activeProfileSummary: String {
        guard !viewModel.profiles.isEmpty else { return "" }
        if let active = viewModel.profiles.first(where: { $0.id == viewModel.activeID }) {
            return active.name
        }
        return "None"
    }
}

// MARK: - Provider row

/// The AI Provider row's `SettingsIconRow` form, factored so the
/// WI-5 composition test can assert on the `spec` identity without
/// reaching into private state.
struct AISettingsProviderRow: View {
    let theme: ReaderThemeV2
    let spec: SettingsRowSpec
    let title: String
    let trailingValue: String

    /// Exposed for the WI-5 composition test — pins the row's
    /// design-data identity to `SettingsRowPalette.aiProvider`.
    var specForTesting: SettingsRowSpec { spec }

    var body: some View {
        SettingsIconRow(
            theme: theme,
            icon: Image(systemName: spec.symbolName),
            iconBackground: spec.background.color,
            title: title,
            trailingValue: trailingValue.isEmpty ? nil : trailingValue,
            showsChevron: false
        )
    }
}
