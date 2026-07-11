---
branch: feat/128-wi6-query-pipeline
threadId: 019f4f59-6ee0-7ab0-a26f-728156492747
rounds: 2
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 Codex audit — feature #128 WI-6 (search query pipeline)

Model: gpt-5.6-sol (read-only sandbox). Two rounds via `scripts/run-codex.sh` (rule 53).

Scope: the WI-6 query/recents/VM layer — `SearchRepository` (observable text-hit Flow),
`RecentSearchesStore` (device-local MRU DataStore), `SearchViewModel` (debounce + combine + ordering
+ completeness gate), the `SearchDao.observeSearchSectionsCount` addition (fix #1), the
`SearchQueryBuilder` and/or/not/near keyword quoting (fix #3), and the AppContainer wiring — plus
the three cross-WI-review fixes.

## Round 1 — verdict: block-recommended (thread 019f4f56-4949-7f40-9c12-024f9efae547)

- **High — stale-query state overwrite during the debounce window.** The `debounce` preceded
  `flatMapLatest`, so a raw-query change did not cancel the previous query pipeline until the new
  debounced value emitted; during that window an old library/index emission could overwrite state
  while the emitted `query` field read `_query.value` (the new text), mislabeling stale rows and
  briefly showing a stale definitive no-results copy.
  - **Fix**: each settled result batch is now tagged with its originating trimmed query
    (`SearchResults(query, searched, rows)`). The state collector DISCARDS a batch whose `query` no
    longer equals the live raw query; `onQueryChange` immediately resets `searched=false` +
    `results=emptyList()` so no mislabeled rows or stale copy linger while the debounce settles.
- **Medium — the live-growth repo test did not test a held collector.** It called
  `repo.textHits("widget").first()` three separate times, so a one-shot implementation would have
  passed.
  - **Fix**: `SearchRepositoryTest.textHits_growAsSectionsPublish_forAHeldQuery` now holds ONE
    collector across both index publications and asserts successive `0 → 1 → 2` emissions (bounded
    poll). A one-shot implementation fails it.
- **Low — `distinctUntilChanged()` on the section count suppressed re-query on a same-count reindex.**
  A reindex into the same chunk count kept the total unchanged, so the distinct filter dropped the
  invalidation.
  - **Fix**: removed `distinctUntilChanged()` from `observeSearchSectionsCount()` before
    `flatMapLatest` — Room re-emits on any `search_sections` write and dedupes identical results
    downstream via the collector/StateFlow.

Confirmed correct in round 1: null/blank BuiltQuery short-circuits before the FTS MATCH (fix #2);
FTS keyword barewords are quoted (fix #3); RecentSearchesStore atomic capped/deduped MRU +
code-point-safe truncation; nil-author never matches an author query.

## Round 2 — verdict: ship-as-is (thread 019f4f59-6ee0-7ab0-a26f-728156492747)

All three round-1 findings verified fixed; no new Critical/High/Medium findings.

## Test evidence

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest` for `*SearchRepositoryTest` (6),
`*RecentSearchesStoreTest` (11), `*SearchViewModelTest` (14), `*SearchQueryBuilderTest` (13),
`*SearchDaoTest` (19) — 63/63, 0 failures. (Codex's own wrapper run reported NO_EMULATOR because the
read-only sandbox cannot create the wrapper's temp log/sentinel files; the gate was run by the lane
outside the sandbox.)
