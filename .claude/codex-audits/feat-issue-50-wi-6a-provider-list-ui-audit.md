---
branch: feat/issue-50-wi-6a-provider-list-ui
threadId: 019e1763-2e46-7830-9f18-6160ca6f8887
rounds: 3
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex Gate-4 Audit — Feature #50 WI-6a

Settings UI Phase A — provider list + active selection. Multi-round
Codex MCP audit (sandbox: read-only, thread
`019e1763-2e46-7830-9f18-6160ca6f8887`).

Scope: rewrite `AISettingsViewModel` from single-profile to multi-profile
list VM backed by `ProviderProfileStore.shared`. Add list/active/delete
ops. Add `AIProviderListView` (new). Rewrite `AISettingsSection` as
thin wrapper. Editor sheet placeholder lands here (filled in by WI-6b).

## Round 1 findings

| # | File:line | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | `vreader/Views/Settings/AISettingsViewModel.swift:loadProfiles` | High | `loadProfiles()` did two separate actor reads (`loadAll()` then `activeProfile()`). Concurrent mutation between the awaits could publish a stale `profiles` snapshot with a different `activeID`. | **Fixed.** Added atomic `ProviderProfileStore.loadSnapshot()` (single actor hop, returns `(profiles, activeID)` tuple). VM consumes the snapshot. Also added defensive resolve: if persisted active id no longer resolves to a present profile, VM publishes `activeID = nil` rather than dangling. |
| 2 | `vreader/Views/Settings/AISettingsViewModel.swift:setActive` | Medium | `setActive(_:)` wrote the requested id optimistically. A caller passing an unknown id, or a concurrent delete clearing active before the task resumed, would leave the VM with a dangling active id. | **Fixed.** `setActive` now (a) rejects ids not in current `profiles` list before writing, (b) reads back authoritatively via `await store.activeProfile()` after the write so a concurrent delete clearing active is reflected. |
| 3 | `vreaderTests/Views/Settings/AISettingsViewModelMultiProfileTests.swift:loadProfiles_triggersLegacyMigration` | Medium | Migration test asserted only `vm.profiles.count == storeProfiles.count` — too loose, would pass even if migration produced wrong contents. | **Fixed.** Test now asserts exactly one migrated profile, `.openAICompatible` kind, model/baseURL/temperature/maxTokens copied verbatim from legacy `AIConfiguration`, `vm.activeID == migrated.id`, AND legacy API key (seeded via `AIService.apiKeyAccount`) is copied to the per-profile keychain account read via `keychain.readAPIKey(forProfile:)`. |
| 4 | `vreader/Views/Settings/AIProviderListView.swift:profileRow` | Low | Active row was indicated to VoiceOver only via `accessibilityValue("Active")` string. The radio-style selection wasn't semantically surfaced — VoiceOver reported a plain button. | **Fixed.** Active row now carries `.accessibilityAddTraits([.isSelected, .isButton])` (vs `.isButton` only otherwise). Inactive rows get `.accessibilityHint("Double-tap to make active.")`. Visual checkmark + `.isSelected` trait is the correct sighted+VO pairing, not duplication. |

## Round 2 findings

| # | File | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | `vreaderTests/Views/Settings/AISettingsViewModelMultiProfileTests.swift` | Low | The round-1 dangling-id defense in `setActive(_:)` wasn't pinned by a VM-level test. The underlying `ProviderProfileStore` still accepts unknown ids (by design), so the round-1 fix was vulnerable to silent regression. | **Fixed.** Added `setActive_unknownID_isIgnored_andDoesNotMutateStore` — loads a known profile, calls `vm.setActive(UUID())` with an id not in the list, asserts both `vm.activeID` AND `await store.activeProfile()?.id` remain pointing at the known profile. |

## Round 3 verdict

> No findings. Ship-as-is.

Auditor verbatim on round 3:

> The new test at AISettingsViewModelMultiProfileTests.swift:146 correctly
> pins the VM-level contract: unknown ids are ignored by
> `AISettingsViewModel.setActive(_:)`, and both the VM mirror and
> authoritative store state remain unchanged.

