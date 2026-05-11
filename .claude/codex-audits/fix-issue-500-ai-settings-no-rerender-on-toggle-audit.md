---
branch: fix/issue-500-ai-settings-no-rerender-on-toggle
threadId: 019e13c8-60bf-72b0-9c14-a3159358941d
rounds: 2
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex audit — bug #167 fix (AI Settings expanded sections don't render after toggle ON until app relaunch)

GH issue: #500. Severity: medium.

## Root cause

`AISettingsViewModel` is `@Observable @MainActor`. The `isAIEnabled`
property was a pure get/set computed property delegating to
`FeatureFlags.isEnabled(.aiAssistant)` / `setOverride(_:for:)`:

```swift
var isAIEnabled: Bool {
    get { featureFlags.isEnabled(.aiAssistant) }
    set { featureFlags.setOverride(newValue, for: .aiAssistant) }
}
```

`FeatureFlags` is a `nonisolated final class Sendable` with
`OSAllocatedUnfairLock`-protected storage — not `@Observable`. The
`@Observable` macro only instruments stored properties; a computed
property whose body reads/writes a non-Observable class bypasses
`_$observationRegistrar` entirely on both read and write.

Result: in `AISettingsSection`, the conditional
`if viewModel.isAIEnabled { /* API Key, Provider Configuration, Data & Privacy sections */ }`
never re-evaluated after the toggle's setter wrote through — SwiftUI
didn't know to invalidate the view. The flag DID persist to UserDefaults
correctly; the conditional just didn't re-render. Only an app
kill+relaunch re-initialized the view model from FeatureFlags on first
render, picking up the new value.

## Files changed

Production:
- `vreader/Views/Settings/AISettingsViewModel.swift` — convert
  `isAIEnabled` from a pure computed property to a stored property with
  a `didSet` write-through that calls `featureFlags.setOverride` only
  when the value actually changes. Seed `self.isAIEnabled =
  featureFlags.isEnabled(.aiAssistant)` once at init time. The
  `@Observable` macro instruments the stored property's storage, so
  writes fire `_$observationRegistrar.withMutation` and reads call
  `_$observationRegistrar.access`.

Tests:
- `vreaderTests/Views/Settings/AISettingsViewModelTests.swift` — three
  new tests:
  1. `toggleNotifiesObservationTracker` — pins that
     `withObservationTracking { _ = vm.isAIEnabled } onChange: { ... }`
     fires when the toggle is written. RED on the pre-fix computed
     property; GREEN after the stored-property fix.
  2. `toggleStillWritesThroughToFeatureFlags` — pins the write-through
     so `FeatureFlags.shared.isEnabled(.aiAssistant)` is correctly
     updated after `vm.isAIEnabled = true` (needed by
     `AIReaderAvailability.isAvailable` gating the in-reader AI button).
  3. `idempotentSetIsNoOpAgainstFeatureFlags` — pins the `oldValue !=
     isAIEnabled` write-through dedup via a sentinel value trick: write
     a `0xDEAD` Int directly under the persistence key, then assign the
     same `true` to `vm.isAIEnabled`. If `setOverride` runs, the bool
     overwrites the sentinel; if the guard works, the sentinel survives.

## Round 1 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Medium | `AISettingsViewModelTests.swift:163` (initial `idempotentSetDoesNotFireObservation`) | Test asserted that same-value writes to a stored `@Observable` property would NOT fire the registrar. That's an implementation-defined property of the Observation runtime, not a contract the code can promise. Pinning it could lock in a false assumption or break on a future Swift/SwiftUI release. | **Fixed**. Replaced with `idempotentSetIsNoOpAgainstFeatureFlags` which uses a sentinel-value technique against UserDefaults to pin the write-through dedup contract (the user-visible invariant) without relying on Observation-runtime behavior. |
| 2 | Low | `AISettingsViewModel.swift:48` (initial comment) | Comment claimed the `oldValue != isAIEnabled` guard "avoids spurious re-renders". The guard actually avoids redundant `setOverride` calls and UserDefaults writes — it does NOT necessarily affect Observation invalidation. | **Fixed**. Comment rescoped to "guard dedupes the *write-through* to FeatureFlags (and the resulting UserDefaults write) on same-value assignments"; explicitly notes that whether the Observation runtime also skips same-value notifications is "an implementation detail this code does NOT rely on". |

## Round 2 verification

**Zero new findings**. Codex confirmed:
- Updated comment scopes the guarantee correctly to write-through dedup.
- Revised test no longer asserts anything about Observation's same-value semantics.
- Sentinel test is sound for the contract it claims to pin —
  `FeatureFlags.setOverride` calls `defaults.set(value, forKey:)`, so a
  redundant call would overwrite the `0xDEAD` Int slot with a Bool;
  reading back as Int would no longer return `0xDEAD`.
- Test isolation correct: unique per-test UserDefaults suite name,
  `removePersistentDomain` in `defer`.

Residual note (NOT a finding): `hasConsent` has the same computed-property/non-observable shape. Currently it's only used as a `Toggle` binding — no conditional render — so no user-visible bug. If future UI conditionally renders off `viewModel.hasConsent`, it will need the same treatment. Filed mentally; not in scope here.

Final verdict: `ship-as-is`.

> "No findings. The two round-1 issues are resolved. The updated comment now scopes the guarantee correctly to write-through dedup, and the revised test no longer asserts anything about Observation's same-value notification semantics. The sentinel test is sound for the contract it claims to pin." — Codex round 2

## Test gate

`xcodebuild test -only-testing:vreaderTests/AISettingsViewModelTests` —
**32/32 green** (29 pre-existing + 3 new bug-#167 tests).

## Plan compliance

Fix scope per the issue body matches:
- [x] Flipping the AI Assistant toggle now triggers SwiftUI body re-render so API Key / Provider Configuration / Data & Privacy sections appear without app relaunch.
- [x] Write-through to `FeatureFlags` preserved so cross-app readers (`AIReaderAvailability.isAvailable`) see the toggle change.
- [x] Idempotent set (same value) is a no-op against `FeatureFlags` — no spurious UserDefaults writes on view rebuild.
- [x] FeatureFlags' `Sendable` concurrency contract unchanged — fix is local to `AISettingsViewModel`.

## Files OUT of scope

- `vreader/Services/FeatureFlags.swift` — kept as `nonisolated final class Sendable`; making it `@Observable` would change its concurrency story and is not needed to fix this bug.
- `AISettingsViewModel.hasConsent` — same shape as the old `isAIEnabled` but no conditional UI reads it; revisit if future UI adds one.
- `AISettingsSection.swift` — read site unchanged; the `if viewModel.isAIEnabled` conditional works correctly once the viewModel property is observable.
