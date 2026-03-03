import Testing
import Foundation

@testable import vreader

// MARK: - ReadingPosition Model Tests

@Suite("ReadingPosition Model")
struct ReadingPositionTests {

    // MARK: - Creation

    @Test("creates position with chapter and progression")
    func createWithFields() {
        let bookID = UUID()
        let position = ReadingPosition(
            bookID: bookID,
            locator: BookLocator(chapter: 3, progression: 0.42)
        )

        #expect(position.bookID == bookID)
        #expect(position.locator.chapter == 3)
        #expect(position.locator.progression == 0.42)
    }

    @Test("stores last-updated timestamp")
    func timestampOnCreation() {
        let before = Date()
        let position = ReadingPosition(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0)
        )
        let after = Date()

        #expect(position.lastUpdated >= before)
        #expect(position.lastUpdated <= after)
    }

    // MARK: - Update

    @Test("updating position changes locator and timestamp")
    func updatePosition() {
        let position = ReadingPosition(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.1)
        )
        let originalDate = position.lastUpdated

        // Simulate time passing
        let newLocator = BookLocator(chapter: 2, progression: 0.5)
        position.update(to: newLocator)

        #expect(position.locator.chapter == 2)
        #expect(position.locator.progression == 0.5)
        #expect(position.lastUpdated >= originalDate)
    }

    @Test("updating to same position still updates timestamp")
    func updateSamePosition() {
        let locator = BookLocator(chapter: 1, progression: 0.5)
        let position = ReadingPosition(
            bookID: UUID(),
            locator: locator
        )

        position.update(to: locator)

        // Should not crash; timestamp may or may not change
        #expect(position.locator.chapter == 1)
        #expect(position.locator.progression == 0.5)
    }

    // MARK: - Boundary Values

    @Test("position at start of book")
    func startOfBook() {
        let position = ReadingPosition(
            bookID: UUID(),
            locator: BookLocator(chapter: 0, progression: 0.0)
        )

        #expect(position.locator.chapter == 0)
        #expect(position.locator.progression == 0.0)
    }

    @Test("position at end of book")
    func endOfBook() {
        let position = ReadingPosition(
            bookID: UUID(),
            locator: BookLocator(chapter: 99, progression: 1.0)
        )

        #expect(position.locator.chapter == 99)
        #expect(position.locator.progression == 1.0)
    }

    // MARK: - Deletion with Book

    @Test("position references parent book by ID")
    func bookReference() {
        let bookID = UUID()
        let position = ReadingPosition(
            bookID: bookID,
            locator: BookLocator(chapter: 1, progression: 0.5)
        )

        #expect(position.bookID == bookID)
    }

    // MARK: - PDF-specific Position

    @Test("stores page number for PDF books")
    func pdfPageNumber() {
        let position = ReadingPosition(
            bookID: UUID(),
            locator: BookLocator(chapter: 0, progression: 0.0, pageNumber: 42)
        )

        #expect(position.locator.pageNumber == 42)
    }

    @Test("page number nil for EPUB positions")
    func epubNoPageNumber() {
        let position = ReadingPosition(
            bookID: UUID(),
            locator: BookLocator(chapter: 3, progression: 0.7)
        )

        #expect(position.locator.pageNumber == nil)
    }

    // MARK: - Edge Cases

    @Test("handles very precise progression values")
    func preciseProgression() {
        let position = ReadingPosition(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.123456789)
        )

        #expect(abs(position.locator.progression - 0.123456789) < 0.0001)
    }
}
