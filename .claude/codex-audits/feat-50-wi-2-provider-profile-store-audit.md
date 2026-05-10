---
branch: feat/50-wi-2-provider-profile-store
threadId: 019e12e7-7dc5-7182-85ef-8051d91cf35d
rounds: 3
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex Gate-4 audit — feature #50 WI-2 (`ProviderProfileStore` actor + commit-style migration)

Files audited:

Production:
- `vreader/Services/AI/ProviderProfileStore.swift`
- `vreader/Services/AI/ProviderProfileMigrator.swift`

Tests:
- `vreaderTests/Services/AI/ProviderProfileStoreTests.swift`
- `vreaderTests/Services/AI/ProviderProfileMigratorTests.swift`

## Round 1 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | High | `ProviderProfileStore.swift:141` | `ensureMigrated()` set `migrationCompleted = true` unconditionally, even when migrator bailed out (keychain verify fail, etc.) — turning a transient failure into a permanent skip. | **Fixed**. After running migrator, re-check `shouldMigrate(...)`. Only set the in-memory flag if it returns false. Bailed-out runs leave both flags clear so the next read retries. |
| 2 | High | `ProviderProfileMigrator.swift:136` | `shouldMigrate` integrity check used `string?.isEmpty == false` — corrupt JSON would pass. Plus, "flag set + profiles missing + keychain-only legacy" couldn't recover because shouldMigrate didn't see keychain. | **Fixed**. `shouldMigrate(preferences:keychain:)` now actually decodes the JSON; corrupt JSON triggers re-migration. New `legacyDataExists(preferences:keychain:)` helper checks both preferences-config-key AND keychain-legacy-account. The migrator's call passes keychain so recovery has full visibility. |
| 3 | Medium | `ProviderProfileMigratorTests.swift:130` | Tests didn't pin the broken recovery paths above. Test 3 allowed 0 OR 1 profile (would hide a regression); test 6 only covered "flag set + profiles missing"; no keychain-only crash test. | **Fixed**. Test 3 renamed `corruptLegacyConfig_producesDefaultProfileAndSetsFlag` and tightened to assert exactly 1 profile of kind .openAICompatible with the documented `gpt-4o-mini` default. New Test 6b covers corrupt-JSON-at-profilesKey + legacy data → re-migrate. New Test 6c covers keychain-only legacy + flag + missing profiles → re-migrate. |

## Round 2 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Medium | `ProviderProfileMigrator.swift:160` | The integrity check accepted a successfully-decoded `[]` as "migration succeeded" without consulting legacy data. If profile data was written as `[]` but legacy data still exists, recovery would be skipped. | **Fixed**. The decode path now special-cases `decoded.isEmpty`: falls through to `legacyDataExists(...)` and only returns false (no migrate) when no legacy data remains. |
| 2 | Low | `ProviderProfileMigratorTests.swift:231` | No test exercised the `[]` + legacy-data state. | **Fixed**. New Test 6d (`midMigrationCrash_emptyProfileArrayWithLegacyData_reRunsCleanly`) seeds `profilesKey = "[]"` + flag + legacy data, asserts re-migration. |

## Round 3 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Low | `ProviderProfileMigrator.swift:143` | Stale doc comment for `shouldMigrate` still said "decodes (even to [])  → migrated successfully" — implementation has changed, comment hadn't. | **Fixed**. Doc bullets updated to reflect the new empty-array semantics (consults `legacyDataExists`). |

Round 3 verdict: `ship-as-is`.

> "The new `[]` branch interacts cleanly with the fresh-install path: a true fresh install still writes `[]` + flag, and on the next read `legacyDataExists(...)` returns `false`, so `shouldMigrate(...)` returns `false` and does not loop. Test 6d drives the intended recovery path." — Codex round 3

## Notable design decisions discovered during the audit

1. **Sync migrator** — original draft had `migrateIfNeeded` as `async` per protocol. The concurrency-stress test caught actor re-entrancy: 20 concurrent `upsert` calls each suspended at the `await migrator.migrateIfNeeded(...)` line, the migrator ran 20 times concurrently, all writing the same fixed-UUID profile but races corrupted the final list (only 1 profile landed). Fix: make the migrator protocol synchronous. The migrator does no async work anyway. Sync removes the suspension point so actor serialization makes upsert read-modify-write atomic. Documented inline in the migrator's protocol header.

2. **Stable migrated-profile UUID** — the migrator uses a fixed UUID (`00000001-AAAA-4000-8000-000000000001`) for the auto-migrated profile. This makes mid-crash recovery idempotent: re-running migration after a partial failure produces the same profile id, not a duplicate. Documented inline.

3. **Recovery semantics** — `shouldMigrate(preferences:keychain:)` now treats every state explicitly:
   - flag NOT set → migrate
   - flag set + decoded list non-empty → migrated
   - flag set + decoded list empty + no legacy data → fresh-install completed
   - flag set + decoded list empty + legacy data exists → mid-crash, re-migrate
   - flag set + non-decodable JSON → corrupt, re-migrate
   - flag set + missing JSON + legacy data exists → mid-crash, re-migrate
   - flag set + missing JSON + no legacy data → fresh-install completed

## Test gate

`xcodebuild test -only-testing:vreaderTests/ProviderProfileMigratorTests -only-testing:vreaderTests/ProviderProfileStoreTests` — **25/25 green** (10 migrator tests, 15 store tests). Round-1 baseline was 22; rounds 1+2 added 3 tests as audit fixes.

## Plan compliance

WI-2 deliverables per `dev-docs/plans/20260510-feature-50-multi-provider-ai.md`:

- [x] `ProviderProfileStore` actor with `.shared` singleton + test-injectable init
- [x] All public surface async (loadAll, activeProfile, activeProfileSnapshot, upsert, remove, setActiveProfileID)
- [x] Lazy-on-read migration via `ensureMigrated`
- [x] `ProviderProfileMigrating` protocol + `DefaultProviderProfileMigrator` struct
- [x] Commit-style migration: keychain copy → write profiles → verify decode → THEN flag
- [x] Snapshot semantics: `activeProfileSnapshot()` returns by-value
- [x] Mid-migration crash recovery via `shouldMigrate` checking flag AND profile data integrity AND legacy data presence
- [x] Concurrency stress test (`withTaskGroup`)
- [x] Shared-instance contract (`ObjectIdentifier` equality test)

Tier classification: WI-2 is **Behavioral** (per Gate-2 round-1 audit finding [2] re-tier — migration writes to UserDefaults + Keychain on first read).

## Files OUT of WI-2

- `AnthropicProvider` (WI-3 + WI-4)
- `AIService` modifications (WI-5)
- Settings UI rewrites (WI-6a + WI-6b)
- In-reader picker (WI-7)
- `AIConfigurationStore` deprecation (NOT in this feature; follow-up PR after migration flag is set on shipped users for one release)
