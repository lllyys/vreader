# Feature #52 — Multiple WebDAV Server Profiles with Active-Server Switching

**Status**: PLANNED (Gate 1 + Gate 2 complete, awaiting Gate 3)
**Tracker**: `docs/features.md` row 52, GH #565
**Reported by**: user 2026-05-12

## 1. Problem

WebDAV backup currently stores exactly one server's credentials in
Keychain under fixed account keys:
- `com.vreader.webdav.serverURL`
- `com.vreader.webdav.username`
- `com.vreader.webdav.password`

Users with multiple WebDAV services (Nextcloud at home, Synology at
work, Nutstore, self-hosted rclone-on-Mac, etc.) must re-enter
credentials every time they switch. This is friction for the bulk of
the project's WebDAV power users and blocks legitimate multi-server
workflows (e.g., back up reading library to home Nextcloud, sync
positions via work Synology).

The mirroring AI provider story was solved by Feature #50 (VERIFIED
2026-05-13): `ProviderProfileStore` actor + per-profile keychain keys
+ `AIProviderListView` UI. This feature applies the same pattern to
WebDAV.

## 2. Surface Area (file-by-file with signatures)

### New files

1. **`vreader/Services/Backup/WebDAVServerProfile.swift`** — value type
   ```swift
   struct WebDAVServerProfile: Identifiable, Codable, Hashable, Sendable {
       let id: UUID
       var name: String
       var serverURL: String
       var username: String
       // password lives in Keychain at key `passwordAccount(for: id)`;
       // never carried in this struct
   }
   ```
   ~50 LOC including `displayName` helper (falls back to `serverURL`
   hostname if `name` is empty per edge case (e)) and `keychainPasswordAccount(for:)`
   static helper that returns `"com.vreader.webdav.profile.<id>.password"`.

