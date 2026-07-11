---
branch: feat/133-wi1-dao-pagination
threadId: 019f52a5-10cc-74f1-ac20-ca317589e5f3
rounds: 1
final_verdict: follow-up-recommended
date: 2026-07-12
---

# Gate-4 audit — feature #133 WI-1 (book-scoped find-in-book DAO surface, TXT/MD)

**Scope:** the additive diff to `android/app/src/main/kotlin/com/vreader/app/data/SearchDao.kt`
(`matchingChunksPage`, `chunkAtOrAfter`, `matchingChunkCount`, `observeIndexState`) + the new
Robolectric in-memory Room test `android/app/src/test/kotlin/com/vreader/app/data/InBookSearchDaoTest.kt`.

**Auditor:** Codex via `scripts/run-codex.sh` (rule 53), read-only sandbox. Author/auditor separation
preserved (Codex is a separate process from the implementing Claude lane).

## Verdict: follow-up-recommended (1 round)

Codex confirmed the full requested contract holds:

- All new FTS queries use `s.id = f.rowid`, `search_sections_fts MATCH`, and `s.bookKey = :bookKey`.
- Results order by `(sectionIndex, chunkOrdinal, id)`.
- `matchingChunksPage` implements strict lexicographic `>` on the `(sectionIndex, chunkOrdinal, id)`
  tuple correctly (disjoint pages).
- `chunkAtOrAfter` implements inclusive lexicographic `>=` with `LIMIT 1` correctly (the resume path).
- Paging tests establish ordered, gapless, disjoint retrieval and an empty terminal page; resume tests
  cover re-fetching the current chunk, advancing, and exhaustion.
- `observeIndexState` is a `Flow` querying `search_index_state`.
- Tests use a real Robolectric in-memory Room database (not stubs).
- No schema, migration, or occurrence-expansion implementation was added; the existing corpus-search
  methods are untouched.

## Findings — all LOW, all adjudicated

1. **LOW — header said "DB stays v7" but the DB is version 8.** FIXED. The plan's "v7" was stale
   (the search FTS tables were added at the 6→7 migration; the DB has since advanced to v8 via the
   #135 bookmarks unique-index migration). No schema/migration change is introduced by this WI — the
   load-bearing fact. The header comment now reads "query-only, no schema change and no DB version
   bump" (no stale version number).

2. **LOW — `observeIndexState` test used two separate `first()` calls, not two emissions from one
   live Flow.** ADJUDICATED — accepted-with-rationale, NOT the suggested implementation. Collecting
   two emissions from a single Room `Flow` via `take(2).toList()` under `runBlocking` on Robolectric
   **deadlocks** Room's `InvalidationTracker` (verified empirically: the suggested change hung the test
   JVM for the full watchdog window; reverting to sequential `.first()` runs green). The established
   codebase idiom for an observable-Flow DAO test — `SearchDaoTest.observeUnsettledIndexableCount`
   (line 262) — is exactly sequential `.first()` calls. The test asserts the pre- and post-write
   emission values, which is what the UI gate actually consumes. Rationale recorded in the test's
   comment.

3. **LOW — `matchingChunksPage_usesFtsRowidJoinShape` test commentary overclaims that it distinguishes
   `s.id` from an implicit `s.rowid`.** ACCEPTED. Codex agrees the SQL itself uses the required
   `s.id = f.rowid` shape; the overclaim is only in the test's comment. The production query is correct;
   no action taken (a Low, cosmetic test-comment nit).

## Test result

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `InBookSearchDaoTest` 10/10 green (`--rerun-tasks`, actual
re-execution); full `:app:testDebugUnitTest` JVM suite 881/881 green (103 suites, 0 failures, 0 errors).
