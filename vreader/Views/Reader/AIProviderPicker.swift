// Purpose: SwiftUI Menu-based picker for the in-reader AI provider
// switch — feature #50 WI-7 acceptance criterion (b). Renders in the
// AIReaderPanel toolbar so a user can flip the active provider /
// model without leaving the reader.
//
// Behavior:
// - Empty state (no profiles): shows a single disabled "No providers"
//   item with a hint to add one in Settings. The toolbar Menu label
//   still renders so the affordance is always visible.
// - Populated: lists every saved profile with the active one marked
//   by a leading checkmark. Tapping a row dispatches
//   `setActive(id)` via the ViewModel; the change persists to the
//   shared ProviderProfileStore and propagates to every in-flight
//   AIService call on the next `AIService.resolveProvider()` invocation.
//
// Visual:
// - Toolbar label combines the active profile's name + a downward
//   chevron, so the user can see which provider is active at a glance.
// - When no provider is active, the label reads "Provider" to keep
//   the menu discoverable.
//
// @coordinates-with: AIProviderPickerViewModel.swift, AIReaderPanel.swift,
//   ProviderProfile.swift, ProviderKind.swift

import SwiftUI

/// In-reader provider picker. Toolbar Menu over the saved profiles
/// with one-tap active-selection switching.
struct AIProviderPicker: View {
    @Bindable var viewModel: AIProviderPickerViewModel

    var body: some View {
        Menu {
            if viewModel.hasProfiles {
                ForEach(viewModel.profiles) { profile in
                    Button {
                        Task { await viewModel.setActive(profile.id) }
                    } label: {
                        // Active row carries a visible checkmark for
                        // sighted users; the SF Symbol is hidden from
                        // VoiceOver since the `.isSelected` trait below
                        // already conveys the selected state. Non-active
                        // rows render plain text.
                        if viewModel.activeID == profile.id {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                    .accessibilityIdentifier("aiProviderPickerRow_\(profile.id.uuidString)")
                    // Round-1 audit finding [2]: surface the active row
                    // via the `.isSelected` accessibility trait, mirroring
                    // WI-6a's AIProviderListView pattern. Without this,
                    // VoiceOver only reports "button" + name; the
                    // checkmark glyph is a visual-only cue.
                    .accessibilityAddTraits(viewModel.activeID == profile.id ? [.isSelected] : [])
                }
            } else {
                // Single disabled "no providers" row. Tapping it does
                // nothing; the hint is in the label.
                Text("No providers — add one in Settings")
                    .accessibilityIdentifier("aiProviderPickerEmpty")
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
            }
            .accessibilityLabel("AI provider")
            .accessibilityValue(activeName)
            .accessibilityIdentifier("aiProviderPickerMenu")
        }
        .task { await viewModel.loadProfiles() }
    }

    /// Active profile name when available; otherwise a generic "Provider"
    /// fallback so the menu remains discoverable in the empty state.
    private var activeName: String {
        guard let id = viewModel.activeID,
              let active = viewModel.profiles.first(where: { $0.id == id }) else {
            return "Provider"
        }
        return active.name
    }
}
