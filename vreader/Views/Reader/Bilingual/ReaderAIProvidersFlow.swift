// Purpose: Feature #81 — the testable navigation/activation core of the
// in-reader AI Providers flow. Owns the push state for the bilingual sheet's
// NavigationStack and the "a provider became the engine → refresh + pop"
// transitions, decoupled from the SwiftUI view so the logic is unit-testable
// without a render path.
//
// Why a model (not view-inline logic): the Gate-2 audit (rounds 1-2) flagged
// two hazards that live here — (1) the saved provider must be activated
// EXPLICITLY (AISettingsViewModel.addProfile only auto-activates the FIRST
// provider, so a second provider added in the "Change…" flow would otherwise
// not become the engine), and (2) activation/pop must run AFTER the editor
// sheet dismisses, never underneath it. Both are exercised by
// ReaderAIProvidersFlowTests.
//
// @coordinates-with: BilingualSetupSheetContainer.swift, ReaderAIProvidersView.swift,
//   AISettingsViewModel.swift, BilingualReadingViewModel.swift (refreshAIConfigured)

import Foundation
import Observation

/// Drives the in-reader AI Providers push + the post-configure return to the
/// bilingual sheet. `@MainActor` because it mutates SwiftUI-observed state and
/// calls the `@MainActor` `AISettingsViewModel`.
@MainActor
@Observable
final class ReaderAIProvidersFlow {

    /// The provider-list view model, shared with `ReaderAIProvidersView` /
    /// `AIProviderListView`. Defaults to the production singletons; tests
    /// inject an isolated one.
    let viewModel: AISettingsViewModel

    /// Drives the bilingual sheet's `NavigationStack` push. `false` = the
    /// bilingual setup root; `true` = the AI Providers list is pushed.
    var showingProviders: Bool = false

    /// Called when a provider becomes the active engine — the host wires this
    /// to `bilingualViewModel.refreshAIConfigured()` so the engine strip
    /// re-resolves truthfully. Async; awaited before the pop.
    private let onConfigured: () async -> Void

    init(
        viewModel: AISettingsViewModel = AISettingsViewModel(),
        onConfigured: @escaping () async -> Void
    ) {
        self.viewModel = viewModel
        self.onConfigured = onConfigured
    }

    /// "Set up" / "Change…" tapped — push the providers list.
    func openProviders() {
        showingProviders = true
    }

    /// The editor sheet added/edited a provider and has FULLY dismissed
    /// (re-emitted by `AIProviderListView.onDismiss`). Make the saved provider
    /// the active engine EXPLICITLY (works for non-first adds too — the
    /// Gate-2 Critical fix), refresh the strip, then pop to the bilingual
    /// root. Runs post-dismiss, so it never pops underneath the editor.
    func handleEditorSaveSuccess(id: UUID, wasAdd: Bool) async {
        await viewModel.setActive(id)
        // `setActive` silently rejects an id not in the current list (stale /
        // concurrent state). Only refresh + pop when activation actually took —
        // otherwise the engine didn't change, so stay on the list.
        guard viewModel.activeID == id else { return }
        await onConfigured()
        showingProviders = false
    }

    /// A row tap already ran `setActive` inside the list; refresh the strip
    /// and pop. Tapping the already-active row in the Change flow still pops
    /// (confirms the current engine).
    func handleRowActivated(id: UUID) async {
        await onConfigured()
        showingProviders = false
    }
}
