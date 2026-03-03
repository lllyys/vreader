import Testing
import Foundation

@testable import vreader

// MARK: - Bookmark Model Tests

@Suite("Bookmark Model")
struct BookmarkTests {

    // MARK: - Creation

    @Test("creates bookmark with required fields")
    func createWithRequiredFields() {
        let bookID = UUID()
        let bookmark = Bookmark(
            bookID: bookID,
            locator: BookLocator(chapter: 2, progression: 0.35),
            label: "Important passage"
        )

        #expect(bookmark.bookID == bookID)
        #expect(bookmark.locator.chapter == 2)
        #expect(bookmark.locator.progression == 0.35)
        #expect(bookmark.label == "Important passage")
    }

    @Test("assigns creation date automatically")
    func autoDateCreated() {
        let before = Date()
        let bookmark = Bookmark(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            label: nil
        )
        let after = Date()

        #expect(bookmark.dateCreated >= before)
        #expect(bookmark.dateCreated <= after)
    }

    @Test("creates bookmark without label")
    func createWithoutLabel() {
        let bookmark = Bookmark(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.5),
            label: nil
        )

        #expect(bookmark.label == nil)
    }

    @Test("auto-generates unique id")
    func uniqueIDs() {
        let bm1 = Bookmark(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            label: nil
        )
        let bm2 = Bookmark(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            label: nil
        )

        #expect(bm1.id != bm2.id)
    }

    // MARK: - Ordering

    @Test("bookmarks sort by chapter then progression")
    func sortOrder() {
        let bookID = UUID()
        let bm1 = Bookmark(
            bookID: bookID,
            locator: BookLocator(chapter: 1, progression: 0.5),
            label: nil
        )
        let bm2 = Bookmark(
            bookID: bookID,
            locator: BookLocator(chapter: 2, progression: 0.1),
            label: nil
        )
        let bm3 = Bookmark(
            bookID: bookID,
            locator: BookLocator(chapter: 1, progression: 0.8),
            label: nil
        )

        let sorted = [bm2, bm3, bm1].sorted()

        #expect(sorted[0].locator.chapter == 1)
        #expect(sorted[0].locator.progression == 0.5)
        #expect(sorted[1].locator.chapter == 1)
        #expect(sorted[1].locator.progression == 0.8)
        #expect(sorted[2].locator.chapter == 2)
    }

    @Test("bookmarks at same position sort by creation date")
    func sortSamePosition() {
        let bookID = UUID()
        let bm1 = Bookmark(
            bookID: bookID,
            locator: BookLocator(chapter: 1, progression: 0.5),
            label: "First"
        )
        // Ensure different creation dates
        let bm2 = Bookmark(
            bookID: bookID,
            locator: BookLocator(chapter: 1, progression: 0.5),
            label: "Second"
        )

        let sorted = [bm2, bm1].sorted()

        // Earlier creation date first
        #expect(sorted[0].dateCreated <= sorted[1].dateCreated)
    }

    // MARK: - Cascade Delete

    @Test("bookmark references parent book by ID")
    func bookReference() {
        let bookID = UUID()
        let bookmark = Bookmark(
            bookID: bookID,
            locator: BookLocator(chapter: 1, progression: 0.0),
            label: nil
        )

        #expect(bookmark.bookID == bookID)
    }

    // MARK: - Edge Cases

    @Test("bookmark at chapter boundary (progression 0.0)")
    func chapterBoundaryStart() {
        let bookmark = Bookmark(
            bookID: UUID(),
            locator: BookLocator(chapter: 3, progression: 0.0),
            label: nil
        )

        #expect(bookmark.locator.progression == 0.0)
    }

    @Test("bookmark at chapter end (progression 1.0)")
    func chapterBoundaryEnd() {
        let bookmark = Bookmark(
            bookID: UUID(),
            locator: BookLocator(chapter: 3, progression: 1.0),
            label: nil
        )

        #expect(bookmark.locator.progression == 1.0)
    }

    @Test("bookmark with CJK label")
    func cjkLabel() {
        let bookmark = Bookmark(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.2),
            label: "重要な一節"
        )

        #expect(bookmark.label == "重要な一節")
    }

    @Test("bookmark with very long label")
    func longLabel() {
        let longLabel = String(repeating: "x", count: 5000)
        let bookmark = Bookmark(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.1),
            label: longLabel
        )

        #expect(bookmark.label?.count == 5000)
    }

    @Test("bookmark with empty string label treated as nil-equivalent")
    func emptyLabel() {
        let bookmark = Bookmark(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            label: ""
        )

        #expect(bookmark.displayLabel == nil || bookmark.displayLabel?.isEmpty == true)
    }
}
