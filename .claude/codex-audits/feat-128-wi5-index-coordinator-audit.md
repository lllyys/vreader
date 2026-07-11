---
branch: feat/128-wi5-index-coordinator
threadId: run-codex-wi5-2026-07-11
rounds: 2
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 Codex audit — feature #128 WI-5 (SearchIndexCoordinator)

Tool: `scripts/run-codex.sh` (rule 53, stdin-isolated, watchdog). Scope: the WI-5 diff
(`SearchIndexCoordinator.kt` + `VReaderApp.kt` wiring + `SearchIndexCoordinatorTest.kt`).

## Round 1 — verdict: follow-up-recommended

Everything requested was confirmed correct:

- `collect` (NOT `collectLatest`).
- One lifecycle-owned collector; `AtomicBoolean` start guard; injected dispatcher; single `Mutex`; no `GlobalScope`.
- Cancellation clears staging under `NonCancellable` and rethrows `CancellationException`.
- Publish is transactional + `bookExists`-guarded; all four search tables cascade from `books`.
- Streaming batches are flushed and dropped; `flushRemaining()` covers the final partial batch (bounded EPUB memory).
- EPUB/TXT/MD eligibility + current/stale/failed semantics match the contract.
- `skipped_unsupported` settled; `failed` retryable.
- `indexedText` = `SearchTextNormalizer.normalize` then `segmentCJK`.

**One finding (concurrency gap).** The terminal/retry state write (`skipped_unsupported` / `failed`)
performed `bookExists()` then `markIndexed()` as two separate operations. A delete landing BETWEEN
the check and the write makes `markIndexed()` fail its FK constraint. From the ordinary-exception
`catch` path (which itself calls the mark), that FK exception could ESCAPE the surrounding catch and
terminate the sole lifetime collector — silently stopping ALL future indexing. It could not leave an
orphan state row, but it could kill the pipeline.

## Fix applied

Both terminal writes now route through a single `markTerminalState(bookKey, status)` that wraps
`clearStaging` + `bookExists` + `markIndexed` in `runCatching` and swallows any non-`Cancellation`
failure as a benign no-op (the book is gone → nothing to record → keep draining), while still
rethrowing `CancellationException` so structured cancellation is intact. Also added a `Log.w` on the
swallowed-failure path for observability (round-2 note). New regression test
`failedBookDeletedMidMark_doesNotKillCollector` proves the collector survives a Failed book deleted
mid-mark and the healthy book still indexes.

## Round 2 — verdict: ship-as-is

> No blocking findings. The fix closes the collector-death path: both `Failed` and `Unsupported` use
> `markTerminalState`; any FK failure between `bookExists()` and `markIndexed()` is contained by
> `runCatching` so it cannot escape and terminate the sole collector; `CancellationException` is
> explicitly rethrown (including cancellation raised by `clearStaging`/`bookExists`/`markIndexed`).

Non-blocking follow-ups (accepted, not addressed in this WI):

- Add failure logging/telemetry on the swallowed path — **addressed** (`Log.w`).
- A deterministic DAO fault-injection test that forces the delete BETWEEN `bookExists()` and
  `markIndexed()` (the current regression test deletes just before `bookExists()`, which still
  exercises the FK path but not the exact instruction-level window) — deferred; the runCatching guard
  is unconditional so the exact window is covered by construction.

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `SearchIndexCoordinatorTest` 13/13 pass (indexes epub/txt/md,
skips pdf/azw3; skipped_unsupported; already-indexed skip; stale-version reindex; failed retry;
author-only-if-null; cancellation atomicity; delete-mid-index no-op; partial-batch flush 1/N-1/N/N+1;
bounded EPUB memory; corrupt isolation; failed-deleted-mid-mark survival; double-start idempotency).
