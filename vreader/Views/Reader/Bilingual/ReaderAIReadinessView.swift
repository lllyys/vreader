// Purpose: Feature #82 — the in-reader AI readiness container, pushed inside
// the bilingual sheet's NavigationStack from the engine strip's "Set up" /
// "Change…" (and, via Bug #308, from the bottom-bar AI button through
// `ReaderAIReadinessSheet`). Makes the full `BilingualAIReadiness` gate
// satisfiable in one scoped surface: a 3-step tracker, the `aiAssistant` master
// toggle, an explicit consent disclosure card (shown only when AI on), the
// inline provider block, and a "ready" payoff.
//
// Supersedes the #81 `ReaderAIProvidersView` (which was the provider list only)
// — the bilingual container now pushes THIS. Toggles bind to
// `AISettingsViewModel.isAIEnabled` / `.hasConsent`; gate changes drive the
// flow's generation-guarded recompute. Consent is granted ONLY by the consent
// card's own toggle (the readiness flow never grants it).
//
// Layout pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-readiness.jsx`
// (`ReadinessSheetBody`).
//
// @coordinates-with: ReaderAIProvidersFlow.swift, ReadinessTracker.swift,
//   ReadinessRows.swift, ReadinessProviderBlock.swift, BilingualSetupSheetContainer.swift,
//   AISettingsViewModel.swift, SettingsToggleRow.swift, ReaderThemeV2.swift

import SwiftUI

/// The readiness sheet body. Drives the 4-gate flow to "ready" + pop.
struct ReaderAIReadinessView: View {

    let theme: ReaderThemeV2
    let flow: ReaderAIProvidersFlow

    static let accessibilityIdentifier = "readerAIReadinessView"

    /// Design `RDY_BRAND` — the AI-assistant tile.
    private var brand: Color { Color(red: 0.549, green: 0.184, blue: 0.184) }

    private var activeProviderName: String {
        flow.viewModel.profiles.first(where: { $0.id == flow.viewModel.activeID })?.name ?? "Your provider"
    }

    var body: some View {
        @Bindable var vm = flow.viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ReadinessTracker(
                    theme: theme,
                    aiOn: flow.aiEnabled,
                    consentOn: flow.consentGranted,
                    providerReady: flow.hasActiveProvider && flow.hasKey
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

                stepLabel("1 · Assistant")
                SettingsToggleRow(
                    theme: theme,
                    icon: Image(systemName: "sparkles"),
                    iconBackground: brand,
                    title: "Turn on AI assistant",
                    detail: "Off everywhere by default. Turn it on to grant consent and connect a provider.",
                    isOn: $vm.isAIEnabled,
                    toggleAccessibilityIdentifier: "readinessAIToggle"
                )
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Color(theme.sheetCardSurfaceColor))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(theme.ruleColor), lineWidth: 0.5))
                )

                if vm.isAIEnabled {
                    stepLabel("2 · Data sharing")
                    // `hasConsent` is a computed UserDefaults pass-through, NOT
                    // observed storage — `.onChange(of: vm.hasConsent)` would not
                    // reliably fire. Use an explicit binding whose setter writes
                    // consent AND drives the recompute, so toggling consent (which
                    // may be the LAST gate) always re-evaluates readiness + pop.
                    ConsentDisclosureCard(theme: theme, consentOn: Binding(
                        get: { vm.hasConsent },
                        set: { newValue in
                            vm.hasConsent = newValue
                            Task { await flow.handleGateToggled() }
                        }
                    ))

                    stepLabel("3 · Provider")
                    ReadinessProviderBlock(
                        theme: theme,
                        viewModel: vm,
                        locked: !vm.isAIEnabled,
                        onRowActivated: { id in Task { await flow.handleRowActivated(id: id) } },
                        onEditorSaveSuccess: { id, wasAdd in Task { await flow.handleEditorSaveSuccess(id: id, wasAdd: wasAdd) } }
                    )
                }

                if flow.isReady {
                    ReadyBanner(theme: theme, providerName: activeProviderName)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Color(theme.sheetSurfaceColor).ignoresSafeArea())
        .navigationTitle("Set up translation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
        .task {
            // Commit the initial readiness snapshot (`startedReady`) FIRST —
            // `recompute()` reads the provider store directly, so it doesn't
            // need the list. Doing it before `loadProfiles()` closes the race
            // where a gate toggle during the (async) load would record the
            // post-toggle state as the initial one and skip the ready pop.
            await flow.recompute()
            // Then populate the inline provider rows (the deleted
            // AIProviderListView used to do this on its own `.task`).
            await flow.viewModel.loadProfiles()
        }
        // `isAIEnabled` IS observed stored state (didSet → setOverride), so
        // .onChange fires reliably. Consent uses the explicit binding above.
        .onChange(of: vm.isAIEnabled) { _, _ in Task { await flow.handleGateToggled() } }
    }

    private func stepLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(theme.subColor))
            .tracking(0.5)
            .padding(.top, 4)
    }
}
