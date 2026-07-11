---
branch: feat/133-wi7-index-state
threadId: 019f533b-20f3-7b42-a95c-d51d44bdba4b
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 Codex audit — feature #133 WI-7 (per-book index-state → in-book-search UI-state gate)

Independent Codex audit (rule 53, `scripts/run-codex.sh`, stdin-isolated) of the two files this WI
touches:

- `android/app/src/main/kotlin/com/vreader/app/search/IndexStateGate.kt` (impl)
- `android/app/src/test/kotlin/com/vreader/app/search/InBookIndexStateTest.kt` (tests)

Read-only context: `search/SearchIndexCoordinator.kt` (authoritative status vocabulary +
`INDEXER_VERSION` + `isEligible`), `data/SearchDao.kt` (`observeIndexState`), `data/SearchEntities.kt`
(`SearchIndexStateEntity`).

## Round 1 — session `019f5334-1b87-75b3-9a54-3d90c4bbd84f`

Verdict: **do not ship as-is.** Findings:

- **High — current-version unexpected status could stay `Indexing` forever.** The v1 ladder mapped
  ANY non-settled status (including a current-version typo/`indexing`) to `Indexing`. But
  `SearchIndexCoordinator.isEligible` re-indexes ONLY missing / stale-version / current-version-`failed`
  rows — a current-version non-`failed` status is never re-indexed and never settles, so `Indexing`
  would spin the UI forever waiting for a `Flow` emission that can't come. The gate did not faithfully
  mirror the coordinator.
- **Low — Flow guarantees asserted in comments but not tested** (non-FTS never subscribes to the
  index-state flow; `hasOccurrence()` only consulted for an `indexed` row; cancellation propagates).

### Fixes applied (commit `d475e3e`)

- Collapsed `evaluate()` and the observed `evaluateSuspending()` onto ONE `classify()` ladder that is a
  faithful mirror of `isEligible`: **version-staleness dominates** (a MISSING row or ANY status at a
  stale `indexerVersion` → `Indexing`, because the coordinator WILL re-index → it settles); at the
  current version, `failed` → `Failed` (retryable), `skipped_unsupported` → `Unsupported`, `indexed` →
  occurrence-check (`Ready`/`NoResults`), and any **UNEXPECTED** current-version status → **`Failed`**
  (the recoverable terminal), never `Indexing`. This also removed the duplicated decision order the
  audit flagged as drift risk.
- Test updated: `txt_currentVersionUnexpectedStatus_isFailed_notIndexingForever` codifies the fix;
  `txt_staleVersionUnexpectedStatus_isIndexing` + `txt_failedStaleVersion_isIndexing` codify that
  version-staleness dominates; no test preserves the old forever-`Indexing` behavior.
- Added the three Low-finding tests: `observe_nonFts_neverSubscribesToTheIndexStateFlow` (a
  subscription-counting flow proves EPUB/PDF/AZW3 never collect it), `observe_hasOccurrence_calledOnlyForIndexedRow`,
  `observe_cancellingScope_stopsCollecting`.
- File header + KDoc synced to the corrected semantics (rule 22).

## Round 2 — session `019f533b-20f3-7b42-a95c-d51d44bdba4b`

Verdict: **ship-as-is.** No remaining findings. Verified by inspection:

- `classify()` faithfully mirrors `SearchIndexCoordinator.isEligible` for missing / stale-any-status /
  every current-version status.
- Unexpected current-version statuses resolve to `Failed`, never permanent `Indexing`.
- EPUB → `Ready`, PDF/AZW3 → `Unsupported`; none subscribe to the FTS flow or call `hasOccurrence`.
- `hasOccurrence` evaluated only for a current-version `indexed` row.
- Flow correctness: `distinctUntilChanged`, injected `flowOn(dispatcher)`, structured cancellation, no
  hidden scope/dispatcher.
- `evaluate()` and `observe()` share one classification ladder; no duplicate/dead decision logic.

(Codex's own Gradle run was blocked by its read-only sandbox; the test evidence is the local
`RUN-ANDROID-TESTS RESULT: SUCCEEDED` for the targeted suite AND the full JVM suite, run by the lane.)

## Rounds summary

| Round | Session | Verdict |
|---|---|---|
| 1 | `019f5334-1b87-75b3-9a54-3d90c4bbd84f` | do-not-ship-as-is (1 High, 1 Low) — fixed |
| 2 | `019f533b-20f3-7b42-a95c-d51d44bdba4b` | ship-as-is (0 findings) |
