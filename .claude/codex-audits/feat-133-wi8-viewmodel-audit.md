---
branch: feat/133-wi8-viewmodel
threadId: 019f5371-9cec-7602-b636-162e09dd6033
rounds: 3
final_verdict: follow-up-recommended
---

# Gate-4 Codex audit — feature #133 WI-8 (in-book-search ViewModel)

Independent Codex audit (author/auditor separation; `scripts/run-codex.sh`, read-only sandbox,
model gpt-5.6-sol) of the new WI-8 files:

- `android/app/src/main/kotlin/com/vreader/app/search/InBookSearchViewModel.kt`
- `android/app/src/main/kotlin/com/vreader/app/search/InBookSearchViewState.kt`
- `android/app/src/test/kotlin/com/vreader/app/search/InBookSearchViewModelTest.kt`

## Round 1 — session `019f5364-5ac8-72a1-a328-6b6dd4a8b0de` — 0 Critical, 2 High, 2 Medium, 1 Low

- **H1** — `loadMore()` permitted concurrent appends: rapid scroll callbacks could double-consume the
  SAME `nextCursor` → duplicate pages / expired EPUB cursor.
- **H2** — a superseded first-page's late completion mutated `nextCursor`/`currentGroups`/`resultsQuery`
  before the stale-discard check → could corrupt the active query's paging metadata.
- **M1** — reset-on-change left paging state live through the debounce window + didn't cancel an active
  append.
- **M2** — `onDismiss()` left in-flight search/append coroutines running → a late completion could mint an
  abandoned EPUB cursor.
- **L1** — the stale-response test had no suspension gate (verified sequential replacement, not a late race).

**Fix:** a single monotonic `generation` search-session token (bumped per distinct query, on empty-query
reset, and on dismiss) gating ALL paging-field writes + result commits; a single-flight `loadingMore` guard;
`TaggedContent` carries the generation; added a `GatedSearcher` (CompletableDeferred gate) + 3 race tests
(rapid-double-loadMore, late-first-page-superseded, dismiss-during-first-page).

## Round 2 — session `019f5368-cc5d-7560-b009-918b65f724ea` — 0 Critical, 1 High, 1 Medium

- **H** — the session was invalidated only after the 250 ms debounce (`flatMapLatest`), leaving a window
  where an in-flight `loadMore` could commit into a new query's state, and `loadMore` read `_query.value`
  inside the coroutine (could page the new query text).
- **M** — dismiss could still leak a repository-owned EPUB cursor minted AFTER `closeAllEpubCursors()`.

**Fix:** `onQueryChange()` now begins a new session SYNCHRONOUSLY when the trimmed query changes (bumps
generation + clears paging + records `sessionQuery`); `loadMore()` captures + threads `sessionQuery`, never
`_query` inside the coroutine; a stale (`gen != generation`) EPUB completion reaped its just-minted iterator
via `closeAllEpubCursors()`. Added 2 tests (queryChange-during-in-flight-loadMore, loadMore-threads-session-
query) + a live-cursor registry in `GatedSearcher`.

## Round 3 — session `019f536e-fab7-7280-9a76-deba0c0c2cdb` — 0 Critical, 1 High, 0 Medium

- **H (self-introduced by the round-2 M fix)** — the reap-on-stale used the CLOSE-ALL
  `closeAllEpubCursors()`, which could close a LIVE cursor a newer session had already minted.

**Fix:** REVERTED the inline reap-on-stale in both `mapOutcome()` and `loadMore()` (the over-close bug is
gone). The stale-minted EPUB iterator is instead reaped by the next `beginSession()` →
`closeAllEpubCursors()` (any query change / clear / dismiss) and unconditionally by `onCleared()` — a
BOUNDED resource hold (bounded by sheet re-interaction / VM lifetime), never an unbounded leak. Documented
in `mapOutcome()`'s KDoc; the `dismiss_duringInFlightFirstPage` test asserts `onCleared()` reaps to 0.

## Confirmation — session `019f5371-9cec-7602-b636-162e09dd6033` — final_verdict: follow-up-recommended

- No stale-path `closeAllEpubCursors()` remains in `mapOutcome()`/`loadMore()` — the over-close bug is
  eliminated. Generation invalidation + single-flight `loadMore` remain intact. **No new Critical/High/
  Medium found.**
- The remaining residual is BOUNDED and correctly attributed to the repository's close-all-only API. A
  precise per-session reap needs a repository session-scoped close API — **owned by WI-6
  `InBookSearchRepository`, OUT of this WI's write-set** — so it is a named WI-6 follow-up. A VM-only
  serialization scheme could avoid the overlap but adds substantial coordination/latency complexity not
  warranted for WI-8.

**Terminal state: zero Critical/High/Medium in the VM's own scope; one bounded, documented residual
deferred to a WI-6 follow-up (close-all API limitation).** Targeted suite green (27 tests, 0 failures).
