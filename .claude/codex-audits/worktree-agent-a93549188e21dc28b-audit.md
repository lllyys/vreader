---
branch: worktree-agent-a93549188e21dc28b
gate: 4
kind: implementation-audit
feature: 152
work_item: WI-2
threadId: 019fd55f-410d-74f3-8106-bc20041e54a2
threads:
  - round: 1
    id: 019fd543-8a03-74b3-a3b9-33704b23792d
  - round: 2
    id: 019fd552-0c97-7bd1-bdec-f4ee4aedec2d
  - round: 3
    id: 019fd55f-410d-74f3-8106-bc20041e54a2
rounds: 3
final_verdict: ship-as-is
---

# Gate-4 audit — feature #152 WI-2 (Android cover-state columns)

Runner: `scripts/run-codex.sh` (rule 53). Raw transcripts: `.reports/audit-r{1,2,3}.txt`
(worktree-local, not committed).

**Scope audited**: `data/Entities.kt`, `data/VReaderDatabase.kt`, `data/Daos.kt`,
`data/LibraryRepository.kt`, the generated `schemas/…/10.json`, and the tests
`BookDaoCoverStateTest.kt` / `VReaderDatabaseMigrationTest.kt` / `BookImporterTest.kt`.

**Outcome across rounds**: 0 Critical, 0 High ever. 2 Medium in round 1 → 2 Medium in round 2
(one carried, re-argued and re-scoped; one newly shown to be in-scope) → 0 Medium in round 3.

---

## Round 1 — `019fd543-8a03-74b3-a3b9-33704b23792d`

Verdict: no Critical/High. 2 Medium, 1 Low.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | Medium | `setCoverState(key, path: String?, version: Int?)` admits `(path != null, version == null)` — a state the tri-state does not define — and makes "reset to eligible" indistinguishable from a definite outcome at the call site. Also permits stale/out-of-order writes. | **FIXED (partially, round 1)** — the nullable-pair primitive was replaced by three named transitions: `setCoverArt(key, path: String, version: Int)`, `setCoverAbsent(key, version: Int)`, `clearCoverState(key)`. The illegal fourth state became unrepresentable. The **ordering** half was **rejected** in round 1 (see below) and then **fixed in round 2**. |
| 2 | Medium | `LibraryRepository.upsertBook` → the whole-row `@Upsert` can overwrite `(coverPath, coverExtractorVersion)` with `(null, null)`. Suggested fix: remove or rename the seam. | **REJECTED AS PROPOSED, round 1; FIXED DIFFERENTLY in round 2.** Removal/rename was declined on evidence: zero production callers, but ~45 call sites in `src/test/` across 12+ files plus 6 `src/androidTest/` files — and `androidTest/` is outside WI-2's declared write-set, so the refactor would have put the lane in violation of rule 55. Round 1's interim disposition was "pin + document + defer". Round 2 then produced an in-scope fix that needed no caller change, and that was taken. |
| 3 | Low | `Daos.kt` is 378 lines vs rule 50's ~300. | **ACCEPTED, deferred.** Splitting `BookDao` into its own file is a new file outside the declared write-set. Named as a follow-up. Re-confirmed Low by the auditor in rounds 2 and 3. |

### Rejected with reasoning (round 1) — the monotonic SQL guard

The auditor proposed gating writes on "stored version is null or older than the incoming version".
I declined **that formulation**, because a strictly-newer guard silently drops two writes the plan
requires at the *current* version:

- `dev-docs/plans/20260806-feature-152-android-cover-extraction.md` §7 `CoverCoordinatorConnectedTest`
  — "a book with an existing cover FILE but a `NULL` `coverPath` (the #153 user-pick case) → pointer
  reconciled".
- #153 replacing an extracted cover with a user-chosen one.

Round 2 accepted the objection **and refined the guard so both still land** (`>=` on the art path).
The refinement was correct and was implemented — see round 2. Recording this because the round-1
rejection was right about the constraint and wrong about the conclusion that no guard could satisfy it.

### Confirmed by round 1 (load-bearing, already checked — do not re-derive)

- Every production writer to `books` was enumerated independently by the auditor:
  `upsert`, `insertIfAbsent`, `upsertPreservingAuthor`→`updateImportedColumns`, `applyRestoredMetadata`,
  `BookDao.backfillAuthorIfNull`, **`SearchDao.backfillAuthorIfNull`** (a writer outside `BookDao`
  that my own scan had not listed — it is safely column-scoped), `markOpened`, `setCoverState`,
  `delete`, and the migration. Only the whole-row seam could clobber cover state.
- The no-clobber exclusion in `updateImportedColumns` is correct and load-bearing.
- Migration DDL matches the generated `10.json`; additive, non-destructive, correctly registered.
- The guard tests are non-vacuous — the anti-vacuity half (asserting the import-owned columns *did*
  change in the same call) was explicitly credited.

---

## Round 2 — `019fd552-0c97-7bd1-bdec-f4ee4aedec2d`

