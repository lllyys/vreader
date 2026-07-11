---
branch: feat/135-wi3-bookmark-migration
threadId: 019f5187-608d-7ac1-af09-dbb20b8747ef
rounds: 3
final_verdict: follow-up-recommended
date: 2026-07-11
---

# Gate-4 audit — feature #135 WI-3 (atomic bookmark toggle + unique-index migration + dedupe)

Codex (`scripts/run-codex.sh`, rule 53), 3 rounds. Files audited:
`data/Daos.kt`, `data/Entities.kt`, `data/VReaderDatabase.kt`,
`annotations/Annotation.kt`, `annotations/AnnotationsRepository.kt`,
`data/VReaderDatabaseMigrationTest.kt`, `data/BookmarkToggleTest.kt`. The
generated `schemas/.../8.json` (unique index `index_bookmarks_bookKey_profileKey`
on `(bookKey, profileKey)`) was confirmed by the tool + by inspection to match
the `CREATE UNIQUE INDEX` DDL exactly (Room schema validation passes at open).

## Migration — validated correct (round 1, unchanged since)

Codex confirmed `MIGRATION_7_8`:
- The dedupe DELETE self-join deletes a row only when another row in the same
  `(bookKey, profileKey)` group ranks strictly higher; a unique (non-duplicate)
  row can never match the join → is preserved.
- The winner order `(updatedAt DESC, createdAt DESC, bookmarkId ASC)` is a total,
  deterministic order (`bookmarkId` is a non-null PK).
- Dedupe runs BEFORE the `CREATE UNIQUE INDEX`, so a pre-existing legacy duplicate
  cannot fail the migration.
- Index name/uniqueness/columns/order match Room's generated schema; `version = 8`;
  `MIGRATION_7_8` appended to `ALL_MIGRATIONS`; no `fallbackToDestructiveMigration`;
  no other table mutated. Other tables' data preserved.

## Round 1 — verdict `follow-up-recommended`

- **Medium** — `toggleBookmark` treated every `@Insert(IGNORE)` `-1` as "position
  occupied → Removed". `-1` can also be a `bookmarkId` PK collision at a DIFFERENT
  position → a phantom `Removed`. **Fixed**: the toggle now decides add-vs-remove by
  the position's actual presence (`findBookmarkByProfile != null`), inside the
  `@Transaction`, with the unique index as the hard backstop.
- **Low** — a doc comment wrongly called the toggle "idempotent" (a toggle
  alternates state). **Fixed**: repository + DAO comments corrected.

## Round 2 — verdict `block-recommended`

- **Medium (residual)** — the presence-driven toggle closed the phantom-`Removed`,
  but on the `Added` branch a `bookmarkId` PK collision at a free position left the
  row un-inserted while still claiming `Added` (false `Added`). **Fixed**: on the
  `Added` branch, if the insert is ignored while the position is STILL free, the
  entity is re-keyed with a fresh UUID and re-inserted so `Added` truly persists;
  the regression test now asserts BOTH positions are truly bookmarked (2 rows).

## Round 3 (final) — verdict `follow-up-recommended`

- Codex confirmed both correctness classes are closed; the toggle is transactional
  and reuses `insertBookmarkIfAbsent` (no re-declaration); the regression test proves
  both positions persist.
- **Low (accepted, with rationale)** — a *theoretical* edge: the single fresh-UUID
  retry's result is not itself re-verified, so a SECOND collision would again make
  `Added` untruthful. Codex: "astronomically unlikely, not a practical shipping
  blocker." A second collision on a fresh v4 UUID is a ~1-in-2^122 event — an
  unreachable branch; a bounded retry loop would add complexity for no practical
  gain. Accepted per Gate-4 (Low findings may be accepted with rationale);
  documented in the `toggleBookmark` code comment.

## Disposition

Zero open Critical/High/Medium findings after round 3. The sole residual is an
accepted Low (documented). Max audit rounds (3) reached with all correctness
findings resolved. Test gate green throughout each fix (`RUN-ANDROID-TESTS RESULT:
SUCCEEDED`; migration 11/0, toggle 10/0). Ready for integration.
