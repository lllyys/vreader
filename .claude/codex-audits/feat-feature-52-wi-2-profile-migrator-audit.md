---
branch: feat/feature-52-wi-2-profile-migrator
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Feature #52 WI-2 — WebDAVProfileMigrator (audit log)

## Context

WI-2 of Feature #52 (Multiple WebDAV server profiles). Foundational
tier: one-shot migration from the pre-#52 flat-Keychain triplet
(`com.vreader.webdav.serverURL/username/password`) to the WI-1
profile store, creating a single "Default" profile and copying the
password to the new per-profile keychain slot.

Plan: `dev-docs/plans/20260514-feature-52-multiple-webdav-profiles.md`
section 2.3 / 4 / 5. Plan + Gate 2 audit shipped in PR #646; WI-1
foundation shipped in PR #648.

## Codex availability

Codex MCP unavailable this session (manual fallback per rule 47).
Same posture as bugs #167/#176/#177/#178/#183/#174 + Feature #52 WI-1
audits in this session.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Services/Backup/WebDAVProfileMigrator.swift` (new, 109 LOC) | enum with single static async `migrateIfNeeded(store:keychain:defaults:)` + legacy keychain account constants | reviewed |
| `vreaderTests/Services/Backup/WebDAVProfileMigratorTests.swift` (new, 6 tests, ~210 LOC) | fresh-install / legacy-migration / partial-legacy / marker-set / store-non-empty / repeat-call idempotency | reviewed |

## Manual audit evidence

### Files read

- `vreader/Services/AI/ProviderProfileMigrator.swift` (full, 246 LOC) — the canonical precedent. Decision: deliberately match the plan's simpler ~80 LOC shape (enum + single async function) rather than the protocol-based crash-recovery shape, because:
  1. The plan explicitly chose simpler (section 4 "WI-2 ~80 LOC + tests"; section 6 Risks documented the trade-off: legacy keys kept intact, idempotency via marker OR non-empty-store guard, no UserDefaults-side legacy data to integrity-check).
  2. WebDAV credentials are recoverable from the user's server settings (URL/username typed once, password retrievable from server admin); losing them is recoverable. AI API keys are not — losing them silently is irrecoverable, justifying ProviderProfileMigrator's commit-ordering ceremony.
  3. WebDAV migrator reads from keychain (not UserDefaults), so it has no "corrupt JSON" surface to defend against beyond what the store already handles in WI-1.
- `vreader/Services/Backup/WebDAVServerProfileStore.swift` (full, 244 LOC) — confirmed `loadAll`, `upsert`, `setActiveProfileID`, `writePassword`, `readPassword` async signatures.
- `vreader/Services/Backup/WebDAVProviderFactory.swift` (lines 1-78) — confirmed the three legacy keychain account constants are still authoritative for the existing make-path. WI-2 does NOT touch the factory; WI-3 will add the profileStore variant. Migrator duplicates the constants locally so it stays self-contained when WI-3 drops them from the factory.
- `vreader/Services/KeychainService.swift` (init signature, line 60) — confirmed `init(serviceIdentifier: String = "com.vreader.keychain")` — tests use unique per-test service IDs for isolation, same pattern as `AIProviderPickerViewModelTests`.
- `vreaderTests/Services/Backup/WebDAVServerProfileStoreTests.swift` (read for nonisolated(unsafe) UserDefaults pattern) — confirmed the same Sendable-crossing pattern is needed when the same `defaults` instance crosses into multiple actor-init / async-call sites. Replicated in the new tests' inline construction (replaced an extracted `makeStore` helper that initially failed the Swift 6 sending-risk check).

### Symbols verified

- `WebDAVServerProfile.init(id:name:serverURL:username:)` ✓ — matches WI-1's struct shape exactly.
- `WebDAVServerProfileStore.init(defaults:keychain:)` ✓ — test-injectable, defaults to `.standard` + `KeychainService()`.
- `WebDAVServerProfileStore.writePassword(_:for:) async throws` ✓ — invoked from `try await store.writePassword(...)`.
- `WebDAVServerProfileStore.readPassword(for:) async throws -> String?` ✓ — invoked from tests.
- `KeychainService.saveString(_:forAccount:) throws` ✓ — same correction as WI-1 (NOT `writeString`).
- `KeychainService.readString(forAccount:) throws -> String?` ✓ — tolerates missing entries by returning nil.
- `Logger` declared `nonisolated private static` ✓ — same pattern as WI-1 store + bug #183 fix.

### Edge cases checked

1. **Fresh install (no legacy data)**: marker not set, all 3 keychain reads fail/return nil → guard `hasLegacyData = false` → set marker + log "fresh install" + return. No profile created. **Test: `migrateIfNeeded_freshInstall_setsMarkerCreatesNoProfile`**.
2. **Full legacy data**: all 3 keychain entries present → build profile with verbatim URL/username, copy password to per-profile slot, upsert + setActive + set marker. **Test: `migrateIfNeeded_existingLegacy_createsDefaultProfile`** verifies all 5 invariants (id/name/URL/username, active, password copied, marker).
3. **Partial legacy (URL + username, no password)**: hasLegacyData=true via URL OR username, password write is skipped (the `if !legacyPassword.isEmpty` guard), profile still created with empty per-profile password slot. **Test: `migrateIfNeeded_partialLegacy_urlOnly_createsProfileWithEmptyPasswordSlot`** verifies the empty password slot reads back as nil.
4. **Marker already set** (idempotency axis 1): legacy data present in keychain but the migrator must NOT touch the store. **Test: `migrateIfNeeded_markerAlreadySet_isNoOp`** verifies empty store post-migrate when marker was pre-set.
5. **Store non-empty but marker missing** (idempotency axis 2 — defensive crash-recovery): legacy data present + a user-added profile already in the store + marker not set. Migrator must set marker but NOT add a Default profile (otherwise it would shadow / duplicate against the user's profile). **Test: `migrateIfNeeded_storeNonEmpty_setsMarkerWithoutMigrating`** verifies the user's profile is the only one present after migration runs.
6. **Repeat call**: two consecutive `migrateIfNeeded` calls must not duplicate the Default profile. First call sets marker; second call short-circuits on axis 1. **Test: `migrateIfNeeded_secondCall_doesNotDuplicateProfile`**.
7. **Partial-failure mid-migration**: if `writePassword` throws, the throw propagates BEFORE `upsert`/`setActiveProfileID`/marker-set. Next launch sees marker unset + store empty → retries from scratch. Legacy keys still intact in keychain so the retry has the same inputs. (Not unit-tested — would need a failing keychain mock; acceptable per plan because the failure mode is recoverable.)
8. **Empty-password legacy with URL+username present**: same path as edge case 3 — partial-legacy. Profile created without per-profile password slot write.
9. **Stable migrated UUID**: `migratedProfileID = UUID("00000002-AAAA-4000-8000-000000000001")` — different from `ProviderProfileMigrator.migratedProfileID` (`00000001-...`). No namespace overlap because the per-profile keychain accounts differ (`com.vreader.webdav.profile.<uuid>.password` vs `com.vreader.ai.profile.<uuid>.apiKey`); the disambiguation is defensive only.

### Concurrency / Swift 6

- `WebDAVProfileMigrator` is an `enum` (uninstantiable) — no per-instance state, all functions static.
- `migrateIfNeeded` is `async throws` because:
  - `await store.loadAll()` — actor hop for the non-empty guard
  - `try await store.writePassword(...)` — actor hop with potential keychain throw
  - `await store.upsert(profile)` — actor hop
  - `await store.setActiveProfileID(profile.id)` — actor hop
- All `await` points are independent state writes inside the actor's own serialized region — no observable interleaving with concurrent callers (the actor IS the serialization boundary).
- `Logger` is `nonisolated private static let` — same pattern as the store. Allows the static migrator to log without crossing actor boundaries.
- `UserDefaults` Sendable-crossing: tests use `nonisolated(unsafe) let defaults = makeDefaults()` inside each test. The migrator's `defaults: UserDefaults = .standard` parameter is a global in production (no crossing concern). Tests must NOT extract the store-construction into a helper that takes a `UserDefaults` parameter — that helper's parameter would not inherit the `nonisolated(unsafe)` marker and Swift 6 strict concurrency rejects it. Initial draft tripped exactly this; corrected by inlining the store construction in each test.
- Build clean under `SWIFT_STRICT_CONCURRENCY: complete`.

### VReader compliance

- Swift 6 strict concurrency: clean.
- `@MainActor` correctness: not applicable (no MainActor types).
- File size: WebDAVProfileMigrator.swift 109 LOC. Under 300.
- Bridge safety: not applicable.
- DEBUG gating: not applicable (production code).
- Per `.claude/rules/50-codebase-conventions.md`: error handling via `throws`, OSLog via `Logger(subsystem: "com.vreader.app", category: "WebDAVProfileMigrator")`, no bare print.

### Risks accepted

- **Mid-migration partial-failure retry**: as in edge case 7, the marker is set last so any throw above leaves the marker unset → next launch retries with the same keychain inputs. No deterministic test (would require a controllable failing-keychain seam); the design ensures retry-safety by construction.
- **Legacy keychain entries kept**: deliberate per plan section 6. Cleanup deferred to a later WI after dwell time. Same posture as Feature #50's `AIConfigurationStore` retention.
- **Migrator doesn't verify the post-upsert state via read-back** (unlike `ProviderProfileMigrator` step 8): accepted because the store's `upsert` is in-actor and synchronous-from-the-caller's-perspective inside that actor hop. ProviderProfileMigrator's step 8 reads `preferences.string(...)` to verify the JSON encode round-trip — that paranoia is justified there because the legacy AIConfiguration data is irrecoverable. For WebDAV, the legacy keys remain in keychain, so a missed write here means the next launch retries from intact source.
- **No bool-vs-string format for the marker**: chose `defaults.set(true, forKey:)` / `defaults.bool(forKey:)` instead of ProviderProfileMigrator's `"true"` string sentinel. Bool is the native UserDefaults type; the string sentinel in ProviderProfileMigrator is a legacy choice. The plan didn't specify; bool is cleaner.

### Tests added or intentionally deferred

- **WebDAVProfileMigratorTests**: 6 tests covering exactly the contract the plan named (section 5 test catalogue: "Legacy flat-keys → one Default profile (verbatim URL/username, name `\"Default\"`, keychain key per-id), idempotent on second run, skipped when profiles list non-empty, marker written" — all 4 explicit axes covered + 2 extra (partial-legacy / repeat-call double-check).
- **Deferred to WI-3**: factory integration tests (`WebDAVProviderFactoryProfileDispatchTests` per plan section 5).
- **Deferred to WI-4a/4b**: list view + editor sheet UI tests.

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — implementation matches plan section 2/4/5 + WI-1's foundational shape | n/a |

## Final verdict

**ship-as-is** — foundational WI delivers exactly what the plan
specified: a 109 LOC enum + 6 tests covering both idempotency axes
+ legacy-data round-trip + partial-legacy + fresh-install. 6/6
tests pass. Build clean under Swift 6 strict concurrency.
No user-observable behavior change (WI-3 wires the migrator into
`VReaderApp.init` and the factory; WI-2 is callable but currently
unwired — that's intentional per the plan's sequencing).
