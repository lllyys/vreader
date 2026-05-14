// Purpose: SwiftUI list of saved WebDAV server profiles with active
// selection, swipe-to-delete, pencil-edit, and Add toolbar button.
// Feature #52 WI-4a — list UI + reachable stub editor. WI-4b adds the
// real editor form behind the same `.sheet(item:)` binding.
//
// Mirrors `AIProviderListView` (Feature #50 WI-6a + bug #174 fix)
// exactly:
// - `@Bindable` ViewModel so SwiftUI re-renders when the underlying
//   `profiles` / `activeID` mutate.
// - `WebDAVEditorContext` Identifiable wrapper drives `.sheet(item:)`
//   so add-vs-edit presentation is atomic (no separate state pair
//   like the pre-bug-174 split that could race).
// - Two-button row pattern (radio + pencil) — `.buttonStyle(.borderless)`
//   on each so SwiftUI keeps them as distinct hit areas instead of
//   merging into one row-wide tap that would steal the pencil.
// - Empty state with globe icon + Add CTA, mirroring `OPDSCatalogListView`
//   precedent (a project convention).
// - Resync via `webdavProfilesDidChange` notification when an external
//   path mutates the store (e.g. WI-4b's editor sheet, or WI-2's
//   migrator running mid-presentation).
//
// @coordinates-with: WebDAVProfileListViewModel.swift,
//   WebDAVServerProfile.swift, WebDAVServerProfileStore.swift,
//   WebDAVServerProfileEditSheet.swift, WebDAVSettingsView.swift

import SwiftUI

/// One-shot wrapper that drives `.sheet(item:)` for the editor sheet.
/// Same race-fix rationale as `AIEditorContext` (bug #174): folding
/// "what to edit" + "is the sheet up" into one `Identifiable` value
/// makes presentation atomic and replaces the pre-bug-174 split
/// `editingProfile + showEditor` state pair.
///
/// `id` is the profile UUID string for edit-mode, or `"new"` for
/// add-mode, so SwiftUI re-creates the sheet body on target change.
struct WebDAVEditorContext: Identifiable, Equatable, Sendable {
    /// Non-nil = edit-mode; nil = add-new.
    let profile: WebDAVServerProfile?

    var id: String {
        profile?.id.uuidString ?? "new"
    }

    static func add() -> WebDAVEditorContext {
        WebDAVEditorContext(profile: nil)
    }

    static func edit(_ profile: WebDAVServerProfile) -> WebDAVEditorContext {
        WebDAVEditorContext(profile: profile)
    }
}

/// Unified alert state for the list view. Codex round-2 Medium fix:
/// SwiftUI honors only one `.alert(...)` per view branch in practice,
/// so the previous dual-alert (`listError` + delete-confirm) had one
/// of the two paths becoming unreachable depending on system version.
/// Folding both into a single `@State alertItem` + one `.alert(...)`
/// guarantees mutually-exclusive presentation.
enum WebDAVListAlertItem: Identifiable {
    case listError(message: String)
    case confirmDeleteActive(profile: WebDAVServerProfile)

    var id: String {
        switch self {
        case .listError: return "listError"
        case .confirmDeleteActive(let p): return "confirmDelete-\(p.id.uuidString)"
        }
    }
}

/// List of saved WebDAV server profiles with active selection.
struct WebDAVServerProfileListView: View {
    @Bindable var viewModel: WebDAVProfileListViewModel

    /// Single `Identifiable` state field that drives the editor sheet
    /// (`.sheet(item:)`). Nil = no sheet; non-nil = present for the
    /// wrapped target. See `WebDAVEditorContext` for the race rationale.
    @State private var editorContext: WebDAVEditorContext? = nil

    /// Unified alert state. Nil = no alert; non-nil = present the
    /// indicated alert (list error or active-delete confirmation).
    @State private var alertItem: WebDAVListAlertItem? = nil