Final verdict from round 2 (re-confirmed in round 3):

> The four round-1 findings themselves are addressed correctly:
>
> - `loadProfiles()` now uses one actor hop via `loadSnapshot()` and then
>   resolves `activeID` against the same loaded list. That removes the
>   split-read race.
> - `setActive(_:)` no longer trusts the caller's id and now reads back
>   the store's authoritative active profile. That is the right
>   trade-off; if a concurrent delete or concurrent second selection
>   wins, the VM reflects real store state.
> - The migration test is now contract-level, not wiring-level.
> - The accessibility fix is appropriate: visual checkmark plus
>   `.isSelected` is the normal pairing, not duplication.

Cross-checks confirmed:
- `loadSnapshot()` ordering is correct (`ensureMigrated` runs first, then
  both reads happen in the same actor turn against the same preferences
  backing store).
- `setActive` read-back doesn't introduce a worse race.
- `AIService.apiKeyAccount` is the correct legacy keychain account name
  (matches both `AIService.swift` and `ProviderProfileMigrator.swift`).

## Test gate

- 31/31 tests pass across the three exercised suites:
  - `AISettingsViewModelTests` (6 — feature flag + consent + bug #167 regressions)
  - `AISettingsViewModelMultiProfileTests` (11 — load/setActive/delete/migration, new in this WI)
  - `ProviderProfileStoreTests` (15 — pre-existing, still GREEN; `loadSnapshot()` addition didn't regress)

## Diff summary

| File | Change | LOC delta |
|---|---|---|
| `vreader/Services/AI/ProviderProfileStore.swift` | Added `loadSnapshot()` for atomic snapshot read | +12 |
| `vreader/Views/Settings/AISettingsViewModel.swift` | Rewrite single → multi-profile (drop API key / model / baseURL fields; add list/active/delete) | ~-95 (was 224 lines, now ~130 with profile-list ops) |
| `vreader/Views/Settings/AISettingsSection.swift` | Rewrite to thin wrapper (toggle + NavigationLink + consent) | -76 (was 150, now ~70) |
| `vreader/Views/Settings/AIProviderListView.swift` | NEW: list UI with active selector + swipe-delete + editor-placeholder sheet | +180 |
| `vreaderTests/Views/Settings/AISettingsViewModelTests.swift` | Slimmed to feature-flag + consent + bug #167 regressions only | -266 (was 446, now ~190) |
| `vreaderTests/Views/Settings/AISettingsViewModelMultiProfileTests.swift` | NEW: 11 tests covering load/setActive/delete/migration | +275 |

Net: ~+30 LOC in product code, -250 LOC of retired single-profile tests
replaced by ~+275 LOC of multi-profile tests. All files stay under
the 300-line guideline.

## WI-6b prep

WI-6b will:
- Replace `editorPlaceholder` in `AIProviderListView.swift` with the real
  `AIProviderEditSheet.swift` (~180 LOC) containing kind picker, name,
  baseURL, model, temperature, maxTokens, API key SecureField with save/
  delete, and test-connection button.
- Add to `AISettingsViewModel`: `addProfile(_:apiKey:)`, `updateProfile(_:)`,
  `saveAPIKey(_:forID:)`, `deleteAPIKey(forID:)`, `testConnection(forID:)`.
- Add the matching tests to `AISettingsViewModelMultiProfileTests.swift`
  (the suite is already named generically so it covers both WI-6a and
  WI-6b list+editor ops).

Until WI-6b ships, users can:
- See migrated/saved profiles
- Switch active profile (radio-button row tap)
- Delete profile (swipe-left → Delete)
- NOT add new profile through this UI (the "+" button opens a stub
  sheet explaining WI-6b is the next step)
- NOT edit existing profile fields (model, baseURL, etc.)

This is the intended interim state per the plan's WI-6a/6b split
(round-1 audit finding [7] in the original feature plan).
