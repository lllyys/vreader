---
branch: feat/131-wi2-room-cache
threadId: 019f54cc-a3b5-7080-bb69-116e788ea260
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 Implementation Audit — feature #131 WI-2 (Room translation cache)

Independent Codex audit (gpt-5.6-sol, read-only sandbox) of the WI-2 diff:
the `chapter_translations` Room cache — `ChapterTranslationEntity` (PK `lookupKey`,
all columns NOT NULL, FK→`books.fingerprintKey` ON DELETE CASCADE, `bookKey` index)
+ `ChapterTranslationDao` (`@Upsert` on the PK, `getByLookupKey`, `deleteByLookupKey`,
`count`) + `ChapterTranslationStore` (coroutine boundary decoding `translatedJson` →
`CachedTranslation`, corrupt-JSON-as-miss) + `VReaderDatabase` v8→v9 `MIGRATION_8_9`
(exact DDL, appended to `ALL_MIGRATIONS`) + the generated `9.json` schema + the
Robolectric migration/dao/store tests.

## Round 1 — verdict: ship-as-is

No Critical, High, Medium, or actionable Low findings.

Confirmed by the auditor:

- **`MIGRATION_8_9` matches the generated `9.json`** — column order, affinities,
  nullability, PK `lookupKey`, FK actions (ON UPDATE NO ACTION / ON DELETE CASCADE),
  and index name/shape (`index_chapter_translations_bookKey`) all identical (no drift
  the migration test could miss).
- **`@Entity` mirrors the existing child-table FK/CASCADE conventions** (highlights /
  bookmarks precedent) exactly.
- **The exact-DDL guard is real** — the full-chain 1→9 test opens the REAL Room DB via
  `Room.databaseBuilder(...).addMigrations(*ALL_MIGRATIONS).build()` and touches DAOs,
  so Room's structural PRAGMA validation runs on open and would throw on any drift
  (not a hand-written column-list assertion). A MIGRATION_8_9-in-isolation test against
  an authentic v8 DB additionally exercises the table/index/FK-CASCADE/PK directly.
- **Store decode semantics** — corrupt `translatedJson` returns a cache MISS (null),
  a well-formed `[]` remains a legitimate empty hit (distinct from miss), Room entities
  stay off the boundary (value-type `CachedTranslation` crosses).
- **Cache identity** is consistently profile-agnostic `book|unit|language|prompt`
  (iOS Bug #342 parity).
- **DAO operations are suspending and use `@Upsert`** (never `@Insert(REPLACE)`, which
  would fire the FK CASCADE and wipe child rows).
- **Tests** cover upsert-by-PK-replaces, book-delete cascade, missing-key delete no-op,
  distinct-key coexistence, empty segments, and Unicode/CJK/embedded-quote/backslash
  round-trips.
- **All production files < 300 lines; `@coordinates-with` headers maintained.**

## Test result

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — targeted Robolectric suite:
`ChapterTranslationDaoTest` 7/0, `VReaderDatabaseMigrationTest` 13/0,
`ChapterTranslationStoreTest` 8/0 (28 tests, 0 failures). The Room compiler emitted
`android/app/schemas/com.vreader.app.data.VReaderDatabase/9.json` (committed).

No code changes were required from the audit; no re-test needed.
