---
branch: feat/133-wi5-epub-search-engine
threadId: 019f5310-326b-75b2-8258-8ce17c64b9ee
rounds: 3
final_verdict: ship-as-is
date: 2026-07-12
---

# Gate-4 audit — feature #133 WI-5 (EpubInBookSearchEngine over Readium's own SearchService)

Independent Codex audit (`scripts/run-codex.sh`, rule 53) of the WI-5 diff:
`android/app/src/main/kotlin/com/vreader/app/search/EpubInBookSearchEngine.kt` (NEW) +
`android/app/src/test/kotlin/com/vreader/app/search/EpubInBookSearchEngineTest.kt` (NEW).

Author (implementer) ≠ auditor (Codex) — rule 48 separation preserved. 3 rounds, ending clean.

## Round 1 — `block-recommended`

Findings + resolutions:

- **Critical — pagination not resumable / data loss.** The engine closed the iterator in `finally` and
  discarded budget-overflow locators; `EpubSearchPage` carried no continuation, so WI-6 could not page
  further and past-budget results were lost. **RESOLVED**: made paging genuinely resumable + COMPLETE
  (the round-3 completeness contract, the EPUB analog of the FTS intra-chunk cursor). `Results` now
  carries an `EpubSearchCursor` (the LIVE `SearchIteratorSource` + un-placed `leftover` locators);
  `nextPage(cursor)` resumes; overflow locators are NEVER discarded. The iterator is closed ONLY on a
  terminal page (exhaustion / error / zero hits), staying open behind the cursor while `moreAvailable`.
  Added an overflow-completeness test (a Readium page larger than `pageSize` retrieved IN FULL across
  pages — union = all, no gap/dupe) + a live-cursor resume test.
- **Medium — nullable `Locator.text` fields untested.** Production mapping used `orEmpty()`; the test
  builder required non-null strings. **RESOLVED**: `loc(...)` now accepts nulls; a test asserts
  before/highlight/after = null all map to `""`.
- **Medium — iterator closure not asserted.** **RESOLVED**: closure asserted on exhaustion, immediate
  error, and mid-fill error.
- **Low — invalid `pageSize` unsafe.** **RESOLVED**: `require(pageSize > 0)` at construction + tests
  for `0` and `-1`.

## Round 2 — `block-recommended` (round-1 findings confirmed resolved; 2 NEW Highs from the redesign)

- **High — abandoned live cursor leaked the iterator.** `EpubSearchCursor` owned a live Readium iterator
  but exposed no `close()`; closing only on terminal pagination did not cover abandoned cursors (new
  query, UI dismiss, declined "load more"). **RESOLVED**: `EpubSearchCursor.close()` is now public +
  idempotent; WI-6 disposes an abandoned cursor via it.
- **High — cursor reusable / concurrency-unsafe.** `nextPage(cursor)` did not consume/invalidate the
  cursor: reuse replayed the immutable `leftover` (duplicate hits); concurrent calls raced the shared
  iterator + `close()`. **RESOLVED**: `nextPage` claims the cursor atomically (`compareAndSet`) BEFORE
  touching the iterator; a reused / concurrently-dispatched cursor returns `Error` without replaying
  leftover or racing the iterator. `consume()` and `close()` share ONE atomic guard, so exactly one of
  {resume, close} wins per cursor (a consumed cursor's `close` is a no-op — the fresh cursor owns the
  iterator; a closed cursor's resume is rejected). Added reused-cursor-rejected, closed-cursor-resume-
  rejected, abandoned-close-idempotent, and close-exactly-once-across-full-drain tests (fake iterator
  now counts closes — resolves the round-2 "test weakness" note).

## Round 3 — `ship-as-is` (FINAL, clean)

No blocking findings. Both prior Highs confirmed genuinely resolved:
- Abandoned cursors close idempotently; the shared atomic guard makes `consume()`/`close()` mutually
  exclusive; reuse/concurrent resume fails before reading leftovers or touching the iterator; a
  successful resume transfers ownership to a fresh cursor or the terminal close path; a full drain
  preserves every locator, emits no duplicates, and closes exactly once; a cancellation/exception in
  `fillPage()` closes the claimed iterator.
- Readium 3.3.0 API usage confirmed correct: `publication.isSearchable` (extension property), nullable
  `publication.search(query)`, `next()` folded as `Try<LocatorCollection?, SearchError>` (success wrapping
  null = exhausted), nullable `Locator.text` before/highlight/after.
- The engine does NOT touch the FTS index and does NOT route EPUB through the TXT/MD resolver.

Accepted low (auditor-agreed, non-blocking):
- The engine file is ~348 lines (over the ~300 soft guideline). The co-located engine + 5 result DTOs +
  3 seam interfaces + lifecycle KDoc form ONE cohesive WI-6-facing contract; splitting solely for the
  soft limit is out of this WI's single-file write-set and would add churn (rule 55 degrades — a new
  file needs orchestrator-owned structural regen). Auditor explicitly: "not blocking."
- The concurrency tests validate reuse sequentially, not a literal resume-vs-resume race; the auditor
  agreed the `AtomicBoolean.compareAndSet(false, true)` design is nevertheless sufficient (exactly one
  contender crosses the ownership boundary).

Test gate: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:compileDebugKotlin :app:testDebugUnitTest`
(targeted `*EpubInBookSearchEngineTest` + full JVM `:app:testDebugUnitTest`), pure JVM, no emulator.
(Codex ran in a read-only env and could not execute the wrapper itself — the implementer ran it.)