Verdict: follow-up-recommended. No Critical/High. 2 Medium.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 4 | Medium | The named transitions fixed the invalid-state half, but **older-version writes can still overwrite newer state**. Supplied refined SQL that permits the required same-version reconcile while rejecting stale writes. | **FIXED.** Implemented essentially verbatim. `setCoverArt`: `coverExtractorVersion IS NULL OR :version >= coverExtractorVersion`. `setCoverAbsent`: `IS NULL OR :version > stored OR (:version = stored AND coverPath IS NULL)` — so a same-version "no art" verdict cannot wipe an established pointer. `clearCoverState` left unguarded as the explicit re-run lever. Both recording calls now return `Int` (rows written) so a stale rejection is observable rather than a silent no-op; the repository maps it to `Boolean`. |
| 5 | Medium | The whole-row upsert **can** be fixed inside WI-2's write-set after all: replace the Room `@Upsert` with a `@Transaction` insert-if-absent + a column-scoped update of every pre-v10 column. No caller changes. | **FIXED.** Implemented as proposed. `BookDao.upsert` is now `@Transaction`: `insertIfAbsent`, and on `-1` a new `updateAllColumnsExceptCoverState` covering title/originalFormat/contentSHA256/fileByteCount/localFilePath/sourceUri/addedAt/lastOpenedAt/author. `author`/`lastOpenedAt` are still overwritten — that is the seam's documented purpose — but cover state is not. Deliberately still not `@Insert(REPLACE)`: that is delete-then-insert and would cascade away the saved reading position (#106 Gate-4 Critical). The round-1 test pinning destruction was **inverted**. |

This round is the reason the round-1 disposition on finding 2 does not stand as written: "pinned +
documented + deferred" was judged inadequate for a data-loss seam **once an in-scope fix was shown to
exist**. The auditor was right; the fix cost ~25 lines and zero caller churn.

### Disproven by measurement / confirmed in round 2

- `theObservedFlow_emitsAgainWhenCoverStateChanges` was challenged as a possible CI flake or hang.
  The auditor examined it and found no credible mechanism: the subscription is established by
  awaiting the first emission *before* the write, both waits are bounded by `withTimeout`, and the
  structured `runBlocking` scope joins the cancelled child. `runBlocking` (not `runTest`) is required
  because Room drives invalidation on its own executor, which virtual time does not advance.
- Migration re-verified as correct and complete after the edits.
- `Daos.kt` length re-confirmed Low and non-blocking.

---

## Round 3 (final) — `019fd55f-410d-74f3-8106-bc20041e54a2`

Verdict: **ship-as-is**. No Critical, High, or Medium findings remain.

The round-3 prompt asked specifically whether the changed shared seam lost a column, since that
would be a silent app-wide data-loss regression. The auditor enumerated `BookEntity`'s 12 columns
against the new UPDATE and confirmed the split is exactly right: `fingerprintKey` (PK), nine columns
updated on the conflict branch, `coverPath` + `coverExtractorVersion` intentionally preserved. It
further confirmed Room 2.8.4/KSP generates `BookDao_Impl.upsert()` via
`performInTransactionSuspending` delegating to the interface default method, matching the
`upsertPreservingAuthor` precedent, and that guard SQL, `Int.MAX_VALUE` binding, missing-row
behaviour, the migration, and `10.json` are all correct. The nine new guard/upsert tests were
judged non-vacuous.

---

## Accepted, not blocking

- **`Daos.kt` is 435 lines** (rule 50 target ~300). Splitting `BookDao` into `BookDao.kt` is a new
  file outside the declared write-set. **Follow-up.**
- **`VReaderDatabaseMigrationTest.kt` is ~1,060 lines**, debt substantially predating this WI; the
  auditor suggests eventually splitting it by migration generation. **Follow-up.**
- **`VLogTest` full-suite failure** — bug #374, order-dependent on process-global log state, filed
  before this WI by the #141 WI-1 lane; passes 17/17 in isolation; touches no file in this change.

## Test evidence at the final round

`ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --rerun-tasks --tests 'com.vreader.app.data.*'" scripts/run-android-tests.sh`
→ `RUN-ANDROID-TESTS RESULT: SUCCEEDED`, 159 tests, 0 skipped, 0 failures.

Full JVM suite: 2557 tests, 0 skipped, 1 failure (the bug #374 `VLogTest` flake above).

## Mutation pass (pre-audit, on the round-0 implementation)

Six mutations, all killed; none survived.

| Mutation | Reddened |
|---|---|
| Drop the `coverExtractorVersion` `ALTER TABLE` from `MIGRATION_9_10` | 11 tests — both new migration tests plus every pre-existing full-chain test, via Room's `Migration didn't properly handle: books` structural validation |
| Add the cover columns to `updateImportedColumns` (remove the exclusion) | exactly the 3 no-clobber tests, with their intended messages |
| Make the migration destructive (`UPDATE books SET lastOpenedAt = NULL`) | exactly 1 — `migrate9To10_inIsolation…isNonDestructive` ("lastOpenedAt survived") |
| `setCoverState` writes only `coverPath`, not the version | 11 tests |
| Drop `coverPath` from the entity→DTO mapping | 2 tests |
| Omit `MIGRATION_9_10` from `ALL_MIGRATIONS` | 9 tests ("A migration from 1 to 10 was required but not found") |
