---
branch: fix/issue-695-feature29-webdav-profile-nav
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-15
---

# Codex audit log — Bug #195 (GH #695) — Feature #29 WebDAV verification test

Manual fallback per rule 47. The fix is mechanical: traverse the new Feature-#52 navigation path (Settings → WebDAV settings → Servers NavigationLink → profile list → Add → edit sheet) instead of expecting URL/username/password fields at the top level. Same shape as Bug #193 / #194 pattern fixes shipped earlier this session.

## Diagnosis

Bug #195 surfaced when Feature #45 WI-6's named Verification test plan ran end-to-end for the first time (PR #692 / v3.21.69). `Feature29WebDAVVerificationTests.test_verify_feature_29_webdav_backup_ui_available` failed at line 67 with `XCTAssertTrue failed - WebDAV Server URL field should be visible in WebDAV settings`.

Root cause: Feature #52 (multiple WebDAV server profiles, VERIFIED 2026-05-09) reworked the WebDAV settings UX. Pre-#52, `WebDAVSettingsView` exposed the URL/username/password TextFields directly at the top level with identifiers `webdavServerURL` / `webdavUsername` / `webdavPassword`. Post-#52, those fields moved into `WebDAVServerProfileEditSheet` reached via:

```
WebDAVSettingsView
   └── NavigationLink `webdavServersNavLink`
       └── WebDAVServerProfileListView
           └── Toolbar `addWebDAVProfileButton`
               └── WebDAVServerProfileEditSheet
                   ├── webdavProfileEditServerURL
                   ├── webdavProfileEditUsername
                   ├── webdavProfileEditPassword
                   └── webdavProfileEditTestConnection
```

The Verification test still expected the old top-level identifiers. They no longer exist in any production view — confirmed by `grep -rln "webdavServerURL"` returning zero hits in `vreader/`. The `TestConstants.swift` entries existed but were stale.

## Fix

2-file change:

