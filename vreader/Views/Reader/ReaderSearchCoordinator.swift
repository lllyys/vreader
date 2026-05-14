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

    /// Sets up the search pipeline for a book:
    /// creates the persistent index store, SearchService, and SearchViewModel,
    /// then enqueues background indexing if the book is not already indexed.
    /// Lightweight setup: creates store + service + VM without indexing. (bug #79)
    /// Call on reader open so the search panel has a VM immediately when opened.
    func prepareService(fingerprint: DocumentFingerprint) async {
        guard searchService == nil else { return }
        do {
            // Open SQLite — makePersistentStore is MainActor-isolated but fast after first call (bug #89)
            let store = try Self.makePersistentStore()
            let service = SearchService(store: store)
            searchService = service
            persistentStore = store
            searchViewModel = SearchViewModel(
                searchService: service,
                bookFingerprint: fingerprint
            )
        } catch {
            Self.logger.error("Search prepare failed: \(error.localizedDescription)")
        }
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
            // Restore persisted segment offsets for valid locators (bug #61)
            if let offsets = store.getSegmentBaseOffsets(
                fingerprintKey: fingerprint.canonicalKey
            ) {
                await service.restoreSegmentOffsets(
                    fingerprint: fingerprint,
                    offsets: offsets
                )
            }
        } else {
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

    /// Creates a persistent file-backed SearchIndexStore.
    /// Falls back to in-memory if file creation fails.
    private static func makePersistentStore() throws -> SearchIndexStore {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SearchIndex", isDirectory: true)
        let dbPath = dir.appendingPathComponent("search.sqlite3")
        do {
            let core = try SearchIndexCore(databasePath: dbPath.path)
            return try SearchIndexStore(core: core)
        } catch {
            logger.warning("Persistent index failed, using in-memory: \(error.localizedDescription)")
            return try SearchIndexStore()
        }
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
