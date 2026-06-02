// Purpose: Feature #81 + #82 — pin the in-reader AI readiness flow model.
// Verifies the #82 readiness semantics: gates are recomputed (AI flag · consent
// · active provider · per-profile key); pop happens ONLY when all four are
// satisfied; the configured-user "Change…" flow (startedReady) never auto-pops
// on appear; a gate toggle pops only on an in-session not-ready→ready
// transition; and — the consent-safety invariant — the flow NEVER grants
// consent. Also keeps the #81 Critical (explicit setActive activates a
// non-first provider).
//
// @coordinates-with: vreader/Views/Reader/Bilingual/ReaderAIProvidersFlow.swift,
//   AISettingsViewModel.swift, BilingualAIReadiness.swift, ProviderProfileStore.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #81/#82 — ReaderAIProvidersFlow (readiness)")
@MainActor
struct ReaderAIProvidersFlowTests {

    private struct Deps {
        let vm: AISettingsViewModel
        let flags: FeatureFlags
        let consent: AIConsentManager
        let keychain: KeychainService
        let store: ProviderProfileStore
    }

    private static func makeDeps() -> Deps {
        let flags = FeatureFlags(environment: .prod)               // aiAssistant default OFF
        let consent = AIConsentManager(
            defaults: UserDefaults(suiteName: "com.vreader.test.consent.\(UUID().uuidString)")!
        )                                                          // consent default OFF
        let keychain = KeychainService(serviceIdentifier: "com.vreader.test.\(UUID().uuidString)")
        let store = ProviderProfileStore(
            preferences: MockPreferenceStore(),
            migrator: DefaultProviderProfileMigrator(),
            keychain: keychain
        )
        let vm = AISettingsViewModel(
            featureFlags: flags, consentManager: consent,
            keychainService: keychain, profileStore: store
        )
        return Deps(vm: vm, flags: flags, consent: consent, keychain: keychain, store: store)
    }

    private static func profile(_ name: String) -> ProviderProfile {
        let kind = ProviderKind.openAICompatible
        return ProviderProfile(id: UUID(), name: name, kind: kind,
                               baseURL: kind.defaultBaseURL, model: kind.defaultModel,
                               temperature: 0.7, maxTokens: 2048)
    }

    /// Drives all four gates true on `deps`.
    private static func makeReady(_ deps: Deps) async -> ProviderProfile {
        deps.flags.setOverride(true, for: .aiAssistant)
        deps.consent.grantConsent()
        let p = profile("Ready")
        await deps.vm.addProfile(p, apiKey: "sk-test")             // adds key + activates (first)
        await deps.vm.loadProfiles()
        return p
    }

    // MARK: - recompute captures the four gates

