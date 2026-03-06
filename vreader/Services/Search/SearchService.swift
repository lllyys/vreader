// Purpose: Protocol-based search service that coordinates FTS5 indexing and querying.
// Wraps SearchIndexStore + SearchHitToLocatorResolver for a clean API.
//
// Key decisions:
// - Protocol `SearchProviding` for testability (mock injection in tests).
// - SearchResult combines snippet, locator, and match range.
// - SearchResultPage supports offset-based pagination.
// - Implementation delegates to SearchIndexStore for FTS5 and
//   SearchHitToLocatorResolver for locator resolution.
// - Background-priority indexing via structured concurrency.
//
// @coordinates-with SearchIndexStore.swift, SearchHitToLocatorResolver.swift,
//   SearchTextNormalizer.swift, Locator.swift

import Foundation
import os

// MARK: - Result Types

/// A single search result with locator for navigation.
struct SearchResult: Sendable, Identifiable, Equatable {
    /// Stable ID derived from fingerprint + source unit + offsets for consistent List diffing.
    let id: String
    /// Snippet of matching text (may contain highlight markers).
    let snippet: String
    /// Locator for navigating to the match position.
    let locator: Locator
    /// Source context description (chapter name, page number, segment).
    let sourceContext: String
}

/// A page of search results with pagination metadata.
struct SearchResultPage: Sendable, Equatable {
    let results: [SearchResult]
    let page: Int
    let hasMore: Bool
    let totalEstimate: Int?
}

// MARK: - Protocol

/// Protocol for search operations — indexing and querying.
protocol SearchProviding: Sendable {
    /// Indexes a book's text units for full-text search.
    func indexBook(
        fingerprint: DocumentFingerprint,
        textUnits: [TextUnit],
        segmentBaseOffsets: [Int: Int]?
    ) async throws

    /// Searches for a query within a specific book, returning paginated results.
    func search(
        query: String,
        bookFingerprint: DocumentFingerprint,
        page: Int,
        pageSize: Int
    ) async throws -> SearchResultPage

    /// Removes the search index for a book.
    func removeIndex(fingerprint: DocumentFingerprint) async throws

    /// Checks whether a book has been indexed.
    func isIndexed(fingerprint: DocumentFingerprint) async -> Bool
}

// MARK: - Implementation

/// Internal state protected by OSAllocatedUnfairLock.
private struct ServiceState {
    /// Segment base offsets per fingerprint key for TXT locator resolution.
    var segmentOffsets: [String: [Int: Int]] = [:]
    /// Fingerprint keys that have been indexed.
    var indexedKeys: Set<String> = []
}

/// Production search service wrapping SearchIndexStore and resolver.
final class SearchService: SearchProviding, @unchecked Sendable {

    private let store: SearchIndexStore
    private let state = OSAllocatedUnfairLock(initialState: ServiceState())

    init(store: SearchIndexStore) {
        self.store = store
    }

    func indexBook(
        fingerprint: DocumentFingerprint,
        textUnits: [TextUnit],
        segmentBaseOffsets: [Int: Int]?
    ) async throws {
        let key = fingerprint.canonicalKey
        try store.indexBook(fingerprintKey: key, textUnits: textUnits)

        state.withLock { s in
            if let offsets = segmentBaseOffsets {
                s.segmentOffsets[key] = offsets
            }
            s.indexedKeys.insert(key)
        }
    }

    func search(
        query: String,
        bookFingerprint: DocumentFingerprint,
        page: Int,
        pageSize: Int
    ) async throws -> SearchResultPage {
        let safePage = max(0, page)
        let safePageSize = max(1, pageSize)

        guard !query.isEmpty else {
            return SearchResultPage(results: [], page: safePage, hasMore: false, totalEstimate: 0)
        }
        let key = bookFingerprint.canonicalKey
        let offset = safePage * safePageSize

        // Fetch enough results to cover the requested page + 1 for hasMore detection.
        let totalFetchLimit = offset + safePageSize + 1
        let allHits = try store.search(
            query: query,
            bookFingerprintKey: key,
            limit: totalFetchLimit
        )

        // Slice for the requested page
        let pageHits: [SearchHit]
        let hasMore: Bool
        if offset >= allHits.count {
            pageHits = []
            hasMore = false
        } else {
            let endIndex = min(offset + safePageSize, allHits.count)
            pageHits = Array(allHits[offset..<endIndex])
            hasMore = allHits.count > offset + safePageSize
        }

        let offsets = state.withLock { $0.segmentOffsets[key] }

        let results = pageHits.compactMap { hit -> SearchResult? in
            guard let locator = SearchHitToLocatorResolver.resolve(
                hit: hit,
                fingerprint: bookFingerprint,
                segmentBaseOffsets: offsets
            ) else { return nil }

            let context = Self.formatSourceContext(sourceUnitId: hit.sourceUnitId)

            return SearchResult(
                id: "\(hit.fingerprintKey):\(hit.sourceUnitId):\(hit.matchStartOffsetUTF16)",
                snippet: hit.snippet ?? "",
                locator: locator,
                sourceContext: context
            )
        }

        return SearchResultPage(
            results: results,
            page: page,
            hasMore: hasMore,
            totalEstimate: nil
        )
    }

    func removeIndex(fingerprint: DocumentFingerprint) async throws {
        let key = fingerprint.canonicalKey
        try store.removeBook(fingerprintKey: key)

        state.withLock { s in
            s.segmentOffsets.removeValue(forKey: key)
            s.indexedKeys.remove(key)
        }
    }

    func isIndexed(fingerprint: DocumentFingerprint) async -> Bool {
        state.withLock { $0.indexedKeys.contains(fingerprint.canonicalKey) }
    }

    // MARK: - Private

    /// Formats a human-readable source context from a sourceUnitId.
    static func formatSourceContext(sourceUnitId: String) -> String {
        if sourceUnitId.hasPrefix("epub:") {
            let href = String(sourceUnitId.dropFirst("epub:".count))
            // Strip extension for cleaner display
            let name = (href as NSString).deletingPathExtension
            return name.isEmpty ? "Chapter" : name
        } else if sourceUnitId.hasPrefix("pdf:page:") {
            let pageStr = String(sourceUnitId.dropFirst("pdf:page:".count))
            if let page = Int(pageStr) {
                return "Page \(page + 1)" // Display as 1-indexed
            }
            return "Page"
        } else if sourceUnitId.hasPrefix("txt:segment:") {
            let segStr = String(sourceUnitId.dropFirst("txt:segment:".count))
            if let seg = Int(segStr) {
                return "Section \(seg + 1)" // Display as 1-indexed
            }
            return "Section"
        }
        return ""
    }
}
