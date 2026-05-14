---
branch: fix/issue-653-epub-indexer-actor-deallocates
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #187 — EPUB search indexer actor deallocates before processing (audit log)

## Context

GH #653 / bugs.md row #187. Filed by verify-cron 2026-05-14 while
attempting to verify bug #182 fix (EPUB cross-chapter search
highlight). Symptom: EPUB search returns "No Results" for words
clearly visible in the open chapter (e.g. "emphasized" on chapter
1's screen). Reproducible on iPhone 17 Pro Sim at v3.21.50 with
mini-epub3 fixture.

## Codex availability

Codex MCP unavailable this session (manual fallback per rule 47).
Same posture as bugs #167/#174/#176/#177/#178/#182/#183 + Feature
#52 WI-1/WI-2 audits in this session.

## Root cause investigation

### What I observed directly

- `Library/Application Support/SearchIndex/search.sqlite3` on the sim contained ONE indexed book: `txt:0000...f1ca5e:18027`, indexed `2026-05-12T18:02:22Z` (yesterday). NO EPUB has ever been indexed in this sim's history.
- Today's session: `vreader-debug://reset` → `seed?fixture=mini-epub3` → tap book → search panel → paste query. Search returns "No Results" for every term tried (5+ words including ones visible on-screen). DB file mtime stayed at 2026-05-13 02:02 — today's flow did NOT write to the index.
- `vreader-debug://snapshot` confirms the book is loaded: `currentBookId: epub:f284fd07...:2198`, format `epub`, no `lastError`.
- Existing `BackgroundIndexingCoordinatorTests` all retain their `coordinator` as a local that lives through the entire test function via `try? await Task.sleep(for: .milliseconds(100))`. Tests pass because they hold the strong reference; the production failure mode is hidden.

### Reasoning chain

1. `ReaderSearchCoordinator.setup(...)` (the on-search-panel-open path):
   ```swift
   } else {
       let coordinator = BackgroundIndexingCoordinator(searchService: service)
       await Self.enqueueBookIndexing(coordinator: coordinator, ...)
       searchViewModel?.retriggerIfNeeded()
   }
   // function returns; `coordinator` local goes out of scope
   ```
   The `BackgroundIndexingCoordinator` is created as a function-scope local. No instance retainer.

2. Inside `coordinator.enqueueIndexing(...)`:
   ```swift
   pendingJobs.append((key, textUnits, segmentBaseOffsets))
   if !isProcessing {
       isProcessing = true
       Task.detached(priority: .background) { [weak self] in
           await self?.processQueue()
       }
   }
   ```
   `Task.detached` is scheduled but NOT yet running. The closure captures `self` weakly.

3. Lifetime race:
   - Caller awaits `enqueueIndexing` → actor work runs → `Task.detached` is scheduled → actor's `enqueueIndexing` returns control to caller.
   - Caller (`enqueueBookIndexing`) returns → `setup`'s local `coordinator` goes out of scope → ARC drops the strong reference → actor is deallocated.
   - System schedules the detached `.background` priority task to run → closure body begins → `await self?.processQueue()` → `self?` resolves to nil → `processQueue` never called → `pendingJobs` never drained → FTS5 store never written.

4. Why EPUB exposes this more than TXT:
   - TXT enqueue path (`extractWithOffsets` → `enqueueIndexing`): the extractor does synchronous `Data(contentsOf:)` + a small `decodeForDisplayAndSearch` step. Total time from `coordinator` creation to local-out-of-scope is short. The detached task often wins the race.
   - EPUB enqueue path: `EPUBParser.open(...)` → spine iteration → text extraction per spine item → HTML strip → `parser.close()`. Multiple `await` suspension points, each potentially yielding to other queued work. Total time from `coordinator` creation to local-out-of-scope is much longer. By task-start time, the actor is almost certainly deallocated.
   - The race is non-deterministic but EPUB's slower path makes loss the dominant outcome — hence "search never works for EPUB" while "search sometimes works for TXT".

### Empirical confirmation

Added regression test `enqueueIndexing_processesEvenWhenCallerDropsCoordinator` that creates the coordinator in an inner `do { ... }` scope, enqueues, exits scope (dropping the local strong reference), then sleeps for 300ms and asserts `indexCallCount == 1`.

**Pre-fix run** (with `[weak self]`):
```
✘ Test enqueueIndexing_processesEvenWhenCallerDropsCoordinator() recorded an issue at BackgroundIndexingCoordinatorTests.swift:327:9: Expectation failed: (callCount → 0) == 1
```
`callCount` is 0 — the actor was deallocated before `processQueue` ran. Exactly matches the production symptom.

**Post-fix run** (with strong `self`):
```
✔ Test enqueueIndexing_processesEvenWhenCallerDropsCoordinator() passed after 0.319 seconds.
```
`callCount` is 1 — strong capture keeps the actor alive until processQueue completes.

This is a definitive root-cause confirmation, not a guess.

## Fix shape

Single-line production change in `vreader/Services/Search/BackgroundIndexingCoordinator.swift`'s `enqueueIndexing`:

```diff
- Task.detached(priority: .background) { [weak self] in
-     await self?.processQueue()
- }
+ Task.detached(priority: .background) {
+     await self.processQueue()
+ }
```

Why strong-self is correct here (and the `[weak self]` was the bug, not a load-bearing design choice):

- Actors are reference types. `Task.detached` captures `self` strongly by default — this is the standard pattern for "schedule background work that must complete."
- The actor's invariant immediately above the Task creation is: `if !isProcessing { isProcessing = true; <schedule task> }`. Once we flip `isProcessing = true`, the actor MUST live to drain `pendingJobs`. The task is the only thing that flips `isProcessing` back to false. So the strong reference is exactly bounded by "queue has work."
- When `processQueue` returns (queue drained, `isProcessing = false`), the Task closure ends and its strong reference is released. The actor can then be deallocated normally if no other references exist. No leak.
- Cancellation: `cancelIndexing(fingerprint:)` removes pending jobs and updates `cancelledKeys`. `processQueue` checks `cancelledKeys` per-job and skips. The strong-self capture doesn't prevent cancellation — the task still cooperates correctly.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Services/Search/BackgroundIndexingCoordinator.swift` (modified, 1-line semantic change + 14-line explanatory comment) | strong self-capture in Task.detached | reviewed |
| `vreaderTests/Services/Search/BackgroundIndexingCoordinatorTests.swift` (modified, +47 LOC test) | regression test `enqueueIndexing_processesEvenWhenCallerDropsCoordinator` | reviewed |
| `docs/bugs.md` row #187 | TODO → FIXED with FIXED note + root cause + verification evidence | reviewed |

## Manual audit evidence

### Files read

- `vreader/Services/Search/BackgroundIndexingCoordinator.swift` (full, pre-edit 154 LOC) — confirmed actor structure, enqueueIndexing's Task.detached scheduling, processQueue's queue drain.
- `vreader/Views/Reader/ReaderSearchCoordinator.swift` (lines 55-114, 147-225) — confirmed caller pattern (local `coordinator`, awaited, returns, drops).
- `vreader/Services/Search/EPUBTextExtractor.swift` (full, 169 LOC) — confirmed extraction logic is correct; spine iteration produces valid TextUnits for mini-epub3 (regex-based HTML strip).
- `vreaderTests/Services/Search/BackgroundIndexingCoordinatorTests.swift` (lines 75-130) — confirmed existing tests use local-coordinator-via-sleep retention; the production failure mode wasn't exercised before this fix.
- `vreaderTests/Integration/SearchWiringTests.swift` (head) — confirmed the integration test bypasses the BackgroundIndexingCoordinator entirely (calls `searchService.indexBook` directly), so it doesn't catch this either.
- `Library/Application Support/SearchIndex/search.sqlite3` (queried via sqlite3) — empirical confirmation that only TXT was ever indexed; no EPUB row exists historically.

### Symbols verified

- `BackgroundIndexingCoordinator.enqueueIndexing(fingerprint:textUnits:segmentBaseOffsets:) async` ✓
- `BackgroundIndexingCoordinator.processQueue() async` (private) ✓ — drains `pendingJobs`, sets `isProcessing = false` at the end.
- `MockSearchService.indexCallCount` (test mock) ✓ — incremented in `indexBook(...)`.
- `Task.detached(priority: .background) { ... }` ✓ — standard concurrency API; strong capture by default unless explicitly weakened.

### Edge cases checked

1. **Caller drops local coordinator immediately after enqueue (the bug)**: pre-fix → `callCount == 0`. Post-fix → `callCount == 1`. **Verified by `enqueueIndexing_processesEvenWhenCallerDropsCoordinator`.**
2. **Caller holds strong reference (existing tests' pattern)**: works under both pre-fix and post-fix because the local retains the actor. Existing 13 tests still pass.
3. **Cancellation while pending**: `cancelIndexing(fingerprint:)` removes from `pendingJobs` and inserts into `cancelledKeys`. `processQueue` checks `cancelledKeys` before and after each job. Strong-self doesn't interfere — cancellation cooperates via state, not retention.
4. **Multiple sequential enqueues**: `pendingJobs.append(...)` adds; if `isProcessing` is already true, no new Task is scheduled (existing task drains all jobs serially). Strong-self pattern unchanged.
5. **Empty textUnits**: existing test `enqueueEmptyTextUnits` passes — `searchService.indexBook` called with empty list, status flips to `indexed`. No change in behavior.
6. **indexBook throws**: existing test `statusFailedAfterError` passes — error is caught, status flips to `.failed(msg)`. Strong-self holds through the failure path; actor deallocates when queue empty.
7. **Test isolation**: the regression test uses `nonisolated(unsafe) weak var weakCoordinator: BackgroundIndexingCoordinator?` to track the weak reference without retaining. Swift 6 strict concurrency satisfied. The actor is `Sendable`; the weak var is read-only inside the test.

### Concurrency / Swift 6

- `BackgroundIndexingCoordinator` is an `actor` — isolation is the safety guarantee.
- `Task.detached(priority: .background)` creates a task on the global concurrent executor. The closure body uses `await` to hop into the actor's isolation for `processQueue()`.
- Strong-self capture is the default for closures over reference types; it's only `[weak self]` (the previous code) that was unusual and incorrect here.
- Build clean under `SWIFT_STRICT_CONCURRENCY: complete`.

### VReader compliance

- Swift 6 strict concurrency: clean.
- `@MainActor` correctness: not applicable (actor type, non-MainActor).
- File size: BackgroundIndexingCoordinator.swift 168 LOC (was 154; +14 for explanatory comment). Under 300.
- Bridge safety: not applicable.
- DEBUG gating: not applicable.

### Risks accepted

- **Strong-self holds actor alive while pendingJobs has work**: this is the intended behavior; documented in the comment. The actor voluntarily releases its self-reference when `processQueue` returns. No risk of leak.
- **Race-condition recovery in extreme cases**: if `cancelIndexing` is called after the task was scheduled but before `processQueue` runs its first iteration, the cancellation is recorded in `cancelledKeys` and the first-job check skips. Strong-self doesn't prevent this — cancellation cooperates via state, not retention.
- **Test relies on a 300ms sleep**: same pattern as the existing tests (which use 100-300ms). May be flaky on extremely slow CI runners. If observed in CI, increase to 500ms; the assertion is the load-bearing piece.

### Tests added

- `vreaderTests/Services/Search/BackgroundIndexingCoordinatorTests.swift::enqueueIndexing_processesEvenWhenCallerDropsCoordinator` — 1 new test that directly reproduces the bug:
  - Creates `BackgroundIndexingCoordinator` inside `do { ... }` block (inner scope).
  - Enqueues one indexing job.
  - Exits scope (drops local strong reference).
  - Sleeps 300ms for background task to run.
  - Asserts `mock.indexCallCount == 1`.

Pre-fix: fails with `callCount → 0`. Post-fix: passes.

Total: 14 tests in BackgroundIndexingCoordinatorTests pass.

## Downstream unblocks

This fix should restore EPUB (and any other format's) background indexing for fresh book opens. Post-merge, both:
- **Feature #2** (Highlight search result at destination) EPUB-leg device verification — previously blocked because search returned no results
- **Bug #182** (EPUB cross-chapter search highlight) close-gate device verification — same precondition

should become reachable.

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — the diagnosis was confirmed empirically (pre-fix test fails, post-fix passes); the fix is a 1-character semantic change (`[weak self]` → strong) with a 14-line documenting comment; the regression test prevents recurrence | n/a |

## Final verdict

**ship-as-is** — root cause directly confirmed by the regression
test; the fix is minimal (single-line change in production); the
test prevents regression. Strong-self capture is the standard
pattern for "schedule background work that must complete" and the
actor's invariant (`isProcessing` flip requires drain) makes it
correct here. 14/14 tests pass post-fix.
