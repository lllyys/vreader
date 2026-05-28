---
branch: fix/issue-1226-search-driver-premature-nil
threadId: 019e6dcf-0443-7611-a6f5-d878bccc1c24
rounds: 2
final_verdict: ship-as-is
date: 2026-05-28
---

# Codex audit — Bug #1226 (DebugBridge search-driver premature-nil)

Fix: `ReaderContainerView.awaitSearchResult` returned nil ~106ms after setting
`viewModel.query`, BEFORE the 300ms-debounced FTS search ran, because the
pre-search default state (isSearching=false, empty results, hasMore=false)
tripped the `!hasMore → return nil` fail-fast. The per-poll decision was
extracted into a pure, `nonisolated`, unit-testable function
`searchResultPollAction(...)` with a `searchObserved` flag + a grace deadline
(`min(0.8, timeout)`).

Files audited:
- `vreader/Views/Reader/ReaderContainerView+DebugBridgeSearch.swift` (consumer)
- `vreader/Views/Reader/ReaderContainerView+SearchPollAction.swift` (pure fn, round 2 relocation)
- `vreaderTests/Views/Reader/ReaderContainerViewDebugBridgeSearchTests.swift`

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| ReaderContainerView+DebugBridgeSearch.swift:350 | Medium | Gate protected only `.giveUp`, not `.resolved`/`.loadMore`. During the debounce window the sheet can hold STALE results from a prior query; the first poll could tap an old result or paginate against stale page state before the new search runs. | **Fixed** — hoisted the Bug #1226 gate (`if !searchObserved && !graceElapsed { return .keepPolling }`) ABOVE all three settled interpretations, so nothing resolves/paginates/gives-up until a search is observed or grace elapses. Added 2 regression tests (`preSearchStaleResults_keepsPolling_notResolved`, `preSearchStaleHasMore_keepsPolling_notLoadMore`). |
| ReaderContainerView+DebugBridgeSearch.swift:1 | Low | File grew to 365 lines, over the ~300 guideline. | **Fixed** — relocated the enum + pure function into a new DEBUG-only file `ReaderContainerView+SearchPollAction.swift` (~57 lines). Driver file back to ~322 (net +3 vs the pre-fix 319; the 319 baseline was pre-existing and out of scope for this bug). |

## Round 2

Re-audited the relocated pure function + consumer. Codex verdict verbatim:

> No Critical/High/Medium findings. Ship verdict: the hoisted pre-search gate
> closes the stale-results/stale-`hasMore` hole, post-search behavior is
> preserved, and the DEBUG-only extraction is wired into the app target and
> tests cleanly.

## Summary

2 rounds. Round 1: 1 Medium + 1 Low, both fixed. Round 2: clean.
**Verdict: ship-as-is.** 10 unit tests green
(`vreaderTests/ReaderContainerViewDebugBridgeSearchTests`, 0 failures).
Codex ran read-only (no `xcodebuild`); the test gate was run separately by the
implementer.
