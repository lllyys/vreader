// Purpose: SQLite FTS5 wrapper for full-text search indexing and querying.
// Owns SearchIndexCore (db + lock) and SearchQueryExecutor (query logic).
// Stores content in FTS5 virtual table and token positions in a span map table.
//
// Key decisions:
// - All DB access goes through SearchIndexCore — no raw SQLite3 in this file.
// - Query execution delegated to SearchQueryExecutor (WI-007).
// - In-memory database for this vertical slice (":memory:").
// - FTS5 with unicode61 tokenizer handles diacritic removal at query time.
// - Span map stores per-token UTF-16 offsets for locator resolution.
// - Thread-safe via SearchIndexCore's internal lock.
// - Re-indexing the same book DELETEs old rows before INSERT (no duplicates).
//
// @coordinates-with: SearchIndexCore.swift, SearchQueryExecutor.swift,
//   SearchTextExtractor.swift, SearchTextNormalizer.swift,
//   SearchHitToLocatorResolver.swift, TokenSpan.swift, SearchTokenizer.swift

import Foundation

/// A search result from the FTS5 index.
struct SearchHit: Sendable, Equatable {
    /// Canonical fingerprint key of the book.
    let fingerprintKey: String
    /// Source unit ID (e.g., "epub:chapter1.xhtml", "pdf:page:0", "txt:segment:0").
    let sourceUnitId: String
    /// Snippet of matching text (may contain FTS5 highlight markers).
    let snippet: String?
    /// Start offset of the match in UTF-16 code units within the source unit.
    let matchStartOffsetUTF16: Int
    /// End offset of the match in UTF-16 code units within the source unit.
    let matchEndOffsetUTF16: Int
}

/// Errors from SearchIndexStore operations.
enum SearchIndexError: Error, Sendable {
    case databaseOpenFailed(String)
    case queryFailed(String)
    case indexFailed(String)
}

/// SQLite FTS5 search index with token span map for offset resolution.
/// Thread-safe via SearchIndexCore's internal lock — callers may call from any thread.
final class SearchIndexStore: @unchecked Sendable {

    private let core: SearchIndexCore
    private let queryExecutor: SearchQueryExecutor

    /// Creates a new in-memory search index.
    init() throws {
        let core = try SearchIndexCore()
        self.core = core
        self.queryExecutor = SearchQueryExecutor(core: core)
        try createTables()
    }

    /// Creates a search index using a pre-configured SearchIndexCore.
    /// Use this with a file-backed core for persistent indexing (WI-F06).
    init(core: SearchIndexCore) throws {
        self.core = core
        self.queryExecutor = SearchQueryExecutor(core: core)
        try createTables()
    }

    // MARK: - Schema

