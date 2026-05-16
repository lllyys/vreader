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

@Suite("LibraryBookItem.ReadingProgressState (feature #60 WI-8)")
struct LibraryBookItemProgressStateTests {

    @Test("nil progress fraction is notStarted")
    func nilFractionIsNotStarted() {
        #expect(LibraryBookItem.stub(progressFraction: nil)
            .readingProgressState == .notStarted)
    }

    @Test("zero progress is notStarted")
    func zeroFractionIsNotStarted() {
        #expect(LibraryBookItem.stub(progressFraction: 0)
            .readingProgressState == .notStarted)
    }

    @Test("a negative fraction is notStarted")
    func negativeFractionIsNotStarted() {
        #expect(LibraryBookItem.stub(progressFraction: -0.3)
            .readingProgressState == .notStarted)
    }

    @Test("NaN progress is notStarted")
    func nanFractionIsNotStarted() {
        #expect(LibraryBookItem.stub(progressFraction: .nan)
            .readingProgressState == .notStarted)
    }

    @Test("infinite progress is notStarted")
    func infiniteFractionIsNotStarted() {
        #expect(LibraryBookItem.stub(progressFraction: .infinity)
            .readingProgressState == .notStarted)
    }

    @Test("a tiny positive fraction is inProgress")
    func tinyFractionIsInProgress() {
        #expect(LibraryBookItem.stub(progressFraction: 0.0001)
            .readingProgressState == .inProgress(0.0001))
    }

    @Test("a mid fraction is inProgress carrying that fraction")
    func midFractionIsInProgress() {
        #expect(LibraryBookItem.stub(progressFraction: 0.5)
            .readingProgressState == .inProgress(0.5))
    }

    @Test("just under 1.0 is inProgress, not finished")
    func justUnderOneIsInProgress() {
        #expect(LibraryBookItem.stub(progressFraction: 0.9999)
            .readingProgressState == .inProgress(0.9999))
    }

    @Test("exactly 1.0 is finished")
    func exactlyOneIsFinished() {
        #expect(LibraryBookItem.stub(progressFraction: 1.0)
            .readingProgressState == .finished)
    }

    @Test("past 1.0 is finished (rounding-drift tolerance)")
    func pastOneIsFinished() {
        #expect(LibraryBookItem.stub(progressFraction: 1.5)
            .readingProgressState == .finished)
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
