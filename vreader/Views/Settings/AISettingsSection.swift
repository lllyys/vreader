// Purpose: SwiftUI Form section for AI assistant configuration. Wraps the
// AI Assistant toggle, a navigation link to the provider list, and the
// data-sharing consent toggle.
//
// Feature #50 WI-6a: previously held the single-profile UI (API key
// SecureField, model/baseURL/temperature/maxTokens fields). Those move
// to `AIProviderEditSheet.swift` in WI-6b. WI-6a keeps the section thin
// and delegates the list management to `AIProviderListView`.
//
// Feature #67 WI-5: restyled the AI Provider `NavigationLink` row to the
// design's colored-icon `SettingsIconRow` treatment
// (`SettingsRowPalette.aiProvider`).
//
// Feature #67 WI-6 (design #1068 `vreader-ai-toggles.jsx`, Variant A —
// the design's recommended variant): restyles the AI Assistant master
// toggle + the Data & Privacy consent toggle to the design's
// `SettingsToggleRow` (colored tile + `PillSwitch`), and merges the three
// formerly-separate `Section`s into the design's single "AI" group so it
// reads as one card. Render order (Variant A): AI Assistant (always
// visible, master gate) → AI Provider (nav) → Allow AI data sharing
// (consent) — the provider + consent rows are shown only when AI is on,
// matching the design's `aiOn &&` gate.
//
// Key decisions:
// - The section is just a wrapper now (~110 lines). Heavy lifting lives in
//   the new list view and (WI-6b) the editor sheet.
// - The provider list is reachable via a `NavigationLink` from the
//   Settings form. We don't auto-load the list here — `AIProviderListView`
//   calls `viewModel.loadProfiles()` on its own `.task`.
// - All three AI rows live in one `Section` (the design's single AI card),
//   matching Variant A. They are global, not per-profile.
// - `rowPaletteKeysForTesting` mirrors `SettingsView.rowPaletteKeysForTesting`
//   so `SheetReSkinSnapshotTests` / `AISettingsSectionRestyleTests`
//   can pin the restyled rows without a render path: it returns
//   `[aiAssistant]` when AI is off (master toggle only) and
//   `[aiAssistant, aiProvider, aiDataSharing]` when AI is on.
// - The `aiToggle` / `aiProvidersNavLink` / `consentToggle` accessibility
//   identifiers + the `AIProviderListView` destination are preserved
//   verbatim from the pre-restyle wiring (a re-skin must not drop wiring —
//   the feature #60 WI-9 lesson).
//
// @coordinates-with: AISettingsViewModel.swift, AIProviderListView.swift,
//   SettingsView.swift, SettingsRowStyle.swift, SettingsToggleRow.swift,
//   SettingsRowPalette.swift, PillSwitch.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-toggles.jsx`

import SwiftUI

/// Form section containing AI assistant settings.
struct AISettingsSection: View {
    @Bindable var viewModel: AISettingsViewModel

    /// The sheet theme — Settings is always `.paper`. Held as a
    /// constant so the rows carry the same theme `SettingsView` uses;
    /// matches the WI-4 precedent of `SettingsView.paperTheme`.
    private let theme: ReaderThemeV2 = .paper

    var body: some View {
        Section("AI") {
            // Master gate — always visible (Variant A). The
            // `aiToggle` identifier lands on the underlying `Toggle`
            // (the actionable switch), not the row container.
            SettingsToggleRow(
                theme: theme,
                icon: Image(systemName: SettingsRowPalette.aiAssistant.symbolName),
                iconBackground: SettingsRowPalette.aiAssistant.background.color,
                title: "Enable AI Assistant",
                detail: "Translation, summarize, ask about the text",
                isOn: $viewModel.isAIEnabled,
                toggleAccessibilityIdentifier: "aiToggle"
            )

            if viewModel.isAIEnabled {
                NavigationLink {
                    AIProviderListView(viewModel: viewModel)
                } label: {
                    providerRowForTesting
                }
                .accessibilityIdentifier("aiProvidersNavLink")

                SettingsToggleRow(
                    theme: theme,
                    icon: Image(systemName: SettingsRowPalette.aiDataSharing.symbolName),
                    iconBackground: SettingsRowPalette.aiDataSharing.background.color,
                    title: "Allow AI data sharing",
                    detail: "Send passages and chat history for better answers",
                    isOn: $viewModel.hasConsent,
                    toggleAccessibilityIdentifier: "consentToggle"
                )
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
    /// order — exposed for the feature #67 WI-5/WI-6 composition tests.
    /// The master AI Assistant toggle (`aiAssistant`) is always present;
    /// the AI Provider (`aiProvider`) + Allow-AI-data-sharing
    /// (`aiDataSharing`) rows are present only when AI is enabled
    /// (Variant A render order).
    var rowPaletteKeysForTesting: [String] {
        guard viewModel.isAIEnabled else {
            return [SettingsRowPalette.aiAssistant.paletteKey]
        }
        return [
            SettingsRowPalette.aiAssistant.paletteKey,
            SettingsRowPalette.aiProvider.paletteKey,
            SettingsRowPalette.aiDataSharing.paletteKey
        ]
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
