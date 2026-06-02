// Purpose: Feature #81 — pin the in-reader AI Providers flow model. Verifies
// the two Gate-2 hazards are handled: (1) the editor-save path activates the
// saved provider EXPLICITLY (works for a non-first add, which
// AISettingsViewModel.addProfile would NOT auto-activate), and (2) every
// configure path refreshes the strip (onConfigured) and pops to root.
//
// @coordinates-with: vreader/Views/Reader/Bilingual/ReaderAIProvidersFlow.swift,
//   AISettingsViewModel.swift, ProviderProfileStore.swift

import Testing
import Foundation
@testable import vreader

@Suite("Feature #81 — ReaderAIProvidersFlow")
@MainActor
struct ReaderAIProvidersFlowTests {

    private static func makeIsolatedVM() -> AISettingsViewModel {
        AISettingsViewModel(
            featureFlags: FeatureFlags(environment: .prod),
            consentManager: AIConsentManager(
                defaults: UserDefaults(suiteName: "com.vreader.test.consent.\(UUID().uuidString)")!
            ),
            keychainService: KeychainService(serviceIdentifier: "com.vreader.test.\(UUID().uuidString)"),
            profileStore: ProviderProfileStore(
                preferences: MockPreferenceStore(),
                migrator: DefaultProviderProfileMigrator(),
                keychain: KeychainService(serviceIdentifier: "com.vreader.test.kc.\(UUID().uuidString)")
            )
        )
    }

    private static func profile(_ name: String) -> ProviderProfile {
        let kind = ProviderKind.openAICompatible
        return ProviderProfile(id: UUID(), name: name, kind: kind,
                               baseURL: kind.defaultBaseURL, model: kind.defaultModel,
                               temperature: 0.7, maxTokens: 2048)
    }

    @Test func openProviders_pushesTheList() {
        let flow = ReaderAIProvidersFlow(viewModel: Self.makeIsolatedVM(), onConfigured: {})
        #expect(flow.showingProviders == false)
        flow.openProviders()
        #expect(flow.showingProviders == true)
    }

    @Test func editorSaveSuccess_activatesSavedProvider_refreshes_andPops() async {
        let vm = Self.makeIsolatedVM()
        let p = Self.profile("First")
        await vm.addProfile(p, apiKey: "k")          // first → auto-active
        await vm.loadProfiles()

        var refreshed = 0
        let flow = ReaderAIProvidersFlow(viewModel: vm, onConfigured: { refreshed += 1 })
        flow.openProviders()

        await flow.handleEditorSaveSuccess(id: p.id, wasAdd: true)

        #expect(vm.activeID == p.id)
        #expect(refreshed == 1, "the engine strip must be refreshed on configure")
        #expect(flow.showingProviders == false, "must pop back to the bilingual root")
    }

    /// The Gate-2 Critical: a SECOND provider added during the Change flow is
    /// NOT auto-activated by addProfile (an active one already exists), so the
    /// reader flow's EXPLICIT setActive is what makes it the engine.
    @Test func editorSaveSuccess_activatesNonFirstProvider_theCriticalFix() async {
        let vm = Self.makeIsolatedVM()
        let a = Self.profile("A")
        let b = Self.profile("B")
        await vm.addProfile(a, apiKey: "ka")          // A becomes active (first)
        await vm.addProfile(b, apiKey: "kb")          // B added, NOT auto-active
        await vm.loadProfiles()
        #expect(vm.activeID == a.id, "precondition: addProfile auto-activates only the first")

        let flow = ReaderAIProvidersFlow(viewModel: vm, onConfigured: {})
        await flow.handleEditorSaveSuccess(id: b.id, wasAdd: true)

        #expect(vm.activeID == b.id, "the reader flow must explicitly activate the just-saved non-first provider")
        #expect(flow.showingProviders == false)
    }

    /// Gate-4 Low fix: if `setActive` rejects the id (stale / not in the list),
    /// the flow must NOT refresh or pop — the engine didn't change.
    @Test func editorSaveSuccess_rejectedActivation_doesNotRefreshOrPop() async {
        let vm = Self.makeIsolatedVM()   // empty store — no profiles
        var refreshed = 0
        let flow = ReaderAIProvidersFlow(viewModel: vm, onConfigured: { refreshed += 1 })
        flow.openProviders()

        await flow.handleEditorSaveSuccess(id: UUID(), wasAdd: true)

        #expect(vm.activeID == nil)
        #expect(refreshed == 0, "no strip refresh when activation didn't take")
        #expect(flow.showingProviders == true, "stay on the list when activation didn't take")
    }

    @Test func rowActivated_refreshes_andPops_withoutNeedingReactivation() async {
        let vm = Self.makeIsolatedVM()
        let p = Self.profile("Row")
        await vm.addProfile(p, apiKey: "k")
        await vm.loadProfiles()

        var refreshed = 0
        let flow = ReaderAIProvidersFlow(viewModel: vm, onConfigured: { refreshed += 1 })
        flow.openProviders()

        await flow.handleRowActivated(id: p.id)

        #expect(refreshed == 1)
        #expect(flow.showingProviders == false)
    }
}
