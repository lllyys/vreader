// Purpose: DEBUG-only setup that makes the `--enable-ai` XCUITest / DebugBridge
// launch flag enable the FULL AI request path — not just UI availability.
//
// Bug #237 forwarded `--enable-ai` to `AITestOverride.forceAvailable`, which
// short-circuits `AIReaderAvailability.isAvailable` (the UI gate). But the live
// request path `AIService.sendRequest` / `streamRequest` gates SEPARATELY and
// DIRECTLY on `featureFlags.aiAssistant` AND `consentManager.hasConsent` — those
// are NOT routed through `AIReaderAvailability`. So forcing availability alone
// left every live AI request (bilingual translate, summarize, chat) throwing
// `featureDisabled` / `consentRequired`, which the bilingual prefetcher swallows
// silently — so CU-free AI verification saw the UI light up but no content ever
// rendered. This setup also sets the two real gates so `--enable-ai` exercises
// the whole request path end-to-end.
//
// @coordinates-with: VReaderApp.swift (TestLaunchConfig handling),
//   AIService.swift (the gates), AIReaderAvailability.swift (AITestOverride),
//   FeatureFlags.swift, AIConsentManager.swift

#if DEBUG

import Foundation

@MainActor
enum AITestSetup {
    /// Apply the `--enable-ai` launch flag to ALL three AI gates so a CU-free /
    /// XCUITest run exercises the live AI request path:
    /// 1. `AITestOverride.forceAvailable` — the `AIReaderAvailability` UI gate.
    /// 2. `featureFlags.aiAssistant` — checked directly by `AIService.sendRequest`.
    /// 3. `consentManager.hasConsent` — checked directly by `AIService.sendRequest`.
    ///
    /// Availability is written unconditionally (both branches) so a prior launch's
    /// value in the same process doesn't leak. The flag + consent are only GRANTED
    /// when enabling — never revoked here, so a verification run that intentionally
    /// configured them stays configured.
    static func apply(
        enableAI: Bool,
        featureFlags: FeatureFlags,
        consentManager: AIConsentManager
    ) {
        AITestOverride.forceAvailable = enableAI
        guard enableAI else { return }
        featureFlags.setOverride(true, for: .aiAssistant)
        consentManager.grantConsent()
    }
}

#endif
