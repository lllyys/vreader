// Purpose: SwiftUI list view of saved AI provider profiles with an
// active-selection radio button, per-row swipe-to-delete, and an
// "Add Profile" entry point that opens the editor sheet (WI-6b stub
// — empty sheet for WI-6a, filled in by WI-6b).
//
// Feature #50 WI-6a: the list management surface. Editor sheet body
// is intentionally a stub here; AIProviderEditSheet lands in WI-6b
// and replaces the placeholder. Wiring (sheet presentation, "Add"
// button) is in place so WI-6b only has to fill in the sheet body.
//
// Key decisions:
// - `@Bindable` on the AISettingsViewModel so SwiftUI re-renders when
//   `profiles` / `activeID` change after `loadProfiles` / `setActive`
//   / `deleteProfile`.
// - List `.task` calls `loadProfiles()` on first appearance. SwiftUI
//   re-invokes `.task` on view identity changes; that's fine here
//   because `loadProfiles()` is idempotent against the actor store.
// - Swipe-to-delete uses `.swipeActions(edge: .trailing)` with role
//   `.destructive`. The actual delete is async; we wrap in a Task
//   because SwiftUI's swipe action closure is synchronous.
// - Empty state shows a globe icon + helper text + Add CTA. Mirrors
//   `OPDSCatalogListView.swift`'s empty-state pattern (project precedent).
// - The active selector is a single tap on the row — leading checkmark
//   shows the active state. We deliberately don't use SwiftUI's `Picker`
//   here because the row also needs to show provider kind + base URL.
//
// @coordinates-with: AISettingsViewModel.swift, AISettingsSection.swift,
//   ProviderProfile.swift, ProviderProfileStore.swift

import SwiftUI

/// List view for saved AI provider profiles.
struct AIProviderListView: View {
    @Bindable var viewModel: AISettingsViewModel

    @State private var showEditor: Bool = false
    /// Non-nil when an existing profile is being edited; nil = add-new.
    @State private var editingProfile: ProviderProfile? = nil

    var body: some View {
        Group {
            if viewModel.profiles.isEmpty {
                emptyState
            } else {
                profileList
            }
        }
        .navigationTitle("AI Providers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingProfile = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addProviderProfileButton")
            }
        }
        .task {
            await viewModel.loadProfiles()
        }
        .sheet(isPresented: $showEditor) {
            AIProviderEditSheet(viewModel: viewModel, existing: editingProfile)
        }
        .alert(
            "Profile Error",
            isPresented: Binding(
                get: { viewModel.listError != nil },
                set: { if !$0 { viewModel.listError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.listError ?? "")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No AI Providers")
                .font(.headline)

            Text("Add an AI provider to use the assistant. You can save multiple providers and switch between them.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                // Round-1 audit finding [5]: the empty-state Add path
                // didn't clear editingProfile, so after deleting the
                // last row a stale "edit" sheet could re-present. Mirror
                // the toolbar Add button's behavior.
                editingProfile = nil
                showEditor = true
            } label: {
                Label("Add Provider", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("emptyAddProviderButton")
        }
        .accessibilityIdentifier("aiProvidersEmptyState")
    }

    // MARK: - Profile List

    private var profileList: some View {
        List {
            ForEach(viewModel.profiles) { profile in
                profileRow(profile)
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("aiProvidersList")
    }

    @ViewBuilder
    private func profileRow(_ profile: ProviderProfile) -> some View {
        Button {
            Task { await viewModel.setActive(profile.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.activeID == profile.id
                      ? "largecircle.fill.circle"
                      : "circle")
                    .foregroundStyle(viewModel.activeID == profile.id ? .blue : .secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(profile.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(profile.baseURL.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .accessibilityIdentifier("providerProfileRow_\(profile.id.uuidString)")
        .accessibilityLabel(profile.name)
        .accessibilityValue(viewModel.activeID == profile.id ? "Active" : "Not active")
        // Round-1 audit finding [4]: surface the radio-style selection
        // semantically. Without `.isSelected`, VoiceOver reports the row
        // as a regular button and the active state is only carried in the
        // accessibilityValue string, which is weaker than the visual UI
        // suggests. The `.isButton` trait is added explicitly because the
        // selected trait would otherwise eclipse the default button
        // behavior on some VoiceOver configurations.
        .accessibilityAddTraits(viewModel.activeID == profile.id ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(viewModel.activeID == profile.id ? "" : "Double-tap to make active.")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await viewModel.deleteProfile(profile.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteProviderProfile_\(profile.id.uuidString)")
        }
        // Leading-edge swipe reveals Edit (WI-6b). Mirrors Mail.app's
        // common Edit + Delete row gesture pair.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editingProfile = profile
                showEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            .accessibilityIdentifier("editProviderProfile_\(profile.id.uuidString)")
        }
    }
}
