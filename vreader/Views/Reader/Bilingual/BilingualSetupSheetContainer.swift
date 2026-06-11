// Purpose: Feature #81 — the shared wrapper that all 6 bilingual hosts present
// instead of a bare `BilingualSetupSheet`. Wraps the setup sheet in a
// `NavigationStack` so the engine strip's "Set up" / "Change…" button pushes
// the scoped `ReaderAIReadinessView` (slide-left, `‹ Bilingual` back) instead
// of dismissing. On a provider becoming the active engine it refreshes the
// strip and pops back to the bilingual root.
//
// Key decisions:
// - **Root keeps its own `ReaderSheetChrome`.** The system nav bar is hidden on
//   the root (`.toolbar(.hidden, for: .navigationBar)`) so there's no double
//   chrome; only the pushed `ReaderAIReadinessView` shows the system nav bar.
// - **Navigation + activation live in `ReaderAIProvidersFlow`** (a `@State`
//   model) so the logic is unit-tested without a render path. The container is
//   thin wiring: present root → push on `onOpenSettings` → the flow handles
//   configure→refresh→pop.
// - **`onOpenSettings` is consumed internally** — hosts no longer pass it (the
//   old per-host "dismiss" stub is gone). Hosts pass the same `state` /
//   `engineDescriptor` / `onConfirm` / `onCancel` bindings as before, plus an
//   `onConfigured` that refreshes the host's `bilingualViewModel`.
//
// @coordinates-with: BilingualSetupSheet.swift, ReaderAIReadinessView.swift,
//   ReaderAIProvidersFlow.swift, ReaderSheetChrome.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-ai-provider-entry.md`

import SwiftUI

/// Navigation wrapper around `BilingualSetupSheet` that hosts the in-reader AI
/// Providers push.
struct BilingualSetupSheetContainer: View {

    let theme: ReaderThemeV2
    @Binding var state: BilingualSetupSheetState
    let engineDescriptor: BilingualEngineDescriptor
    let onConfirm: () -> Void
    let onCancel: () -> Void
    /// Bug #344 (design #1646): threads the per-format sentence-granularity
    /// capability into the sheet's dim-or-selectable control state.
    let sentenceGranularityAvailable: Bool

    /// Owns the AI-providers VM + the push/activation transitions. Built once
    /// from the `onConfigured` init param (which fires when a provider becomes
    /// the active engine — the host wires it to
    /// `bilingualViewModel?.refreshAIConfigured()` so the strip re-resolves
    /// truthfully on the return to the bilingual root).
    @State private var flow: ReaderAIProvidersFlow

    init(
        theme: ReaderThemeV2,
        state: Binding<BilingualSetupSheetState>,
        engineDescriptor: BilingualEngineDescriptor,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onConfigured: @escaping () async -> Void,
        sentenceGranularityAvailable: Bool = true
    ) {
        self.theme = theme
        self._state = state
        self.engineDescriptor = engineDescriptor
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.sentenceGranularityAvailable = sentenceGranularityAvailable
        _flow = State(initialValue: ReaderAIProvidersFlow(onConfigured: onConfigured))
    }

    var body: some View {
        @Bindable var flow = flow
        return NavigationStack {
            BilingualSetupSheet(
                theme: theme,
                state: $state,
                engineDescriptor: engineDescriptor,
                onConfirm: onConfirm,
                onCancel: onCancel,
                onOpenSettings: { flow.openProviders() },
                sentenceGranularityAvailable: sentenceGranularityAvailable
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $flow.showingProviders) {
                ReaderAIReadinessView(theme: theme, flow: flow)
            }
        }
    }
}
