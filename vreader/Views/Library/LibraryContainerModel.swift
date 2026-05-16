// Purpose: Pure derivation layer for the feature #60 WI-9 Library
// container re-skin. Holds the two view-state inputs the re-skinned
// `LibraryView` toggles — the search query and the active collection
// filter — and derives the filtered grid set, the "Continue reading"
// rail set, the rail-visibility predicate, and the subtitle counts.
//
// Kept as a separate value type (not inline `@State` logic in the
// view) so the derivations are unit-testable without a SwiftUI render
// — the rule 47 WI-9 catalogue entry pins "view-model state preserved
// across the re-skin".
//
// Key decisions:
// - **Pure value type, no SwiftUI import.** Every member is a pure
//   function of its inputs + the passed-in book list. The view owns
//   the `@State` storage; this type only computes.
// - **Search mirrors the design's client-side filter** — case-
//   insensitive substring against title + author (`vreader-library.jsx`
//   `LibraryScreen.filtered`). It does NOT search file content; the
//   design's placeholder text says "content" but the JSX filter is
//   title/author only, so this matches the actual designed behavior.
// - **Collection filter delegates to `LibraryFilter.matches(_:)`** so
//   bug #155's exact-string membership semantics stay in one place.
// - **Search AND filter compose** — a book must satisfy both to appear.
// - **Subtitle counts the whole library**, not the filtered subset —
//   the design's `{BOOKS.length} books` is the unfiltered count.
//
// @coordinates-with: LibraryView.swift, LibraryFilter (CollectionSidebar.swift),
//   LibraryBookItem.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`

import Foundation

/// Pure derivation layer for the re-skinned Library container.
struct LibraryContainerModel: Equatable, Sendable {

    /// Raw search text as typed into the search bar. Trimmed before use.
    let searchQuery: String

    /// Active collection / tag / series filter from `CollectionSidebar`.
    let activeFilter: LibraryFilter

    /// Counts shown in the Library subtitle — `{total} books · {reading} reading`.
    struct SubtitleCounts: Equatable, Sendable {
        let total: Int
        let reading: Int
    }

    // MARK: - Derived state

    /// The query trimmed of surrounding whitespace, or `nil` when the
    /// trimmed query is empty (so a whitespace-only query is a no-op).
    var normalizedQuery: String? {
        let trimmed = searchQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether the "Continue reading" rail should be shown. Per the
    /// design (`vreader-library.jsx`: `filter === 'All' && !query`) the
    /// rail appears only with the default `.allBooks` filter and no
    /// active search query.
    var showsContinueReadingRail: Bool {
        activeFilter == .allBooks && normalizedQuery == nil
    }

    // MARK: - Filtering

    /// Books visible in the main grid / list under the active filter
    /// and search query. Filter and query compose with AND semantics.
    func matchingBooks(in books: [LibraryBookItem]) -> [LibraryBookItem] {
        books.filter { book in
            activeFilter.matches(book) && matchesQuery(book)
        }
    }

    /// Books for the "Continue reading" rail — in-progress books that
    /// also satisfy the active search query. (The rail is only mounted
    /// under `.allBooks`, but applying the query here keeps the
    /// derivation honest if a caller mounts it under other conditions.)
    func continueReadingBooks(in books: [LibraryBookItem]) -> [LibraryBookItem] {
        books.filter { book in
            guard matchesQuery(book) else { return false }
            if case .inProgress = book.readingProgressState { return true }
            return false
        }
    }

    /// Subtitle counts over the WHOLE library — total books and the
    /// number currently in progress. Independent of the active filter
    /// / query, matching the design's unfiltered `BOOKS.length`.
    func subtitleCounts(for books: [LibraryBookItem]) -> SubtitleCounts {
        let reading = books.reduce(into: 0) { count, book in
            if case .inProgress = book.readingProgressState { count += 1 }
        }
        return SubtitleCounts(total: books.count, reading: reading)
    }

    // MARK: - Private

    /// Whether `book` matches the active search query. An empty /
    /// whitespace-only query matches everything. Otherwise the trimmed
    /// query must be a case-insensitive substring of the title or the
    /// author (a `nil` author simply never contributes a match).
    private func matchesQuery(_ book: LibraryBookItem) -> Bool {
        guard let query = normalizedQuery else { return true }
        if book.title.localizedCaseInsensitiveContains(query) {
            return true
        }
        if let author = book.author,
           author.localizedCaseInsensitiveContains(query) {
            return true
        }
        return false
    }
}
