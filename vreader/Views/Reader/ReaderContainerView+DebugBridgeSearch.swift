// Purpose: DEBUG-only wiring that drives the in-reader search sheet from the
// `.debugBridgeSearchCommand` notification (Bug #238 verification harness).
// The observer in ReaderContainerView calls this helper; this file owns the
// open-sheet → wait-for-index → set-query → wait-for-results → tap-result-N
// orchestration so the host stays trivial.
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with ReaderContainerView.swift, ReaderSearchCoordinator.swift,
//   SearchViewModel.swift, RealDebugBridgeContext.swift,
//   DebugBridgeNotifications.swift

#if DEBUG

import SwiftUI
import OSLog

/// Dedicated `ViewModifier` for the Bug #238 search-driver observer. Mirrors
/// the `ReaderOpenAITranslateObserver` pattern in `ReaderContainerView.swift`
/// — extracting the `.onReceive` keeps the SwiftUI body inside the
/// type-inference budget.
struct ReaderDebugBridgeSearchObserver: ViewModifier {
    let onCommand: (_ query: String, _ index: Int?) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeSearchCommand)
        ) { notification in
            guard let query = notification.userInfo?["query"] as? String else { return }
            let index = notification.userInfo?["index"] as? Int
            onCommand(query, index)
        }
    }
}

extension ReaderContainerView {

    /// Handle a `.debugBridgeSearchCommand` notification. Opens the search
    /// sheet (which triggers `ensureSearchReady()` setup), waits for the
    /// SearchViewModel to come online AND the book to be indexed, sets the
    /// query, waits for results, then taps result N (firing the same
    /// `.readerNavigateToLocator` + `showSearch = false` the
    /// `SearchView.onNavigate` callback fires for a real tap).
    ///
    /// Serialization: only one bridge-search task at a time. A new URL
    /// cancels the previous in-flight task. `.onDisappear` also cancels so
    /// late completion can't fire after the reader closed.
    ///
    /// No-op when the URL fires with no reader presented — `.onReceive`
    /// only delivers to a mounted view, so callers see the same posture as
    /// `tts` / `theme` (the URL succeeds; the live view applies it if
    /// present).
    @MainActor
    func handleDebugBridgeSearchCommand(query: String, index: Int?) {
        let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")
        log.info(
            "search observer: received query=\(query, privacy: .public) index=\(index.map(String.init) ?? "nil", privacy: .public)"
        )

        // Serialize: a second URL while the first is still running cancels
        // the first. Audit round-1 High #2 — without this, two quick URLs
        // can race on the shared SearchViewModel.query and the earlier
        // task could tap a later query's result.
        debugBridgeSearchTask?.cancel()

        // Open the sheet eagerly so the on-show side-effects
        // (`.onChange(of: showSearch)` → `ensureSearchReady()`) start
        // before the task awaits its first suspension point.
        showSearch = true

        // Snapshot dependencies into local values so the Task doesn't have
        // to capture `self` directly — the @State coordinator is a value
        // type the closure can use safely on MainActor. The fingerprint is
        // resolved from the active book; a malformed canonical key here
        // (shouldn't happen — `LibraryView` only navigates to validated
        // books) leaves `fingerprint == nil` and the task bails before
        // the index wait.
        let coordinator = searchCoordinator
        let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey)