    @Test func recompute_capturesAllFourGates_whenReady() async {
        let deps = Self.makeDeps()
        _ = await Self.makeReady(deps)
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: {})
        await flow.recompute()
        #expect(flow.aiEnabled)
        #expect(flow.consentGranted)
        #expect(flow.hasActiveProvider)
        #expect(flow.hasKey)
        #expect(flow.isReady)
    }

    @Test func recompute_notReady_whenGatesMissing() async {
        let deps = Self.makeDeps()                                  // nothing satisfied
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: {})
        await flow.recompute()
        #expect(flow.isReady == false)
        #expect(flow.aiEnabled == false)
    }

    @Test func openProviders_pushes() async {
        let flow = ReaderAIProvidersFlow(viewModel: Self.makeDeps().vm, onConfigured: {})
        #expect(flow.showingProviders == false)
        flow.openProviders()
        #expect(flow.showingProviders == true)
    }

    // MARK: - Consent-safety invariant: the flow NEVER grants consent

    @Test func flowNeverGrantsConsent() async {
        let deps = Self.makeDeps()
        deps.flags.setOverride(true, for: .aiAssistant)
        let p = Self.profile("P")
        await deps.vm.addProfile(p, apiKey: "sk")                   // provider + key, consent still OFF
        await deps.vm.loadProfiles()
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: {})

        await flow.recompute()
        await flow.handleGateToggled()
        await flow.handleEditorSaveSuccess(id: p.id, wasAdd: true)
        await flow.handleRowActivated(id: p.id)

        #expect(deps.consent.hasConsent == false, "the readiness flow must NEVER grant consent — only the consent toggle does")
        #expect(flow.isReady == false, "without consent, the flow is not ready")
    }

    // MARK: - Change flow (startedReady) does NOT auto-pop on appear

    @Test func changeFlow_startedReady_doesNotAutoPop() async {
        let deps = Self.makeDeps()
        _ = await Self.makeReady(deps)
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: {})
        flow.openProviders()
        await flow.recompute()                                      // initial-ready snapshot
        #expect(flow.startedReady == true)
        await flow.handleGateToggled()                             // a no-op toggle while already ready
        #expect(flow.showingProviders == true, "a configured user must not be auto-popped on appear / no-op toggle")
    }

    // MARK: - Set-up flow: a gate toggle that COMPLETES readiness pops

    @Test func setupFlow_gateToggleTransitionToReady_pops() async {
        let deps = Self.makeDeps()
        // Pre-satisfy provider + key + consent; leave the AI flag OFF.
        deps.consent.grantConsent()
        let p = Self.profile("P")
        await deps.vm.addProfile(p, apiKey: "sk")
        await deps.vm.loadProfiles()
        var refreshed = 0
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: { refreshed += 1 })
        flow.openProviders()
        await flow.recompute()
        #expect(flow.startedReady == false)
        #expect(flow.isReady == false)

        // The user flips the last gate (AI flag) → readiness transitions true.
        deps.flags.setOverride(true, for: .aiAssistant)
        await flow.handleGateToggled()

        #expect(flow.isReady == true)
        #expect(refreshed == 1, "completing readiness in-session refreshes the strip")
        #expect(flow.showingProviders == false, "completing the last gate pops back to Bilingual")
    }

    // MARK: - Editor save pops only when ready

    @Test func editorSave_popsOnlyWhenReady() async {
        let deps = Self.makeDeps()
        deps.flags.setOverride(true, for: .aiAssistant)
        deps.consent.grantConsent()
        var refreshed = 0
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: { refreshed += 1 })
        flow.openProviders(); await flow.recompute()

        // Save a provider WITH a key → all four gates clear → pop.
        let p = Self.profile("Saved")
        await deps.vm.addProfile(p, apiKey: "sk")
        await flow.handleEditorSaveSuccess(id: p.id, wasAdd: true)
        #expect(flow.isReady == true)
        #expect(refreshed == 1)
        #expect(flow.showingProviders == false)
    }

    @Test func editorSave_keyless_doesNotPop() async {
        let deps = Self.makeDeps()
        deps.flags.setOverride(true, for: .aiAssistant)
        deps.consent.grantConsent()
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: {})
        flow.openProviders(); await flow.recompute()

        // Save a provider with NO key → not ready → stay on the view.
        let p = Self.profile("NoKey")
        await deps.vm.addProfile(p, apiKey: "")
        await flow.handleEditorSaveSuccess(id: p.id, wasAdd: true)
        #expect(flow.hasKey == false)
        #expect(flow.isReady == false)
        #expect(flow.showingProviders == true, "a key-less provider is not ready — stay on the readiness view")
    }

    // MARK: - #81 Critical preserved: non-first add is activated explicitly

    @Test func editorSave_activatesNonFirstProvider() async {
        let deps = Self.makeDeps()
        deps.flags.setOverride(true, for: .aiAssistant)
        deps.consent.grantConsent()
        let a = Self.profile("A"); let b = Self.profile("B")
        await deps.vm.addProfile(a, apiKey: "ka")                  // A active (first)
        await deps.vm.addProfile(b, apiKey: "kb")                  // B not auto-active
        await deps.vm.loadProfiles()
        #expect(deps.vm.activeID == a.id)
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: {})
        flow.openProviders(); await flow.recompute()

        await flow.handleEditorSaveSuccess(id: b.id, wasAdd: false)
        #expect(deps.vm.activeID == b.id, "the flow must explicitly activate the just-saved non-first provider")
        #expect(flow.isReady == true)
        #expect(flow.showingProviders == false)
    }

    // MARK: - Row activation pops only when ready (Change flow)

    @Test func rowActivated_changeFlow_pops() async {
        let deps = Self.makeDeps()
        _ = await Self.makeReady(deps)                             // already ready (Change flow)
        let p2 = Self.profile("Other")
        await deps.vm.addProfile(p2, apiKey: "k2")                 // a second ready provider
        await deps.vm.loadProfiles()
        var refreshed = 0
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: { refreshed += 1 })
        flow.openProviders(); await flow.recompute()
        #expect(flow.startedReady == true)

        await deps.vm.setActive(p2.id)
        await flow.handleRowActivated(id: p2.id)
        #expect(refreshed == 1)
        #expect(flow.showingProviders == false, "an explicit row pick pops in the Change flow too")
    }

    // MARK: - startedReady resets per push (Gate-4 fix)

    @Test func openProviders_resetsStartedReadyPerPush() async {
        let deps = Self.makeDeps()
        _ = await Self.makeReady(deps)
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: {})
        flow.openProviders(); await flow.recompute()
        #expect(flow.startedReady == true)

        // A second push (dismiss → reopen) must re-snapshot, not carry over.
        flow.openProviders()
        #expect(flow.startedReady == nil, "each push resets the session-readiness snapshot")
        await flow.recompute()
        #expect(flow.startedReady == true)
    }

    // MARK: - Generation guard: concurrent recompute converges, no crash

    @Test func concurrentRecompute_convergesToLatestState() async {
        let deps = Self.makeDeps()
        _ = await Self.makeReady(deps)
        let flow = ReaderAIProvidersFlow(viewModel: deps.vm, onConfigured: {})
        async let a: Void = flow.recompute()
        async let b: Void = flow.recompute()
        _ = await (a, b)
        #expect(flow.isReady == true, "concurrent recomputes converge to the current (ready) state")
    }
}
