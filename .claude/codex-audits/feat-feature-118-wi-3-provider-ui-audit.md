---
branch: feat/feature-118-wi-3-provider-ui
threadId: 019eec40-f118wi3
rounds: 2
final_verdict: ship-as-is
date: 2026-06-22
---

# Codex audit — feature #118 WI-3 (AI provider list + editor UI + ViewModel)

Scope: `android/app/.../ai/{AiSettingsUiState,AiProviderListScreen,AiProviderEditSheet,
AiSettingsViewModel}.kt` + tests. The provider gate + the EditorSheet (Compose), reusing the #114
form vocabulary. Instrumented Compose tests pass on emulator-5554.

## Round 1 — 5 findings (2 High / 2 Medium / 1 Low)

| file:line | severity | issue | resolution |
|---|---|---|---|
| AiSettingsViewModel.test() | High | The injected `clientDispatcher` was unused — the key lookup + factory + `testConnection` ran on Main until the client's internal `withContext(IO)`. | FIXED — the whole test body runs in `withContext(clientDispatcher)`. |
| AiSettingsUiState.canSave | High | `canSave` only required a non-blank name; an add-mode save with a blank key passed `null` to `store.upsert` for a new UUID → `IllegalArgumentException`. | FIXED — `canSave = name.isNotBlank() && (apiKey.isNotBlank() || (editMode && keyAlreadySaved))` — a new provider must have a key. |
| AiSettingsViewModel.test() | Medium | A test result was applied to whatever editor state was current at completion — a stale Ok/Fail could land on a different form (closed / another provider / re-test). | FIXED — a `testGen` generation token, bumped on open/close/test; the result is applied only if `gen == testGen`. |
| AiProviderEditSheet.TemperatureRow | Medium | `widthPx` was a non-state local reset on recomposition + mutated outside composition → the thumb laid out using a stale `1f` width. | FIXED — `onSizeChanged` → `mutableIntStateOf(trackPx)`; the thumb + tap-map use the measured width. |
| AiProviderEditSheet.TemperatureRow | Low | The thumb start padding clamped only the left edge → at max value the 22dp thumb spilled past the right edge. | FIXED — `startPad.coerceIn(0.dp, (trackDp - 22.dp).coerceAtLeast(0.dp))`. |

## Round 2 — verify pass

All five confirmed fixed; the `testGen` guard drops stale completions, the `withContext` snapshot is
sound, and `canSave` edge cases hold. **No new defects.**

Verdict: **ship-as-is.** 3 JVM `AiSettingsViewModelTest` + 7 instrumented Compose tests
(`AiProviderListScreenTest` 2 + `AiProviderEditSheetTest` 5) green on emulator-5554 + full `:app`
suite green. Slice-verified (Gate-5a); final acceptance in WI-5.