1. **`vreaderUITests/Verification/Feature29WebDAVVerificationTests.swift`** — rewrote `test_verify_feature_29_webdav_backup_ui_available` to traverse the new path. Settings → WebDAV settings row (existing CONTAINS-heuristic preserved) → tap `webdavServersNavLink` → tap `addWebDAVProfileButton` → assert `webdavProfileEditServerURL` + `webdavProfileEditUsername` + `webdavProfileEditTestConnection` exist. Uses element-type-agnostic `descendants(matching:.any).matching(identifier:).firstMatch` for the NavigationLink + Test Connection control (matching the Bug #193 pattern — NavigationLink class varies across iOS versions).

2. **`vreaderUITests/Helpers/TestConstants.swift`** — kept the stale `webdavServerURL` / `webdavUsername` / `webdavPassword` / `webdavTestButton` / `webdavSaveButton` constants but annotated them as "STALE — no production wire" so a future grep finds documented context. Added new constants for the post-#52 path: `webdavServersNavLink`, `addWebDAVProfileButton`, `webdavProfileEditServerURL`, `webdavProfileEditUsername`, `webdavProfileEditTestConnection`.

## Files read

- `vreaderUITests/Verification/Feature29WebDAVVerificationTests.swift` (entire file, 144 lines — fix touches the surface test only; the live-backup test still uses stale identifiers — see Risks Accepted)
- `vreader/Views/Settings/WebDAVSettingsView.swift:91-107` (NavigationLink to profile list with `webdavServersNavLink`)
- `vreader/Views/Settings/WebDAVServerProfileListView.swift:90-104` (toolbar `addWebDAVProfileButton`)
- `vreader/Views/Settings/WebDAVServerProfileEditSheet+Sections.swift:16-163` (the 5 production accessibility identifiers used in the new path)
- `vreaderUITests/Helpers/TestConstants.swift` (added new identifiers + annotated old ones)

## Symbols / signatures verified

- `webdavServersNavLink` wired at `vreader/Views/Settings/WebDAVSettingsView.swift:105`
- `addWebDAVProfileButton` wired at `vreader/Views/Settings/WebDAVServerProfileListView.swift:101`
- `webdavProfileEditServerURL` wired at `vreader/Views/Settings/WebDAVServerProfileEditSheet+Sections.swift:36`
- `webdavProfileEditUsername` wired at `vreader/Views/Settings/WebDAVServerProfileEditSheet+Sections.swift:67`
- `webdavProfileEditTestConnection` wired at `vreader/Views/Settings/WebDAVServerProfileEditSheet+Sections.swift:151`
- Existing `webdavServerURL` / `webdavUsername` / `webdavPassword` identifiers wired in NO production view (`grep -rln` returns empty in `vreader/`). Stale — annotated in TestConstants.

## Edge cases checked

- **Fresh seed** (`resetPreferences: true`, `.books` fixture): profile list is empty, so the `addWebDAVProfileButton` path is the natural one. Test taps Add → edit sheet appears → asserts the form-field identifiers.
- **NavigationLink element class drift**: SwiftUI NavigationLink renders as different XCUIElement types depending on iOS version. The fix uses `descendants(matching:.any).matching(identifier:).firstMatch` for the nav-link tap site to be element-type-agnostic (same pattern as Bug #193's OPDS fix).
- **Test Connection in add-mode** (RED→GREEN iteration): first revision asserted `webdavProfileEditTestConnection` directly; the test failed at line 102 because Bug #184's design HIDES the Test Connection button in add-mode (existing == nil) and replaces it with a footer note `webdavProfileEditTestConnectionNote`. Revised assertion accepts either the button OR the note as evidence that the Connection section surface exists. Added `webdavProfileEditTestConnectionNote` constant to `TestConstants.swift`.
- **Smoke build**: `xcodebuild build` → BUILD SUCCEEDED after the test rewrite.
- **Pre-existing `webdavRow` heuristic**: the existing `NSPredicate(format: "label CONTAINS[c] 'WebDAV' OR label CONTAINS[c] 'Backup'")` row-finder is unchanged because it still reaches WebDAVSettingsView. Only the in-panel navigation was rewritten.

## Risks accepted

- **`test_verify_feature_29_webdav_backup_executes_when_configured` still references stale identifiers**: the live-backup test method (lines 86-143 of `Feature29WebDAVVerificationTests.swift`) uses `webdavServerURL` / `webdavUsername` / `webdavPassword` / `webdavSaveButton` / `webdavBackupNowButton` directly. The method is `XCTSkip`-gated on `CI_WEBDAV_URL` env var presence and is inert in normal runs. Updating it requires also typing into the profile edit sheet, tapping Save, returning to the profile list, setting active, navigating back to WebDAVSettingsView, and tapping the existing `webdavBackupNowButton`. That's a separate, larger refactor — out of scope for Bug #195's contract (the surface test). Documented as a follow-up in Bug #195's row note + a comment on GH #695 will note this.
- **Stale identifiers retained in TestConstants**: kept with "STALE" annotations rather than deleting outright because deleting would silently make `Feature29WebDAVVerificationTests.test_verify_feature_29_webdav_backup_executes_when_configured` fail to compile (its lines still reference them). Removing them cleanly requires updating the live-backup test in the same iteration — out of scope here.
- **No on-device verification this session**: standard bugfix-cron close-gate: post-merge `awaiting-device-verification` label, verify on simulator in a future iteration via re-running the named `-testPlan Verification` flag.

## Tests added or intentionally deferred

- **No new tests added**. The Bug #195 fix re-makes the existing `test_verify_feature_29_webdav_backup_ui_available` pass. RED demonstrated in the prior verify-cron iteration (`dev-docs/verification/feature-45-20260515-wi-6-full-run.md`, line 67 failure). GREEN demonstrated in this PR by running the same test against the fix branch.
- **Live-backup test update deferred**: see Risks Accepted #1 — separate Bug or feature scope; the inert XCTSkip-gated method doesn't impact day-to-day Verification suite health.

## Verdict

**ship-as-is.** 2-file, mechanical accessibility-identifier path-traversal fix matching the established Bug #193 / #194 pattern. RED→GREEN demonstrated. The deferred live-backup test scope is documented for a follow-up iteration.
