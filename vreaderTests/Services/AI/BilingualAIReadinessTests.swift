// Bug #301: BilingualAIReadiness mirrors the EXACT gate the bilingual pipeline
// enforces — aiAssistant + consent + an ACTIVE provider profile + that profile's
// PER-PROFILE key. (The prior fix wrongly reused AIReaderAvailability, which
// checks the LEGACY keychain key + the wrong surface.) These tests pin the gate,
// especially the cases the legacy gate got wrong: an active profile with no key,
// and no active profile at all.

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("BilingualAIReadiness — the real bilingual gate (Bug #301)")
struct BilingualAIReadinessTests {

    private func makeStore() -> (ProviderProfileStore, KeychainService) {
        let prefs = MockPreferenceStore()
        let keychain = KeychainService(serviceIdentifier: "com.vreader.test.\(UUID().uuidString)")
        prefs.set("true", forKey: DefaultProviderProfileMigrator.migrationFlagKey)
        let store = ProviderProfileStore(
            preferences: prefs, migrator: DefaultProviderProfileMigrator(), keychain: keychain)
        return (store, keychain)
    }

    private func flags(ai: Bool) -> FeatureFlags {
        let f = FeatureFlags(environment: .prod)
        if ai { f.setOverride(true, for: .aiAssistant) }
        return f
    }

    private func consent(_ granted: Bool) -> AIConsentManager {
        let c = AIConsentManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        if granted { c.grantConsent() }
        return c
    }

    private func profile() -> ProviderProfile {
        ProviderProfile(id: UUID(), name: "T", kind: .openAICompatible,
                        baseURL: URL(string: "https://api.test.example.com/v1")!,
                        model: "m", temperature: 0.5, maxTokens: 1024)
    }

    @Test("false when aiAssistant is off")
    func aiOff() async {
        let (store, kc) = makeStore()
        let r = await BilingualAIReadiness.resolve(
            featureFlags: flags(ai: false), consentManager: consent(true),
            profileStore: store, keychainService: kc)
        #expect(r == false)
    }

    @Test("false when consent is not granted")
    func noConsent() async {
        let (store, kc) = makeStore()
        let r = await BilingualAIReadiness.resolve(
            featureFlags: flags(ai: true), consentManager: consent(false),
            profileStore: store, keychainService: kc)
        #expect(r == false)
    }

    @Test("false when there is NO active provider profile (the real gate, not the legacy key)")
    func noActiveProfile() async {
        let (store, kc) = makeStore()  // empty
        let r = await BilingualAIReadiness.resolve(
            featureFlags: flags(ai: true), consentManager: consent(true),
            profileStore: store, keychainService: kc)
        #expect(r == false)
    }

    @Test("false when the active profile has NO per-profile key")
    func profileButNoKey() async {
        let (store, kc) = makeStore()
        let p = profile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)  // active, but no key saved
        let r = await BilingualAIReadiness.resolve(
            featureFlags: flags(ai: true), consentManager: consent(true),
            profileStore: store, keychainService: kc)
        #expect(r == false)
    }

    @Test("true when aiAssistant + consent + active profile + per-profile key all present")
    func fullyConfigured() async throws {
        let (store, kc) = makeStore()
        let p = profile()
        try kc.saveAPIKey("sk-test", forProfile: p.id)
        await store.upsert(p)
        await store.setActiveProfileID(p.id)
        let r = await BilingualAIReadiness.resolve(
            featureFlags: flags(ai: true), consentManager: consent(true),
            profileStore: store, keychainService: kc)
        #expect(r == true)
    }

    // The defining regression vs the prior wrong fix (which reused
    // `AIReaderAvailability` → it reads the LEGACY `AIService.apiKeyAccount`
    // key directly): the new probe goes through the ACTIVE profile + per-profile
    // key, exactly like the live `AIService.resolveProviderConfig` path.

    // A pre-profile-model user has ONLY a legacy `apiKeyAccount` key. Reading the
    // store triggers `ensureMigrated`, which lifts that key into a new ACTIVE
    // provider profile (with its own per-profile key) — the same migration the
    // real pipeline runs. So the probe correctly reports configured=true. This
    // pins that the probe integrates with migration rather than ignoring legacy
    // users (and is NOT a naive "legacy key present" check like the old gate).
    @Test("true when a legacy apiKeyAccount key is migrated into an active profile on read")
    func legacyKeyMigratesToActiveProfile() async throws {
        let (store, kc) = makeStore()
        try kc.saveString("sk-legacy", forAccount: AIService.apiKeyAccount)
        let r = await BilingualAIReadiness.resolve(
            featureFlags: flags(ai: true), consentManager: consent(true),
            profileStore: store, keychainService: kc)
        #expect(r == true)
    }

    // The clean old-gate-vs-new-probe differentiator: an active profile with NO
    // per-profile key of its own, while a legacy key sits in `apiKeyAccount`.
    // The OLD gate (`hasAPIKey` reads `apiKeyAccount`) would return TRUE; the new
    // probe reads the ACTIVE profile's per-profile key (nil) → FALSE.
    @Test("false when a LEGACY key exists + an active profile WITHOUT its own per-profile key")
    func legacyKeyButActiveProfileMissingPerProfileKey() async throws {
        let (store, kc) = makeStore()
        try kc.saveString("sk-legacy", forAccount: AIService.apiKeyAccount)
        let p = profile()
        await store.upsert(p)
        await store.setActiveProfileID(p.id)  // active, but no per-profile key
        let r = await BilingualAIReadiness.resolve(
            featureFlags: flags(ai: true), consentManager: consent(true),
            profileStore: store, keychainService: kc)
        #expect(r == false)
    }

    @Test("false when the active profile's per-profile key is the empty string")
    func emptyPerProfileKey() async throws {
        let (store, kc) = makeStore()
        let p = profile()
        // Empty key — whether the keychain stores it or rejects it, no usable
        // key results, so readiness must be false either way.
        try? kc.saveAPIKey("", forProfile: p.id)
        await store.upsert(p)
        await store.setActiveProfileID(p.id)
        let r = await BilingualAIReadiness.resolve(
            featureFlags: flags(ai: true), consentManager: consent(true),
            profileStore: store, keychainService: kc)
        #expect(r == false)
    }
}
