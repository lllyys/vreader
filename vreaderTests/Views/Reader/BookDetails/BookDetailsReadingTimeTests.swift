// Purpose: Feature #101 WI-2b — pins the Book details Reading time
// composition (`BookDetailsSheet.readingTimeRows`: the three designed
// rows from `RTBookDetailsRows`, omitted while the host fetch is in
// flight) and the `.readerSessionTimeDidChange` mirror's pure keying
// rules (`BookDetailsReadingTimeMirror.sessionDisplayUpdate`).

import Testing
import Foundation
@testable import vreader

@Suite("Feature #101 WI-2b — Reading time rows + session mirror")
@MainActor
struct BookDetailsReadingTimeTests {

    // MARK: - Fixtures

    private let bookKey =
        "epub:0000000000000000000000000000000000000000000000000000000000000000:204800"

    private func makeItem() -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: bookKey,
            title: "Sample Book", author: "Jane Austen",
            coverImagePath: nil, format: "epub", fileByteCount: 204_800,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0,
            averagePagesPerHour: nil, averageWordsPerMinute: nil,
            collectionNames: [], totalPageCount: nil
        )
    }

    private func makeSheet(
        stats: BookReadingTimeStats?, live: String?
    ) -> BookDetailsSheet {
        BookDetailsSheet(
            book: makeItem(), theme: .paper,
            coverPickCoordinator: CoverPickCoordinator(),
            onExportAnnotations: {},
            readingTimeStats: stats, liveSessionDisplay: live
        )
    }

    private func record(total: Int, sessions: Int) -> ReadingStatsRecord {
        ReadingStatsRecord(
            bookFingerprintKey: bookKey, totalReadingSeconds: total,
            sessionCount: sessions, lastReadAt: nil,
            averagePagesPerHour: nil, averageWordsPerMinute: nil,
            totalPagesRead: nil, totalWordsRead: nil, longestSessionSeconds: 0
        )
    }

    // MARK: - Row composition

    @Test("Section is omitted while the stats fetch is in flight")
    func nilStatsYieldsNoRows() {
        let sheet = makeSheet(stats: nil, live: "12m read")
        #expect(sheet.readingTimeRows.isEmpty)
    }

    @Test("Three designed rows render from a fetched record")
    func threeRowsInDesignOrder() {
        let stats = BookReadingTimeStats(
            record: record(total: 24_000, sessions: 23),
            firstSessionDate: nil
        )
        let rows = makeSheet(stats: stats, live: "12m read").readingTimeRows
        #expect(rows.map(\.label) == ["Reading time", "This session", "Average session"])
        #expect(rows[0].value == "6h 40m total")
        #expect(rows[0].sub == "23 sessions")
        #expect(rows[1].value == "12m")
        #expect(rows[1].sub == nil)
        #expect(rows[2].value == "17m")
    }

    @Test("Never-read book renders truthful zeros with dashes")
    func absentRecordRendersZeros() {
        let stats = BookReadingTimeStats(record: nil, firstSessionDate: nil)
        let rows = makeSheet(stats: stats, live: nil).readingTimeRows
        #expect(rows[0].value == "0m total")
        #expect(rows[0].sub == nil)
        #expect(rows[1].value == "\u{2014}")
        #expect(rows[2].value == "\u{2014}")
    }

    @Test("No live reader shows an em-dash session row")
    func noLiveSessionShowsDash() {
        let stats = BookReadingTimeStats(
            record: record(total: 7_200, sessions: 4), firstSessionDate: nil)
        let rows = makeSheet(stats: stats, live: nil).readingTimeRows
        #expect(rows[1].value == "\u{2014}")
    }

    // MARK: - Session-display mirror keying

    @Test("Payload keyed to this book sets the display")
    func matchingKeySetsDisplay() {
        let update = BookDetailsReadingTimeMirror.sessionDisplayUpdate(
            from: ["fingerprintKey": bookKey, "display": "12m read"],
            bookFingerprintKey: bookKey
        )
        #expect(update == .set("12m read"))
    }

    @Test("Payload for a different book is ignored")
    func otherBookIsIgnored() {
        let update = BookDetailsReadingTimeMirror.sessionDisplayUpdate(
            from: ["fingerprintKey": "epub:other:1", "display": "9m read"],
            bookFingerprintKey: bookKey
        )
        #expect(update == .ignore)
    }

    @Test("Empty display maps to nil (the row falls back to the dash)")
    func emptyDisplayMapsToNil() {
        let update = BookDetailsReadingTimeMirror.sessionDisplayUpdate(
            from: ["fingerprintKey": bookKey, "display": ""],
            bookFingerprintKey: bookKey
        )
        #expect(update == .set(nil))
    }

    @Test("Malformed payload is ignored")
    func malformedPayloadIsIgnored() {
        #expect(BookDetailsReadingTimeMirror.sessionDisplayUpdate(
            from: nil, bookFingerprintKey: bookKey) == .ignore)
        #expect(BookDetailsReadingTimeMirror.sessionDisplayUpdate(
            from: ["display": "12m read"], bookFingerprintKey: bookKey) == .ignore)
    }
}
