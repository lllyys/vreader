---
branch: feat/feature-123-wi-1-annotations-schema
threadId: codex-exec-f123-wi1
rounds: 1
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #123 WI-1 (foundational) — annotations Room schema

Adds the `highlights` / `annotation_notes` / `bookmarks` tables (`HighlightEntity`,
`AnnotationNoteEntity`, `BookmarkEntity`), the `AnnotationDao` (transactional
dedupe upsert + CRUD/observe per type), DB v3→v4, and `MIGRATION_3_4`.

Files: `data/Entities.kt`, `data/Daos.kt`, `data/VReaderDatabase.kt`,
`test/.../AnnotationDaoTest.kt`, `test/.../VReaderDatabaseMigrationTest.kt`,
`schemas/.../4.json`, `docs/architecture.md`.

## Round 1 — findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | VReaderDatabase.kt (MIGRATION_3_4) | Low | DDL not byte-exact: Room emits `… ON DELETE CASCADE )` (trailing space) per the exported `4.json`; the migration had `CASCADE)`. No runtime hazard (Room validates structurally, and the 1→4 migration test passes), but it violated the byte-exact claim. | FIXED — added the trailing space to all 3 FK clauses to match `4.json`. |
| 2 | docs/architecture.md:540 | Low | Android data-layer doc still said `@Database` v3; this PR is a schema change (rule 24 doc-sync trigger). | FIXED — updated to v4, listing the 3 annotation entities + `AnnotationDao` + `MIGRATION_3_4` + the `anchorKey` sentinel + the canonical-`locatorJSON` contract. |

Core verdict (Codex): **clean.** Entities match the v3 plan (non-null `anchorKey`,
unique `(profileKey, anchorKey)`, canonical `locatorJSON`, FK CASCADE, indices).
The hand-written DDL matches Room's generated v4 schema (column order, affinities,
nullability, FK semantics, index names). The DAO's `INSERT OR IGNORE` + unique
index + `UPDATE WHERE profileKey AND anchorKey` is duplicate-race-safe (serialized
through the SQLite/Room transaction), last-writer-wins on a duplicate upsert (the
WI's intended "update in place"). No missing index, dead code, or file-size issue.

## Tests
- `AnnotationDaoTest` (Robolectric, 8 tests) — CRUD/observe/FK-cascade/transactional-dedupe — **SUCCEEDED**.
- `VReaderDatabaseMigrationTest` (incl. new 1→4 chain) — Room structural validation of `MIGRATION_3_4` — **SUCCEEDED**.

## Verdict
**ship-as-is.** Both Low findings fixed; schema + migration validated by Room's
own structural check on the merged migration chain.
