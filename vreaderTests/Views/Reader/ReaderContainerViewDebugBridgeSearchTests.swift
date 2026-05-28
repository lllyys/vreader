// Purpose: Unit tests for the DebugBridge search driver's per-poll result
// decision (`ReaderContainerView.searchResultPollAction`). Bug #1226: the
// driver returned nil ("no result — out of range") ~106ms after setting the
// query, BEFORE the 300ms-debounced FTS search had run, because the pre-search
// state (isSearching=false, empty results, hasMore=false) tripped the
// fail-fast. These tests pin the corrected decision logic.

#if DEBUG

import Testing
@testable import vreader

@Suite("DebugBridge search-driver poll decision (#1226)")
struct ReaderContainerViewDebugBridgeSearchTests {

    private typealias Action = ReaderContainerView.SearchResultPollAction

    /// Bug #1226 regression: the PRE-search default state (no search has run
    /// yet — query just set, debounce pending) must NOT be read as "no result".
    /// Before the fix this returned the equivalent of `.giveUp` (nil in ~106ms);
    /// it must `.keepPolling` until a search actually runs or grace elapses.
    @Test func preSearchEmptyState_keepsPolling_notGiveUp() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: true,
            isSearching: false,
            resultCount: 0,
            index: 0,
            hasMore: false,
            searchObserved: false,
            graceElapsed: false,
            lastObservedCount: -1
        )
        #expect(action == .keepPolling)
    }

    /// Bug #1226 (Gate-4 Medium): the sheet may still hold STALE results from a
    /// prior query during the new query's debounce window. Until a search runs
    /// (or grace elapses), a non-empty pre-search result set must NOT resolve —
    /// otherwise the driver taps a result that's about to be evicted.
    @Test func preSearchStaleResults_keepsPolling_notResolved() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: true, isSearching: false, resultCount: 3, index: 0,
            hasMore: false, searchObserved: false, graceElapsed: false,
            lastObservedCount: -1
        )
        #expect(action == .keepPolling)
    }

    /// Companion to the above: a stale pre-search `hasMore: true` must NOT
    /// trigger pagination against the old query's page state.
    @Test func preSearchStaleHasMore_keepsPolling_notLoadMore() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: true, isSearching: false, resultCount: 2, index: 5,
            hasMore: true, searchObserved: false, graceElapsed: false,
            lastObservedCount: -1
        )
        #expect(action == .keepPolling)
    }

    /// Once a search has actually executed (searchObserved) and there's
    /// genuinely nothing, give up.
    @Test func emptyAfterSearchObserved_givesUp() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: true, isSearching: false, resultCount: 0, index: 0,
            hasMore: false, searchObserved: true, graceElapsed: false,
            lastObservedCount: 0
        )
        #expect(action == .giveUp)
    }

    /// Grace window (longer than the debounce) elapsing is the fallback
    /// give-up trigger when a fast search's isSearching=true flip was missed
    /// between polls.
    @Test func emptyAfterGraceElapsed_givesUp() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: true, isSearching: false, resultCount: 0, index: 0,
            hasMore: false, searchObserved: false, graceElapsed: true,
            lastObservedCount: 0
        )
        #expect(action == .giveUp)
    }

    @Test func resultAtIndexAvailable_resolves() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: true, isSearching: false, resultCount: 3, index: 0,
            hasMore: false, searchObserved: true, graceElapsed: true,
            lastObservedCount: 3
        )
        #expect(action == .resolved)
    }

    @Test func searchInFlight_keepsPolling() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: true, isSearching: true, resultCount: 0, index: 0,
            hasMore: false, searchObserved: true, graceElapsed: true,
            lastObservedCount: -1
        )
        #expect(action == .keepPolling)
    }

    /// Index past the loaded page but more pages exist → paginate, once per
    /// landed page (count differs from lastObserved).
    @Test func outOfRangeWithMorePages_loadsMore() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: true, isSearching: false, resultCount: 2, index: 5,
            hasMore: true, searchObserved: true, graceElapsed: true,
            lastObservedCount: -1
        )
        #expect(action == .loadMore)
    }

    /// Don't re-fire loadMore while the prior page is still the latest landed
    /// (count == lastObserved) — avoids thrashing.
    @Test func outOfRangeSamePageAlreadyLoaded_keepsPolling() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: true, isSearching: false, resultCount: 2, index: 5,
            hasMore: true, searchObserved: true, graceElapsed: true,
            lastObservedCount: 2
        )
        #expect(action == .keepPolling)
    }

    @Test func queryDiverged_abandons() {
        let action = ReaderContainerView.searchResultPollAction(
            queryMatches: false, isSearching: false, resultCount: 3, index: 0,
            hasMore: false, searchObserved: true, graceElapsed: true,
            lastObservedCount: 3
        )
        #expect(action == .abandon)
    }
}

#endif