        let task = Task { @MainActor in
            // Step 1: wait for the SearchViewModel to come online (sheet
            // open + prepareService). 5s budget covers slow disk / first
            // SQLite open.
            guard !Task.isCancelled,
                  let viewModel = await Self.awaitSearchViewModel(
                    coordinator: coordinator,
                    timeout: 5.0
                  )
            else {
                if Task.isCancelled {
                    log.info("search observer: cancelled before VM ready")
                } else {
                    log.error("search observer: timed out waiting for SearchViewModel")
                }
                return
            }

            // Step 2: wait for the book's search index to be ready. Audit
            // round-1 High #1 — `setup()`'s `retriggerIfNeeded()` fires
            // before our query lands, so setting `query` immediately would
            // run against an unindexed store and return 0 hits with no
            // retrigger. Polling `service.isIndexed` here closes that gap.
            // 30s budget — large CJK TXT (5MB+) takes a few seconds; EPUB
            // is faster. Skipped (returns true immediately) when the index
            // was already persisted from a prior session.
            guard !Task.isCancelled,
                  let fingerprint,
                  await Self.awaitSearchIndexed(
                    coordinator: coordinator,
                    fingerprint: fingerprint,
                    timeout: 30.0
                  )
            else {
                if Task.isCancelled {
                    log.info("search observer: cancelled before index ready")
                } else if fingerprint == nil {
                    log.error("search observer: book.fingerprintKey did not parse as a DocumentFingerprint")
                } else {
                    log.error("search observer: timed out waiting for search index")
                }
                return
            }

            // Step 3: assign the query. The VM's didSet kicks off a
            // debounced (300ms) FTS5 search. A no-op assignment (same
            // value as oldValue) is safe — VM bails internally — but
            // here we want to FORCE a fresh search even when the prior
            // sheet already held this query (e.g. the user dismissed
            // and the URL re-fires). `retriggerIfNeeded` covers that.
            if viewModel.query == query {
                viewModel.retriggerIfNeeded()
            } else {
                viewModel.query = query
            }

            // If no index, we're done — the sheet stays open showing
            // results.
            guard let index else {
                log.info("search observer: query set, no index — leaving sheet open")
                return
            }

            // Step 4: wait for the search to settle and result N to be
            // present (paginate if needed), then tap. Audit round-1 High #2
            // — `expectedQuery` guards against a later URL having
            // overwritten the shared query between our assignment and the
            // result-ready callback.
            guard !Task.isCancelled,
                  let result = await Self.awaitSearchResult(
                    viewModel: viewModel,
                    expectedQuery: query,
                    index: index,
                    timeout: 15.0
                  )
            else {
                if Task.isCancelled {
                    log.info("search observer: cancelled before result ready")
                } else {
                    log.error(
                        "search observer: no result at index \(index) for query=\(query, privacy: .public) (out of range or timeout)"
                    )
                }
                return
            }

            // Final cancellation check before the side effect — covers
            // the rare case where the reader was dismissed (or another
            // URL arrived) between the result resolving and this line.
            guard !Task.isCancelled else {
                log.info("search observer: cancelled before navigation")
                return
            }

            log.info("search observer: tapping result \(index) → \(result.id, privacy: .public)")

            // Mirror the SearchView.onNavigate path verbatim:
            //   1. Post `.readerNavigateToLocator` with the result's locator.
            //   2. Dismiss the search sheet.
            NotificationCenter.default.post(
                name: .readerNavigateToLocator,
                object: result.locator
            )
            showSearch = false
        }
        debugBridgeSearchTask = task
    }

    // MARK: - Polling helpers

    /// Polls `coordinator.searchViewModel` on the MainActor until it becomes
    /// non-nil or `timeout` elapses. Returns nil on timeout. 100ms poll
    /// interval matches the existing settle-readiness probe pattern.
    static func awaitSearchViewModel(
        coordinator: ReaderSearchCoordinator,
        timeout: TimeInterval
    ) async -> SearchViewModel? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return nil }
            if let vm = coordinator.searchViewModel {
                return vm
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        return nil
    }

    /// Polls `coordinator.searchService?.isIndexed(...)` until it returns
    /// true or `timeout` elapses. Returns false on timeout. Audit round-1
    /// High #1 fix.
    ///
    /// When the book was indexed in a prior session (`alreadyIndexed`
    /// branch of `ReaderSearchCoordinator.setup`), `restoreSegmentOffsets`
    /// marks the key indexed synchronously — so this returns true on the
    /// first poll. The slow path is a fresh import where
    /// `BackgroundIndexingCoordinator` has to finish before
    /// `service.isIndexed` flips.
    ///
    /// `fingerprint` is the book's `DocumentFingerprint` — passed in
    /// because `SearchViewModel`'s `bookFingerprint` is `private`; the
    /// caller resolves it from `ReaderContainerView.book.fingerprintKey`.
    static func awaitSearchIndexed(
        coordinator: ReaderSearchCoordinator,
        fingerprint: DocumentFingerprint,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if let service = coordinator.searchService {
                let indexed = await service.isIndexed(fingerprint: fingerprint)
                if indexed { return true }
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return false
    }

    /// Polls `viewModel.results` until at least `index + 1` entries are
    /// present AND the VM is no longer searching, or `timeout` elapses.
    /// Returns the result at `index` on success, nil on timeout or
    /// out-of-range (when `hasMore == false`).
    ///
    /// Audit round-1 + round-2 fixes:
    ///   - Medium #3 — when `index >= results.count && hasMore`, call
    ///     `loadMore()` to paginate. When `hasMore == false` and results
    ///     are short, fail fast instead of waiting out the timeout.
    ///     Round 2: keep paginating until reach-or-exhaust, not just once.
    ///     Track the previous page's `results.count` so we only fire a
    ///     fresh `loadMore()` after the prior one has landed
    ///     (`isSearching == false && resultsCount changed`).
    ///   - High #2 — verify `viewModel.query == expectedQuery` before
    ///     accepting results. If a later URL overwrote the query mid-flight,
    ///     bail rather than tap a result that belongs to the new query.
    ///
    /// The "not searching" guard prevents tapping a partial first-page
    /// result before the FTS5 query has actually completed — the VM's
    /// `results` array is replaced wholesale by `performSearch`, so a
    /// stale tap could fire against a result that's about to be evicted.
    static func awaitSearchResult(
        viewModel: SearchViewModel,
        expectedQuery: String,
        index: Int,
        timeout: TimeInterval
    ) async -> SearchResult? {
        let deadline = Date().addingTimeInterval(timeout)
        // Round-2 audit fix: paginate iteratively. `lastObservedCount`
        // tracks the most-recently-landed page size so we only fire
        // another `loadMore()` after the previous one settled (results
        // grew or hasMore flipped). Without this we'd either re-fire
        // every poll (thrashing) or stop after one extra page (round-1
        // posture — Medium #3 of round 2).
        var lastObservedCount = -1
        // Bug #1226: setting `viewModel.query` kicks off a 300ms-DEBOUNCED FTS
        // search, so the first poll(s) observe the PRE-search default state
        // (isSearching=false, results empty, hasMore=false). Concluding "no
        // result" then is a false negative — the driver returned nil in ~106ms
        // before the search even started. Gate the give-up on a search having
        // actually run (`searchObserved`) OR a grace window longer than the
        // debounce having elapsed.
        let graceDeadline = Date().addingTimeInterval(min(0.8, timeout))
        var searchObserved = false
        while Date() < deadline {
            if Task.isCancelled { return nil }

            // Query-divergence guard. Trimmed compare matches the VM's
            // own search-input normalisation in `performSearch`.
            let queryMatches = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                == expectedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let results = viewModel.results
            let isSearching = viewModel.isSearching
            if isSearching { searchObserved = true }

            switch Self.searchResultPollAction(
                queryMatches: queryMatches,
                isSearching: isSearching,
                resultCount: results.count,
                index: index,
                hasMore: viewModel.hasMore,
                searchObserved: searchObserved,
                graceElapsed: Date() >= graceDeadline,
                lastObservedCount: lastObservedCount
            ) {
            case .abandon, .giveUp:
                return nil
            case .resolved:
                return results[index]
            case .loadMore:
                // Trigger another `loadMore()`, but only once per landed page
                // (track the count so we don't re-fire while a prior load is
                // still in flight).
                lastObservedCount = results.count
                Task { @MainActor in
                    await viewModel.loadMore()
                }
            case .keepPolling:
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        return nil
    }
}

#endif
