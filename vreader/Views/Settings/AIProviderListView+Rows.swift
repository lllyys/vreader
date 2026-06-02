// Purpose: Row activation + the profile list/row rendering for
// `AIProviderListView`, split out to keep the main file under the ~300-line
// guideline (rule 50 §9). The members are `internal` (not `private`) so they
// can live in this cross-file extension; `editorContext` is likewise internal
// on the main struct.
//
// @coordinates-with: AIProviderListView.swift, AISettingsViewModel.swift,
//   AIProviderEditSheet.swift, ProviderProfile.swift

import SwiftUI

extension AIProviderListView {

    // MARK: - Row activation

    /// Activates the tapped profile, then (feature #81) signals the reader
    /// flow so it can pop back to the bilingual sheet. Extracted from the row
    /// button so the row body stays within SwiftUI's type-inference budget.
    func handleRowActivation(_ profile: ProviderProfile) {
        Task {
            await viewModel.setActive(profile.id)
            // Only signal the reader flow when activation actually took —
            // `setActive` silently rejects a stale id, and we must not pop the
            // reader stack as if the engine changed when it didn't.
            guard viewModel.activeID == profile.id else { return }
            onRowActivated?(profile.id)
        }
    }

    // MARK: - Profile List

    var profileList: some View {
        List {
            ForEach(viewModel.profiles) { profile in
                profileRow(profile)
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("aiProvidersList")
    }

    @ViewBuilder
    func profileRow(_ profile: ProviderProfile) -> some View {
        // Two-button row: the wide leading half (radio + text) activates
        // the profile; a trailing pencil button opens the editor.
        // `.buttonStyle(.borderless)` on each button is required so
        // SwiftUI doesn't merge them into one row-wide hit area — that
        // would re-introduce the "tap does only setActive" bug for
        // anyone trying to land on the pencil.
        HStack(spacing: 12) {
            Button {
                handleRowActivation(profile)
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
