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

    /// Feature #81 reader seam: when supplied, replaces the built-in globe
    /// empty state. The builder RECEIVES this view's internal add action so
    /// its CTA still drives the canonical editor (`editorContext = .add()`).
    /// Default nil → the Library globe empty state (byte-identical).
    let emptyState: ((@escaping () -> Void) -> AnyView)?

    /// Feature #81 reader seam: fired AFTER the editor sheet fully dismisses
    /// following a successful add/edit, carrying the saved profile id +
    /// `wasAdd`. The reader flow activates the saved provider + pops. Default
    /// nil → Library path unchanged. (Re-emitted from `.sheet(onDismiss:)`,
    /// NOT directly from the editor, so the reader nav stack never pops
    /// underneath a still-present editor.)
    let onEditorSaveSuccess: ((UUID, _ wasAdd: Bool) -> Void)?

    /// Feature #81 reader seam: fired after a row tap's `setActive`
    /// completes. The reader flow pops back to the bilingual sheet. Default
    /// nil → Library path unchanged.
    let onRowActivated: ((UUID) -> Void)?

    init(
        viewModel: AISettingsViewModel,
        emptyState: ((@escaping () -> Void) -> AnyView)? = nil,
        onEditorSaveSuccess: ((UUID, _ wasAdd: Bool) -> Void)? = nil,
        onRowActivated: ((UUID) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.emptyState = emptyState
        self.onEditorSaveSuccess = onEditorSaveSuccess
        self.onRowActivated = onRowActivated
    }

    /// Single Identifiable state field that drives the editor sheet
    /// (`.sheet(item:)`). Nil = no sheet; non-nil = present sheet for
    /// the wrapped target. See `AIEditorContext` for the race-fix
    /// rationale. Internal (not `private`) so the row rendering in
    /// `AIProviderListView+Rows.swift` can drive `.edit(profile)`.
    @State var editorContext: AIEditorContext? = nil

    /// Feature #81: buffers the editor's reported save id until the editor
    /// sheet's `onDismiss` re-emits it to `onEditorSaveSuccess`. nil = no
    /// pending save.
    @State private var pendingSavedID: UUID? = nil
    @State private var pendingSavedWasAdd: Bool = false

    var body: some View {
        Group {
            if viewModel.profiles.isEmpty {
                if let emptyState {
                    // Feature #81: reader-supplied empty state. Its CTA drives
                    // THIS view's internal add presentation so the canonical
                    // editor is reused.
                    emptyState({ editorContext = .add() })
                } else {
                    defaultEmptyState
                }
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
        .sheet(item: $editorContext, onDismiss: {
            // Feature #81: re-emit the editor's reported save id to the
            // reader flow AFTER the editor sheet has fully dismissed — so
            // the reader nav stack pops without racing the editor's own
            // dismissal. No-op for the Library path (callback nil / no
            // pending save).
            if let id = pendingSavedID {
                pendingSavedID = nil
                onEditorSaveSuccess?(id, pendingSavedWasAdd)
            }
        }) { context in
            AIProviderEditSheet(
                viewModel: viewModel,
                existing: context.profile,
                onSaveSuccess: { id, wasAdd in
                    // Buffer only — the re-emit happens in onDismiss above.
                    pendingSavedID = id
                    pendingSavedWasAdd = wasAdd
                }
            )
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

    /// The Library default empty state (globe icon + generic copy). The
    /// feature-#81 reader flow overrides this via the `emptyState` builder
    /// param. Renamed from `emptyState` to free that name for the param.
    private var defaultEmptyState: some View {
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

    // Row activation + the profile list/row rendering live in
    // `AIProviderListView+Rows.swift` to keep this file under the ~300-line
    // guideline (rule 50 §9).
}
