// Purpose: Feature #91 WI-8b — assemble the AIToolRegistry for an agentic chat
// turn from the open book's context + the production backends. Pure assembly: the
// current-book search tool is included only when a book is open; the library tools
// always are. The AIChatViewModel passes the resulting registry into the
// AgenticChatDriver.
//
// @coordinates-with: AIToolRegistry.swift, SearchCurrentBookTool.swift,
//   SearchOtherBooksTool.swift, GetBookContentTool.swift,
//   LibrarySearchBackendAdapter.swift, BookContentProviderAdapter.swift,
//   AIChatViewModel.swift (the WI-8 consumer),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Foundation

enum AgenticToolRegistryBuilder {

    /// Build the read-only tool registry for a chat turn.
    /// - `currentBook` / `currentBookSearch`: the open book's fingerprint + its live
    ///   (already-indexed) search service — when both are present, `search_current_book`
    ///   is offered. General (no-book) chat omits it.
    /// - `libraryBackend`: powers `search_other_books` (the whole library, excluding
    ///   the open book).
    /// - `contentProvider`: powers `get_book_content` (fetch a book's text by title).
    static func build(
        currentBook: DocumentFingerprint?,
        currentBookSearch: (any SearchProviding)?,
        libraryBackend: any LibrarySearchBackend,
        contentProvider: any BookContentProvider
    ) -> AIToolRegistry {
        var tools: [any AITool] = []

        if let currentBook, let currentBookSearch {
            tools.append(SearchCurrentBookTool(
                search: currentBookSearch, bookFingerprint: currentBook))
        }
        tools.append(SearchOtherBooksTool(
            backend: libraryBackend, currentBookFingerprintKey: currentBook?.canonicalKey))
        tools.append(GetBookContentTool(provider: contentProvider))
        // Feature #97: enumerate the library (shares the same `libraryBackend` as
        // search_other_books — no new dependency).
        tools.append(ListLibraryTool(
            backend: libraryBackend, currentBookFingerprintKey: currentBook?.canonicalKey))

        return AIToolRegistry(tools)
    }

    /// Build the LIVE registry over the production backends: the persistent FTS
    /// store (the SAME one the reader indexes into) + the persistence actor. Async
    /// — the cold SQLite open runs OFF the main actor (Gate-4 Medium). STRICT — a
    /// store that can't open THROWS (no empty in-memory fallback that would silently
    /// lose search coverage — Gate-4 High); the caller falls back to a non-agentic
    /// chat. The composition is exercised by `build(...)`'s tests; the live
    /// construction is integration/device-verified.
    static func buildLive(
        currentBook: DocumentFingerprint?, library: any LibraryPersisting
    ) async throws -> AIToolRegistry {
        let store = try await Task.detached { try PersistentSearchIndex.makeStoreStrict() }.value
        let search = SearchService(store: store)

        // search_current_book is only safe when the open book is searchable from the
        // persistent index — the SAME gate as search_other_books (Gate-4 High):
        // for TXT/MD, restore the segment offsets into THIS search service so hits
        // resolve (without them the locator resolver drops every hit); for an
        // ineligible / unindexed book, OMIT the tool (the model uses the library
        // tools / get_book_content instead of getting a misleading "No matches").
        var currentBookSearch: (any SearchProviding)?
        if let fingerprint = currentBook {
            let key = fingerprint.canonicalKey
            let state = LibraryIndexState(
                isIndexed: store.isBookIndexed(fingerprintKey: key),
                requiresReindex: store.requiresReindex(fingerprintKey: key),
                segmentOffsets: store.getSegmentBaseOffsets(fingerprintKey: key))
            if case .searchable(let restore) = LibraryBookSearchGate.evaluate(
                format: fingerprint.format.rawValue, state: state) {
                if let restore {
                    search.restoreSegmentOffsets(fingerprint: fingerprint, offsets: restore)
                }
                currentBookSearch = search
            }
        }

        return build(
            currentBook: currentBook,
            currentBookSearch: currentBookSearch,
            libraryBackend: LibrarySearchBackendAdapter(library: library, index: store, search: search),
            contentProvider: BookContentProviderAdapter(library: library))
    }
}
