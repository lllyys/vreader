// Purpose: Feature #82 / Bug #308 — pin that AI reader availability mirrors the
// ACTIVE PROVIDER's per-profile key, not only the legacy single-key account.
// Before the fix, a user who configured a provider through the multi-profile
// path (the in-reader readiness flow / Library AI settings) had no legacy key,
// so the AI button stayed a silent no-op and looped back to readiness forever.
//
// @coordinates-with: vreader/Services/AI/AIReaderAvailability.swift,
//   ProviderProfileMigrator.swift, KeychainService+ProviderProfile.swift

import Testing
import Foundation
@testable import vreader

@Suite("AIReaderAvailability — active-provider per-profile key (Feature #82 / Bug #308)")
@MainActor
struct AIReaderAvailabilityPerProfileTests {

    private func keychain() -> KeychainService {
        KeychainService(serviceIdentifier: "com.vreader.test.\(UUID().uuidString)")
    }
    private func flags(ai: Bool) -> FeatureFlags {
        let f = FeatureFlags(environment: .prod); f.setOverride(ai, for: .aiAssistant); return f
    }
    private func consent(_ granted: Bool) -> AIConsentManager {
        let c = AIConsentManager(defaults: UserDefaults(suiteName: "com.vreader.test.consent.\(UUID().uuidString)")!)
        if granted { c.grantConsent() }
        return c
    }
    private func profile(_ id: UUID) -> ProviderProfile {
        let kind = ProviderKind.openAICompatible
        return ProviderProfile(id: id, name: "P", kind: kind, baseURL: kind.defaultBaseURL,
                               model: kind.defaultModel, temperature: 0.7, maxTokens: 2048)
    }

    private func resetOverride() {
        #if DEBUG
        AITestOverride.forceAvailable = false
        #endif
    }

    // MARK: - The Bug #308 regression: per-profile key, NO legacy key

    @Test func available_withActiveProviderPerProfileKey_noLegacyKey() throws {
        resetOverride()
        let kc = keychain()
        let prefs = MockPreferenceStore()
        let id = UUID()
        DefaultProviderProfileMigrator.writeProfiles([profile(id)], activeID: id, preferences: prefs)
        try kc.saveAPIKey("sk-perprofile", forProfile: id)   // per-profile key, NO legacy key

        let result = AIReaderAvailability.isAvailable(
            featureFlags: flags(ai: true), keychainService: kc,
            consentManager: consent(true), providerPreferences: prefs)
        #expect(result == true, "an active provider with a per-profile key must make AI available even without a legacy key")
    }

    // MARK: - Gating still applies

    @Test func unavailable_whenFlagOff() throws {
        resetOverride()
        let kc = keychain(); let prefs = MockPreferenceStore(); let id = UUID()
        DefaultProviderProfileMigrator.writeProfiles([profile(id)], activeID: id, preferences: prefs)
        try kc.saveAPIKey("sk", forProfile: id)
        #expect(AIReaderAvailability.isAvailable(
            featureFlags: flags(ai: false), keychainService: kc,
            consentManager: consent(true), providerPreferences: prefs) == false)
    }

    @Test func unavailable_whenNoConsent() throws {
        resetOverride()
        let kc = keychain(); let prefs = MockPreferenceStore(); let id = UUID()
        DefaultProviderProfileMigrator.writeProfiles([profile(id)], activeID: id, preferences: prefs)
        try kc.saveAPIKey("sk", forProfile: id)
        #expect(AIReaderAvailability.isAvailable(
            featureFlags: flags(ai: true), keychainService: kc,
            consentManager: consent(false), providerPreferences: prefs) == false)
    }

    @Test func unavailable_whenActiveProviderHasNoKey() {
        resetOverride()
        let kc = keychain(); let prefs = MockPreferenceStore(); let id = UUID()
        DefaultProviderProfileMigrator.writeProfiles([profile(id)], activeID: id, preferences: prefs)
        // no key saved for the active provider, no legacy key
        #expect(AIReaderAvailability.isAvailable(
            featureFlags: flags(ai: true), keychainService: kc,
            consentManager: consent(true), providerPreferences: prefs) == false)
    }

    @Test func unavailable_whenNoProviderAndNoLegacyKey() {
        resetOverride()
        #expect(AIReaderAvailability.isAvailable(
            featureFlags: flags(ai: true), keychainService: keychain(),
            consentManager: consent(true), providerPreferences: MockPreferenceStore()) == false)
    }

    // MARK: - Legacy single-key install still works (fallback)

    @Test func available_withLegacyKey_noProfiles() throws {
        resetOverride()
        let kc = keychain()
        try kc.saveString("sk-legacy", forAccount: AIService.apiKeyAccount)
        #expect(AIReaderAvailability.isAvailable(
            featureFlags: flags(ai: true), keychainService: kc,
            consentManager: consent(true), providerPreferences: MockPreferenceStore()) == true)
    }

    // MARK: - Active provider takes precedence over a stale legacy key (Gate-4 fix)

    @Test func unavailable_legacyKeyButActiveProviderHasNoKey() throws {
        resetOverride()
        let kc = keychain()
        let prefs = MockPreferenceStore()
        let id = UUID()
        DefaultProviderProfileMigrator.writeProfiles([profile(id)], activeID: id, preferences: prefs)
        // A stale legacy key exists, but the ACTIVE profile has none. The live
        // request path uses the active profile → would throw apiKeyMissing, so
        // the gate must NOT be masked into "available" by the legacy key.
        try kc.saveString("sk-legacy", forAccount: AIService.apiKeyAccount)
        #expect(AIReaderAvailability.isAvailable(
            featureFlags: flags(ai: true), keychainService: kc,
            consentManager: consent(true), providerPreferences: prefs) == false,
            "an active profile with no key is unavailable even if a stale legacy key exists")
    }
}
