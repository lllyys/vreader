---
branch: feat/feature-52-wi-3-factory-and-app-init
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Feature #52 WI-3 — WebDAVProviderFactory profile-store variants + app-init migration (audit log)

## Context

WI-3 of Feature #52 (Multiple WebDAV server profiles). Foundational
tier. Two deliverables per plan section 2.4 + 2.5:
- New `WebDAVProviderFactory.make(profileStore:)` async variant that
  reads credentials from the WI-1 store + WI-2 migrator-populated
  profile (instead of the legacy flat-keychain triplet).
- New `WebDAVProviderFactory.makeRequestBuilder(profileStore:)` async
  variant for the lazy-download path.
- `VReaderApp.init()` wires `WebDAVProfileMigrator.migrateIfNeeded(...)`
  as a fire-and-forget background Task.

Plan: `dev-docs/plans/20260514-feature-52-multiple-webdav-profiles.md`
section 2.4 + 2.5; WI-3 spec at section 4.3.

## Codex availability

Codex MCP unavailable this session (manual fallback per rule 47).
Same posture as bugs #167/#174/#176/#177/#178/#182/#183/#187 +
Feature #52 WI-1/WI-2 audits this session.

## Scope decisions (deliberate divergence from plan wording)

The plan's section 2.4 said: "Existing `make(persistence:keychain:...)`
becomes a thin wrapper that resolves `WebDAVServerProfileStore.shared`
then delegates — keeps legacy callers compiling unchanged."

There's a tension in that wording: the new path REQUIRES `await` to
read the actor-isolated store, so any "thin wrapper" over the legacy
sync `throws` signature would either need to block on a semaphore
(antipattern) or change the signature to `async throws` (which would
NOT keep callers compiling unchanged).