    private func createTables() throws {
        try core.exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                fingerprint_key, source_unit_id, content,
                tokenize='unicode61 remove_diacritics 2'
            )
        """)

        try core.exec("""
            CREATE TABLE IF NOT EXISTS token_spans (
                fingerprint_key TEXT NOT NULL,
                source_unit_id TEXT NOT NULL,
                normalized_token TEXT NOT NULL,
                start_offset_utf16 INTEGER NOT NULL,
                end_offset_utf16 INTEGER NOT NULL
            )
        """)

        try core.exec("""
            CREATE INDEX IF NOT EXISTS idx_spans_lookup
            ON token_spans(fingerprint_key, source_unit_id, normalized_token)
        """)

        // Store original texts for per-occurrence snippet generation (bug #28).
        try core.exec("""
            CREATE TABLE IF NOT EXISTS source_texts (
                fingerprint_key TEXT NOT NULL,
                source_unit_id TEXT NOT NULL,
                original_text TEXT NOT NULL,
                PRIMARY KEY (fingerprint_key, source_unit_id)
            )
        """)

        // Metadata for persistent index tracking (WI-F06).
        try core.exec("""
            CREATE TABLE IF NOT EXISTS search_metadata (
                fingerprint_key TEXT PRIMARY KEY,
                indexed_at TEXT NOT NULL,
                content_hash TEXT,
                segment_base_offsets TEXT
            )
        """)

        // Bug #99 cause #2: per-row `decode_version` records which decode
        // pipeline version produced the indexed offsets. When the decode
        // pipeline changes (e.g. fix that aligns search with display),
        // existing rows with older versions must be reindexed because
        // their offsets reference a different decoded string. Idempotent
        // ALTER (SQLite errors on duplicate column; ignore).
        do {
            try core.exec("ALTER TABLE search_metadata ADD COLUMN decode_version TEXT")
        } catch {
            // Column already exists — that's fine.
        }
    }

    /// Bug #99 cause #2: bump this when the TXT decode pipeline changes
    /// in a way that affects UTF-16 offsets. Indexes built with older
    /// versions will be force-reindexed on next access.
    static let currentDecodeVersion: String = "2"

    // MARK: - Indexing

    /// Removes all indexed data for a book.
    func removeBook(fingerprintKey: String) throws {
        try core.withLock {
            try core.exec("BEGIN TRANSACTION")
            do {
                try deleteBookDataUnlocked(fingerprintKey: fingerprintKey)
                try core.exec("COMMIT")
            } catch {
                try? core.exec("ROLLBACK")
                throw error
            }
        }
    }

    /// Indexes a book's text units into FTS5 and the span map.
    /// Re-indexing the same book replaces existing rows (no duplicates).
    /// Empty textUnits clears stale data for the book without inserting new rows.
    func indexBook(fingerprintKey: String, textUnits: [TextUnit]) throws {
        try core.withLock {
            try core.exec("BEGIN TRANSACTION")
            do {
                try deleteBookDataUnlocked(fingerprintKey: fingerprintKey)

                let ftsSQL = "INSERT INTO search_index(fingerprint_key, source_unit_id, content) VALUES (?, ?, ?)"
                let srcSQL = "INSERT INTO source_texts(fingerprint_key, source_unit_id, original_text) VALUES (?, ?, ?)"
                for unit in textUnits {
                    let normalized = SearchTextNormalizer.normalize(unit.text)
                    let segmented = SearchTextNormalizer.segmentCJK(normalized)
                    try core.execBind(ftsSQL, params: [fingerprintKey, unit.sourceUnitId, segmented])
                    try core.execBind(srcSQL, params: [fingerprintKey, unit.sourceUnitId, unit.text])
                }
                for unit in textUnits {
                    try indexSpans(fingerprintKey: fingerprintKey, sourceUnitId: unit.sourceUnitId, text: unit.text)
                }
                // Record in metadata (WI-F06).
                // Bug #99 cause #2: tag the row with the current decode-version
                // so a future decode-pipeline change can detect stale indexes.
                let now = ISO8601DateFormatter().string(from: Date())
                try core.execBind(
                    """
                    INSERT OR REPLACE INTO search_metadata(fingerprint_key, indexed_at, decode_version)
                    VALUES (?, ?, ?)
                    """,
                    params: [fingerprintKey, now, Self.currentDecodeVersion]
                )

                try core.exec("COMMIT")
            } catch {
                try? core.exec("ROLLBACK")
                throw error
            }
        }
    }

    /// Deletes all rows for a book across all tables. Must be called within core.withLock.
    private func deleteBookDataUnlocked(fingerprintKey: String) throws {
        try core.execBind("DELETE FROM search_index WHERE fingerprint_key = ?", params: [fingerprintKey])
        try core.execBind("DELETE FROM token_spans WHERE fingerprint_key = ?", params: [fingerprintKey])
        try core.execBind("DELETE FROM source_texts WHERE fingerprint_key = ?", params: [fingerprintKey])
        try core.execBind("DELETE FROM search_metadata WHERE fingerprint_key = ?", params: [fingerprintKey])
    }

    private func indexSpans(fingerprintKey: String, sourceUnitId: String, text: String) throws {
        let tokens = SearchTokenizer.tokenize(text)
        let sql = """
            INSERT INTO token_spans(fingerprint_key, source_unit_id, normalized_token,
                                    start_offset_utf16, end_offset_utf16) VALUES (?, ?, ?, ?, ?)
        """
        for token in tokens {
            try core.execBind(sql, params: [
                fingerprintKey, sourceUnitId, token.normalized,
                "\(token.startUTF16)", "\(token.endUTF16)"
            ])
        }
    }

    // MARK: - Searching (delegated to SearchQueryExecutor)

    /// Searches the FTS5 index for the given query within a specific book.
    func search(query: String, bookFingerprintKey: String, limit: Int = 50) throws -> [SearchHit] {
        try queryExecutor.search(query: query, bookFingerprintKey: bookFingerprintKey, limit: limit)
    }

    /// Retrieves token spans for a specific source unit and optional token filter.
    func tokenSpans(fingerprintKey: String, sourceUnitId: String, normalizedToken: String? = nil) throws -> [TokenSpan] {
        try queryExecutor.tokenSpans(fingerprintKey: fingerprintKey, sourceUnitId: sourceUnitId, normalizedToken: normalizedToken)
    }

    /// Extracts a context snippet around match offsets in the original text.
    static func extractSnippet(from text: String?, matchStart: Int, matchEnd: Int, contextChars: Int) -> String {
        SearchQueryExecutor.extractSnippet(from: text, matchStart: matchStart, matchEnd: matchEnd, contextChars: contextChars)
    }

    // MARK: - Persistent Index Metadata (WI-F06)

    /// Bug #99 cause #2: returns true when the indexed offsets were produced
    /// by an older decode pipeline (or no version recorded — rows from
    /// before the column existed). Callers should treat this as "force
    /// reindex" and rebuild the index for this book before serving search.
    func requiresReindex(fingerprintKey: String) -> Bool {
        core.withLock {
            do {
                let rows = try core.query(
                    "SELECT decode_version FROM search_metadata WHERE fingerprint_key = ? LIMIT 1",
                    params: [fingerprintKey]
                ) { reader -> String in
                    reader.text(0)
                }
                guard let stored = rows.first else {
                    // No metadata row → not indexed at all → not "needs reindex"
                    // in this contract (caller should index fresh anyway).
                    return false
                }
                // Stored is "" (legacy row pre-column → NULL → "" via reader)
                // OR != current version → needs reindex.
                return stored != Self.currentDecodeVersion
            } catch {
                // On query error, conservatively assume reindex is safer than stale.
                return true
            }
        }
    }

    /// Checks whether a book has been indexed (has a metadata row).
    func isBookIndexed(fingerprintKey: String) -> Bool {
        core.withLock {
            do {
                let rows = try core.query(
                    "SELECT 1 FROM search_metadata WHERE fingerprint_key = ? LIMIT 1",
                    params: [fingerprintKey]
                ) { _ in true }
                return !rows.isEmpty
            } catch {
                return false
            }
        }
    }

    /// Sets the content hash for a fingerprint key (skip-reindex optimization).
    func setContentHash(fingerprintKey: String, contentHash: String) {
        core.withLock {
            try? core.execBind(
                "UPDATE search_metadata SET content_hash = ? WHERE fingerprint_key = ?",
                params: [contentHash, fingerprintKey]
            )
        }
    }

    /// Checks if the stored content hash matches the provided one.
    func contentHashMatches(
        fingerprintKey: String, contentHash: String
    ) -> Bool {
        core.withLock {
            do {
                let rows = try core.query(
                    "SELECT content_hash FROM search_metadata WHERE fingerprint_key = ?",
                    params: [fingerprintKey]
                ) { row in row.text(0) }
                return rows.first == contentHash
            } catch {
                return false
            }
        }
    }

    /// Stores segment base offsets as JSON for TXT locator resolution.
    func setSegmentBaseOffsets(
        fingerprintKey: String, offsets: [Int: Int]
    ) {
        let stringKeyed = Dictionary(
            uniqueKeysWithValues: offsets.map { ("\($0.key)", $0.value) }
        )
        guard let data = try? JSONSerialization.data(withJSONObject: stringKeyed),
              let json = String(data: data, encoding: .utf8) else { return }
        core.withLock {
            try? core.execBind(
                "UPDATE search_metadata SET segment_base_offsets = ? WHERE fingerprint_key = ?",
                params: [json, fingerprintKey]
            )
        }
    }

    /// Retrieves stored segment base offsets, or nil if not stored.
    func getSegmentBaseOffsets(fingerprintKey: String) -> [Int: Int]? {
        core.withLock {
            do {
                let rows = try core.query(
                    "SELECT segment_base_offsets FROM search_metadata WHERE fingerprint_key = ?",
                    params: [fingerprintKey]
                ) { row in row.text(0) }
                guard let json = rows.first, !json.isEmpty,
                      let data = json.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data)
                          as? [String: Int] else {
                    return nil
                }
                return Dictionary(uniqueKeysWithValues: dict.compactMap { key, value in
                    guard let intKey = Int(key) else { return nil }
                    return (intKey, value)
                })
            } catch {
                return nil
            }
        }
    }
}
