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

        return AIToolRegistry(tools)
    }
}
