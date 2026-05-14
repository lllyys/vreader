---
branch: feat/feature-52-wi-5-cleanup
threadId: 019e26ec-f6ec-75d3-b9b6-f6ba32f46a2f
rounds: 4
final_verdict: ship-as-is
date: 2026-05-14
---

# Codex audit log — Feature #52 WI-5

WI-5 foundational cleanup: complete the multi-profile migration by
retiring the legacy single-server credentials form + flat-keychain
factory variants. The plan section budgeted ~30 LOC, but Codex round-1
showed the surgical change would leave source-of-truth divergence;
the scope was escalated to remove the legacy form entirely.

## Round 1 — initial audit

3 findings (1 High + 1 Medium + 1 Low). The High forced a rescope.

| file:line | severity | issue | resolution |
|---|---|---|---|
| `WebDAVSettingsView.swift:407` | High | `loadCredentials()` now preloads from active profile but `refreshBackupVMIfNeeded`, `saveCredentials`, `clearCredentials` still operate on flat-keychain — switching the active profile in the list view shows profile B in the form while backup runs against legacy credentials A. | **FIXED** by removing the legacy form entirely. Sections removed: Server URL/Username/Password fields, Test Connection, Save/Remove Credentials, supporting state vars, 4 helper methods, 3 keychain account constants, the `keychain:` init parameter, `TestResult` struct. `refreshBackupVMIfNeeded` now uses async `make(persistence:profileStore:)`. `LibraryView`'s row-tap observer also migrated to async `makeRequestBuilder(profileStore:)`. Legacy `make(keychain:)` + `makeRequestBuilder(keychain:)` factory variants deleted. |
| `WebDAVSettingsView.swift:483` | Medium | Plan says "stop reading flat keychain directly" but the fallback remained. | **FIXED** — the fallback went away with the legacy form. |
| `docs/architecture.md:104` | Low | `WebDAVServerProfileStore` row lists backing as only `KeychainService`. | **FIXED** — backing now reads `UserDefaults` / `KeychainService`; purpose text expanded to note where each persists. |

## Round 2 — verification

3 new findings from the escalated round-1 fixes.

| file:line | severity | issue | resolution |
|---|---|---|---|
| `WebDAVSettingsView.swift:137` | Medium | `refreshBackupVMIfNeeded` re-runs on `.webdavProfilesDidChange`, but `writePassword` / `deletePassword` don't post that notification. Password-only mutations from the editor sheet leave the backup section stale. | **FIXED** — added `Self.postDidChangeNotification()` to both `WebDAVServerProfileStore.writePassword(_:for:)` and `deletePassword(for:)`. 2 new tests pin the notification-on-mutation contract. |
| `docs/architecture.md:103` | Low | Architecture rows still describe `WebDAVProviderFactory` as having transitional legacy paths; `WebDAVServerProfileStore` row still lists `KeychainService` only. | **FIXED** — factory row simplified ("profile-store-only after WI-5"); store row now `UserDefaults` / `KeychainService` with purpose text noting the split. |
| `WebDAVSettingsView.swift:36` | Low | `@Environment(\.dismiss)` orphaned after the legacy form went away. | **FIXED** — removed. |

## Round 3 — verification

2 Low findings — stale comments.

| file:line | severity | issue | resolution |
|---|---|---|---|
| `VReaderApp.swift:260` | Low | Migrator-block comment still says production reads go through the removed `make(keychain:)` path until WI-5. | **FIXED** — rewrote the comment to describe the post-WI-5 state. |
| `WebDAVProviderFactory.swift:87` | Low | `makeRequestBuilder(profileStore:)` doc comment described it as "variant of `makeRequestBuilder(keychain:)`" but the keychain variant was deleted. | **FIXED** — rewrote the doc comment to describe the current method directly. |

## Round 4 — verification

1 Low finding — `docs/features.md` Feature #52 row still listed WI-5
as remaining work.

| file:line | severity | issue | resolution |
|---|---|---|---|
| `docs/features.md:108` | Low | Feature #52 narrative said "Remaining WIs: WI-5 cleanup, WI-6 final acceptance" and described legacy variants as still present. | **FIXED** — appended WI-5 shipped narrative documenting the full cleanup, updated "Remaining WI" to just WI-6. |

Final verdict: **ship-as-is.**

## Test gate

`xcodebuild test -only-testing:vreaderTests/WebDAVProfileListViewModelEditorTests`
— 33/33 pass (was 31 after WI-4b; added 2 notification-on-password-mutation
tests in WI-5):

- `writePassword_postsDidChangeNotification`
- `deletePassword_postsDidChangeNotification`

Full WebDAV-adjacent suite — 122/122 pass across 7 suites:
- WebDAVProfileListViewModelTests
- WebDAVProfileListViewModelEditorTests
- WebDAVServerProfileStoreTests
- WebDAVServerProfileTests
- WebDAVProviderTests
- WebDAVProfileMigratorTests
- WebDAVProviderFactoryProfileDispatchTests

## Summary

`ship-as-is`. WI-5 lands the multi-profile architecture cleanly:
the legacy single-server form + flat-keychain factory variants are
gone; the active profile (read through `WebDAVServerProfileStore`) is
the sole credential source. The escalated scope (originally budgeted
~30 LOC, shipped at ~250 LOC modified) was necessary to avoid
source-of-truth divergence Codex flagged in round 1. Codex 4-round
audit produced 9 findings total (1 High + 2 Medium + 6 Low); all
addressed. 33 unit tests cover the editor's full behavior including
the new round-2 password-notification contract.
