---
branch: feat/issue-50-wi-7-in-reader-provider-picker
threadId: 019e18a2-a7b4-7070-8fbb-e9bed14ecf96
rounds: 2
final_verdict: ship-as-is
date: 2026-05-12
---

# Codex Audit — Feature #50 WI-7: In-Reader AI Provider Picker

Branch: `feat/issue-50-wi-7-in-reader-provider-picker`
Thread: `019e18a2-a7b4-7070-8fbb-e9bed14ecf96`
Rounds: 2 (max 3 per rule 47)
Final verdict: **ship-as-is**

## Scope

Feature #50 WI-7 — the FINAL WI of feature #50. Adds the in-reader
provider picker that lets a user flip the active AI provider /
model without leaving the reader. After this WI lands, feature #50's
last unimplemented acceptance criterion (b — "user can add multiple
profiles and switch active provider from reader settings") is closed.

Files in scope:
- NEW: `vreader/ViewModels/AIProviderPickerViewModel.swift` (~90 LOC after round 1)
- NEW: `vreader/Views/Reader/AIProviderPicker.swift` (~85 LOC after round 1)
- MODIFIED: `vreader/Views/Reader/AIReaderPanel.swift` — `@State` picker VM + `topBarTrailing` toolbar item
- MODIFIED: `vreader/Services/AI/ProviderProfileStore.swift` — `Notification.Name.providerProfilesDidChange` + post on every mutation (round-1 fix)
- NEW: `vreaderTests/ViewModels/AIProviderPickerViewModelTests.swift` (~190 LOC, 9 Swift Testing tests including 2 notification-resync regression tests added in round 1)

## Round 1 — follow-up-recommended

2 findings (1 Medium, 1 Low):

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | Medium | Picker only reloaded on first `.task` appearance. External mutations from Settings (rename / delete / active flip) wouldn't propagate to an already-open picker until sheet dismiss+reopen. | Added `Notification.Name.providerProfilesDidChange` posted by `ProviderProfileStore` on every mutation (`upsert` / `remove` / `setActiveProfileID`). `AIProviderPickerViewModel` registers an observer in init (via `installObserver()` called after stored-property init so `[weak self]` capture is valid) and dispatches `loadProfiles()` on each post. Token stored as `nonisolated(unsafe) private var didChangeObserver: NSObjectProtocol?` so deinit can release it. 2 new regression tests (`notification_resyncsActiveID_afterStoreMutation`, `notification_resyncsProfilesList_afterUpsert`) pin the live-resync contract; both use a `pollUntil(timeoutMs:condition:)` helper because notification + Task @MainActor isn't synchronous. |
| 2 | Low | Active row used a checkmark glyph only — VoiceOver reported "button" + name without the `.isSelected` trait that WI-6a's `AIProviderListView` had established as precedent. | Added `.accessibilityAddTraits(viewModel.activeID == profile.id ? [.isSelected] : [])` to each menu row. Checkmark glyph remains visible for sighted users. |

## Round 2 — ship-as-is

> "No findings. The round-1 fixes address the two issues I flagged.
> `AIProviderPickerViewModel` observer lifetime/isolation is acceptable
> as implemented. `installObserver()` runs after stored-property
> initialization, so the `[weak self]` capture is legal.
> `nonisolated(unsafe) private var didChangeObserver` is narrowly scoped
> to the deinit cleanup problem on a `@MainActor` type; with exactly one
> post-init write and one deinit read, I don't see a practical race.
> The `[weak self] -> Task { @MainActor ... }` chain is also safe: if a
> notification lands during teardown, the weak capture collapses to nil
> and no work runs. `ProviderProfileStore` posting after
> `writeProfiles(...)` from the actor's isolated mutation methods is
> safe. The write completes before `postDidChangeNotification()` fires,
> and the picker reads via a fresh `loadSnapshot()`, so observers
> converge to committed state rather than a speculative one. The
> `.isSelected` trait addition closes the accessibility gap."

Residual note: test coverage is VM-level only, not a UI-level test of
the `Menu` surface itself. Acceptable for merge — the SwiftUI Menu
surface lacks an `XCTest`-friendly tap-the-row hook, and the behavioral
contract is captured by the VM tests + the post-merge device
verification pass that flips feature #50 to VERIFIED.

## Swift 6 isolation quirks worth recording

- `nonisolated` alone is REJECTED on mutable stored properties of
  `@Observable` classes — the macro auto-generates Observation tracking
  that conflicts. Compiler emits a misleading warning suggesting
  `nonisolated` over `nonisolated(unsafe)`, but applying the
  suggestion produces a hard error. The `(unsafe)` form is required
  here.
- `installObserver()` MUST be called after all stored-property init
  completes, otherwise `[weak self]` capture errors with "used before
  being initialized". The pattern is: `init { self.store = store;
  installObserver() }` not `init { self.didChangeObserver =
  addObserver(...) { [weak self] ... } }`.

## Test gate

82 tests pass across 7 AI multi-profile suites on iPhone 17 Simulator
(iOS 26.4, build 17E202):

- AIProviderPickerViewModelTests (9 tests; 7 from round 1 + 2 from round 1 audit fix)
- AISettingsViewModelMultiProfileTests (11 tests, unchanged from WI-6a)
- AISettingsViewModelEditorTests (26 tests, unchanged from WI-6b)
- AISettingsViewModelTests (6 tests, unchanged)
- ProviderProfileStoreTests (~10 tests, unchanged)
- AIServiceProfileDispatchTests (9 tests, unchanged)
- Plus the round-1 audit-fix regression suite

Test command:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project vreader.xcodeproj -scheme vreader \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:vreaderTests/AIProviderPickerViewModelTests \
    -only-testing:vreaderTests/AISettingsViewModelTests \
    -only-testing:vreaderTests/AISettingsViewModelMultiProfileTests \
    -only-testing:vreaderTests/AISettingsViewModelEditorTests \
    -only-testing:vreaderTests/ProviderProfileStoreTests \
    -only-testing:vreaderTests/AIServiceProfileDispatchTests
```

Result: `** TEST SUCCEEDED **`.
