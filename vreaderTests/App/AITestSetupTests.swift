// Tests for AITestSetup (Bug #237 follow-up): `--enable-ai` must enable the FULL
// AI request path, not just UI availability. `AIService.sendRequest` gates on
// `featureFlags.aiAssistant` AND `consentManager.hasConsent` DIRECTLY (not via
// `AIReaderAvailability`), so forcing availability alone left live AI requests
// (bilingual translate, summarize, chat) throwing featureDisabled/consentRequired
// in CU-free verification. This pins that `--enable-ai` sets all three gates.

#if DEBUG
import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("AITestSetup — --enable-ai enables the full AI request path")
struct AITestSetupTests {

    private func freshDefaults() -> UserDefaults {
        let suite = "AITestSetupTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("enableAI=true sets availability + aiAssistant flag + consent")
    func enableTrueSetsAllThreeGates() {
        // The override is a global @MainActor static — reset it so this test
        // can't contaminate later AIReaderAvailability tests.
        defer { AITestOverride.forceAvailable = false }
        AITestOverride.forceAvailable = false
        let defaults = freshDefaults()
        let flags = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        let consent = AIConsentManager(defaults: defaults)
        #expect(consent.hasConsent == false)   // precondition
        #expect(flags.aiAssistant == false)

        AITestSetup.apply(enableAI: true, featureFlags: flags, consentManager: consent)

        #expect(AITestOverride.forceAvailable == true)
        #expect(flags.aiAssistant == true, "aiAssistant flag must be set so AIService doesn't throw featureDisabled")
        #expect(consent.hasConsent == true, "consent must be granted so AIService doesn't throw consentRequired")
    }

    @Test("enableAI=false clears the availability override (no leak)")
    func enableFalseClearsAvailability() {
        defer { AITestOverride.forceAvailable = false }
        let defaults = freshDefaults()
        let flags = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        let consent = AIConsentManager(defaults: defaults)
        AITestSetup.apply(enableAI: true, featureFlags: flags, consentManager: consent)
        #expect(AITestOverride.forceAvailable == true)

        AITestSetup.apply(enableAI: false, featureFlags: flags, consentManager: consent)
        #expect(AITestOverride.forceAvailable == false, "a later launch without --enable-ai must not inherit availability")
    }

    @Test("enableAI=false does NOT grant the aiAssistant flag or consent (cold start)")
    func enableFalseGrantsNothing() {
        defer { AITestOverride.forceAvailable = false }
        AITestOverride.forceAvailable = false
        let defaults = freshDefaults()
        let flags = FeatureFlags(environment: .prod, persistenceDefaults: defaults)
        let consent = AIConsentManager(defaults: defaults)

        AITestSetup.apply(enableAI: false, featureFlags: flags, consentManager: consent)

        #expect(AITestOverride.forceAvailable == false)
        #expect(flags.aiAssistant == false, "no --enable-ai → the real aiAssistant flag stays off")
        #expect(consent.hasConsent == false, "no --enable-ai → consent is not auto-granted")
    }
}
#endif
