---
branch: feat/128-wi1-author-preserving
threadId: run-codex-b5fm0epnq
rounds: 1
final_verdict: follow-up-recommended
date: 2026-07-11
---

# Gate-4 audit — feature #128 WI-1 (Room v6 `books.author` + author-preserving persistence)

Independent Codex audit of the WI-1 diff (`git diff origin/main..HEAD`), run via
`scripts/run-codex.sh` (rule 53; `RUN-CODEX RESULT: SUCCEEDED`). Raw output:
`.reports/wi1-audit-raw.txt`.

## Verdict

**follow-up-recommended** — no correctness blocker found in the production
implementation. All three follow-ups are Low / non-blocking.

## What the audit confirmed (correctness)

- `upsertPreservingAuthor` is atomic under Room's `@Transaction`: `INSERT OR
  IGNORE` returns `-1L` on the existing PK, then the scoped `UPDATE` changes
  exactly the import-owned columns. No check-then-act race outside the
  transaction (Room serializes it).
- The `UPDATE` excludes both `author` and `lastOpenedAt`, so both survive a
  duplicate import; `title`/`originalFormat`/`contentSHA256`/`fileByteCount`/
  `localFilePath`/`sourceUri`/`addedAt` update.
- Avoids `REPLACE`, so `reading_positions`' `ON DELETE CASCADE` never fires
  (the position is preserved across a re-import).
- `MIGRATION_5_6` is correct — a nullable `TEXT` add needs no default and no
  table reconstruction.
- `6.json` is exported and differs from `5.json` only by version/hash + the
  nullable `books.author` field.
- `applyRestoredMetadata` semantics are as intended: non-null `manifestAuthor`
  wins, null preserves the stored author; `title`/`addedAt`/`lastOpenedAt` are
  applied directly (incl. clearing `lastOpenedAt` when null).
- All SQL identifiers match `BookEntity` and the exported schema; Kotlin/SQLite
  nullability + affinities align.
- Room 2.8.4 supports every DAO pattern used (suspend methods, interface default
  `@Transaction`, `@Insert(IGNORE)` returning `Long`, retained whole-row `@Upsert`).

## Follow-ups + resolution

1. **Authentic isolated v5→6 migration test (Low).** The `migrate5To6…` chain
   test seeds a v1 file and runs the full 1→6 chain — it validates the final
   schema + migration registration but not an authentic exported-v5 starting
   point in isolation. **RESOLVED this round**: added
   `migrate5To6_inIsolation_onAuthenticV5Books_addsNullableAuthor_preservesData`,
   which hand-builds the exact v5 `books` shape (has `lastOpenedAt`, no
   `author`), seeds a legacy + an already-opened row, applies ONLY
   `MIGRATION_5_6` via a raw `SupportSQLiteOpenHelper` upgrade path, and asserts
   the column is added + nullable, all data survives, migrated rows read
   `author = NULL`, and the new column is writable.

2. **Return affected-row counts from `updateImportedColumns` /
   `applyRestoredMetadata` (Low).** **Accepted, not changed.** A missing target
   row is not a real failure mode here: the import path always inserts-first (so
   the update branch only runs when the row exists), and the restore path
   (WI-2) always restores the book row before calling `applyRestoredMetadata`.
   A no-op UPDATE on a missing row is harmless; adding row-count plumbing would
   be speculative and is deferred.

3. **Make `backfillAuthorIfNull`'s author non-null (Low).** **Accepted, not
   changed.** The nullable parameter is intentional so a coordinator (WI-3/WI-4)
   that resolves a possibly-absent author can pass `null` and get a safe no-op,
   rather than forcing the caller to branch. The `WHERE author IS NULL` guard
   already makes a null value a harmless no-op.

## Gate result

Zero Critical/High/Medium findings. The one actionable Low (isolated migration
test) is fixed this round; the other two Lows are accepted with rationale
above. Ready for integration.
