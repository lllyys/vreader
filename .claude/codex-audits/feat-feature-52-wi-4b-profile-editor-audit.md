---
branch: feat/feature-52-wi-4b-profile-editor
threadId: 019e26d6-93f9-7981-beef-b43de89da0a1
rounds: 3
final_verdict: ship-as-is
date: 2026-05-14
---

# Codex audit log — Feature #52 WI-4b

Feature #52 WI-4b: replace WI-4a's stub WebDAV editor with the full
add/edit form including Server URL validation, Save / Test Connection
buttons, and add-mode bug #184 pattern (hide keychain + Test
Connection buttons in add-mode, show edit-mode).

## Round 1 — initial audit

6 findings — fixed inline before round 2.

| file:line | severity | issue | resolution |
|---|---|---|---|
| `WebDAVServerProfileEditSheet.swift:162` | High | Save validation only checks `URL(string:)` + `scheme != nil`, so malformed-but-schemed values like `https://` / hostless URLs can still be saved. Violates the plan's "malformed URL — validation before save" requirement. | **FIXED** — added shared `WebDAVProfileListViewModel.validatedServerURL(from:)` static helper that requires trim, parses to URL, scheme is http/https, AND non-empty host. Used by `canSave`, `save()`, `testConnection`, and the field `.onChange` validator. 6 new unit tests pin behavior. |
| `WebDAVProfileListViewModel+Editor.swift:69` | Medium | `updateProfile(_:)` blindly `upsert`s. If the profile is deleted while the edit sheet is open, tapping Save recreates it instead of rejecting the stale edit. | **FIXED** (round-1 partial → round-2 final). |
| `WebDAVServerProfileEditSheet.swift:255` | Medium | Test Connection failure text is generic — `WebDAVError` doesn't conform to `LocalizedError`. | **FIXED** — `WebDAVError` now conforms to `LocalizedError` with case-specific messages: authenticationFailed mentions username/password, httpError(405) mentions PROPFIND + 405 + WebDAV (specifically diagnostic per plan's risk-mitigation section), connectionFailed includes the detail, etc. 3 tests. |
| `WebDAVProfileListViewModel+Editor.swift:132` | Medium | `testConnection(...)` treats whitespace-only username/password as valid because it checks raw strings, not trimmed strings. | **FIXED** — trims before emptiness checks AND passes trimmed values into `makeTransport`. 2 tests. |
| `WebDAVServerProfileEditSheet.swift:191` | Medium | Plan called for the name field to auto-fill from server URL hostname when blank; implementation persisted `trimmedName` verbatim and relied only on `displayName`'s read-time fallback. | **FIXED** — `save()` derives `resolvedName = trimmedName.isEmpty ? url.host : trimmedName` before constructing the profile. Persistence now matches plan edge case (e). |
| `WebDAVServerProfileEditSheet.swift:95` | Low | The sheet probed Keychain via `KeychainService()` directly instead of going through the injected store/VM dependency, bypassing test injection. | **FIXED** — added `WebDAVProfileListViewModel.readStoredPassword(for:)` that delegates to `profileStore.readPassword`. Sheet's init no longer constructs `KeychainService`; a `.task` on the body probes via the VM. `runTest()` also uses the VM-side probe. 2 tests. |

## Round 2 — verification

2 new Medium findings from the round-1 fixes — both real correctness
issues, fixed inline.

| file:line | severity | issue | resolution |
|---|---|---|---|
| `WebDAVProfileListViewModel+Editor.swift:75` | Medium | The stale-edit fix is still racy. `updateProfile(_:)` does `loadAll → upsert` as two actor hops. A concurrent delete between them slips through. | **FIXED** — added single-hop `WebDAVServerProfileStore.updateIfExists(_:) -> Bool` (atomic read-modify-write inside the actor). VM calls this instead of `loadAll + upsert`. Test: `updateProfile_singleHopRejectsConcurrentlyDeletedProfile` reproduces the previously-racy sequence and confirms the store stays empty + editorError set. |
| `WebDAVProfileListViewModel+Editor.swift:46` | Medium | `addProfile` and `savePassword` validate against trimmed copies but persist the raw `password` string. A user typing `" secret "` saves whitespace permanently; Test Connection trims and succeeds the same session, but stored credential mismatches form input. | **FIXED** — both `addProfile` and `savePassword` trim BEFORE writing. `addProfile` also rejects whitespace-only password before the keychain write. 3 tests: `addProfile_persistsTrimmedPassword`, `addProfile_rejectsWhitespaceOnlyPassword`, `savePassword_persistsTrimmedPassword`. |

## Round 3 — verification

> "No findings. The round-2 fixes are correct as implemented.
> `WebDAVServerProfileStore.updateIfExists(_:)` closes the stale-edit
> race by doing the existence check and replacement in one actor hop,
> and the VM now handles the `false` path cleanly without re-creating
> deleted profiles. The password-write paths also now behave
> consistently with validation and Test Connection: both add-mode and
> edit-mode trim before persisting, and whitespace-only add/save
> attempts fail without writing keychain state or adding a profile."

Verdict: **ship-as-is.**

## Test gate

`xcodebuild test -only-testing:vreaderTests/WebDAVProfileListViewModelEditorTests`
— 31/31 pass:

- 7 list / add / update tests (addProfile / updateProfile / savePassword
  / deletePassword path-correctness)
- 6 testConnection HTTP-shape tests (success, auth-failed, invalid-URL,
  missing username, missing password, connection-failed)
- 6 URL validator tests (accepts https+host, accepts http for local
  networks, rejects scheme-only-hostless, rejects missing-scheme,
  rejects wrong-scheme, trims whitespace)
- 3 round-1 fix tests (updateProfile rejects unknown id, whitespace
  username, whitespace password)
- 2 keychain VM-probe tests (readStoredPassword for known + unknown id)
- 3 WebDAVError localized message tests (authenticationFailed,
  httpError(405), connectionFailed)
- 4 round-2 fix tests (single-hop updateProfile, addProfile trim,
  addProfile rejects whitespace-only, savePassword trim)

Adjacent suites also green: WebDAVProfileListViewModelTests,
WebDAVServerProfileStoreTests, WebDAVServerProfileTests,
WebDAVProviderTests.

## Summary

`ship-as-is`. WI-4b ships the full WebDAV add/edit form per the
plan's WI-4b spec (line 267-276 of `dev-docs/plans/20260514-feature-52-multiple-webdav-profiles.md`):
fields (Name / Server URL / Username / Password), Save / Test
Connection buttons, bug #184 add-mode pattern, edit-mode Save Key
/ Delete Key buttons, single-hop store updates, trimmed-password
persistence. Codex 3-round audit produced 8 findings total (all
addressed); round-3 clean. 31 unit tests cover the editor's behavior
including the discovered race + whitespace-persistence edge cases.
