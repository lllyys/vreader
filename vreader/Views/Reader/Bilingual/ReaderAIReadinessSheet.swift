// Purpose: Feature #82 WI-2 / Bug #308 — the STANDALONE entry to the AI
// readiness flow, presented from the reader bottom-bar AI button when AI is
// unconfigured (instead of the old silent no-op). Unlike the bilingual entry
// (which pushes `ReaderAIReadinessView` inside the bilingual sheet's
// NavigationStack via `BilingualSetupSheetContainer`), this owns its OWN
// `@State` flow + `NavigationStack`, so it doesn't depend on the bilingual
// stack's push state.
//
// On the ready transition the flow fires `onConfigured` → `onReady`, which the
// host wires to "dismiss this sheet (+ open the AI panel)". Because the host's
// AI-availability gate now mirrors the active-provider per-profile key
// (`AIReaderAvailability` fix), the next AI-button tap opens the panel rather
// than looping back here.
//
// @coordinates-with: ReaderAIReadinessView.swift, ReaderAIProvidersFlow.swift,
//   ReaderContainerView.swift (onAI), AIReaderAvailability.swift

import SwiftUI

/// Standalone presentation of the readiness flow for the Bug #308 AI-button
/// entry. `onReady` fires once all four gates clear (dismiss + open the panel).
struct ReaderAIReadinessSheet: View {

    let theme: ReaderThemeV2
    @State private var flow: ReaderAIProvidersFlow

    init(theme: ReaderThemeV2, onReady: @escaping () -> Void) {
        self.theme = theme
        // The flow's `onConfigured` fires on the in-session not-ready→ready
        // transition (the user arrived here BECAUSE AI was unconfigured, so
        // `startedReady` is false — the transition pop is exactly "now ready").
        _flow = State(initialValue: ReaderAIProvidersFlow(onConfigured: { onReady() }))
    }

    var body: some View {
        NavigationStack {
            ReaderAIReadinessView(theme: theme, flow: flow)
        }
    }
}