    var body: some View {
        Group {
            if viewModel.profiles.isEmpty {
                emptyState
            } else {
                profileList
            }
        }
        .navigationTitle("WebDAV Servers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorContext = .add()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addWebDAVProfileButton")
                .accessibilityLabel("Add server")
            }
        }
        .task {
            await viewModel.loadProfiles()
        }
        // Resync when external mutation lands (WI-2 migrator OR future
        // WI-4b editor upserts) while we're presented.
        .onReceive(NotificationCenter.default.publisher(for: .webdavProfilesDidChange)) { _ in
            Task { await viewModel.loadProfiles() }
        }
        .sheet(item: $editorContext) { context in
            WebDAVServerProfileEditSheet(
                existing: context.profile,
                profileStore: viewModel.profileStore
            )
        }
        // Codex round-2 Medium fix: single `.alert(...)` driven by an
        // Identifiable enum. The previous dual-alert (listError + delete-
        // confirm) hit SwiftUI's "one alert per branch" limitation and
        // could leave one path silently unreachable depending on system
        // version.
        .onChange(of: viewModel.listError) { _, newValue in
            if let msg = newValue {
                // Only promote into the unified slot if no higher-priority
                // alert is already on screen. The delete-confirm prompt
                // is the user-blocking path; the listError is informational.
                if alertItem == nil {
                    alertItem = .listError(message: msg)
                }
            }
        }
        .alert(
            alertTitle(for: alertItem),
            isPresented: alertIsPresentedBinding,
            presenting: alertItem
        ) { item in
            alertButtons(for: item)
        } message: { item in
            Text(alertMessageText(for: item))
        }
    }

    // MARK: - Unified alert plumbing

    private var alertIsPresentedBinding: Binding<Bool> {
        Binding(
            get: { alertItem != nil },
            set: { presented in
                if !presented {
                    // Mirror dismissal back into the source state so the
                    // listError doesn't re-prompt immediately on the
                    // next re-render.
                    if case .listError = alertItem {
                        viewModel.listError = nil
                    }
                    alertItem = nil
                }
            }
        )
    }

    private func alertTitle(for item: WebDAVListAlertItem?) -> String {
        switch item {
        case .listError: return "Profile Error"
        case .confirmDeleteActive: return "Delete active server?"
        case .none: return ""
        }
    }

    @ViewBuilder
    private func alertButtons(for item: WebDAVListAlertItem) -> some View {
        switch item {
        case .listError:
            Button("OK", role: .cancel) {
                // Codex round-3 Medium fix: clear BOTH the local alert
                // slot and the underlying viewModel.listError. Direct
                // button taps don't drive the `alertIsPresentedBinding`
                // setter, so a setter-only clear would leave the VM
                // state stale (later same-message errors would silently
                // re-promote, or fail to re-trigger `.onChange`).
                viewModel.listError = nil
                alertItem = nil
            }
            .accessibilityIdentifier("listErrorOKButton")
        case .confirmDeleteActive(let target):
            Button("Delete", role: .destructive) {
                let id = target.id
                alertItem = nil
                Task { await viewModel.deleteProfile(id) }
                // Codex round-3 Medium fix: if a list error queued up
                // while the confirm was on screen, surface it now.
                promoteDeferredListErrorIfAny()
            }
            .accessibilityIdentifier("confirmDeleteActiveWebDAVProfile")
            Button("Cancel", role: .cancel) {
                alertItem = nil
                promoteDeferredListErrorIfAny()
            }
            .accessibilityIdentifier("cancelDeleteActiveWebDAVProfile")
        }
    }

    /// Promote a deferred `viewModel.listError` into the unified alert
    /// slot if one was queued while a higher-priority alert was on
    /// screen. The `.onChange(of: viewModel.listError)` watcher skips
    /// promotion when `alertItem != nil`; this helper covers the tail
    /// case of "confirm-alert dismissed but listError still non-nil".
    private func promoteDeferredListErrorIfAny() {
        if alertItem == nil, let msg = viewModel.listError {
            alertItem = .listError(message: msg)
        }
    }

    private func alertMessageText(for item: WebDAVListAlertItem) -> String {
        switch item {
        case .listError(let message):
            return message
        case .confirmDeleteActive(let target):
            return "\"\(target.displayName)\" is currently the active backup server. Deleting it leaves no active server until you switch to another or add one."
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No WebDAV Servers")
                .font(.headline)

            Text("Add a WebDAV server to back up and restore your library. You can save multiple servers and switch between them.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                editorContext = .add()
            } label: {
                Label("Add Server", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("emptyAddWebDAVServerButton")
        }
        .accessibilityIdentifier("webdavServersEmptyState")
    }

    // MARK: - Profile List

    private var profileList: some View {
        List {
            ForEach(viewModel.profiles) { profile in
                profileRow(profile)
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("webdavServersList")
    }

    @ViewBuilder
    private func profileRow(_ profile: WebDAVServerProfile) -> some View {
        // Two-button row: wide leading half (radio + text) activates the
        // profile; trailing pencil opens the editor. `.buttonStyle(.borderless)`
        // is required on BOTH so SwiftUI keeps them as distinct hit areas.
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
                        Text(profile.displayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if !profile.username.isEmpty {
                            Text(profile.username)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(profile.serverURL)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("webdavProfileRow_\(profile.id.uuidString)")
            .accessibilityLabel(rowAccessibilityLabel(for: profile))
            .accessibilityValue(viewModel.activeID == profile.id ? "Active" : "Not active")
            .accessibilityAddTraits(viewModel.activeID == profile.id ? [.isSelected, .isButton] : .isButton)
            .accessibilityHint(viewModel.activeID == profile.id ? "" : "Double-tap to make active.")

            // Discoverable edit affordance (bug #174 precedent — leading-
            // edge swipe alone is not discoverable enough).
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
            .accessibilityIdentifier("editWebDAVProfileButton_\(profile.id.uuidString)")
            .accessibilityLabel("Edit \(profile.displayName)")
            .accessibilityHint("Opens the editor for this server.")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                // Active-profile swipe → confirmation alert via the
                // unified alertItem channel.
                // Inactive-profile swipe → immediate delete (low-risk).
                if profile.id == viewModel.activeID {
                    alertItem = .confirmDeleteActive(profile: profile)
                } else {
                    Task { await viewModel.deleteProfile(profile.id) }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteWebDAVProfile_\(profile.id.uuidString)")
        }
        // Leading-edge swipe kept as a power-user shortcut, mirroring the
        // AI provider list view.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editorContext = .edit(profile)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            .accessibilityIdentifier("editWebDAVProfile_\(profile.id.uuidString)")
        }
    }

    // MARK: - Accessibility helpers

    /// Builds a VoiceOver label that disambiguates duplicate display
    /// names by appending username + host. Two profiles with identical
    /// names but different credentials would otherwise sound identical
    /// to non-visual users.
    private func rowAccessibilityLabel(for profile: WebDAVServerProfile) -> String {
        var parts: [String] = [profile.displayName]
        if !profile.username.isEmpty {
            parts.append(profile.username)
        }
        if let host = URL(string: profile.serverURL)?.host, !host.isEmpty {
            parts.append(host)
        }
        return parts.joined(separator: ", ")
    }
}
