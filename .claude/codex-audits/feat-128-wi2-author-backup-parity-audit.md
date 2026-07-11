---
branch: feat/128-wi2-author-backup-parity
threadId: 019f4ece-ca8b-7d11-b450-432cea92f050
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Codex audit — feature #128 WI-2 (author backup/restore parity)

Scope: the diff of `feat/128-wi2-author-backup-parity` vs `origin/main` — Android author
backup/restore parity. `BackupCollector.toManifestEntry` now emits `Book.author`; `RestoreImporter`
replaces its second whole-row `upsertBook` with the single `applyRestoredMetadata` seam (WI-1).

Runner: `scripts/run-codex.sh` (rule 53), model `gpt-5.6-sol`, sandbox read-only. Session
`019f4ece-ca8b-7d11-b450-432cea92f050`. Raw output: `.reports/wi2-audit-raw.txt`.

## Round 1 — verdict: ship-as-is

Codex inspected the DAO SQL, the repository seam, the importer upsert, the serializer config, and
the contract model behind the diff.

Findings confirmed (no defects):

- **(1) Collector emits author, null omitted.** `toManifestEntry` sets `author = author`; a null
  author is omitted from JSON by `BackupJson.DEFAULT`'s `explicitNulls = false` — the manifest stays
  byte-stable. Confirmed by `collect_emitsBookAuthorIntoManifestEntry` and
  `collect_nullAuthor_isOmittedFromManifestJson`.
- **(2) Second whole-row write fully removed; all metadata still applied.** The
  `upsertBook(imported.copy(...))` is gone; `applyRestoredMetadata` applies `title`, `addedAt`,
  nullable `lastOpenedAt`, and `author = COALESCE(:manifestAuthor, author)`. Author ordering is
  correct and atomic at the SQL-statement level: non-null manifest author wins; a later
  `backfillAuthorIfNull` cannot overwrite it; a null manifest author preserves an earlier backfill;
  a later backfill fills a still-null author. Title/date behavior (including clearing `lastOpenedAt`
  when the manifest value is null) matches the removed path.
- **(3) No contract change.** `BackupLibraryEntry.author: String? = null` already existed; an
  additive optional field is compatible.
- **(4) No nullability / ordering / concurrency issue.** Coroutine cancellation stays propagated by
  the surrounding restore loop; the importer DB write completes before metadata application; Room
  serializes each DAO operation.

Minor (non-blocking) observation, explicitly not a required follow-up: the
`restore_coordinatorBackfill_thenNullManifestRestore_preservesBackfill` test simulates the ordering
across two complete restores rather than injecting the backfill precisely between import and metadata
application. The DAO-level COALESCE behavior is directly exercised by the other tests, so this does
not justify blocking or a follow-up. Accepted as-is.

Codex could not run Gradle tests (read-only audit sandbox); the JVM gate
(`BackupCollectorTest`/`RestoreImporterTest`) passed in-lane with
`RUN-ANDROID-TESTS RESULT: SUCCEEDED`, and `git diff --check` was clean.

## Outcome

Zero Critical/High/Medium findings. One accepted Low (test-quality note). Final verdict:
**ship-as-is**. Ready for integration.
