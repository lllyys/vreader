// Purpose: SwiftUI Form section for AI assistant configuration. Wraps the
// AI Assistant toggle, a navigation link to the provider list, and the
// data-sharing consent toggle.
//
// Feature #50 WI-6a: previously held the single-profile UI (API key
// SecureField, model/baseURL/temperature/maxTokens fields). Those move
// to `AIProviderEditSheet.swift` in WI-6b. WI-6a keeps the section thin
// and delegates the list management to `AIProviderListView`.
//
// Key decisions:
// - The section is just a wrapper now (~80 lines). Heavy lifting lives in
//   the new list view and (WI-6b) the editor sheet.
// - The provider list is reachable via a `NavigationLink` from the
//   Settings form. We don't auto-load the list here — `AIProviderListView`
//   calls `viewModel.loadProfiles()` on its own `.task`.
// - The AI toggle and the consent toggle remain sibling rows on the
//   Settings form root; they're global, not per-profile.
//
// @coordinates-with: AISettingsViewModel.swift, AIProviderListView.swift,
//   SettingsView.swift

import SwiftUI

/// Form section containing AI assistant settings.
struct AISettingsSection: View {
    @Bindable var viewModel: AISettingsViewModel

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
                    HStack {
                        Text("AI Providers")
                        Spacer()
                        Text(activeProfileSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityIdentifier("aiProvidersNavLink")
            }

            Section("Data & Privacy") {
                Toggle("Allow AI data sharing", isOn: $viewModel.hasConsent)
                    .accessibilityIdentifier("consentToggle")
            }
        }
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
