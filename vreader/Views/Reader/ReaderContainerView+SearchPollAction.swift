// Purpose: The per-poll decision for the DEBUG-only DebugBridge search driver
// (`ReaderContainerView.awaitSearchResult`), extracted as a pure, nonisolated
// function so it is unit-testable without async timing. Bug #1226: the driver
// must not interpret the PRE-search state — which can hold STALE results from a
// prior query during the 300ms debounce — as a settled answer.

#if DEBUG

import Foundation

extension ReaderContainerView {
    /// What a single `awaitSearchResult` poll should do given the observed VM
    /// state.
    enum SearchResultPollAction: Equatable {
        case resolved      // results[index] is available — tap it
        case giveUp        // a search ran and there is genuinely no result at index
        case loadMore      // index is past the loaded page but more pages exist
        case keepPolling   // not settled yet (search pending / in flight) — wait
        case abandon       // the query diverged from what we asked for — bail
    }

    /// Pure poll decision. Order matters:
    /// 1. Query divergence → abandon (we're no longer driving the query we set).
    /// 2. A search in flight → keep polling (results are mid-replacement).
    /// 3. Bug #1226 gate — until a search has actually run (`searchObserved`)
    ///    or the grace window covered the 300ms debounce (`graceElapsed`), the
    ///    observed `results`/`hasMore` reflect the PRE-search state, which may
    ///    be STALE results from a prior query. Don't resolve, paginate, or give
    ///    up against that — keep polling until the new search's results land.
    /// 4. Only once trusted: resolve in-range, give up if no more pages, else
    ///    paginate once per landed page.
    nonisolated static func searchResultPollAction(
        queryMatches: Bool,
        isSearching: Bool,
        resultCount: Int,
        index: Int,
        hasMore: Bool,
        searchObserved: Bool,
        graceElapsed: Bool,
        lastObservedCount: Int
    ) -> SearchResultPollAction {
        guard queryMatches else { return .abandon }
        if isSearching { return .keepPolling }
        // Bug #1226 gate — see step 3 above. Hoisted ABOVE the settled
        // interpretations so a stale pre-search result can't be tapped or
        // paginated before the new search runs.
        if !searchObserved && !graceElapsed { return .keepPolling }
        if resultCount > index { return .resolved }
        if !hasMore { return .giveUp }
        if resultCount != lastObservedCount { return .loadMore }
        return .keepPolling
    }
}

#endif
