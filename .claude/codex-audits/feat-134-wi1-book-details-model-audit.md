---
branch: feat/134-wi1-book-details-model
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #134 WI-1 (Book Details model + mapper + collectionNamesForBook query)

## Auditor availability

Codex (`scripts/run-codex.sh`, model `gpt-5.6-sol`) was invoked on the
`origin/main..HEAD` diff but returned `RUN-CODEX RESULT: FAILED` — the run
hit the ChatGPT usage limit ("You've hit your usage limit … try again at
8:21 PM"), session id `019f50fd-0c04-7540-ab44-5b140dcc609b`, raw output in
`.reports/wi1-audit.txt`. Per rule 47 "Manual fallback when AI auditor
unavailable", this is a genuine tool-unavailability (quota exhaustion), so the
audit is done manually with recorded evidence below.

## Manual Audit Evidence

### Files read (to verify every signature the change touches)

- `android/app/src/main/kotlin/com/vreader/app/data/LibraryRepository.kt`
  (the `Book` DTO: `fingerprintKey, title, originalFormat: BookFormat,
  contentSHA256, fileByteCount: Long, localFilePath?, sourceUri?, addedAt,
  lastOpenedAt?, author: String? = null`).
- `android/identity/src/main/kotlin/vreader/contracts/Identity.kt`
  (`enum class BookFormat { epub, pdf, txt, md, azw3 }` — lowercase raw = case
  names).
- `android/app/src/main/kotlin/com/vreader/app/data/CollectionEntities.kt`
  (`collections` table: `id, name, nameKey, createdAt`; `book_collection`
  table: `bookKey, collectionId`).
- `android/app/src/main/kotlin/com/vreader/app/data/CollectionDao.kt` (the
  existing `observeCollectionIdsForBook` + `observeCollectionsWithCount` join
  precedent).
- `android/app/src/main/kotlin/com/vreader/app/data/CollectionRepository.kt`
  (the thin Flow-wrapper pattern for `observeCollectionIdsForBook`).
- `android/app/src/main/kotlin/com/vreader/app/data/Entities.kt` (`BookEntity`
  10-field constructor; the 9-positional call in `CollectionDaoTest`).
- `android/app/src/main/kotlin/com/vreader/app/backup/WebDavBackupService.kt`
  (existing hand-rolled SI byte `sizeLabel` precedent, lines 214-218).
- `android/app/src/test/kotlin/com/vreader/app/data/CollectionDaoTest.kt` (the
  in-memory Room + Robolectric harness pattern copied for the query tests).

### Symbols / signatures verified

- `Book.fingerprintKey`, `Book.originalFormat: BookFormat`,
  `Book.fileByteCount: Long`, `Book.localFilePath: String?`,
  `Book.author: String?`, `Book.title` — all exist; the mapper reads only
  these. No new `Book` field added (author already on the live DTO, round-2
  LOW in the plan).
- `BookFormat.md` / `.epub` / `.pdf` / `.txt` / `.azw3` — all five enum cases
  exist; `format.name` = the lowercase raw value; the mapper uppercases all but
  `md`.
- Join query columns are the REAL columns: `book_collection.bookKey`,
  `book_collection.collectionId`, `collections.id`, `collections.name`,
  `collections.createdAt`. The query compiled cleanly under Room's annotation
  processor (build SUCCEEDED — Room validates the SQL against the schema at
  compile time, so a bad column name would have failed the build).
- `VReaderDatabase.collectionDao()` / `.bookDao().upsert(BookEntity(...))` —
  used verbatim from the existing `CollectionDaoTest` harness.

### Findings (checked against the plan's WI-1 spec)

1. **Purity (rule 50 boundary) — PASS.** `BookDetailsMapper` imports only
   `Book`, `BookFormat`, `java.io.File`, `java.util.Locale`. `BookDetailsUiModel`
   imports nothing. No Compose, no Android UI type, no `Context`. The mapper is a
   pure JVM `object` callable off any thread.
2. **`fingerprintFull == fingerprintKey` — PASS.** Literal
   `fingerprintFull = book.fingerprintKey`; `fingerprintDisplay =
   middleTruncate(...)` = `take(14)+"…"+takeLast(8)` for keys > 28 chars, verbatim
   otherwise (iOS thresholds). Both derived from the same canonical key.
3. **Size formatting — PASS.** `bytes <= 0L -> "Unknown"` covers BOTH the `0`
   and `-1` cases in one guard. SI decimal divisors match the `.file`/existing
   `WebDavBackupService.sizeLabel` count style. `Long.MAX_VALUE` takes the MB
   branch via `bytes / 1_000_000.0` (double division — no Long overflow), yielding
   a non-empty, non-"Unknown" label. Hand-rolled (not `Formatter.formatShortFileSize`)
   is the deliberate call: the WI-1 mapper must stay Context-free/pure, and the
   plan pins exact string outputs that a locale-varying platform formatter can't
   guarantee; the existing project precedent (`WebDavBackupService.sizeLabel`)
   uses the same SI hand-roll. Recorded as a documented, precedent-backed
   deviation from §size-formatting's "use `Formatter.formatShortFileSize`"
   suggestion.
4. **Format label (md -> Markdown) — PASS.** `when` maps `md` to "Markdown",
   `else` uppercases the raw name; exhaustive over the sealed enum.
5. **year / cover ABSENCE — PASS.** No `year` / `coverPath` model fields; a
   reflection guard test asserts their absence structurally.
6. **pagesLabel only when supplied — PASS.** `pageCount?.toString()` → null
   when the host passes null (every non-PDF host); a String when PDF supplies a
   count.
7. **collectionNamesForBook join — PASS.** ONE atomic `INNER JOIN` on the real
   columns, `ORDER BY c.createdAt ASC` (deterministic oldest-first), INNER JOIN so
   the result is empty when the book has no membership. Only THIS book's names
   (WHERE `bc.bookKey = :bookKey`). Repository wrapper mirrors the existing
   `observeCollectionIdsForBook` pattern.
8. **Additive-only DAO change — PASS.** One new abstract `@Query fun` + one
   repository wrapper. No `@Entity`, no schema-version bump, no `Migration` — the
   `book_collection`/`collections` tables already exist. No entity touched.
9. **Duplicate / dead code — none.** The new query is distinct from the
   ids-only `observeCollectionIdsForBook`; the mapper duplicates no existing
   formatter beyond deliberately mirroring the SI `sizeLabel` precedent.
10. **File size / conventions — PASS.** `BookDetailsMapper.kt` ~61 lines,
    `BookDetailsUiModel.kt` ~32 lines, both far under 300; KDoc + `// Purpose:`
    header present (rule 22).

### Edge cases checked

byte-count `0` / `-1` / `512` (B) / `1_000` (KB boundary) / `1_000_000` (MB
boundary) / `Long.MAX_VALUE` (no crash); short vs long fingerprint key (ellipsis
present/absent); null vs present author; null vs present localFilePath; empty
vs populated collection names; every `BookFormat` case's label; join ordering
(inserted out of createdAt order, asserted oldest-first); empty membership;
another book's memberships excluded.

### Risks accepted

- **Hand-rolled SI size formatter instead of `android.text.format.Formatter`**
  (finding 3) — accepted to keep the mapper pure/Context-free and to pin
  deterministic outputs; backed by the existing `WebDavBackupService.sizeLabel`
  precedent. If a later WI wants exact platform-formatter parity it can wrap the
  Context call at the ViewModel/host layer without changing this pure mapper.

### Tests added

`android/app/src/test/kotlin/com/vreader/app/reader/details/BookDetailsMapperTest.kt`
— 23 cases (JVM mapper assertions + in-memory Room join-query assertions).
`RUN-ANDROID-TESTS RESULT: SUCCEEDED`; JUnit XML shows `tests="23" skipped="0"
failures="0" errors="0"` (confirmed non-zero — not a silent 0-test false pass).

## Verdict

**ship-as-is.** Zero Critical/High/Medium findings. The one deviation (hand-rolled
SI size formatter) is deliberate, precedent-backed, and recorded above.
