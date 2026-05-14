// Purpose: SwiftUI list view of saved AI provider profiles with an
// active-selection radio button, per-row swipe-to-delete + swipe-to-edit,
// a discoverable trailing pencil button, and an "Add Profile" entry
// point that opens the editor sheet (Feature #50 WI-6a + bug #174 fix).
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
// - Row tap activates the profile — leading radio button shows the
//   active state. We deliberately don't use SwiftUI's `Picker` here
//   because the row also needs to show provider kind + base URL.
// - **Bug #174 fix**: edit affordance is no longer hidden behind a
//   leading-edge swipe. A visible trailing pencil button is the
//   primary discoverable edit entry, while the leading swipe is kept
//   for power users. Both ride on a single `.sheet(item:)` binding
//   driven by an `AIEditorContext` Identifiable wrapper — replaces
//   the prior split `editingProfile` + `showEditor` state pair that
//   could race on rapid swap of edit targets.
//
// @coordinates-with: AISettingsViewModel.swift, AISettingsSection.swift,
//   ProviderProfile.swift, ProviderProfileStore.swift,
//   AIProviderEditSheet.swift

import SwiftUI

/// One-shot wrapper that drives `.sheet(item:)` for the editor sheet.
/// Bug #174 fix: previously the view used `.sheet(isPresented:)` plus a
/// separate `editingProfile` field, so the two state writes had no
/// guaranteed ordering and rapid swaps (e.g. swipe-edit-A → swipe-edit-B
/// before sheet was fully presented, or empty-state-Add when an edit
/// context was still set) could present the wrong form. Folding both
/// states into a single Identifiable value makes presentation atomic.
///
/// `id` is derived from the profile UUID for edit-mode, or the literal
/// string `"new"` for add-mode, so SwiftUI re-creates the sheet body
/// when the target changes (different `id` invalidates the previous
/// presentation).
struct AIEditorContext: Identifiable, Equatable, Sendable {
    /// Non-nil = edit-mode; nil = add-new.
    let profile: ProviderProfile?

    var id: String {
        profile?.id.uuidString ?? "new"
    }

    static func add() -> AIEditorContext {
        AIEditorContext(profile: nil)
    }

    static func edit(_ profile: ProviderProfile) -> AIEditorContext {
        AIEditorContext(profile: profile)
    }
}

/// List view for saved AI provider profiles.
struct AIProviderListView: View {
    @Bindable var viewModel: AISettingsViewModel

    /// Single Identifiable state field that drives the editor sheet
    /// (`.sheet(item:)`). Nil = no sheet; non-nil = present sheet for
    /// the wrapped target. See `AIEditorContext` for the race-fix
    /// rationale.
    @State private var editorContext: AIEditorContext? = nil

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
                    editorContext = .add()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addProviderProfileButton")
            }
        }
        .task {
            await viewModel.loadProfiles()
        }
        .sheet(item: $editorContext) { context in
            AIProviderEditSheet(viewModel: viewModel, existing: context.profile)
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
                editorContext = .add()
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
        // Two-button row: the wide leading half (radio + text) activates
        // the profile; a trailing pencil button opens the editor.
        // `.buttonStyle(.borderless)` on each button is required so
        // SwiftUI doesn't merge them into one row-wide hit area — that
        // would re-introduce the "tap does only setActive" bug for
        // anyone trying to land on the pencil.
        HStack(spacing: 12) {
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

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("providerProfileRow_\(profile.id.uuidString)")
            .accessibilityLabel(profile.name)
            .accessibilityValue(viewModel.activeID == profile.id ? "Active" : "Not active")
            // Round-1 audit finding [4]: surface the radio-style selection
            // semantically. Without `.isSelected`, VoiceOver reports the row
            // as a regular button and the active state is only carried in the
            // accessibilityValue string, which is weaker than the visual UI
            // suggests.
            .accessibilityAddTraits(viewModel.activeID == profile.id ? [.isSelected, .isButton] : .isButton)
            .accessibilityHint(viewModel.activeID == profile.id ? "" : "Double-tap to make active.")

            // Bug #174 fix: discoverable Edit affordance. The leading-edge
            // swipe (kept below) was the only edit entry pre-fix.
            Button {
                editorContext = .edit(profile)
            } label: {
                Image(systemName: "pencil")
                    .font(.body)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("editProviderProfileButton_\(profile.id.uuidString)")
            .accessibilityLabel("Edit \(profile.name)")
            .accessibilityHint("Opens the editor for this provider.")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await viewModel.deleteProfile(profile.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteProviderProfile_\(profile.id.uuidString)")
        }
        // Leading-edge swipe remains as a power-user shortcut. Mirrors
        // Mail.app's common Edit + Delete row gesture pair.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editorContext = .edit(profile)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            .accessibilityIdentifier("editProviderProfile_\(profile.id.uuidString)")
        }
    }
}
