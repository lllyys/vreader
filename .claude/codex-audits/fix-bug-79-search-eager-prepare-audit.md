---
branch: fix/bug-79-search-eager-prepare
threadId: codex-exec (read-only sandbox, 2 rounds)
rounds: 2
final_verdict: follow-up-recommended
date: 2026-05-30
---

# Gate-4 Codex audit — Bug #79 (REOPENED, GH #1266) search eager-prepare regression

## Scope

Restore the original Bug #79 fix (eager `prepareService()` on reader open, so the
FIRST search of a session shows the real search field instead of the "Preparing
search…" placeholder) WITHOUT re-introducing the Bug #89-class book-open stall
that motivated its removal in commit `fd12ab0e` (the cold `sqlite3_open` +
`PRAGMA integrity_check` + FTS5/table DDL ran synchronously on the @MainActor).

Files audited:
- `vreader/Views/Reader/ReaderSearchCoordinator.swift`
- `vreader/Views/Reader/ReaderContainerView.swift`
- `vreaderTests/Views/Reader/BookOpenPerformanceTests.swift`

Fix shape:
1. `ReaderContainerView` `.task` calls `searchCoordinator.prepareEagerly(fingerprint:)`
   on reader open (restores #79).
2. `makePersistentStore()` is now `nonisolated`; `prepareService` builds the cold
   store on `Task.detached(priority:.userInitiated)` and hops back to @MainActor
   only for the state assignment + the (I/O-free) `SearchViewModel` init (the #89
   seam — eager prep never blocks reader open).
3. (round-2) Single-flight coalescing: an in-flight `prepareTask: Task<Void, Never>?`
   ensures concurrent callers (reader-open `prepareEagerly` racing search-sheet
   `setup`) join ONE cold open instead of racing two.

## Round 1 — verdict: follow-up-recommended

**Medium** (FIXED in round 2):
- `prepareService` did not coalesce in-flight prepares. Two callers could both
  pass the initial `searchService == nil` guard and open two SQLite connections
  concurrently; a transient `SQLITE_BUSY/LOCKED` during concurrent DDL could let
  `makePersistentStore`'s in-memory fallback win the post-await guard and become
  the session store, silently losing persistent indexing. The post-await guard
  prevented double *assignment* but not duplicate cold opens / wrong-store
  selection.
  → Fixed by adding single-flight coalescing (stored in-flight `prepareTask`;
    concurrent callers `await inFlight.value`). The body moved to a private
    `runPrepare(fingerprint:)`.

**Low** (1 partially addressed, both accepted — see round-2):
- The "off-main" test was mostly wiring.
- The detached task is unstructured / uncancelled.

**Positive checks (round 1):** the `await Task.detached(...).value` does not pull
heavy work back onto MainActor; capturing `Self` in the detached closure is sound
(reaches only nonisolated static members); the losing duplicate store deinits
safely (`SearchIndexCore.deinit` → `sqlite3_close`) because it is never published.

## Round 2 — verdict: follow-up-recommended

**No Critical / High / Medium findings.** (Gate-4 acceptance bar met.)

**Low findings — accepted with rationale:**

1. `concurrentPreparesCoalesce` does not *prove* single-flight without an
   injectable store-factory/counter seam — its assertions would pass even if two
   stores were opened (it observes only the final published service + a later
   no-op).
   **Accepted**: adding a store-factory DI seam + a blocking probe is a larger
   test-infra change beyond this focused regression fix. Codex independently
   verified the gate's correctness by reasoning ("there is no `await` between the
   `prepareTask` nil check, task creation, and assignment, so two callers cannot
   both pass the nil check and assign separate tasks"). The test still guards the
   stable-published-service + no-op-after-settle invariants. Filed as a potential
   follow-up (test seam for single-flight proof).

2. The prepare work remains unstructured/uncancelled — if the view `.task` is
   cancelled, the MainActor task + detached SQLite open can run to completion and
   keep the coordinator alive until done.
   **Accepted**: Codex confirms this is "not a leak cycle … not a correctness
   blocker," a lifecycle/resource follow-up. The store is ARC-managed and
   `SearchIndexCore.deinit` closes SQLite, so there is no permanent leak. A
   cancellation-aware teardown can be a separate hardening follow-up.

**Audit answers confirmed by the auditor:**
- Single-flight gate is correct on @MainActor (no `await` in the check→assign window).
- Strong `self` capture is not a retain cycle in the normal path (temporary; cleared after await).
- `runPrepare`'s post-hop `guard searchService == nil` is now defensive/harmless (protects future direct calls / refactors), not load-bearing for concurrent callers.
- No double-prepare path through `setup()` — `setupStarted` is MainActor-isolated; `setup()` joins `prepareService` when needed.

## Tests

`vreaderTests/Views/Reader/BookOpenPerformanceTests.swift` (Bug #89 suite):
- `searchPrepNotCalledOnInit` — coordinator does NO work in `init()`.
- `prepareServiceReadiesViewModel` — eager prepare readies service + VM (no placeholder).
- `storeOpenIsOffMainActor` — eager prepare driven from a non-MainActor task readies the VM (off-main open).
- `concurrentPreparesCoalesce` — concurrent `prepareEagerly` + `prepareService` publish a stable service; a later prepare is a no-op.

Full `vreaderTests` gate: green (see PR/commit). The previously-observed
`SearchWiringTests.backgroundIndexingCoordinatorIndexesBook()` failure is a
pre-existing timing flake (`Task.sleep` polling of a `.background`-priority task,
untouched by this diff); it passes in the targeted re-run.
