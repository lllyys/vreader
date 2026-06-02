---
branch: feat/feature-80-wi1-test-before-save
threadId: codex-exec (RUN-CODEX RESULT SUCCEEDED, /tmp/feat80-implaudit.txt)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Gate-4 Codex audit — Feature #80 (Test Connection before Save)

Independent impl audit (Codex gpt-5.4, high, read-only) of the diff: in-memory-key
`testConnection` override + add-mode Test button gated on `hasTestableKey` +
`resetTestResult()` stale-result invalidation + the footnote. One round;
author=this session, auditor=Codex (rule-48 separation).

Auditor found no issue in the override-vs-keychain logic, the whitespace-only
`hasTestableKey` gate, typed-key persistence/logging (none), or the @MainActor/
Sendable surface.

## Findings & resolutions

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `AIProviderEditSheet.swift:313` (`runTest`) | High | The `onChange`/`resetTestResult()` hooks clear the label but don't cancel an IN-FLIGHT test: a request that completes after the user edits the form (or save/delete-key) would repaint the STALE result over the new state. | **FIXED** — added a `testGeneration` guard: `runTest` stamps the run; `resetTestResult()` (every request-shaping input + save/delete-key) bumps the generation; the result is applied only if `shouldApplyTestResult(runGeneration:currentGeneration:)` still matches. (Same pattern as #78's progress guard.) |
| 2 | `AISettingsViewModelEditorTests.swift:417` | Medium | Tests covered override precedence / nil fallback / `hasTestableKey` but not the stale-invalidation contract (incl. the in-flight case). | **PARTIALLY ADDRESSED** — added `shouldApplyTestResult_onlyWhenGenerationUnchanged` (pins the in-flight-guard decision, the load-bearing logic). The per-input `onChange` reset wiring + save/delete-key reset are SwiftUI view-@State glue (not cleanly unit-isolable); `resetTestResult()` is a one-liner + the generation guard is unit-pinned, and the add-mode behavior is device-verified in Gate 5. |
| 3 | `AIProviderEditSheet.swift:25` | Low | File header still said "add-mode is gated on a saved keychain entry" (now false). | **FIXED** — header updated to the #80 contract (typed key wins; empty/nil → keychain; generation guard + reset). |

## Verdict

`ship-as-is` — High (in-flight stale-result) fixed with a generation guard + test;
Medium's core logic unit-pinned + the rest device-verified; Low fixed. Suite green:
`AISettingsViewModelEditorTests` (incl. override/fallback/hasTestableKey/generation tests).
