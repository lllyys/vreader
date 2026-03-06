// Purpose: SQLite FTS5 wrapper for full-text search indexing and querying.
// Stores content in FTS5 virtual table and token positions in a span map table.
//
// Key decisions:
// - Uses raw SQLite3 C API (available on iOS without dependencies).
// - In-memory database for this vertical slice (":memory:").
// - FTS5 with unicode61 tokenizer handles diacritic removal at query time.
// - Span map stores per-token UTF-16 offsets for locator resolution.
// - Thread-safe via OSAllocatedUnfairLock protecting all DB access.
// - Re-indexing the same book DELETEs old rows before INSERT (no duplicates).
//
// @coordinates-with SearchTextExtractor.swift, SearchTextNormalizer.swift,
//   SearchHitToLocatorResolver.swift, TokenSpan.swift, SearchTokenizer.swift

import Foundation
import SQLite3
import os

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
/// Thread-safe via internal lock — callers may call from any thread.
final class SearchIndexStore: @unchecked Sendable {

    private var db: OpaquePointer?
    private let lock = OSAllocatedUnfairLock()

    /// Creates a new in-memory search index.
    init() throws {
        var dbPtr: OpaquePointer?
        let rc = sqlite3_open(":memory:", &dbPtr)
        guard rc == SQLITE_OK, let dbPtr else {
            let msg = dbPtr.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SearchIndexError.databaseOpenFailed(msg)
        }
        self.db = dbPtr
        try createTables()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Schema

    private func createTables() throws {
        try exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                fingerprint_key, source_unit_id, content,
                tokenize='unicode61 remove_diacritics 2'
            )
        """)

        try exec("""
            CREATE TABLE IF NOT EXISTS token_spans (
                fingerprint_key TEXT NOT NULL,
                source_unit_id TEXT NOT NULL,
                normalized_token TEXT NOT NULL,
                start_offset_utf16 INTEGER NOT NULL,
                end_offset_utf16 INTEGER NOT NULL
            )
        """)

        try exec("""
            CREATE INDEX IF NOT EXISTS idx_spans_lookup
            ON token_spans(fingerprint_key, source_unit_id, normalized_token)
        """)
    }

    // MARK: - Indexing

    /// Removes all indexed data for a book.
    func removeBook(fingerprintKey: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try exec("BEGIN TRANSACTION")
        do {
            try execBind("DELETE FROM search_index WHERE fingerprint_key = ?", params: [fingerprintKey])
            try execBind("DELETE FROM token_spans WHERE fingerprint_key = ?", params: [fingerprintKey])
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Indexes a book's text units into FTS5 and the span map.
    /// Re-indexing the same book replaces existing rows (no duplicates).
    func indexBook(fingerprintKey: String, textUnits: [TextUnit]) throws {
        guard !textUnits.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        try exec("BEGIN TRANSACTION")
        do {
            // Remove previous index for this book to prevent duplicates on re-index
            try execBind(
                "DELETE FROM search_index WHERE fingerprint_key = ?",
                params: [fingerprintKey]
            )
            try execBind(
                "DELETE FROM token_spans WHERE fingerprint_key = ?",
                params: [fingerprintKey]
            )

            let ftsSQL = "INSERT INTO search_index(fingerprint_key, source_unit_id, content) VALUES (?, ?, ?)"
            for unit in textUnits {
                try execBind(ftsSQL, params: [fingerprintKey, unit.sourceUnitId, unit.text])
            }
            for unit in textUnits {
                try indexSpans(fingerprintKey: fingerprintKey, sourceUnitId: unit.sourceUnitId, text: unit.text)
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func indexSpans(fingerprintKey: String, sourceUnitId: String, text: String) throws {
        let tokens = SearchTokenizer.tokenize(text)
        let sql = """
            INSERT INTO token_spans(fingerprint_key, source_unit_id, normalized_token,
                                    start_offset_utf16, end_offset_utf16) VALUES (?, ?, ?, ?, ?)
        """
        for token in tokens {
            try execBind(sql, params: [
                fingerprintKey, sourceUnitId, token.normalized,
                "\(token.startUTF16)", "\(token.endUTF16)"
            ])
        }
    }

    // MARK: - Searching

    /// Searches the FTS5 index for the given query within a specific book.
    func search(query: String, bookFingerprintKey: String, limit: Int = 50) throws -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        let normalizedQuery = SearchTextNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        let sql = """
            SELECT fingerprint_key, source_unit_id,
                   snippet(search_index, 2, '<b>', '</b>', '...', 32) as snip
            FROM search_index WHERE search_index MATCH ? AND fingerprint_key = ? LIMIT ?
        """
        let ftsQuery = "content : \(SearchTokenizer.escapeFTS5Query(normalizedQuery))"

        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw SearchIndexError.queryFailed(errMsg())
        }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, ftsQuery)
        bindText(stmt, 2, bookFingerprintKey)
        sqlite3_bind_int(stmt, 3, Int32(limit))

        var results: [SearchHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let fpKey = colText(stmt, 0)
            let unitId = colText(stmt, 1)
            let snippet = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let offsets = try findMatchOffsets(fingerprintKey: fpKey, sourceUnitId: unitId, normalizedQuery: normalizedQuery)

            results.append(SearchHit(
                fingerprintKey: fpKey, sourceUnitId: unitId, snippet: snippet,
                matchStartOffsetUTF16: offsets.start, matchEndOffsetUTF16: offsets.end
            ))
        }
        return results
    }

    /// Retrieves token spans for a specific source unit and optional token filter.
    func tokenSpans(fingerprintKey: String, sourceUnitId: String, normalizedToken: String? = nil) throws -> [TokenSpan] {
        lock.lock()
        defer { lock.unlock() }

        return try tokenSpansUnlocked(fingerprintKey: fingerprintKey, sourceUnitId: sourceUnitId, normalizedToken: normalizedToken)
    }

    /// Internal unlocked version for use within already-locked contexts.
    private func tokenSpansUnlocked(fingerprintKey: String, sourceUnitId: String, normalizedToken: String? = nil) throws -> [TokenSpan] {
        var sql = "SELECT fingerprint_key, source_unit_id, normalized_token, start_offset_utf16, end_offset_utf16 FROM token_spans WHERE fingerprint_key = ? AND source_unit_id = ?"
        var params = [fingerprintKey, sourceUnitId]
        if let token = normalizedToken {
            sql += " AND normalized_token = ?"
            params.append(token)
        }
        sql += " ORDER BY start_offset_utf16 ASC"

        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw SearchIndexError.queryFailed(errMsg()) }
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() { bindText(stmt, Int32(i + 1), param) }

        var spans: [TokenSpan] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            spans.append(TokenSpan(
                bookFingerprintKey: colText(stmt, 0), normalizedToken: colText(stmt, 2),
                startOffsetUTF16: Int(sqlite3_column_int64(stmt, 3)),
                endOffsetUTF16: Int(sqlite3_column_int64(stmt, 4)),
                sourceUnitId: colText(stmt, 1)
            ))
        }
        return spans
    }

    // MARK: - Private

    /// Finds the UTF-16 offset range of the first occurrence of the query tokens in the source unit.
    /// For multi-word queries, finds the first token's start and the last token's end.
    private func findMatchOffsets(fingerprintKey: String, sourceUnitId: String, normalizedQuery: String) throws -> (start: Int, end: Int) {
        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
        guard let firstTokenStr = queryTokens.first else { return (0, 0) }

        let firstSpans = try tokenSpansUnlocked(
            fingerprintKey: fingerprintKey, sourceUnitId: sourceUnitId,
            normalizedToken: firstTokenStr
        )
        guard let firstSpan = firstSpans.first else { return (0, 0) }

        // Single-word query: return the first span's range
        if queryTokens.count == 1 {
            return (firstSpan.startOffsetUTF16, firstSpan.endOffsetUTF16)
        }

        // Multi-word: find the last token's span to compute full match range
        if let lastTokenStr = queryTokens.last, lastTokenStr != firstTokenStr {
            let lastSpans = try tokenSpansUnlocked(
                fingerprintKey: fingerprintKey, sourceUnitId: sourceUnitId,
                normalizedToken: lastTokenStr
            )
            // Find the first last-token span that comes after the first-token span
            if let lastSpan = lastSpans.first(where: { $0.startOffsetUTF16 > firstSpan.startOffsetUTF16 }) {
                return (firstSpan.startOffsetUTF16, lastSpan.endOffsetUTF16)
            }
        }

        return (firstSpan.startOffsetUTF16, firstSpan.endOffsetUTF16)
    }

    private func errMsg() -> String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }

    private func colText(_ stmt: OpaquePointer, _ col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }

    /// SQLITE_TRANSIENT tells SQLite to copy the string immediately.
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, Self.SQLITE_TRANSIENT)
    }

    private func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw SearchIndexError.indexFailed(msg)
        }
    }

    private func execBind(_ sql: String, params: [String]) throws {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw SearchIndexError.indexFailed(errMsg()) }
        defer { sqlite3_finalize(stmt) }
        for (i, param) in params.enumerated() { bindText(stmt, Int32(i + 1), param) }
        let stepRC = sqlite3_step(stmt)
        guard stepRC == SQLITE_DONE || stepRC == SQLITE_ROW else {
            throw SearchIndexError.indexFailed(errMsg())
        }
    }
}
