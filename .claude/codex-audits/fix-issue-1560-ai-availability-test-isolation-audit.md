---
branch: fix/issue-1560-ai-availability-test-isolation
threadId: 019e9c3c-8fca-7d22-86a0-396b752eb41f
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Codex audit — Bug #326 (GH #1560): AI-availability unit-test isolation fix

Independent Codex audit (gpt-5.4, read-only) via `scripts/run-codex.sh`. `RUN-CODEX RESULT: SUCCEEDED`.

## Scope (test-only)
- `vreaderTests/ViewModels/AIChatGeneralTests.swift`
- `vreaderTests/ViewModels/AIReaderIntegrationTests.swift`

Inject an isolated empty `MockPreferenceStore()` as `providerPreferences:` into every
`AIReaderAvailability.isAvailable(...)` / `hasAPIKey(...)` call so `readActiveID` is nil
and the legacy-key gate (what these tests verify) runs deterministically — immune to
process-global `UserDefaults.standard` pollution (the order-dependent failure of
`generalChatAccessibleFromLibrary`). No production change.

## Findings

**No findings.** Codex verified:
- (a) The empty store forces the legacy-key branch for ALL affected assertions incl. the
  false cases (flag-off short-circuits before key lookup; no-key/empty-key fail in the
  legacy branch; consent-off fails at the final consent gate; DEBUG override short-circuits).
  Does NOT mask a real regression — these tests assert legacy-key gating, not active-profile.
- (b) No test intent changed — every affected positive test seeds only the legacy
  `AIService.apiKeyAccount` key (never a per-profile key); per-profile coverage stays in the
  dedicated suites (AIReaderAvailabilityPerProfileTests / BilingualAIReadinessTests /
  AISettingsViewModelMultiProfileTests).
- (c) Reusing one immutable `prefs` across grant+revoke in `availableTransitionsAcrossConsentRevoke`
  is correct.
- (d) No missed call site; no new flakiness (fresh store per call except the one immutable shared one).
- (e) Genuinely test-only; does NOT alter Bug #308's active-profile-first production semantics
  (production callers still default to `UserDefaultsPreferenceStore()`).

## Verdict
**ship-as-is.** Zero findings.

## Tests (RED → GREEN)
- `AIChatGeneralTests.generalChatAccessibleFromLibrary` FAILED on `main` (the sim's
  `.standard` carries a stale active-provider UUID), passes after the fix.
- Suites green: `AIChatGeneralTests`, `AIReaderAvailabilityTests`, `AIReaderIntegrationTests`
  (`RUN-TESTS RESULT: SUCCEEDED`).
