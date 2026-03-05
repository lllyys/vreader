// Purpose: Tests for LibraryBookItem — computed properties, Identifiable, Sendable.

import Testing
import Foundation
@testable import vreader

@Suite("LibraryBookItem")
struct LibraryBookItemTests {

    @Test func idIsFingerprintKey() {
        let item = LibraryBookItem.stub(fingerprintKey: "unique-key")
        #expect(item.id == "unique-key")
    }

    @Test func isSendable() {
        // Compile-time check: can be sent across actor boundaries
        let item = LibraryBookItem.stub()
        let _: any Sendable = item
        #expect(item.fingerprintKey == "epub:abc123:1024")
    }

    @Test func formattedReadingTimeForNonZero() {
        let item = LibraryBookItem.stub(totalReadingSeconds: 5400)
        #expect(item.formattedReadingTime == "1h 30m read")
    }

    @Test func formattedReadingTimeNilForZero() {
        let item = LibraryBookItem.stub(totalReadingSeconds: 0)
        #expect(item.formattedReadingTime == nil)
    }

    @Test func formattedSpeedWithPages() {
        let item = LibraryBookItem.stub(
            totalReadingSeconds: 3600,
            averagePagesPerHour: 25.3
        )
        #expect(item.formattedSpeed == "~25 pages/hr")
    }

    @Test func formattedSpeedNilUnder60s() {
        let item = LibraryBookItem.stub(
            totalReadingSeconds: 30,
            averagePagesPerHour: 25.0
        )
        #expect(item.formattedSpeed == nil)
    }

    @Test func formatBadgeUppercased() {
        let epub = LibraryBookItem.stub(format: "epub")
        #expect(epub.formatBadge == "EPUB")

        let pdf = LibraryBookItem.stub(format: "pdf")
        #expect(pdf.formatBadge == "PDF")

        let txt = LibraryBookItem.stub(format: "txt")
        #expect(txt.formatBadge == "TXT")

        let md = LibraryBookItem.stub(format: "md")
        #expect(md.formatBadge == "MD")
    }

    @Test func formatIconForAllFormats() {
        let epub = LibraryBookItem.stub(format: "epub")
        #expect(epub.formatIcon == "book.fill")

        let pdf = LibraryBookItem.stub(format: "pdf")
        #expect(pdf.formatIcon == "doc.fill")

        let txt = LibraryBookItem.stub(format: "txt")
        #expect(txt.formatIcon == "doc.text.fill")

        let md = LibraryBookItem.stub(format: "md")
        #expect(md.formatIcon == "doc.richtext.fill")

        let unknown = LibraryBookItem.stub(format: "xyz")
        #expect(unknown.formatIcon == "doc.fill")
    }

    @Test func equalityByAllFields() {
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let a = LibraryBookItem.stub(fingerprintKey: "k1", title: "Book", addedAt: fixedDate)
        let b = LibraryBookItem.stub(fingerprintKey: "k1", title: "Book", addedAt: fixedDate)
        #expect(a == b)
    }

    @Test func inequalityByTitle() {
        let a = LibraryBookItem.stub(fingerprintKey: "k1", title: "Book A")
        let b = LibraryBookItem.stub(fingerprintKey: "k1", title: "Book B")
        #expect(a != b)
    }
}

@Suite("LibrarySortOrder")
struct LibrarySortOrderTests {

    @Test func isSendable() {
        let sort: LibrarySortOrder = .title
        let _: any Sendable = sort
        #expect(sort == .title)
    }

    @Test func allCasesContainsAllOrders() {
        let cases = LibrarySortOrder.allCases
        #expect(cases.count == 4)
        #expect(cases.contains(.title))
        #expect(cases.contains(.addedAt))
        #expect(cases.contains(.lastReadAt))
        #expect(cases.contains(.totalReadingTime))
    }

    @Test func labelsAreHumanReadable() {
        #expect(LibrarySortOrder.title.label == "Title")
        #expect(LibrarySortOrder.addedAt.label == "Date Added")
        #expect(LibrarySortOrder.lastReadAt.label == "Last Read")
        #expect(LibrarySortOrder.totalReadingTime.label == "Reading Time")
    }

    @Test func idIsRawValue() {
        #expect(LibrarySortOrder.title.id == "title")
        #expect(LibrarySortOrder.addedAt.id == "addedAt")
    }
}
