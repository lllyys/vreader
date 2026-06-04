// Purpose: The single Services-layer source of truth for the on-disk persistent
// FTS index location + store construction. Extracted from ReaderSearchCoordinator
// (which now delegates) so non-reader callers — notably Feature #91's agentic
// search tools, which need the SAME persisted index the reader builds — can open
// the persistent store without reaching into the Views layer.
//
// `makeStore()` mirrors the historical `ReaderSearchCoordinator.makePersistentStore`:
// a cold file-backed SQLite open (heavy — call OFF the main actor), with an
// in-memory fallback if file creation fails.
//
// @coordinates-with: SearchIndexCore.swift, SearchIndexStore.swift,
//   ReaderSearchCoordinator.swift (delegates here),
//   AgenticToolRegistryBuilder.swift (Feature #91 consumer).

import Foundation
import OSLog

enum PersistentSearchIndex {

    private static let log = Logger(subsystem: "com.vreader.app", category: "PersistentSearchIndex")

    /// Application Support/SearchIndex — the canonical persistent-index directory.
    nonisolated static var directoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SearchIndex", isDirectory: true)
    }

    /// The on-disk FTS database path.
    nonisolated static var databasePath: String {
        directoryURL.appendingPathComponent("search.sqlite3").path
    }

    /// Open the file-backed persistent `SearchIndexStore`; fall back to an
    /// in-memory store if file creation fails (the reader's search path tolerates a
    /// degraded session). NOTE: the cold open is heavy — call this off the main actor.
    nonisolated static func makeStore() throws -> SearchIndexStore {
        do {
            return try makeStoreStrict()
        } catch {
            log.warning("Persistent index failed, using in-memory: \(error.localizedDescription)")
            return try SearchIndexStore()
        }
    }

    /// Open the file-backed persistent store, THROWING on failure — NO in-memory
    /// fallback. Feature #91's agentic search must hit the SAME persisted index the
    /// reader builds; an empty in-memory store would silently lose coverage, so the
    /// agentic wiring uses this and falls back to a non-agentic chat on a throw.
    nonisolated static func makeStoreStrict() throws -> SearchIndexStore {
        let core = try SearchIndexCore(databasePath: databasePath)
        return try SearchIndexStore(core: core)
    }
}
