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
        mockAI: Bool = false,
        mockAITranslateDelayMS: Int = 0,
        featureFlags: FeatureFlags,
        consentManager: AIConsentManager
    ) {
        // `--mock-ai` injects a deterministic, KEY-FREE provider (MockAIProvider)
        // so AI flows are CU-free verifiable without entering a real API key.
        // It implies availability (you can't drive AI with the gates closed) and
        // grants the same flag + consent `--enable-ai` does.
        // Feature #77 Gate-5b: `--mock-ai-translate-delay-ms=<N>` widens the
        // `sendRequest` in-flight window so the bilingual loading shimmer can be
        // snapshotted CU-free before the translation lands.
        AITestOverride.forceAvailable = enableAI || mockAI
        AITestOverride.mockProvider = mockAI
            ? MockAIProvider(requestDelayNanos: nanosForDelayMS(mockAITranslateDelayMS))
            : nil
        guard enableAI || mockAI else { return }
        featureFlags.setOverride(true, for: .aiAssistant)
        consentManager.grantConsent()
    }

    /// Convert a millisecond delay to nanoseconds without trapping on overflow
    /// (Codex Gate-4 Medium). Negative → 0; a value large enough to overflow the
    /// `* 1_000_000` is capped at a 60s ceiling — a verification harness never
    /// needs a longer in-flight hold, and a typo'd huge value won't crash DEBUG.
    static func nanosForDelayMS(_ ms: Int) -> UInt64 {
        let clampedMS = UInt64(max(0, min(ms, 60_000)))
        return clampedMS * 1_000_000
    }
}

#endif
