// Purpose: Feature #81 + #82 — the testable navigation/readiness core of the
// in-reader AI flow. Owns the push state for the bilingual sheet's
// NavigationStack and the "AI is now ready → refresh + pop" transitions,
// decoupled from the SwiftUI view so the logic is unit-testable without a
// render path.
//
// Feature #82 extends this from a provider-only flow into a READINESS model:
// it caches the four `BilingualAIReadiness` gates (AI flag · consent · active
// provider · per-profile key) via a generation-guarded async `recompute()`
// (so a stale async result can't overwrite a newer one), records the readiness
// at first appear (`startedReady`) so a configured user's "Change…" flow never
// auto-pops, and pops ONLY when readiness is actually true:
//  - an explicit provider selection (row tap / editor save) pops if ready
//    (covers the Change flow too);
//  - a gate toggle (AI / consent) pops only on an in-session not-ready→ready
//    transition (never on the initial-ready appear).
//
// Consent-safety invariant (Feature #82): this model NEVER calls
// `grantConsent()`. Consent is granted only by the consent card's own toggle
// (which binds `AISettingsViewModel.hasConsent`); `recompute()` only READS it.
//
// @coordinates-with: ReaderAIReadinessView.swift, BilingualSetupSheetContainer.swift,
//   AISettingsViewModel.swift, BilingualAIReadiness.swift, AIConsentManager.swift,
//   FeatureFlags.swift, ProviderProfileStore.swift, KeychainService+ProviderProfile.swift

import Foundation
import Observation

/// Drives the in-reader AI readiness push + the post-ready return to the
/// bilingual sheet. `@MainActor` because it mutates SwiftUI-observed state and
/// calls the `@MainActor` `AISettingsViewModel`.
@MainActor
@Observable
final class ReaderAIProvidersFlow {

    /// The provider-list view model, shared with `ReaderAIReadinessView` /
    /// `AIProviderListView`. Also the source of the AI-enable + consent
    /// toggles (`isAIEnabled` / `hasConsent`). Tests inject an isolated one.
    let viewModel: AISettingsViewModel

    /// Drives the bilingual sheet's `NavigationStack` push. `false` = the
    /// bilingual setup root; `true` = the readiness view is pushed.
    var showingProviders: Bool = false

    // MARK: - Feature #82 readiness gates (cached from `recompute()`)

    private(set) var aiEnabled: Bool = false
    private(set) var consentGranted: Bool = false
    private(set) var hasActiveProvider: Bool = false
    private(set) var hasKey: Bool = false

    /// All four `BilingualAIReadiness` gates satisfied — mirrors
    /// `BilingualAIReadiness.resolve`.
    var isReady: Bool { aiEnabled && consentGranted && hasActiveProvider && hasKey }

    /// Readiness recorded at the FIRST `recompute()` (the sheet's initial
    /// state). `true` = the user arrived already configured (the "Change…"
    /// flow) → a gate toggle must NOT auto-pop on appear. nil until first
    /// recompute.
    private(set) var startedReady: Bool?

    /// Monotonic guard so a slow async `recompute()` can't overwrite the
    /// result of a newer one (rapid toggles / revoke / edit dismissal).
    private var recomputeGeneration = 0

    /// Called when readiness becomes true — the host wires this to
    /// `bilingualViewModel.refreshAIConfigured()` so the engine strip
    /// re-resolves truthfully. Async; awaited before the pop.
    private let onConfigured: () async -> Void

    init(
        viewModel: AISettingsViewModel = AISettingsViewModel(),
        onConfigured: @escaping () async -> Void
    ) {
        self.viewModel = viewModel
        self.onConfigured = onConfigured
    }

    /// "Set up" / "Change…" tapped — push the readiness view. The initial
    /// readiness snapshot is taken by the view's `.task { await recompute() }`
    /// on appear (NOT a detached Task here — that would race the view's own
    /// recompute and leave `startedReady` indeterminate).
    func openProviders() {
        // Reset the session-readiness snapshot so each push re-evaluates
        // `startedReady` fresh (it must reflect THIS push's initial state, not
        // a prior push's). The view's `.task { recompute() }` commits it.
        startedReady = nil
        showingProviders = true
    }

    // MARK: - Readiness recompute (generation-guarded)

    /// Re-reads the four gates (AI flag, consent, active provider, per-profile
    /// key) and caches them. NEVER mutates consent. Discards its result if a
    /// newer recompute started meanwhile. Records `startedReady` on first run.
    func recompute() async {
        recomputeGeneration += 1
        let generation = recomputeGeneration

        let enabled = viewModel.featureFlags.isEnabled(.aiAssistant)
        let consent = viewModel.consentManager.hasConsent
        let active = await viewModel.profileStore.activeProfileSnapshot()
        let key: String?
        if let active {
            key = try? viewModel.keychainService.readAPIKey(forProfile: active.id)
        } else {
            key = nil
        }

        // Stale result — a newer recompute already (or will) win. Drop it.
        guard generation == recomputeGeneration else { return }

        aiEnabled = enabled
        consentGranted = consent
        hasActiveProvider = (active != nil)
        hasKey = (key?.isEmpty == false)
        if startedReady == nil { startedReady = isReady }
    }

    // MARK: - Pop intents

    /// A gate toggle (AI / consent) changed. Recompute; auto-pop ONLY on an
    /// in-session not-ready→ready transition (never when the user arrived
    /// already ready — the Change flow).
    func handleGateToggled() async {
        let wasStartedReady = startedReady
        await recompute()
        if isReady, wasStartedReady == false {
            await popReady()
        }
    }

    /// An editor add/edit FULLY dismissed (re-emitted by AIProviderListView's
    /// `.sheet(onDismiss:)`). Activate the saved provider explicitly (works
    /// for non-first adds), recompute, and pop ONLY if all four gates are now
    /// satisfied — a key-less / not-ready save stays on the view.
    func handleEditorSaveSuccess(id: UUID, wasAdd: Bool) async {
        await viewModel.setActive(id)
        guard viewModel.activeID == id else { return }
        await recompute()
        if isReady { await popReady() }
    }

    /// A provider row tap already ran `setActive`. Recompute + pop if ready —
    /// an explicit selection pops in the Change flow too (where the user is
    /// already ready and is picking a provider).
    func handleRowActivated(id: UUID) async {
        await recompute()
        if isReady { await popReady() }
    }

    /// Refresh the engine strip + pop to the bilingual root.
    private func popReady() async {
        await onConfigured()
        showingProviders = false
    }
}
