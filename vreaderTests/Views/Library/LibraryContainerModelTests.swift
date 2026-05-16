// Purpose: Contract tests for the feature #60 WI-9 Library-container
// re-skin. `LibraryContainerModel` is the pure derivation layer the
// re-skinned `LibraryView` reads — search filtering, the active
// collection filter, the "Continue reading" rail set, and the
// subtitle counts. Testing it here pins the view-model-state-preserved
// invariant (rule 47 Gate 5 WI-9 catalogue entry) without a SwiftUI
// render.
//
// Design source: `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-library.jsx` — `LibraryScreen`'s `filtered` / `reading`
// derivations + the `{N} books · {M} reading` subtitle.
//
// @coordinates-with: LibraryContainerModel.swift, LibraryView.swift,
//   LibraryFilter (CollectionSidebar.swift), LibraryBookItem.swift

import Testing
import Foundation
@testable import vreader

@Suite("LibraryContainerModel — feature #60 WI-9")
struct LibraryContainerModelTests {

    // MARK: - Helpers

    private func book(
        key: String,
        title: String = "Untitled",
        author: String? = nil,
        progress: Double? = nil,
        collections: [String] = []
    ) -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: key,
            title: title,
            author: author,
            coverImagePath: nil,
            format: "epub",
            fileByteCount: 1024,
            addedAt: Date(timeIntervalSince1970: 0),
            lastOpenedAt: nil,
            isFavorite: false,
            totalReadingSeconds: 0,
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil,
            collectionNames: collections,
            progressFraction: progress
        )
    }

    private var sample: [LibraryBookItem] {
        [
            book(key: "epub:a:1", title: "Pride and Prejudice",
                 author: "Jane Austen", progress: 0.4),
            book(key: "epub:b:2", title: "Moby Dick",
                 author: "Herman Melville", progress: nil),
            book(key: "epub:c:3", title: "War and Peace",
                 author: "Leo Tolstoy", progress: 1.0),
            book(key: "epub:d:4", title: "Crime and Punishment",
                 author: "Fyodor Dostoevsky", progress: 0.85,
                 collections: ["Classics"]),
        ]
    }

    // MARK: - Search filtering (design `filtered` derivation)

    @Test("Empty query returns every book under the .allBooks filter")
    func emptyQueryReturnsAll() {
        let model = LibraryContainerModel(
            searchQuery: "", activeFilter: .allBooks
        )
        #expect(model.matchingBooks(in: sample).count == 4)
    }

    @Test("Query matches book titles case-insensitively")
    func queryMatchesTitle() {
        let model = LibraryContainerModel(
            searchQuery: "pride", activeFilter: .allBooks
        )
        let result = model.matchingBooks(in: sample)
        #expect(result.count == 1)
        #expect(result.first?.title == "Pride and Prejudice")
    }

    @Test("Query matches author names case-insensitively")
    func queryMatchesAuthor() {
        let model = LibraryContainerModel(
            searchQuery: "TOLSTOY", activeFilter: .allBooks
        )
        let result = model.matchingBooks(in: sample)
        #expect(result.count == 1)
        #expect(result.first?.title == "War and Peace")
    }

    @Test("Query with no match returns an empty set")
    func queryNoMatchReturnsEmpty() {
        let model = LibraryContainerModel(
            searchQuery: "zzzzz", activeFilter: .allBooks
        )
        #expect(model.matchingBooks(in: sample).isEmpty)
    }

    @Test("Whitespace-only query is treated as no query")
    func whitespaceQueryIgnored() {
        let model = LibraryContainerModel(
            searchQuery: "   ", activeFilter: .allBooks
        )
        #expect(model.matchingBooks(in: sample).count == 4)
    }

    @Test("Query is trimmed before matching")
    func queryTrimmedBeforeMatch() {
        let model = LibraryContainerModel(
            searchQuery: "  moby  ", activeFilter: .allBooks
        )
        #expect(model.matchingBooks(in: sample).count == 1)
    }

    @Test("Query matches a CJK title")
    func queryMatchesCJK() {
        let cjk = [book(key: "epub:x:9", title: "红楼梦", author: "曹雪芹")]
        let model = LibraryContainerModel(
            searchQuery: "红楼", activeFilter: .allBooks
        )
        #expect(model.matchingBooks(in: cjk).count == 1)
    }

    @Test("Query against a book with a nil author does not crash")
    func queryHandlesNilAuthor() {
        let model = LibraryContainerModel(
            searchQuery: "dick", activeFilter: .allBooks
        )
        let result = model.matchingBooks(in: sample)
        #expect(result.count == 1)
        #expect(result.first?.title == "Moby Dick")
    }

    // MARK: - Collection filter (preserves bug #155 behavior)

    @Test("Collection filter narrows to that collection's members")
    func collectionFilterNarrows() {
        let model = LibraryContainerModel(
            searchQuery: "", activeFilter: .collection("Classics")
        )
        let result = model.matchingBooks(in: sample)
        #expect(result.count == 1)
        #expect(result.first?.title == "Crime and Punishment")
    }

    @Test("Search query and collection filter compose (AND)")
    func searchAndFilterCompose() {
        let model = LibraryContainerModel(
            searchQuery: "war", activeFilter: .collection("Classics")
        )
        // "War and Peace" matches the query but is NOT in Classics;
        // "Crime and Punishment" is in Classics but doesn't match "war".
        #expect(model.matchingBooks(in: sample).isEmpty)
    }

    // MARK: - Continue-reading rail (design `reading` derivation)

    @Test("Continue-reading rail holds only in-progress books")
    func continueRailOnlyInProgress() {
        let model = LibraryContainerModel(
            searchQuery: "", activeFilter: .allBooks
        )
        let rail = model.continueReadingBooks(in: sample)
        // 0.4 and 0.85 are in progress; nil (not started) and 1.0
        // (finished) are excluded.
        #expect(rail.count == 2)
        #expect(rail.allSatisfy {
            if case .inProgress = $0.readingProgressState { return true }
            return false
        })
    }

    @Test("Continue-reading rail excludes finished and not-started books")
    func continueRailExcludesTerminal() {
        let model = LibraryContainerModel(
            searchQuery: "", activeFilter: .allBooks
        )
        let railKeys = Set(model.continueReadingBooks(in: sample)
            .map(\.fingerprintKey))
        #expect(!railKeys.contains("epub:b:2"))   // not started
        #expect(!railKeys.contains("epub:c:3"))   // finished
    }

    @Test("Continue-reading rail is empty when nothing is in progress")
    func continueRailEmptyWhenNoneInProgress() {
        let noneReading = [
            book(key: "epub:a:1", progress: nil),
            book(key: "epub:b:2", progress: 1.0),
        ]
        let model = LibraryContainerModel(
            searchQuery: "", activeFilter: .allBooks
        )
        #expect(model.continueReadingBooks(in: noneReading).isEmpty)
    }

    @Test("Continue-reading rail respects the active search query")
    func continueRailRespectsQuery() {
        let model = LibraryContainerModel(
            searchQuery: "pride", activeFilter: .allBooks
        )
        let rail = model.continueReadingBooks(in: sample)
        #expect(rail.count == 1)
        #expect(rail.first?.title == "Pride and Prejudice")
    }

    // MARK: - Rail visibility (design: rail only on .allBooks + no query)

    @Test("Rail is visible only under .allBooks with no query")
    func railVisibleOnlyAllBooksNoQuery() {
        #expect(LibraryContainerModel(
            searchQuery: "", activeFilter: .allBooks
        ).showsContinueReadingRail)
    }

    @Test("Rail is hidden when a search query is active")
    func railHiddenWithQuery() {
        #expect(!LibraryContainerModel(
            searchQuery: "pride", activeFilter: .allBooks
        ).showsContinueReadingRail)
    }

    @Test("Rail is hidden when a collection filter is active")
    func railHiddenWithCollectionFilter() {
        #expect(!LibraryContainerModel(
            searchQuery: "", activeFilter: .collection("Classics")
        ).showsContinueReadingRail)
    }

    @Test("Whitespace-only query still shows the rail")
    func railVisibleWithWhitespaceQuery() {
        #expect(LibraryContainerModel(
            searchQuery: "   ", activeFilter: .allBooks
        ).showsContinueReadingRail)
    }

    // MARK: - Subtitle counts (design `{N} books · {M} reading`)

    @Test("Subtitle counts total books and in-progress books")
    func subtitleCounts() {
        let model = LibraryContainerModel(
            searchQuery: "", activeFilter: .allBooks
        )
        let counts = model.subtitleCounts(for: sample)
        #expect(counts.total == 4)
        #expect(counts.reading == 2)   // 0.4 and 0.85
    }

    @Test("Subtitle counts the full library, not the filtered subset")
    func subtitleCountsFullLibrary() {
        // Even with a query/filter that narrows the grid, the subtitle
        // reflects the whole library — matches the design, where
        // `BOOKS.length` is the unfiltered count.
        let model = LibraryContainerModel(
            searchQuery: "pride", activeFilter: .collection("Classics")
        )
        let counts = model.subtitleCounts(for: sample)
        #expect(counts.total == 4)
        #expect(counts.reading == 2)
    }

    @Test("Subtitle of an empty library is zero / zero")
    func subtitleEmptyLibrary() {
        let model = LibraryContainerModel(
            searchQuery: "", activeFilter: .allBooks
        )
        let counts = model.subtitleCounts(for: [])
        #expect(counts.total == 0)
        #expect(counts.reading == 0)
    }
}
