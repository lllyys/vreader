// Purpose: Manages search service lifecycle, search VM creation, and book indexing.
// Extracted from ReaderContainerView to reduce file size (pure refactor).
//
// @coordinates-with ReaderContainerView.swift, SearchService.swift, SearchViewModel.swift,
//   SearchIndexStore.swift, BackgroundIndexingCoordinator.swift

import Foundation
import os

/// Owns the search pipeline state: SearchService, SearchViewModel, and indexing logic.
@Observable
@MainActor
final class ReaderSearchCoordinator {

    // nonisolated so the nonisolated `enqueueBookIndexing` (bug #183 fix)
    // can write log lines without crossing the MainActor boundary. `Logger`
    // is Sendable.
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "Search"
    )

    /// The search service instance. Nil until setup completes.
    private(set) var searchService: SearchService?
    /// The search view model. Nil until setup completes.
    private(set) var searchViewModel: SearchViewModel?
    /// Whether full setup (indexing) has been started. Prevents double-indexing. (bug #79)
    private var setupStarted = false
    /// In-flight prepare task — single-flight coalescing so concurrent callers
    /// (reader-open `prepareEagerly` racing the search-sheet `setup`) share ONE
    /// cold SQLite open instead of racing two. (Codex Gate-4 Medium, bug #79)
    private var prepareTask: Task<Void, Never>?

    /// Eager-prepare entry point called on reader open (bug #79).
    ///
    /// Restores the original bug #79 fix — preparing the search pipeline when
    /// the reader opens so the FIRST search of a session shows the real search
    /// field immediately instead of the "Preparing search…" placeholder.
    ///
    /// The regression history: the eager call was removed in fd12ab0e because
    /// `prepareService` opened SQLite synchronously on the MainActor, adding a
    /// 500ms–2s book-open stall (the bug #89 class). This restores eager prep
    /// WITHOUT that stall: `prepareService` now builds the cold store off the
    /// MainActor (the SQLite open + integrity_check + FTS5/table DDL run on a
    /// detached task), so reader open is never blocked by the eager prep.
    ///
    /// Thin wrapper over `prepareService` so the reader-open call site reads as
    /// intent ("prepare eagerly") and the unit test has a named seam.
    func prepareEagerly(fingerprint: DocumentFingerprint) async {
        await prepareService(fingerprint: fingerprint)
    }

    /// Sets up the search pipeline for a book:
    /// creates the persistent index store, SearchService, and SearchViewModel,
    /// then enqueues background indexing if the book is not already indexed.
    /// Lightweight setup: creates store + service + VM without indexing. (bug #79)
    /// Call on reader open so the search panel has a VM immediately when opened.
    func prepareService(fingerprint: DocumentFingerprint) async {
        guard searchService == nil else { return }
        // Single-flight (Codex Gate-4 Medium, bug #79): if a prepare is already
        // in flight, await it instead of starting a second cold SQLite open. The
        // coordinator is @MainActor, so reading/writing `prepareTask` is race-free
        // and the first caller wins the assignment; concurrent callers join.
        if let inFlight = prepareTask {
            await inFlight.value
            return
        }
        // Capture `self` strongly: the task is awaited inline below and the
        // handle is cleared immediately after, so it cannot outlive this call
        // and there is no retain cycle. (A `weak self` would make the task
        // `Task<()?, Never>` and break the stored-handle type.)
        let task = Task { @MainActor in
            await self.runPrepare(fingerprint: fingerprint)
        }
        prepareTask = task
        await task.value
        prepareTask = nil
    }

    /// The actual prepare body, guaranteed to run at most once concurrently by
    /// `prepareService`'s single-flight gate.
    private func runPrepare(fingerprint: DocumentFingerprint) async {
        guard searchService == nil else { return }
        // Bug #89 / #79: build the cold store OFF the MainActor. `makePersistentStore`
        // is `nonisolated` and `SearchIndexStore` is `@unchecked Sendable`, so the
        // expensive `sqlite3_open` + integrity_check + FTS5/table DDL run on a
        // detached task and never block reader open. Only the @MainActor-isolated
        // state assignment + the (cheap, I/O-free) SearchViewModel init hop back here.
        let store: SearchIndexStore
        do {
            store = try await Task.detached(priority: .userInitiated) {
                try Self.makePersistentStore()
            }.value
        } catch {
            Self.logger.error("Search prepare failed: \(error.localizedDescription)")
            return
        }
        // Re-check after the off-main hop (defensive — the single-flight gate
        // already prevents a concurrent racer publishing a store first).
        guard searchService == nil else { return }
        let service = SearchService(store: store)
        searchService = service
        persistentStore = store
        searchViewModel = SearchViewModel(
            searchService: service,
            bookFingerprint: fingerprint
        )
    }

    /// Persistent store reference for deferred indexing. (bug #79)
    private var persistentStore: SearchIndexStore?

    func setup(
        fingerprint: DocumentFingerprint,
        fileURL: URL,
        format: String
    ) async {
        guard !setupStarted else { return }
        setupStarted = true

        // Ensure service exists (may already be created by prepareService)
        if searchService == nil {
            await prepareService(fingerprint: fingerprint)
        }
        guard let service = searchService, let store = persistentStore else { return }

        // Check persistent index — skip if already indexed (WI-F06)
        let alreadyPersisted = store.isBookIndexed(
            fingerprintKey: fingerprint.canonicalKey
        )
        let inMemoryIndexed = await service.isIndexed(fingerprint: fingerprint)
        var alreadyIndexed = alreadyPersisted || inMemoryIndexed

        // Bug #99 cause #2: when the TXT decode pipeline changed (display
        // and search now share `decodeForDisplayAndSearch`), pre-existing
        // FTS5 indexes built against the old `decodeText`-only path may
        // hold offsets that don't align with the new display string for
        // non-UTF-8 files. Force a reindex when the persistent index's
        // `decode_version` doesn't match the current pipeline. Limited
        // to TXT — other formats aren't affected by this change.
        if alreadyPersisted, format == "txt",
           store.requiresReindex(fingerprintKey: fingerprint.canonicalKey) {
            try? store.removeBook(fingerprintKey: fingerprint.canonicalKey)
            alreadyIndexed = false
        }

        if alreadyIndexed {
            let offsets = store.getSegmentBaseOffsets(
                fingerprintKey: fingerprint.canonicalKey
            )
            if let offsets {
                // TXT/MD with persisted offsets — restore for valid locators
                // (bug #61); also marks the book indexed in memory.
                await service.restoreSegmentOffsets(
                    fingerprint: fingerprint,
                    offsets: offsets
                )
            } else if inMemoryIndexed {
                // Already marked this session (fresh index earlier) — the
                // persisted row simply lacks offsets; nothing to restore.
            } else if Self.formatRequiresSegmentOffsets(format) {
                // Bug #264: a TXT/MD persisted row with NO restorable offsets
                // is stale (interrupted index, older schema, or a row a DEBUG
                // reset left behind). The restore branch above would silently
                // no-op, leaving the book un-searchable forever — drop it and
                // re-index for real.
                try? store.removeBook(fingerprintKey: fingerprint.canonicalKey)
                alreadyIndexed = false
            } else {
                // Bug #264: EPUB/PDF persist FTS content but never segment
                // offsets, so a nil-offsets persisted row is NORMAL for them.
                // The content rows already exist in the store, so mark the
                // book indexed in memory WITHOUT a wasteful re-index — this
                // makes `service.isIndexed()` honest (the search driver's
                // index-wait then completes) while search already works off
                // the persistent FTS content.
                service.markPersistentlyIndexed(fingerprint: fingerprint)
            }
        }

        if !alreadyIndexed {
            // Defer indexing to background (WI-F05)
            let coordinator = BackgroundIndexingCoordinator(
                searchService: service
            )
            await Self.enqueueBookIndexing(
                coordinator: coordinator,
                store: store,
                fileURL: fileURL,
                fingerprint: fingerprint,
                format: format
            )
            // Re-trigger search if user typed a query while indexing
            searchViewModel?.retriggerIfNeeded()
        }
    }

    // MARK: - Persistent Search Index (WI-F06)

    /// The directory holding the persistent FTS store. Single source of truth
    /// so `makePersistentStore` (production) and `wipeSearchIndex` (the
    /// Bug #264 DEBUG reset-wipe) agree on the path.
    nonisolated static var searchIndexDirectoryURL: URL {
        PersistentSearchIndex.directoryURL   // single source of truth (Services layer)
    }

    /// Removes the persistent FTS store directory. Idempotent — succeeds when
    /// the directory is absent. Bug #264: the DEBUG `vreader-debug://reset`
    /// calls this so a reset is a true clean slate; without it a stale
    /// `search_metadata` row (esp. one with empty `segment_base_offsets`)
    /// survives reset+seed and the indexed-search wait never completes.
    /// Takes the directory as a parameter so it is unit-testable against a
    /// temp directory rather than the real Application Support path.
    nonisolated static func wipeSearchIndex(at directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Bug #264: whether a format persists segment base offsets (the TXT/MD
    /// char-offset locator map) as part of its index. Only TXT and MD do —
    /// EPUB and PDF index FTS content but pass `segmentBaseOffsets: nil`
    /// (they locate by href / page, not char offset). This distinction
    /// decides how `setup` treats a persisted index row that has no
    /// restorable offsets: for TXT/MD that means a STALE row → re-index; for
    /// EPUB/PDF it is the NORMAL state → just mark indexed in memory (the FTS
    /// content already exists), never re-index on every reopen.
    nonisolated static func formatRequiresSegmentOffsets(_ format: String) -> Bool {
        format == "txt" || format == "md"
    }

    /// Creates a persistent file-backed SearchIndexStore.
    /// Falls back to in-memory if file creation fails.
    ///
    /// `nonisolated` (bug #79 / #89): the cold SQLite open (`sqlite3_open` +
    /// integrity_check + FTS5/table DDL) is the heavy part of search prep and
    /// must run OFF the MainActor. This function touches no MainActor state and
    /// returns an `@unchecked Sendable` store, so `prepareService` invokes it on
    /// a detached task and only hops back to the actor for the state assignment.
    nonisolated private static func makePersistentStore() throws -> SearchIndexStore {
        try PersistentSearchIndex.makeStore()   // single source of truth (Services layer)
    }

    /// Extracts text units and enqueues them for background indexing (WI-F05).
    ///
    /// Bug #183 / GH #623: marked `nonisolated` so the body runs on the
    /// generic executor instead of inheriting `@MainActor` from the
    /// enclosing class. `TXTTextExtractor.extractWithOffsets` and the
    /// other format extractors do synchronous file I/O (`Data(contentsOf:)`)
    /// + encoding detection (`TXTService.decodeForDisplayAndSearch`)
    /// internally. Before this fix, the whole chain ran on MainActor
    /// until the first natural suspension point inside the extractor —
    /// which for the synchronous `decodeFile` path is "never" — freezing
    /// the UI on first search-panel open of a large CJK TXT (5MB+).
    /// `BackgroundIndexingCoordinator` is an actor and `SearchIndexStore`
    /// is `@unchecked Sendable`, so the inner awaits hop correctly.
    nonisolated private static func enqueueBookIndexing(
        coordinator: BackgroundIndexingCoordinator,
        store: SearchIndexStore,
        fileURL: URL,
        fingerprint: DocumentFingerprint,
        format: String
    ) async {
        do {
            switch format {
            case "txt":
                let extractor = TXTTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                await coordinator.enqueueIndexing(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )
                // Persist segment offsets for future sessions
                if !result.segmentBaseOffsets.isEmpty {
                    store.setSegmentBaseOffsets(
                        fingerprintKey: fingerprint.canonicalKey,
                        offsets: result.segmentBaseOffsets
                    )
                }

            case "md":
                let extractor = MDTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                await coordinator.enqueueIndexing(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )
                if !result.segmentBaseOffsets.isEmpty {
                    store.setSegmentBaseOffsets(
                        fingerprintKey: fingerprint.canonicalKey,
                        offsets: result.segmentBaseOffsets
                    )
                }

            case "pdf":
                let extractor = PDFTextExtractor()
                let units = try await extractor.extractTextUnits(
                    from: fileURL, fingerprint: fingerprint
                )
                await coordinator.enqueueIndexing(
                    fingerprint: fingerprint,
                    textUnits: units,
                    segmentBaseOffsets: nil
                )

            case "epub":
                let parser = EPUBParser()
                do {
                    let metadata = try await parser.open(url: fileURL)
                    let extractor = EPUBTextExtractor()
                    let units = try await extractor.extractFromParser(
                        parser, metadata: metadata
                    )
                    await parser.close()
                    await coordinator.enqueueIndexing(
                        fingerprint: fingerprint,
                        textUnits: units,
                        segmentBaseOffsets: nil
                    )
                } catch {
                    await parser.close()
                    throw error
                }

            default:
                break
            }
        } catch {
            Self.logger.error(
                "Background index enqueue failed for \(format): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Search Indexing (Legacy)

    /// Extracts text from the book and indexes it for search.
    /// Runs on the calling task -- use from a `.task` modifier for background execution.
    static func indexBookContent(
        service: SearchService,
        fileURL: URL,
        fingerprint: DocumentFingerprint,
        format: String
    ) async {
        do {
            switch format {
            case "txt":
                let extractor = TXTTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                try await service.indexBook(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )

            case "md":
                let extractor = MDTextExtractor()
                let result = try await extractor.extractWithOffsets(from: fileURL)
                try await service.indexBook(
                    fingerprint: fingerprint,
                    textUnits: result.textUnits,
                    segmentBaseOffsets: result.segmentBaseOffsets
                )

            case "pdf":
                let extractor = PDFTextExtractor()
                let units = try await extractor.extractTextUnits(
                    from: fileURL, fingerprint: fingerprint
                )
                try await service.indexBook(
                    fingerprint: fingerprint,
                    textUnits: units,
                    segmentBaseOffsets: nil
                )

            case "epub":
                let parser = EPUBParser()
                do {
                    let metadata = try await parser.open(url: fileURL)
                    let extractor = EPUBTextExtractor()
                    let units = try await extractor.extractFromParser(
                        parser, metadata: metadata
                    )
                    await parser.close()
                    try await service.indexBook(
                        fingerprint: fingerprint,
                        textUnits: units,
                        segmentBaseOffsets: nil
                    )
                } catch {
                    await parser.close()
                    throw error
                }

            default:
                break
            }
        } catch {
            Self.logger.error("Search indexing failed for \(format): \(error.localizedDescription)")
        }
    }
}