**Decision (matches plan's intent more than its letter)**:
- Add the new async variants alongside the legacy sync variants.
- Leave the legacy sync `make(keychain:)` and `makeRequestBuilder(keychain:)`
  untouched. They continue to read from the flat keychain.
- WI-5 (cleanup) migrates the two existing callers
  (`WebDAVSettingsView.swift:371`, `LibraryView.swift:147`) to the new
  async variants and removes the legacy sync versions.
- WI-3's `VReaderApp.init()` wires the migrator so that by the time
  WI-4a/4b's UI is ready, the store contains the "Default" profile
  mirroring the legacy flat-keychain credentials.

This matches the plan's stated **after-WI-3 outcome** ("backup still
works for existing users via the migrated Default profile. No UI
change yet") — the parallel paths design lets us deliver that
outcome without churning the two legacy call sites in this WI.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Services/Backup/WebDAVProviderFactory.swift` (modified, +95 LOC) | Two new async variants (`make(profileStore:)` + `makeRequestBuilder(profileStore:)`) + 16-line section header explaining the dual-path migration plan | reviewed |
| `vreader/App/VReaderApp.swift` (modified, +21 LOC) | Fire-and-forget `Task.detached(priority: .background) { try await WebDAVProfileMigrator.migrateIfNeeded() }` at the end of the success branch of init() | reviewed |
| `vreaderTests/Services/Backup/WebDAVProviderFactoryProfileDispatchTests.swift` (new, 8 tests, ~200 LOC) | Dispatch contract: active-profile happy path, no-active throws missingCredentials, empty-URL profile throws missingCredentials, no-password throws missingCredentials, malformed URL throws invalidServerURL; same 3 variations for makeRequestBuilder | reviewed |
| `docs/features.md` row #52 | WI-3 shipped note | reviewed |

## Manual audit evidence

### Files read

- `vreader/Services/Backup/WebDAVProviderFactory.swift` (full, pre-edit 128 LOC) — confirmed the two existing public entry points (`make(persistence:keychain:...) throws` and `makeRequestBuilder(keychain:) throws`), their happy/error paths, and their dependency wiring (WebDAVClient + BackupDataCollector + BackupDataRestorer + WebDAVProvider). The new async variants mirror this shape exactly, just substituting profile-store reads for keychain reads.
- `vreader/Services/Backup/WebDAVServerProfileStore.swift` (full, 244 LOC) — confirmed `activeProfile() async -> WebDAVServerProfile?` and `readPassword(for: UUID) async throws -> String?` are the right seams.
- `vreader/Services/Backup/WebDAVProfileMigrator.swift` (full, 109 LOC) — confirmed `migrateIfNeeded(store:keychain:defaults:) async throws` is the right signature; default args resolve to `.shared` + new `KeychainService()` + `.standard`. The migrator is idempotent so the fire-and-forget Task is safe.
- `vreader/App/VReaderApp.swift` (lines 53-280) — confirmed init() structure; `let persistence = PersistenceActor(...)` happens at line 191; `KeychainService()` isn't constructed at init scope (production uses a default-arg instance per call). Placed the migrator Task at the end of the success branch (line ~255) after all other init wiring completes — gives any synchronous-init-fail paths a chance to early-return without scheduling unnecessary work.
- `vreader/Views/Settings/WebDAVSettingsView.swift` lines 365-382 — confirmed the single `try WebDAVProviderFactory.make(...)` call site is in an `async` function (`loadBackups()`), so a future WI-5 migration to `try await WebDAVProviderFactory.make(profileStore:)` is a one-line change.
- `vreader/Views/LibraryView.swift` lines 112-158 — confirmed the `try WebDAVProviderFactory.makeRequestBuilder()` call site is in an `.onReceive` closure (sync context). WI-5 will need to wrap that block in `Task { @MainActor in ... }`.
- `vreaderTests/Services/Backup/WebDAVServerProfileStoreTests.swift` (test patterns) — confirmed `nonisolated(unsafe) let defaults = makeDefaults()` is the right pattern for UserDefaults crossings; replicated in the new dispatch tests.

### Symbols verified

- `WebDAVServerProfileStore.activeProfile() async -> WebDAVServerProfile?` ✓
- `WebDAVServerProfileStore.readPassword(for: UUID) async throws -> String?` ✓
- `WebDAVServerProfileStore.upsert(_:) async` ✓ — exposed by store, used in tests.
- `WebDAVServerProfileStore.writePassword(_:for:) async throws` ✓ — exposed by store, used in tests.
- `WebDAVServerProfileStore.setActiveProfileID(_:) async` ✓ — exposed by store, used in tests.
- `WebDAVServerProfile.init(id:name:serverURL:username:)` ✓ — confirmed parameter order from WI-1.
- `KeychainService.init(serviceIdentifier:)` ✓ — test-isolated keychain pattern.
- `PersistenceActor.init(modelContainer:)` ✓ — confirmed to build with in-memory SwiftData container.
- `SchemaV6.models` ✓ — current schema used by tests; matches what VReaderApp.init uses.
- `WebDAVProviderFactoryError.{missingCredentials, invalidServerURL}` ✓ — existing error cases; no new cases needed (plan section 2.4 confirms).
- `Task.detached(priority: .background) { ... }` ✓ — fire-and-forget; no return-value retention concern.

### Edge cases checked

1. **No active profile** (`activeProfileID` is nil, or `activeProfile()` returns nil): factory throws `missingCredentials`. **Test: `make_withNoActiveProfile_throwsMissingCredentials`.**
2. **Active profile with empty URL** (`profile.serverURL.isEmpty`): factory throws `missingCredentials` (NOT `invalidServerURL` — we want a uniform "the user hasn't set up credentials yet" error class, not a URL-parse error). **Test: `make_withActiveButEmptyURL_throwsMissingCredentials`.**
3. **Active profile with no password** (per-profile keychain slot is empty/nil): factory throws `missingCredentials`. The plan deliberately keeps "credentials" as the umbrella error so the UI surfaces "Add a server in WebDAV Settings" rather than format-specific text. **Test: `make_withActiveButNoPassword_throwsMissingCredentials`.**
4. **Active profile with malformed URL**: factory throws `invalidServerURL(serverURL)` carrying the bad string for UI surfacing. **Test: `make_withMalformedURL_throwsInvalidServerURL`.**
5. **`makeRequestBuilder` parity**: same 4 cases mirrored. **Tests: `makeRequestBuilder_withActiveProfileAndPassword_succeeds`, `makeRequestBuilder_withNoActiveProfile_throwsMissingCredentials`, `makeRequestBuilder_withMalformedURL_throwsInvalidServerURL`.**
6. **Migrator fire-and-forget timing**: `WebDAVProfileMigrator.migrateIfNeeded()` runs idempotently. If the user opens WebDAV Settings BEFORE the migration completes, they see an empty profile list (no Default). That's acceptable because: (a) the legacy `WebDAVProviderFactory.make(keychain:)` path still works for "Back Up Now" via flat keychain reads, so backup itself doesn't break; (b) the migrator is idempotent so a subsequent launch completes it. WI-5's call-site migration will be timed AFTER UI ships (WI-4a/4b) and after a release of dwell so users have had multiple launches for the migrator to run.
7. **PersistenceActor sendability**: passing `PersistenceActor` to the factory across an actor hop is safe because `PersistenceActor` is an `actor` (Sendable by virtue of being an actor type).
8. **VReaderApp.init exception path**: the migrator Task is only scheduled inside the `success` branch of init's `try` block. If init throws (corrupt DB, etc.), no migration is scheduled — appropriate because the app is failing to start anyway.

### Concurrency / Swift 6

- New variants are `@MainActor static func ... async throws`. The `await profileStore.activeProfile()` and `try await profileStore.readPassword(for:)` calls are explicit actor hops.
- `Task.detached(priority: .background)` in `VReaderApp.init()` runs on the generic executor. The closure body uses `await` to hop into the migrator's actor (the store). No retention concern — the Task is "fire and forget" but the migrator does its work and the Task body completes naturally. The DEFAULT closure capture (strong on `self` of any captured types) is correct here because the closure references only the migrator's static API + no other state from `VReaderApp` init.
- Build clean under `SWIFT_STRICT_CONCURRENCY: complete`.

### VReader compliance

- Swift 6 strict concurrency: clean.
- `@MainActor` correctness: factory's new variants are `@MainActor` (matches existing variants); fire-and-forget Task is `Task.detached` so it doesn't inherit MainActor (correct because it just awaits the migrator's static async function).
- File size: `WebDAVProviderFactory.swift` 223 LOC (was 128, +95). Under 300.
- Bridge safety: not applicable.
- DEBUG gating: not applicable (production code).
- Per `.claude/rules/50-codebase-conventions.md`: error handling via `throws`, no bare print.

### Risks accepted

- **Parallel paths until WI-5**: legacy sync variants coexist with new async variants. Acceptable per the plan's after-WI-3 outcome statement. Cleanup is WI-5's responsibility.
- **Fire-and-forget migrator may not complete before user opens settings**: documented above (edge case 6). WI-5 + WI-4a/4b will provide a definitive UI fallback ("loading profiles..." spinner if needed); WI-3 just ensures the store eventually catches up.
- **WebDAVProvider integration test doesn't introspect the provider's internal client**: tests assert no-throw for the happy path; the integration test for round-trip backup-then-restore against the live store is deferred to WI-6 (final acceptance).

### Tests added

- `vreaderTests/Services/Backup/WebDAVProviderFactoryProfileDispatchTests.swift` — 8 tests (matches plan section 5 target of "8 dispatch tests"):
  - `make_withActiveProfileAndPassword_returnsWebDAVProvider` — happy path
  - `make_withNoActiveProfile_throwsMissingCredentials`
  - `make_withActiveButEmptyURL_throwsMissingCredentials`
  - `make_withActiveButNoPassword_throwsMissingCredentials`
  - `make_withMalformedURL_throwsInvalidServerURL`
  - `makeRequestBuilder_withActiveProfileAndPassword_succeeds`
  - `makeRequestBuilder_withNoActiveProfile_throwsMissingCredentials`
  - `makeRequestBuilder_withMalformedURL_throwsInvalidServerURL`

All 8 pass under `xcodebuild test -only-testing:vreaderTests/WebDAVProviderFactoryProfileDispatchTests`.

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — foundational WI delivers the contract the plan named; parallel-paths design documented as deliberate divergence from plan wording but matches plan's stated after-WI-3 outcome | n/a |

## Final verdict

**ship-as-is** — foundational WI delivers exactly what the plan
specified: two new async profile-store-backed factory variants
+ 8 dispatch tests + migrator wiring in app init. Both new variants
pass 8/8 tests; build clean. Migrator's idempotency makes the
fire-and-forget Task safe.  No user-observable behavior change at
this WI (legacy callers continue to read flat keychain); WI-4a/4b
adds the UI that depends on these variants, then WI-5 migrates
legacy callers and removes the legacy variants.
