---
branch: feat/issue-50-wi-6b-provider-editor
threadId: 019e1808-81a2-7b00-a9f9-b302f00648b9
rounds: 3
final_verdict: ship-as-is
date: 2026-05-12
---

# Codex Audit — Feature #50 WI-6b: AI Provider Editor Sheet

Branch: `feat/issue-50-wi-6b-provider-editor`
Thread: `019e1808-81a2-7b00-a9f9-b302f00648b9`
Rounds: 3 (max 3 per rule 47)
Final verdict: **ship-as-is**

## Scope

Feature #50 WI-6b — Settings UI Phase B. Adds the profile-editor sheet
that creates / edits AI provider profiles, persists per-profile API
keys to the Keychain, and runs a Test Connection ping against the
selected provider type.

Files audited:
- NEW: `vreader/Views/Settings/AIProviderEditSheet.swift` (252 LOC)
- NEW: `vreader/Views/Settings/AIProviderEditSheet+Sections.swift` (202 LOC)
- NEW: `vreader/Views/Settings/KindResetPolicy.swift` (45 LOC)
- NEW: `vreader/Views/Settings/AISettingsViewModel+Editor.swift` (222 LOC)
- MODIFIED: `vreader/Views/Settings/AISettingsViewModel.swift` (184 LOC)
- MODIFIED: `vreader/Views/Settings/AIProviderListView.swift` (186 LOC)
- NEW: `vreaderTests/Views/Settings/AISettingsViewModelEditorTests.swift` (~640 LOC, 26 tests)

## Round 1 — block-recommended

6 findings (1 High, 5 Medium):

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | High | `Test Connection` ignored unsaved form edits — only read the last-saved profile. Anthropic provider also hardcoded `maxTokens: 1`. | Changed `testConnection(forID:)` → `testConnection(profile:)`. Caller passes a candidate ProviderProfile built from live sheet fields. Anthropic now receives `profile.maxTokens`. Added regression test `usesLiveFormState_notStoredProfile`. |
| 2 | Medium | Kind-picker reset broken after first kind change — `userEditedBaseURL`/`userEditedModel` flags were flipped to true by the kind picker's own programmatic writes. | (Iterated in round 2 — initial fix added `isApplyingKindDefaults` suppression flag; replaced cleanly in round 2 with pure-function `KindResetPolicy`.) |
| 3 | Medium | `validateBaseURL` accepted `::1` / `[::1]` but providers (OpenAICompatibleProvider, AnthropicProvider) only allow `localhost` / `127.0.0.1`. Editor could save profiles that fail at request time. | Tightened validator to match provider preflight exactly. Added regression test `validateBaseURL_httpIPv6Loopback_rejectedToMatchProviderPolicy`. |
| 4 | Medium | Add-mode `Save Key` wrote to Keychain immediately with a freshly-generated UUID; canceling the sheet left an orphaned secret. | Disabled `Save Key` in add-mode (`existing == nil`). Add-mode users enter the key in the SecureField and commit via top-level Save, which calls `addProfile(_:apiKey:)` — atomic write of profile + keychain or clean failure. Helper text updated. |
| 5 | Medium | Empty-state Add path didn't clear `editingProfile`, so after deleting the last row a stale "edit" sheet could re-present. `editorError` was set on the VM but never surfaced. | Empty-state Add button now mirrors the toolbar Add: clears `editingProfile`. AIProviderEditSheet now has its own `.alert` binding on `viewModel.editorError`. |
| 6 | Medium | EditorStubURLProtocol shared static handler state; HTTP-touching tests could race under Swift Testing's default parallel execution. Assertions too weak ("some request happened"). | HTTP-touching tests moved into a nested `@Suite(.serialized)`. Stronger assertions added: OpenAI path ends `/chat/completions` + `Bearer` header; Anthropic path ends `/messages` + `x-api-key` header + no `Authorization` header. |

## Round 2 — follow-up-recommended

2 findings (1 Medium, 1 Low):

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | Medium | Round-1's `isApplyingKindDefaults` flag depended on SwiftUI dispatching field `.onChange` callbacks synchronously inside the kind handler's closure. Not guaranteed; future runtime could deliver them later and recreate the original bug. | Replaced the flag with a pure-function policy in new file `KindResetPolicy.swift`. Two static helpers compare the current field text against the OLD kind's default. No flags, no timing assumption. Added regression test `kindReset_roundTripsOpenAIToAnthropicToOpenAI_withoutUserEdits`. |
| 2 | Low | `AIProviderEditSheet.swift` was 419 LOC, over the ~300-line guideline. Stale comments referenced the old `testConnection(forID:)` signature and the old add-mode key flow. | Split form sections out to `AIProviderEditSheet+Sections.swift` (202 LOC). Main file dropped to 252 LOC. Refreshed stale header comments. Widened `@State` access from `private` to default `internal` so the cross-file extension can bind to them — still module-internal, no external API surface change. |

## Round 3 — follow-up-recommended

1 finding (1 Medium):

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | Medium | Round-2's `KindResetPolicy` changed the edit-mode contract. The original design treated edit-mode prefill as "already edited" (sticky); the value-based policy could overwrite saved values if they happened to equal defaults. | Added `inEditMode: Bool = false` parameter to both `shouldReplaceBaseURL` and `shouldReplaceModel`. When true, both return false unconditionally. The kind .onChange handler passes `inEditMode: existing != nil`. Two new tests: `kindReset_editMode_neverReplaces_evenWhenFieldsEqualOldDefaults` and `kindReset_addMode_explicitFlagMatchesDefault`. |

## Round 3 closing — ship-as-is

Final closing-round verdict: `ship-as-is`. No remaining functional findings.

- `KindResetPolicy` is now order-insensitive with respect to the kind picker (depends only on `(current, oldKind, inEditMode)`).
- Widening `@State` members to module-internal for the cross-file extension is acceptable; no public API surface change.
- `testConnection(profile:)` call sites are clean.
- File-size guideline now satisfied across all WI-6b files.

## Test gate

All 47 tests pass on iPhone 17 Pro Simulator (iOS 26.4, build 17E202):
- AISettingsViewModelEditorTests (26 tests) — addProfile (3), updateProfile (2), saveAPIKey (3), deleteAPIKey (1), testConnection (5 serialized HTTP), validateBaseURL (8), KindResetPolicy (5).
- AISettingsViewModelMultiProfileTests (11 tests) — unchanged from WI-6a.
- AISettingsViewModelTests (6 tests) — unchanged.

Test command:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:vreaderTests/AISettingsViewModelEditorTests \
    -only-testing:vreaderTests/AISettingsViewModelTests \
    -only-testing:vreaderTests/AISettingsViewModelMultiProfileTests
```

Result: `** TEST SUCCEEDED **`.
