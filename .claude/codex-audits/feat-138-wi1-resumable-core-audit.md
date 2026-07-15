---
branch: feat/138-wi1-resumable-core
threadId: 019f63cc-46c6-7930-a4b1-4f6237f18c0d
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #138 WI-1 (resumable measure core in TxtPaginator)

Independent Codex audit (rule 53 `scripts/run-codex.sh`, read-only sandbox) of the WI-1 files:

- `android/app/src/main/kotlin/com/vreader/app/reader/paged/TxtPaginator.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/paged/MeasureCursor.kt`
- `android/app/src/test/kotlin/com/vreader/app/reader/paged/TxtPaginatorResumableCoreTest.kt`

Model: gpt-5.6-sol. Round transcripts: `.reports/wi1-audit-r1.txt`, `.reports/wi1-audit-r2.txt`.

## Round 1 (session 019f63c6-f937-7dd0-8a50-8147fc54f40c) — verdict: changes required

Findings, and how they were resolved:

- **Critical — sealed-page contract not implemented.** `measureFrom` emitted a page start the moment
  the page BEGAN, before its exclusive end was known, violating feature #138's sealed-page model
  (Gate-2 R2 Medium 1): a non-final page seals only once its successor's start is known; the final
  page seals at doc end.
  **Fix:** `measureFrom` now DEFERS the emit — `tryStartPage` emits the PREVIOUS pending page start
  when a new start strictly advances; the final pending page is emitted at doc end. `MeasureCursor`
  gained `currentPageStart` (the pending, unsealed page) SEPARATE from `lastSealedStart` (last
  emitted); `frontierSourceOffset == currentPageStart` while a page is pending (== the last sealed
  page's exclusive end == the next sealed page's start). A page start is never emitted before its
  range is final.

- **High — stop conditions count/cover unsealed starts.** `Pages` counted every begun page and
  `ThroughOffset` accepted `frontier > offset` with no successor page.
  **Fix:** dissolved by the sealed-emit change — `Pages` counts SEALED (emitted) pages;
  `ThroughOffset` requires `lastSealedStart in 0..offset && currentPageStart > offset` (a sealed
  page whose `[start, end)` contains the target, its successor having started).

- **High — no cooperative coroutine cancellation.** The CPU-bound loop checked only the custom
  `PaginationToken`.
  **Fix:** `measureFrom` is now `suspend` and calls `currentCoroutineContext().ensureActive()` per
  chunk, in addition to `checkCancelled(token)`.

- **Medium — `measurePages(0)`/negative + negative `targetOffset` edge cases.**
  **Fix:** `measurePages(additionalPages < 1)` is a no-op returning the cursor unchanged;
  `measureThroughOffset` clamps a negative target to 0.

- **Medium — the equivalence test compares core-vs-core.** Accepted with rationale: the existing
  `TxtPaginatorTest` (25 tests with HARDCODED expected page-start arrays) runs against the refactored
  `index(...)` and is the preserved reference for byte-identity vs the pre-refactor loop; the new
  suite additionally proves incremental == full-pass. New sealed-page tests were also added
  (+1 lookahead, one-page-at-doc-end, exact-boundary `ThroughOffset`, zero/negative validation,
  negative-target clamp), addressing the "decisive sealed-page tests" gap.

## Round 2 (session 019f63cc-46c6-7930-a4b1-4f6237f18c0d) — verdict: ship-as-is

> No remaining Critical/High/Medium/Low findings.
> Final verdict: **ship-as-is**.

Round 2 confirmed: `index(...)` is still byte-identical to the pre-refactor whole-document loop
(`index` drives `StopCondition.None` to completion in one `measureFrom` call, so the deferred emit
does not change its collected set or order — and the 25 hardcoded-array `TxtPaginatorTest` cases
pass); sealed-page emission is now correct (a page emitted only when its exclusive end is final, the
+1 lookahead, the final page at doc end, no double-emit, strict advance against `currentPageStart`);
resumed-cursor determinism is preserved (the carry + `currentPageStart` fully capture the chunk
boundary); coroutine cancellation and the `Pages`/`ThroughOffset` stop conditions are correct.

## Test gate

`ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests 'com.vreader.app.reader.paged.*'"
scripts/run-android-tests.sh` → `RUN-ANDROID-TESTS RESULT: SUCCEEDED`. Per-suite: TxtPaginatorTest
25/0, TxtPaginatorResumableCoreTest 13/0, PageOffsetMapTest 9/0, TxtPageIndexTest 9/0,
TxtPageNavigatorTest 16/0 (72 total, 0 failures). A deliberate resume-carry regression was injected
to confirm the new suite is RED-discriminating (2 failures), then reverted → GREEN.
