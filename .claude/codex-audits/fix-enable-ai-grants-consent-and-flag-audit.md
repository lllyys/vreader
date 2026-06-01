---
branch: fix/enable-ai-grants-consent-and-flag
threadId: codex-exec-gpt-5.5-20260601
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — --enable-ai grants consent + aiAssistant (harness gap)

## Scope

Bug #237 forwarded `--enable-ai` to `AITestOverride.forceAvailable` (the
`AIReaderAvailability` UI gate). But `AIService.sendRequest`/`streamRequest` gate
DIRECTLY on `featureFlags.aiAssistant` + `consentManager.hasConsent` (not via
AIReaderAvailability), so live AI requests (bilingual translate, summarize, chat)
still threw featureDisabled/consentRequired in CU-free verification — the UI lit
up but no content rendered. Fix: DEBUG-only `AITestSetup.apply(enableAI:...)` sets
all three; `VReaderApp` calls it.

Files: `vreader/App/AITestSetup.swift` (NEW), `vreaderTests/App/AITestSetupTests.swift`
(NEW), `vreader/App/VReaderApp.swift` (call site).

## Round 1 — findings

Codex (gpt-5.5, read-only). Implementation **Checked Clean** (no Release leak —
both `AITestSetup` + the call site are `#if DEBUG`; correct stores —
`AIConsentManager()` + `FeatureFlags.shared` match what `AIService` reads;
`@MainActor` correct). 1 Medium + 1 Low (both test-quality) — FIXED:

| # | sev | issue | resolution |
|---|---|---|---|
| 1 | Medium | `enableTrueSetsAllThreeGates` leaked `AITestOverride.forceAvailable == true` (global static) → could contaminate later AIReaderAvailability tests. | FIXED — `defer { AITestOverride.forceAvailable = false }` + reset at start in both gate-setting tests. |
| 2 | Low | No test pinned cold `enableAI=false` not granting the real gates. | FIXED — added `enableFalseGrantsNothing` (asserts aiAssistant + consent stay off, no auto-grant). |

## Test evidence

`AITestSetupTests` — 3 tests green. No Release leak (DEBUG-gated). No production
risk: consent/flag granted ONLY under `--enable-ai` in a `#if DEBUG` path.

## Verdict

ship-as-is (implementation clean; 2 test-quality findings fixed).