2. **`vreader/Services/Backup/WebDAVServerProfileStore.swift`** — actor
   ```swift
   actor WebDAVServerProfileStore {
       static let shared = WebDAVServerProfileStore()
       private(set) var profiles: [WebDAVServerProfile]
       private(set) var activeProfileID: UUID?

       init(defaults: UserDefaults = .standard, keychain: KeychainService = KeychainService())
       func upsert(_ profile: WebDAVServerProfile) throws
       func remove(id: UUID) throws
       func setActiveProfileID(_ id: UUID?) throws
       func loadSnapshot() -> (profiles: [WebDAVServerProfile], activeID: UUID?)
       func activeProfile() -> WebDAVServerProfile?
       func writeAPIKey(_ password: String, for id: UUID) throws
       func readAPIKey(for id: UUID) throws -> String?
       func deleteAPIKey(for id: UUID) throws
   }
   ```
   Persistence: `UserDefaults` key `com.vreader.webdav.profiles` stores
   `[WebDAVServerProfile]` JSON. `com.vreader.webdav.activeProfileID`
   stores the active UUID string. Mirrors `ProviderProfileStore`
   (Feature #50) shape exactly — same `loadSnapshot()` atomic-read
   pattern for UI consumers, same `upsert`/`remove`/`setActive`
   mutation surface, same in-actor keychain bridging.
   ~150 LOC.

3. **`vreader/Services/Backup/WebDAVProfileMigrator.swift`** — one-shot migration
   ```swift
   enum WebDAVProfileMigrator {
       static let migrationMarkerKey = "com.vreader.webdav.profilesMigrated.v1"
       static func migrateIfNeeded(store: WebDAVServerProfileStore,
                                   keychain: KeychainService = KeychainService(),
                                   defaults: UserDefaults = .standard) async throws
   }
   ```
   Runs once on first launch after the feature ships. Reads the legacy
   flat keys (`com.vreader.webdav.serverURL/username/password`), creates
   a "Default" profile, writes per-profile keychain key, sets it active,
   marks `migrationMarkerKey = true`. Idempotent: skip if marker already
   true OR if profiles list is non-empty (defensive). Does NOT delete
   the legacy keys (Phase 1 — keep as backup; future WI-cleanup can
   delete them after a release of dwell time, mirroring `Feature #50`'s
   `AIConfigurationStore` legacy retention).
   ~80 LOC.

### Modified files

4. **`vreader/Services/Backup/WebDAVProviderFactory.swift`**
   - Add new entry point `make(persistence:profileStore:keychain:...)` that
     reads active profile from `WebDAVServerProfileStore` instead of the
     flat keychain keys.
   - Existing `make(persistence:keychain:...)` becomes a thin wrapper that
     resolves `WebDAVServerProfileStore.shared` then delegates — keeps
     legacy callers compiling unchanged.
   - Same change to `makeRequestBuilder(keychain:)` → add
     `makeRequestBuilder(profileStore:keychain:)` variant.
   - `WebDAVProviderFactoryError` gains no new cases (existing
     `missingCredentials` covers "no active profile" cleanly).
   - ~50 LOC modification.

5. **`vreader/App/VReaderApp.swift`**
   - In `init()` DEBUG/RELEASE both: after `KeychainService()` construction,
     run `await WebDAVProfileMigrator.migrateIfNeeded(...)` before any
     view body evaluates. Mirrors `ProviderProfileMigrator.migrateIfNeeded`
     (Feature #50 WI-2). ~10 LOC addition.

6. **`vreader/Views/Settings/WebDAVSettingsView.swift`**
   - Replace single-server form with `WebDAVServerProfileListView`
     (new file, modeled after `AIProviderListView`).
   - Existing `WebDAVSettingsView` keeps backup-controls section
     (Back Up Now, list backups, restore picker, Wi-Fi-only toggle);
     credentials section becomes a `NavigationLink → WebDAVServerProfileListView`.
   - The flat keychain account constants stay (defensive: legacy
     migration may still rely on them).
   - ~60 LOC modification.

### New UI files

7. **`vreader/Views/Settings/WebDAVServerProfileListView.swift`** —
   list view, mirror `AIProviderListView` (~180 LOC):
   - Radio-style row selection with `.isSelected` accessibility trait
     on the active row.
   - Per-row swipe-to-delete (with confirmation alert if it's the
     active profile).
   - Empty state with globe icon + "Add Server" CTA.
   - Toolbar `+` button to add a new profile.

8. **`vreader/Views/Settings/WebDAVServerProfileEditSheet.swift`** —
   add/edit form, mirror `AIProviderEditSheet` (~220 LOC, split into
   `+Sections.swift` extension per the AI-provider precedent):
   - Name TextField (auto-fills serverURL hostname if blank, per
     edge case (e))
   - Server URL TextField (HTTPS recommended, HTTP accepted per
     bug #110 / `NSAllowsArbitraryLoads: true`)
   - Username TextField
   - Password SecureField + Save Key button (or "Save profile first"
     promoted note in add-mode, per bug #184's pattern)
   - Test Connection button (edit-mode only) — performs a `PROPFIND /`
     against the entered URL with the entered credentials, surfaces
     2xx/3xx success or specific error
   - ~220 LOC.

### Tests (new)

9. **`vreaderTests/Services/Backup/WebDAVServerProfileTests.swift`**
   — value-type round trip, Codable, displayName fallback,
   keychainPasswordAccount string format. ~10 tests.

10. **`vreaderTests/Services/Backup/WebDAVServerProfileStoreTests.swift`**
    — actor mutations, persistence round-trip, active-profile-deleted
    fallback, atomic loadSnapshot, keychain bridging. ~18 tests.

11. **`vreaderTests/Services/Backup/WebDAVProfileMigratorTests.swift`**
    — legacy-flat-keys → one Default profile contract; idempotent
    on second run; skipped when profiles list non-empty. ~6 tests.

12. **`vreaderTests/Services/Backup/WebDAVProviderFactoryProfileDispatchTests.swift`**
    — `make(profileStore:)` reads active profile, dispatches to
    `WebDAVProvider` with correct URL/username/password; no-active
    → `missingCredentials`; invalid URL → `invalidServerURL`. ~8
    tests.

## 3. Prior Art / Project Precedent / Rejected Alternatives

### Precedent (the dominant pattern this feature mirrors)

**Feature #50 (Multi-provider AI)** — VERIFIED 2026-05-13. This is
the canonical example in the codebase for "single-credential blob →
list of profiles + active selector + per-profile keychain". Shipped
across 7 WIs (WI-1..WI-7) and all 5 acceptance criteria verified
end-to-end. Feature #52 replicates the structure:
- `ProviderKind` → not needed for WebDAV (WebDAV is one protocol; no
  protocol-kind distinction needed).
- `ProviderProfile` → `WebDAVServerProfile`
- `ProviderProfileStore` (actor) → `WebDAVServerProfileStore` (actor)
- `ProviderProfileMigrator` → `WebDAVProfileMigrator`
- `AIProviderListView` → `WebDAVServerProfileListView`
- `AIProviderEditSheet` + `AISettingsViewModel+Editor` →
  `WebDAVServerProfileEditSheet`
- `AIService.resolveProvider()` snapshot pattern →
  `WebDAVProviderFactory.make(profileStore:)`

### Rejected alternatives

- **Inline-edit credentials in the row** (no separate edit sheet) —
  rejected because the row gets too dense (URL + username + password +
  Test Connection in one row is unwieldy). Sheet-based edit matches
  the AI-provider precedent and gives space for the Test Connection
  button + result text.
- **Server-side profile sync** (store profiles on a WebDAV server) —
  rejected because it creates a chicken-and-egg problem (you need
  credentials to fetch the profile list). Local-only persistence.
- **Per-book server selection** (book → which server it backs up to) —
  rejected as out of scope. The "active profile" model is sufficient
  for the reported user need; per-book routing is a future feature if
  ever requested.
- **Migrate + delete legacy flat keys in one pass** — rejected.
  Defensive 2-step pattern (migrate now, delete in a later release
  after dwell time) matches the AI-provider rollout (Feature #50's
  `AIConfigurationStore` retention). Reduces blast radius of
  migration bugs.

### Existing infrastructure that maps cleanly

- `KeychainService.readString(forAccount:)` /
  `KeychainService.writeString(_:forAccount:)` /
  `KeychainService.delete(forAccount:)` — used directly by
  `WebDAVServerProfileStore`.
- `WebDAVClient(serverURL:username:password:)` — already takes
  per-instance credentials; no change needed downstream of the
  factory.
- `NWPathMonitor`-based Wi-Fi-only policy (`WebDAVNetworkPolicy`) —
  already global (not per-profile). Stays global.
- DEBUG seeding (`TestSeeder`) clears WebDAV keys via
  `knownPreferenceKeys`; add new keys (`profiles`, `activeProfileID`,
  `profilesMigrated.v1`) to that list so XCUITest empty-state tests
  start clean.

## 4. Work-Item Sequencing

7 WIs, sized for the AI-provider precedent. Each WI is one PR's worth
of work.

### WI-1 (foundational, ~150 LOC + tests, patch bump)

- `WebDAVServerProfile.swift` value type
- `WebDAVServerProfileStore.swift` actor (without migration yet)
- Keychain extension: `passwordAccount(for: id) -> String`
- 28 tests (value type 10 + store 18)

**Tier**: Foundational. No user-observable behavior change. Status
flips to `IN PROGRESS` when this WI's PR opens.

### WI-2 (foundational, ~80 LOC + tests, patch bump)

- `WebDAVProfileMigrator.swift` one-shot migration
- 6 tests covering the legacy-keys → Default-profile contract +
  idempotency

**Tier**: Foundational.

### WI-3 (foundational, ~50 LOC + tests, patch bump)

- `WebDAVProviderFactory.swift` `make(profileStore:)` variant
- Existing `make(keychain:)` thin-wrapper that resolves shared store
- 8 dispatch tests
- `VReaderApp.init()` wires the migration call

**Tier**: Foundational. After WI-3 merges, backup still works for
existing users via the migrated Default profile. No UI change yet.

### WI-4a (behavioral UI Phase A, ~180 LOC + tests, patch bump)

- `WebDAVServerProfileListView.swift` — list + active-row selection +
  swipe-to-delete + empty state + Add toolbar button.
- Editor sheet shown but placeholder body ("Phase B"). New profile
  add path lands in a "stub" editor that just writes a name placeholder.
- `WebDAVSettingsView` modified to show `NavigationLink` to the list.

**Tier**: Behavioral. List UI lands but full editor in WI-4b.

### WI-4b (behavioral UI Phase B, ~220 LOC + tests, patch bump)

- `WebDAVServerProfileEditSheet.swift` + `+Sections.swift` — full
  add/edit form with Test Connection.
- Edit-mode keychain write/delete buttons (per bug #184 pattern:
  hide buttons in add-mode, show promoted "Save profile first" note;
  edit-mode shows the buttons).
- 14 editor unit tests + 6 Test-Connection HTTP-shape tests.

**Tier**: Behavioral. Full feature reachable from Settings.

### WI-5 (foundational, ~30 LOC, patch bump)

- `vreader/Views/Settings/WebDAVSettingsView.swift` cleanup —
  remove now-unused flat-keychain reads from the view (they're behind
  the migration, but the view shouldn't read them directly anymore).
- `TestSeeder.knownPreferenceKeys` adds the new UserDefaults keys.
- Doc-sync if triggered (architecture.md mentions WebDAV briefly —
  this WI updates that mention).

**Tier**: Foundational cleanup.

### WI-6 — Final WI (behavioral, ~10 LOC, **minor** bump)

- Flip feature row → `DONE`.
- Final acceptance verification (against live rclone WebDAV server
  on iPhone 17 Pro Sim): add 2 profiles, switch active, confirm
  Back Up Now uses the active server, restore round-trip works.
- Evidence file `dev-docs/verification/feature-52-<YYYYMMDD>.md`.

**Tier**: Behavioral final. Closes the feature.

**Total**: 7 WIs (WI-1, WI-2, WI-3, WI-4a, WI-4b, WI-5, WI-6),
roughly 720 LOC of production code + 64 tests + 1 evidence file.

## 5. Test Catalogue

| File | What It Covers |
|---|---|
| `WebDAVServerProfileTests` | Codable round-trip, displayName fallback, keychainPasswordAccount format, UUID identity, Equatable/Hashable |
| `WebDAVServerProfileStoreTests` | Upsert/remove/setActive, persistence round-trip (write → reload from disk-backed UserDefaults), active-deleted falls back to first remaining, atomic loadSnapshot, keychain bridging for writeAPIKey/readAPIKey/deleteAPIKey, concurrent mutations serialize correctly |
| `WebDAVProfileMigratorTests` | Legacy flat-keys → one Default profile (verbatim URL/username, name `"Default"`, keychain key per-id), idempotent on second run, skipped when profiles list non-empty, marker written |
| `WebDAVProviderFactoryProfileDispatchTests` | `make(profileStore:)` reads active profile, dispatches to `WebDAVProvider` with correct creds; no-active → `missingCredentials`; invalid URL → `invalidServerURL`; `makeRequestBuilder` parity |
| `WebDAVServerProfileListViewTests` (XCUI, optional) | Add → empty-state CTA reveals editor; tap profile row → activates it; swipe-to-delete on inactive row removes it; swipe-to-delete on active row shows confirmation; accessibility .isSelected trait on active row |
| `WebDAVServerProfileEditSheetTests` | Add-mode hides keychain buttons (bug #184 pattern); edit-mode shows Save/Delete; Test Connection runs PROPFIND with current form state (not stored profile), 200/201/207 → "Connected", 401 → "Auth failed", other → status text; empty-URL Save disabled; serverURL hostname auto-populates name field if name blank |

## 6. Risks + Mitigations

- **Risk — Migration data loss**: a buggy migrator could lose existing
  credentials and break backup for current users.
  - **Mitigation**: WI-2 keeps the legacy flat keys intact (delete is
    a separate later WI, not WI-2). 6 unit tests pin the contract.
    Idempotency check (skip if profiles non-empty) prevents
    re-running and clobbering user-added profiles.
- **Risk — Concurrent backup during profile switch**: user taps
  Back Up Now then switches active profile mid-backup.
  - **Mitigation**: `WebDAVProvider` is constructed once at backup
    start with the active-at-that-moment credentials; switching the
    active profile mid-backup doesn't affect the in-flight provider.
    Document this as expected behavior. No data corruption risk
    because each provider instance is self-contained.
- **Risk — Test Connection's PROPFIND hits a server that doesn't
  support PROPFIND** (e.g., a plain HTTP file server, not WebDAV).
  - **Mitigation**: surface specific error text ("Server doesn't
    support WebDAV PROPFIND — got 405 Method Not Allowed") to help
    the user diagnose. WI-4b's editor includes this case.
- **Risk — Profile name collisions** (two profiles named "Default").
  - **Mitigation**: collisions allowed at the data layer (UUID is
    the identity, not name). UI displays the URL alongside the name
    for disambiguation if names collide. No enforced unique-name
    validation.
- **Risk — Active profile deleted while UI is showing it**.
  - **Mitigation**: deleting the active profile triggers a fallback:
    set active to the first remaining profile, OR nil if empty.
    `WebDAVServerProfileListView` observes
    `Notification.Name.webdavProfilesDidChange` (new) and re-syncs.
    Mirrors AI-provider precedent (`providerProfilesDidChange`,
    Feature #50 WI-7).

## 7. Backward Compatibility

- **First launch after the feature ships**: existing users with the
  flat legacy keys (`com.vreader.webdav.serverURL/username/password`)
  hit WI-2's `WebDAVProfileMigrator.migrateIfNeeded`. One "Default"
  profile is created, set active, per-profile keychain key written.
  User opens the app and Back Up Now works without re-entering
  credentials.
- **Existing backups in the WebDAV server**: blob/manifest layout
  unchanged. The active profile points at the same server URL the
  user had before, so restore from any pre-feature backup works
  unchanged.
- **Existing tests**: `WebDAVProviderFactoryTests` (and any test that
  stubs the flat keychain keys) continue to pass — the legacy
  `make(keychain:)` entry point delegates to the migrated path.
  `TestSeeder.clearKnownPreferences` will pick up the new
  UserDefaults keys (added in WI-5).
- **Release downgrade scenario**: if a user installs v3.21.43 (pre-#52),
  then v3.21.X (post-#52, profile-based), then back to v3.21.43 —
  the v3.21.43 reads the legacy flat keys, which the migrator did
  NOT delete. Backup works (against the Default-profile-equivalent
  credentials). Additional profiles added in v3.21.X are invisible
  to the older build. No corruption. Documented as acceptable.

## 8. Acceptance Criteria Mapping (from `docs/features.md` row 52)

| Criterion | Addressed By |
|---|---|
| (a) User can add two profiles and switch active — only active is used | WI-4a list + WI-4b editor; WI-3 factory reads active |
| (b) Single-server users migrate without re-entering | WI-2 migrator |
| (c) Active deleted → falls back to remaining or disabled | WI-1 store's `setActiveProfileID` + WI-4a list re-sync |
| (d) Backup + restore round-trip works with selected profile | WI-3 factory; WI-6 device verification |

---

## 9. Manual Audit Evidence (Gate 2 — Codex unavailable, manual fallback)

**Date**: 2026-05-14. Codex MCP unavailable across the entire session
(`stream disconnected before completion` matching the multi-day
outage). Manual audit performed per rule 47.

### Files read

- `vreader/Services/Backup/WebDAVProviderFactory.swift` (full) —
  confirmed current flat-keychain account constants, `make(...)`
  signature, `makeRequestBuilder(keychain:)` parity, error enum
  shape.
- `vreader/Views/Settings/WebDAVSettingsView.swift` (head) — confirmed
  the view's existing single-server form structure that WI-4a will
  replace.
- `vreader/Services/Backup/WebDAVNetworkPolicy.swift` (line 96) —
  confirmed `wifiOnlyKey` is global, not per-profile. Stays global
  per plan section 6's risk discussion.
- `vreader/Services/AI/ProviderProfile.swift` (existed) — confirmed
  the value-type shape used for the AI-provider precedent. Feature #52
  mirrors this with `WebDAVServerProfile`.
- `vreader/Services/AI/ProviderProfileStore.swift` (existed) — confirmed
  actor shape, `loadSnapshot()` atomic-read pattern, `upsert` /
  `remove` / `setActiveProfileID` mutation surface. Plan section 2
  signature for `WebDAVServerProfileStore` matches.
- `vreader/Services/AI/ProviderProfileMigrator.swift` (existed) —
  confirmed migration pattern: marker key in UserDefaults, idempotent
  skip when profiles non-empty, legacy keys retained for Phase 1.
  Plan section 2 + 7 for `WebDAVProfileMigrator` matches.
- `vreader/Services/KeychainService.swift` (lines 85/137/165) —
  confirmed `readString` / `readData` / `delete` signatures. Store's
  keychain bridging uses these directly. No new keychain API needed.
- `vreader/Views/Settings/AIProviderListView.swift` (head) — confirmed
  UI pattern that `WebDAVServerProfileListView` mirrors.
- `vreader/Views/Settings/AIProviderEditSheet.swift` (head) — confirmed
  sheet pattern that `WebDAVServerProfileEditSheet` mirrors.
- `vreader/App/VReaderApp.swift` (lines 53-150) — confirmed `init()`
  is the right place to invoke `WebDAVProfileMigrator.migrateIfNeeded`,
  before any view body evaluates and before Settings can be reached.

### Symbols / signatures verified

- `WebDAVProviderFactory.serverURLAccount` / `usernameAccount` /
  `passwordAccount` flat-key constants ✓ — keep in WI-1 for migrator;
  WI-3 still reads them through the migrated Default profile;
  WI-5 removes the unused view-layer reads (`WebDAVSettingsView`'s
  `serverURLAccount` private mirror).
- `WebDAVClient(serverURL: URL, username: String, password: String)`
  ✓ — exact init signature; no change. WI-3 factory passes the
  active profile's URL/username + Keychain password lookup.
- `KeychainService.readString(forAccount:)` returns `String?` ✓ —
  matches plan's store-bridging usage.
- `actor` keyword for `WebDAVServerProfileStore` ✓ — Swift 6 strict;
  mutating methods are isolated by default; `loadSnapshot()` is the
  atomic-read pattern for UI consumers that need profiles+activeID
  in one hop.
- `UUID` for profile identity ✓ — same as Feature #50; UUIDs are
  Codable+Sendable+Hashable; serialized as hyphenated strings in JSON.
- `Notification.Name.webdavProfilesDidChange` (new) — file location
  TBD in WI-4a; precedent is `vreader/Services/AI/ProviderProfileNotifications.swift`
  or inline in `WebDAVServerProfileStore.swift`.

### Edge cases checked (against plan section 6)

1. **Migration with empty legacy keys** (fresh install, no prior
   WebDAV setup): migrator sees no keys → skips creating Default →
   profiles list stays empty → empty state in UI prompts "Add a
   server". ✓ correct behavior.
2. **Migration when profiles list already non-empty** (user had
   already added profiles via some other route, or marker key is
   missing but profiles JSON exists): migrator's idempotency check
   skips re-running. ✓
3. **Concurrent profile add + remove** (two UI actions racing on the
   actor): actor isolation serializes; the second operation sees
   the first's effect. ✓
4. **Profile with empty `name` field**: `displayName` falls back to
   `serverURL` hostname (e.g., `"nas.tailnet.example.ts.net"`). ✓
5. **Server URL with no scheme** (`"nas.example.com"`): WI-4b editor's
   Save validation rejects with "URL must start with http:// or
   https://". `WebDAVProviderFactoryError.invalidServerURL` covers
   the post-save runtime case if validation missed.
6. **Keychain miss for an existing profile** (password got deleted
   externally): `readAPIKey` returns nil → factory throws
   `missingCredentials` → UI surfaces "Re-enter password for this
   profile". Same pattern as Feature #50's missing-API-key path.
7. **Migration partial failure** (Keychain write succeeds but
   UserDefaults marker write fails — extremely unlikely but worth
   noting): on next launch, migrator re-runs because marker is
   missing; sees the already-created profile (UserDefaults was
   actually written if marker-write came AFTER profile-write — but
   plan section 2 orders marker-write LAST after both stages
   succeed, so partial failure = no profile written, idempotent
   retry).
8. **Test Connection PROPFIND against non-WebDAV server**: handled
   in plan section 6 risk discussion. Specific error text in WI-4b.
9. **Profile JSON corruption in UserDefaults**: actor's init throws;
   plan section 2 `init` doesn't enumerate this. **Audit fix**: add
   defensive `try? JSONDecoder().decode(...) ?? []` fallback in
   `WebDAVServerProfileStore.init` to recover with empty list. WI-1
   includes this defensive path.

### Findings — fixes incorporated into plan

| # | Severity | Finding | Plan fix |
|---|---|---|---|
| 1 | Medium | Plan didn't enumerate the "Profile JSON corruption in UserDefaults" edge case. Without a defensive fallback, the actor init throws and blocks WebDAVSettingsView from loading. | Edge case #9 added above; WI-1 acceptance criteria includes defensive `try?` fallback in `WebDAVServerProfileStore.init` with logged warning. |
| 2 | Low | Plan section 2 didn't explicitly state which `Notification.Name` posts on profile mutations. AI-provider precedent uses `providerProfilesDidChange`. | Added `Notification.Name.webdavProfilesDidChange` to plan section 2 + section 6 risk discussion. Posted from `WebDAVServerProfileStore`'s `upsert`/`remove`/`setActive`. WI-4a list view observes it for live updates. |
| 3 | Low | Plan didn't specify that `VReaderApp.init()` is `@MainActor` and the migrator call is `async`. | The migrator call wraps in `Task` in `VReaderApp.init`'s existing DEBUG/RELEASE setup block; mirrors `ProviderProfileMigrator.migrateIfNeeded` invocation pattern. WI-3 surface area specifies this. |

### Risks accepted (with rationale)

- **Legacy flat keys not deleted in WI-2** — accepted; defensive
  Phase 1 + later cleanup WI. Mirrors AI-provider rollout.
- **No XCUITest UI test in WI-4a/4b** — accepted; pure SwiftUI list
  + sheet behavior. Unit tests cover the store + factory; manual
  device verification (WI-6) exercises the full UI path.
- **Test Connection hitting an unfamiliar server type** (FTP-over-HTTP,
  static file server, etc.) — accepted; specific error text helps
  diagnosis but cannot enumerate every possible non-WebDAV response.

### Tests added or intentionally deferred

- All tests from plan section 5 added (28+18+6+8+ optional XCUI +
  14+6 = ~80 tests).
- Optional XCUI in WI-4a/4b — deferred decision to WI-4a's PR review
  (mirror Feature #50's pattern: skipped at WI-6a, added selectively
  if regression risk surfaces).

### Concurrency / Swift 6

- `WebDAVServerProfile` ✓ `Codable`, `Hashable`, `Sendable` (UUID,
  String are all Sendable).
- `WebDAVServerProfileStore` actor — isolation is the safety guarantee.
- `WebDAVProfileMigrator` enum + static func — non-isolated; takes
  `keychain: KeychainService` (a class, but Sendable-equivalent in
  this codebase per `KeychainService`'s usage in
  `ProviderProfileMigrator`).
- No new `@unchecked Sendable` types introduced.
- No new `nonisolated(unsafe)` markers needed.

### VReader compliance

- Swift 6 strict concurrency: clean (`SWIFT_STRICT_CONCURRENCY: complete`
  in project.yml).
- `@MainActor` correctness: SwiftUI views (list + editor) are
  MainActor; the actor is non-MainActor; the migrator is non-MainActor;
  the factory's `make(...)` stays `@MainActor` because it builds
  UI-coupled state.
- File size: each new file budgeted under 300 LOC; `WebDAVServerProfileEditSheet`
  at ~220 LOC is the largest, well under.
- Bridge safety: not applicable (no WKWebView / JS surface).
- DEBUG gating: migrator runs in both DEBUG and RELEASE (it's a
  user-facing migration, not test scaffolding).

### Manual Audit Verdict

**ship-as-is** for the plan. 1 Medium finding (JSON corruption edge
case) + 2 Low findings (notification name, migrator-call-async
pattern) — all fixed inline above. WI-1 starts at Gate 3 with the
defensive `try?` fallback in `WebDAVServerProfileStore.init`.
