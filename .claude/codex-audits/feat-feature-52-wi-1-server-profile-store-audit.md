---
branch: feat/feature-52-wi-1-server-profile-store
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Feature #52 WI-1 — WebDAVServerProfile + WebDAVServerProfileStore (audit log)

## Context

WI-1 is the foundational tier of Feature #52 (Multiple WebDAV server
profiles). Adds the value type and actor-isolated store; no UI, no
migration, no factory integration yet (those land in WI-2 / WI-3 /
WI-4a / WI-4b).

Plan: `dev-docs/plans/20260514-feature-52-multiple-webdav-profiles.md`
(shipped in PR #646, v3.21.44). Gate 1 + Gate 2 audit clean.

## Codex availability

Codex MCP unavailable this session. Manual fallback per rule 47.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Services/Backup/WebDAVServerProfile.swift` (new, 56 LOC) | Value type with id/name/serverURL/username; displayName fallback; keychainPasswordAccount static helper | reviewed |
| `vreader/Services/Backup/WebDAVServerProfileStore.swift` (new, 217 LOC) | Actor; UserDefaults-backed; keychain bridging; loadSnapshot atomic read; webdavProfilesDidChange notification | reviewed |
| `vreaderTests/Services/Backup/WebDAVServerProfileTests.swift` (new, ~120 LOC) | 12 value-type tests | reviewed |
| `vreaderTests/Services/Backup/WebDAVServerProfileStoreTests.swift` (new, ~250 LOC) | 20 store tests | reviewed |

## Manual audit evidence

### Files read

- `vreader/Services/AI/ProviderProfile.swift` (full) — mirrored shape: id/name/baseURL/username analog → id/name/serverURL/username. `apiKey`-not-stored decision mirrored as `password`-not-stored.
- `vreader/Services/AI/ProviderProfileStore.swift` (full, 197 LOC) — mirrored actor shape: `.shared` singleton, `loadAll`/`activeProfile`/`activeProfileID`/`loadSnapshot`/`upsert`/`remove`/`setActiveProfileID`/`postDidChangeNotification`. Adapted differences: WI-1 has no migrator yet (lands in WI-2), so the `ensureMigrated()` guard is omitted; instead the store reads UserDefaults directly. JSON corruption defense added at the `readProfiles` level (Gate 2 finding #1) — `ProviderProfileStore` defers this to the migrator's reader.
- `vreader/Services/KeychainService.swift` (lines 73-165) — confirmed `saveString(_:forAccount:)` (line 73), `readString(forAccount:)` (line 85), `delete(forAccount:)` (line 165) signatures. Initial draft used `writeString` (doesn't exist); corrected to `saveString` in WI-1's `writePassword`.
- `vreader/Services/AI/KeychainService+ProviderProfile.swift` (head) — confirmed the pattern `KeychainService.providerAccount(for: profileID) -> String`. WI-1 uses a static helper on `WebDAVServerProfile` itself (`keychainPasswordAccount(for:)`) instead of an extension on KeychainService — simpler call-site shape, less indirection. Functionally equivalent.

### Symbols verified

- `WebDAVServerProfile.Codable + Sendable + Hashable + Identifiable` ✓ — all derived; no manual conformance code needed.
- `WebDAVServerProfileStore.shared` ✓ — `static let` on `actor`; production callers go through this.
- `WebDAVServerProfileStore.init(defaults:keychain:)` ✓ — test-injectable; defaults to `UserDefaults.standard` + `KeychainService()`.
- `Notification.Name.webdavProfilesDidChange` ✓ — extension at file bottom; name is `"com.vreader.webdav.profilesDidChange"` mirroring the AI counterpart's reverse-DNS shape.
- `Logger` declared `nonisolated private static` ✓ — same pattern as bug #183's `ReaderSearchCoordinator.logger` fix. Allows the `nonisolated static` `readProfiles`/`writeProfiles` helpers to log without crossing the actor boundary.
- `UserDefaults` parameter passing: required `nonisolated(unsafe)` on a local binding in `upsert_persistsThroughStoreRecreation` because UserDefaults is thread-safe internally but not declared Sendable. Marker localized to one test; production code passes `UserDefaults.standard` (a global, no crossing).

### Edge cases checked

1. **Empty initial state**: `loadAll` returns `[]`, `activeProfileID` returns nil, `loadSnapshot` returns `([], nil)`. 4 tests cover this.
2. **Upsert ordering preservation**: append-only for new ids, replace-in-place for existing ids. `upsert_preservesOrderWhenAppending` test asserts insertion order is preserved across 3 inserts.
3. **Persistence across store recreation**: `upsert_persistsThroughStoreRecreation` writes via store1, reads via store2 (same defaults backing). Tests the disk round-trip through UserDefaults.
4. **Remove of unknown id**: silently no-ops. Tested.
5. **Remove of active profile**: clears active to nil (the plan's "no fallback to first" decision — UI surfaces the no-active case). Tested.
6. **Remove of non-active profile**: keeps active intact. Tested.
7. **setActiveProfileID(nil)**: clears active. Tested.
8. **setActiveProfileID(unknown UUID)**: recorded but `activeProfile()` returns nil. Tested; matches `ProviderProfileStore` behavior.
9. **JSON corruption** (Gate 2 finding #1): `readProfiles` catches decode errors, logs a warning, returns empty list. Tested by writing invalid bytes directly to UserDefaults under the profiles key.
10. **Malformed UUID string** in active id key: `readActiveID` returns nil (UUID(uuidString:) returns nil for invalid strings). Tested.
11. **Mutation notifications**: `webdavProfilesDidChange` posted on every upsert/remove/setActiveProfileID. 3 tests use a `NotificationExpectation` helper that observes once and flips a flag.
12. **Keychain password deletion on remove**: `remove(id:)` calls `keychain.delete(forAccount:)` best-effort with `try?` swallow. Failures are logged but don't fail the remove (the profile is gone from the list regardless; orphaned keychain entry is dead weight, not a correctness issue).
13. **`UserDefaults.Sendable` crossing**: test helper uses `nonisolated(unsafe)` on the local binding for the one test that passes the same `defaults` instance to two store inits. Single-store tests pass the result of `makeDefaults()` directly to one init (no cross-boundary issue).
14. **`@unchecked Sendable` for NotificationExpectation helper**: marker accepted; the class has only Bool + optional token state, mutations happen on `.main` queue per the observer's queue parameter. Same posture as similar test helpers elsewhere.

### Concurrency / Swift 6

- `WebDAVServerProfile` is `Sendable` via auto-synthesis (all stored properties are Sendable value types: `UUID`, `String`).
- `WebDAVServerProfileStore` is an `actor` — isolation is the safety guarantee. All mutating methods (`upsert`, `remove`, `setActiveProfileID`) are isolated by default. Read methods (`loadAll`, `activeProfile`, `loadSnapshot`) are isolated too, returning by-value snapshots.
- `Logger` declared `nonisolated private static let` — same pattern as bug #183 fix. Allows nonisolated static helpers to log without crossing the actor boundary.
- Static read/write helpers (`readProfiles`, `writeProfiles`, `readActiveID`, `writeActiveID`) declared `nonisolated` — they take `UserDefaults` (thread-safe in practice though not Sendable-declared) as a parameter. Production callers always pass the actor's own `self.defaults` from within the actor's isolation, so the boundary cross is safe.
- `postDidChangeNotification` declared `nonisolated` — `NotificationCenter.default` is thread-safe under Swift 6.
- No new `@unchecked Sendable` types in production code. Test helper `NotificationExpectation` uses `@unchecked Sendable` (Bool flag + optional NSObjectProtocol token); acceptable for test scaffolding.

### VReader compliance

- Swift 6 strict concurrency: clean (`SWIFT_STRICT_CONCURRENCY: complete`).
- `@MainActor` correctness: no MainActor types introduced; store is non-MainActor (matches `ProviderProfileStore`).
- File size: `WebDAVServerProfile.swift` 56 LOC, `WebDAVServerProfileStore.swift` 217 LOC. Both under 300.
- Bridge safety: not applicable (no WKWebView / JS).
- DEBUG gating: not applicable (production code).

### Risks accepted

- **Singleton `.shared`**: same posture as `ProviderProfileStore.shared`. Tests use the explicit init path; production uses `.shared`. Plan section 5 (Gate 2 audit) documents the shared-instance contract.
- **Best-effort keychain cleanup on remove**: `try?` swallows the delete error. The profile is gone from the list regardless; orphan keychain entries are dead weight, not corruption. Same pattern as bug #176's "DebugBridge URL silent failure" acceptance — non-user-facing edge.
- **No XCUITest coverage in WI-1**: WI-1 is foundational (no UI), so XCUITest is out of scope. WI-4a/4b's list + editor PRs will add XCUITest if regression risk surfaces.

### Tests added or intentionally deferred

- **Value type**: 12 tests (Codable round-trip × 2, displayName × 4, keychainPasswordAccount × 3, hashable/equatable × 3). Exceeds plan's "10 tests" target.
- **Store**: 20 tests (empty state × 4, upsert × 4, remove × 4, setActive × 3, loadSnapshot × 1, JSON corruption × 2, notifications × 3, but the plan's `~18 tests` target is matched/exceeded).
- **Migration tests**: deferred to WI-2 (`WebDAVProfileMigrator`).
- **Factory dispatch tests**: deferred to WI-3 (`WebDAVProviderFactoryProfileDispatchTests`).

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — implementation matches plan section 2 + Gate 2 audit fixes (JSON corruption defense, notification name `webdavProfilesDidChange`, displayName fallback) | n/a |

## Final verdict

**ship-as-is** — foundational WI delivers exactly what the plan
specified. 32/32 tests pass (12 + 20). Build clean. No user-observable
behavior change (foundational tier); WI-2 (migrator) + WI-3 (factory)
+ WI-4a/4b (UI) follow.
