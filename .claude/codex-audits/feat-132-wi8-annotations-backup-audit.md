---
branch: feat/132-wi8-annotations-backup
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-8 (Android annotations.json backup + restore)

## Auditor availability

Codex (`scripts/run-codex.sh`, model gpt-5.6-sol) returned
`RUN-CODEX RESULT: FAILED (codex exit 1)` — the ChatGPT usage limit was hit
("You've hit your usage limit… try again at 8:21 PM"). Per rule-47's
manual-fallback clause, this is a genuine tool-unavailability (quota outage),
so the audit was performed manually with evidence recorded below.

## Manual Audit Evidence

### Files read (production + dependency surfaces)
- `android/app/src/main/kotlin/com/vreader/app/backup/BackupCollector.kt` (edited)
- `android/app/src/main/kotlin/com/vreader/app/backup/RestoreImporter.kt` (edited)
- `android/app/src/main/kotlin/com/vreader/app/backup/WebDavBackupService.kt` (edited)
- `android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationsRepository.kt` (WI-6b restore seam — READ-ONLY)
- `android/app/src/main/kotlin/com/vreader/app/annotations/Annotation.kt` (records + `locator.toJson()` — READ-ONLY)
- `android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationsSnapshot.kt` (`RestoreAnnotationsReport`/`KindCounts`)
- `android/identity/src/main/kotlin/vreader/contracts/backup/BackupSections.kt` (#113 DTOs — READ-ONLY, reused)
- `android/identity/src/main/kotlin/vreader/contracts/backup/BackupSchema.kt` (`CURRENT=3`, `ACCEPTED={1,2,3}`)
- `android/app/src/main/kotlin/com/vreader/app/data/Daos.kt` (`allHighlights/allNotes/allBookmarks`, `restoreAnnotationEntities` @Transaction)
- `android/app/src/test/.../backup/CollectionBackupTest.kt`, `.../annotations/RestoreAnnotationsTest.kt` (test precedents)

### Symbols / signatures verified
- `BackupAnnotationsEnvelope(schemaVersion, highlights: List<BackupHighlight>, bookmarks: List<BackupBookmark>, notes: List<BackupNote>)` — field ORDER is highlights, bookmarks, notes; the collector supplies them in that positional order. ✓
- `BackupHighlight(highlightId, bookFingerprintKey, locatorJSON, selectedText, color, note?, createdAt: Instant, updatedAt: Instant)`; `BackupNote(annotationId, bookFingerprintKey, locatorJSON, content, createdAt, updatedAt)`; `BackupBookmark(bookmarkId, bookFingerprintKey, locatorJSON, title?, createdAt, updatedAt)` — all mapped field-for-field. ✓
- `HighlightRecord/NoteRecord/BookmarkRecord` carry `.id`, `.bookKey`, `.locator`, `.createdAt`, `.updatedAt` (+ color/note/content/title). ✓
- `AnnotationsRepository.restoreAnnotations(env: BackupAnnotationsEnvelope, allowedBookKeys: Set<String>): RestoreAnnotationsReport`; `RestoreAnnotationsReport.{highlights,notes,bookmarks}.applied`. ✓
- `allHighlights()/allNotes()/allBookmarks()` are the collector reads (corrupt rows already dropped by `toRecordOrNull`). ✓
- `BackupJson.encode(locator)` / `BackupJson.decode<Locator>(json)` — the PLAIN round-trip pair the positions path (`RestoreImporter.restorePosition` line ~163) and WI-6b's `validate` both use. ✓

### The load-bearing contract check (locatorJSON = PLAIN, not canonical)
- The three DTO mappers use `locatorJSON = BackupJson.encode(locator)` — the plain serialized `Locator`, identical to what `Annotation.kt` stores (`locator.toJson()`), what iOS emits (`encoder.encode(locator)`), what the vector `contracts/vectors/backup-sections.json` holds, and what WI-6b decodes via `BackupJson.decode<Locator>`. `canonicalJson()` is NOT used. `profileKey` is NOT emitted (WI-6b derives it internally from the decoded locator). ✓
- Test `collect_emitsPlainLocatorJson_notCanonical` asserts (a) the emitted `locatorJSON` decodes back to a `Locator` whose `fingerprintKey`/`charOffsetUTF16` match, and (b) it is NOT `== locator.canonicalJson()` and DOES contain the plain object field `charOffsetUTF16`. GREEN.

### Edge cases checked (all covered by JVM tests — 11 tests, 0 failures)
- byte-stability across repeat collects + deterministic sort by (bookFingerprintKey, id) — `collect_isByteStable_sortedAndDeterministic`.
- filter to the collected manifest books (a highlight for a deleted/non-manifest book is dropped) — `collect_filtersToManifestBooks`.
- bookmarks populated — `collect_populatesBookmarks`.
- empty store → valid-empty envelope (or omitted) — `collect_emptyStore_emitsEmptyEnvelope_orOmitted`.
- totalSize includes the section — `collect_includesSectionInTotalSize` (unchanged summation path over `sections.values`).
- round-trip restores highlights+notes+bookmarks preserving UUIDs — `roundTrip_restoresHighlightsNotesBookmarks_preservingUuids`.
- idempotent (second restore applies 0, no duplicates) — `roundTrip_isIdempotent_secondRestoreAppliesZero`.
- scope filter (manifest lists only book a → book b's annotation dropped) — `restore_filtersToManifestScope_dropsOutOfScope`.
- pre-#132 backup (no annotations.json) restores zero, no crash — `restore_absentAnnotationsSection_isNoOp_noCrash`.
- malformed locatorJSON row dropped/failed, not applied — `restore_malformedRow_dropped_notApplied`.
- schema gate: collector emits `CURRENT_SCHEMA_VERSION=3`; restore accepts `ACCEPTED_SCHEMA_VERSIONS={1,2,3}` (WI-6b's own tests use v1 — accepted).

### Concurrency / correctness
- `collectAnnotationsJson` and `restoreAnnotations` are `suspend`; the restore runs inside `restore()`'s `withContext(ioDispatcher)`. The DAO `@Transaction` (restore-all-in-one) stays inside WI-6b (untouched). No hardcoded dispatcher. ✓
- Nullable `annotationsRepository` default preserves back-compat for every existing `BackupCollector`/`RestoreImporter`/`WebDavBackupService` caller — the two existing test call sites still compile with no annotation wiring (verified: `:app:testDebugUnitTest` + `:app:compileDebugAndroidTestKotlin` BUILD SUCCESSFUL). ✓
- Annotation-restore scope = manifest-books-in-selection (`books.map{fingerprintKey}`), NOT blob-download success — so an annotation for an already-local book still restores (iOS parity) and the no-blob JVM tests exercise the real path. ✓

### #113 / contracts isolation
- No file under `android/identity/**` or `contracts/**` was touched. The #113 DTOs are imported + reused, never redefined. ✓

### Risks accepted
- The live connected round-trip (`AnnotationBackupRoundTripConnectedTest`) COMPILES in-lane but its live WebDAV run rides WI-9 acceptance (`scripts/run-webdav-roundtrip.sh`) — the #116/#127 lesson that the connected gate catches device-only XML/crypto bugs. This is by brief design (the lane's gate is compile + JVM green).
- `WebDavBackupService` is not yet instantiated in `VReaderApp.kt` (constructed only in tests + the future UI wiring); the collector's annotation wiring is proven via the connected test's `BackupCollector(repo, annotationsRepository = annotations)`. No container change needed this WI.

## Verdict
**ship-as-is.** No Critical/High/Medium findings. locatorJSON is plain (the load-bearing contract), byte-stable + filtered + UUID-preserving collect, idempotent scoped restore, absent-section tolerated, #113 DTOs reused with no contracts change. JVM suite (11 tests) green; androidTest set compiles.
