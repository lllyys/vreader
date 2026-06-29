---
branch: feat/feature-127-wi-1-collections-schema
threadId: 019f12a7-08bb-7c73-acd2-b382f7f7d5d4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #127 WI-1 (collections schema + Room v4→v5 migration)

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox) of WI-1:
`CollectionEntity` + `BookCollectionCrossRef` + `MIGRATION_4_5` + `@Database(version=5)`
+ a `CollectionDao` skeleton + the exported `5.json`, with a Robolectric v1→v5 migration
test + an in-memory `CollectionDaoTest`.

## Findings — no Critical/High/Medium; 1 Low (fixed)

> "No Critical/High/Medium findings. The schema/migration work is clean for Gate-4:
> `MIGRATION_4_5` matches the exported v5 schema for the new tables/indices, v4 existing
> table DDL is unchanged, `ALL_MIGRATIONS` includes 4→5, and the FK/index design is sound."

| file | severity | issue | resolution |
|---|---|---|---|
| `CollectionDao.kt` / `CollectionDaoTest.kt` | Low | Comment/test name still said "upsert" though the behavior is a strict `@Insert` (ABORT-on-conflict). Doc drift, not a runtime bug. | **Fixed.** DAO header reworded (strict `@Insert`, not `@Upsert`); test renamed `insert_andFindByNameKey`. |

## Auditor confirmations

- Composite PK `(bookKey, collectionId)` + an explicit `collectionId` index is correct (PK covers the
  book-side lookup/FK; the explicit index covers the reverse "books in collection" lookup + the
  collection FK).
- `INSERT OR IGNORE` is appropriate for idempotent membership; FK violations are still not silently
  accepted.
- Storing `nameKey` without a DB CHECK tying it to `name` is a reasonable WI-1/WI-2 split — the
  locale-stable normalization belongs in the repository (WI-2).
- The full 1→5 migration test exercises the 4→5 step + Room's final structural validation, plus
  behavioral coverage for the unique `nameKey` and book-delete cascade.

## Test evidence

- `VReaderDatabaseMigrationTest` — 4/4 (the new `migrate1To5_…addsCollections_cascades_andEnforcesUniqueName`).
- `CollectionDaoTest` — 3/3 (insert/find, observe-ordered, membership idempotent + reverse lookup).

## Verdict

ship-as-is. WI-1 is foundational; `CollectionDao` full + `CollectionRepository` (transactional dedup,
counts) is WI-2.
