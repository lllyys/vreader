// Purpose: Unit tests for ReadingStatsAggregator — time-window aggregation
// over ReadingSession + Book rows. Feature #58 WI-2.

import Foundation
import SwiftData
import Testing
@testable import vreader

@Suite("ReadingStatsAggregator")
struct ReadingStatsAggregatorTests {

    // MARK: - Fixtures

    /// Fixed reference instant: 2026-05-19 14:30:00 UTC.
    private static var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 19
        c.hour = 14; c.minute = 30; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private static func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A valid fingerprint with a distinct 64-lowercase-hex SHA per seed string.
    /// The seed is hashed into the SHA so two different seeds → two different keys.
    private func fingerprint(_ seed: String) -> DocumentFingerprint {
        // Build 64 hex chars deterministically from the seed's bytes.
        var hex = ""
        let bytes = Array(seed.utf8)
        var i = 0
        while hex.count < 64 {
            let byte = bytes[i % bytes.count] &+ UInt8(i)
            hex += String(format: "%02x", byte)
            i += 1
        }
        let sha = String(hex.prefix(64))
        return DocumentFingerprint(contentSHA256: sha, fileByteCount: 1024, format: .epub)
    }

    /// Inserts a ReadingSession into a fresh context and saves.
    private func seedSession(
        _ container: ModelContainer, book: DocumentFingerprint,
        startedAt: Date, durationSeconds: Int, endedAt: Date? = nil
    ) throws {
        let context = ModelContext(container)
        let session = ReadingSession(
            bookFingerprint: book, startedAt: startedAt,
            endedAt: endedAt, durationSeconds: durationSeconds
        )
        context.insert(session)
        try context.save()
    }

    private func seedBook(_ container: ModelContainer, fp: DocumentFingerprint, title: String) throws {
        let context = ModelContext(container)
        let provenance = ImportProvenance(
            source: .localCopy, importedAt: Date(), originalURLBookmarkData: nil
        )
        let book = Book(fingerprint: fp, title: title, provenance: provenance)
        context.insert(book)
        try context.save()
    }

    private func aggregator(_ container: ModelContainer) -> ReadingStatsAggregator {
        ReadingStatsAggregator(modelContainer: container, calendarProvider: { Self.utcCalendar() })
    }

    /// Attaches `n` highlights + `m` annotation notes to the existing Book row
    /// for `fp` (via the cascade relationship). Must be called after `seedBook`.
    private func seedAnnotations(
        _ container: ModelContainer, fp: DocumentFingerprint,
        highlights: Int, notes: Int
    ) throws {
        let context = ModelContext(container)
        let key = fp.canonicalKey
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.fingerprintKey == key }
        )
        let book = try #require(context.fetch(descriptor).first)
        let locator = try #require(Locator.validated(bookFingerprint: fp, page: 1))
        for _ in 0..<highlights {
            let hl = Highlight(locator: locator, selectedText: "h")
            hl.book = book
            context.insert(hl)
        }
        for _ in 0..<notes {
            let note = AnnotationNote(locator: locator, content: "n")
            note.book = book
            context.insert(note)
        }
        try context.save()
    }

    // MARK: - Empty / basic

    @Test func emptyDatabaseYieldsAllZeroSnapshot() async throws {
        let container = try makeContainer()
        let snap = try await aggregator(container).snapshot(
            window: .today, sort: .default, now: Self.now
        )
        #expect(snap.perBook.isEmpty)
        #expect(snap.lifetimeTotalSeconds == 0)
        #expect(snap.trackingSince == nil)
        #expect(snap.windowTotals.allSatisfy { $0.totalSeconds == 0 && $0.sessionCount == 0 })
        #expect(snap.windowTotals.count == 7)
    }

    @Test func singleSessionTodayCountsInEveryWindow() async throws {
        let container = try makeContainer()
        let fp = fingerprint("a")
        try seedBook(container, fp: fp, title: "Book A")
        // Session 1 hour ago, 600s.
        try seedSession(container, book: fp,
                        startedAt: Self.now.addingTimeInterval(-3600), durationSeconds: 600)

        let snap = try await aggregator(container).snapshot(
            window: .today, sort: .default, now: Self.now
        )
        // 1h ago is within today/7d/30d/.../all — all windows count it.
        for window in ReadingStatsWindow.allCases {
            #expect(snap.total(for: window).totalSeconds == 600,
                    "window \(window.rawValue) should total 600s")
            #expect(snap.total(for: window).sessionCount == 1)
        }
        #expect(snap.lifetimeTotalSeconds == 600)
        #expect(snap.perBook.count == 1)
        #expect(snap.perBook[0].title == "Book A")
        #expect(snap.perBook[0].readingSecondsInWindow == 600)
        #expect(snap.perBook[0].isDeleted == false)
    }

    @Test func sessionAtExact7dBoundaryCountsTowardWeek() async throws {
        let container = try makeContainer()
        let fp = fingerprint("b")
        try seedBook(container, fp: fp, title: "Boundary Book")
        // startedAt EXACTLY at now-7d — half-open [start, now) includes the start.
        let weekStart = Self.now.addingTimeInterval(-7 * 86_400)
        try seedSession(container, book: fp, startedAt: weekStart, durationSeconds: 300)

        let snap = try await aggregator(container).snapshot(
            window: .last7Days, sort: .default, now: Self.now
        )
        #expect(snap.total(for: .last7Days).totalSeconds == 300)
        #expect(snap.total(for: .last7Days).sessionCount == 1)
    }

    @Test func sessionStartedBeforeWindowIsExcluded() async throws {
        let container = try makeContainer()
        let fp = fingerprint("c")
        try seedBook(container, fp: fp, title: "Old Book")
        // 8 days ago — outside the 7d window, inside 30d.
        try seedSession(container, book: fp,
                        startedAt: Self.now.addingTimeInterval(-8 * 86_400), durationSeconds: 500)

        let snap = try await aggregator(container).snapshot(
            window: .last7Days, sort: .default, now: Self.now
        )
        #expect(snap.total(for: .last7Days).totalSeconds == 0)
        #expect(snap.total(for: .last30Days).totalSeconds == 500)
        #expect(snap.total(for: .allTime).totalSeconds == 500)
        // The per-book table (for last7Days) shows the book with 0s in-window.
        #expect(snap.perBook.count == 1)
        #expect(snap.perBook[0].readingSecondsInWindow == 0)
    }

    @Test func sessionCrossingMidnightBucketsByStartedAt() async throws {
        let container = try makeContainer()
        let fp = fingerprint("d")
        try seedBook(container, fp: fp, title: "Midnight Reader")
        // startedAt 23:50 YESTERDAY (UTC), endedAt 00:30 today. Now is 14:30 today.
        let cal = Self.utcCalendar()
        let todayMidnight = cal.startOfDay(for: Self.now)
        let startedAt = todayMidnight.addingTimeInterval(-10 * 60)  // 23:50 yesterday
        let endedAt = todayMidnight.addingTimeInterval(30 * 60)     // 00:30 today
        try seedSession(container, book: fp, startedAt: startedAt,
                        durationSeconds: 2400, endedAt: endedAt)

        let snap = try await aggregator(container).snapshot(
            window: .today, sort: .default, now: Self.now
        )
        // startedAt is yesterday → NOT in today (today = local-midnight..<now).
        #expect(snap.total(for: .today).totalSeconds == 0)
        // But within 7d.
        #expect(snap.total(for: .last7Days).totalSeconds == 2400)
    }

    // MARK: - Zero-session live book (edge case a — Codex WI-2 audit finding)

    @Test func liveBookWithNoSessionsStillShownAsZeroRow() async throws {
        let container = try makeContainer()
        let fp = fingerprint("zero")
        // A live Book row but ZERO ReadingSession rows.
        try seedBook(container, fp: fp, title: "Unread Book")

        let snap = try await aggregator(container).snapshot(
            window: .allTime, sort: .default, now: Self.now
        )
        // Plan edge case (a): the book is still shown, with 0m.
        #expect(snap.perBook.count == 1)
        let row = snap.perBook[0]
        #expect(row.title == "Unread Book")
        #expect(row.isDeleted == false)
        #expect(row.readingSecondsInWindow == 0)
        #expect(row.lastReadAt == nil)
    }

    @Test func liveBookHighlightAndNoteCountsMatchRelationships() async throws {
        let container = try makeContainer()
        let fp = fingerprint("annotated")
        try seedBook(container, fp: fp, title: "Annotated Book")
        try seedAnnotations(container, fp: fp, highlights: 3, notes: 2)
        try seedSession(container, book: fp,
                        startedAt: Self.now.addingTimeInterval(-3600), durationSeconds: 120)

        let snap = try await aggregator(container).snapshot(
            window: .allTime, sort: .default, now: Self.now
        )
        #expect(snap.perBook.count == 1)
        let row = snap.perBook[0]
        #expect(row.highlightsCount == 3)
        #expect(row.notesCount == 2)
        #expect(row.readingSecondsInWindow == 120)
    }

    // MARK: - Deleted book

    @Test func bookDeletedSessionsRemainShowsDeletedRowWithZeroCounts() async throws {
        let container = try makeContainer()
        let fp = fingerprint("e")
        // Seed a session but NO Book row (the post-restore scenario).
        try seedSession(container, book: fp,
                        startedAt: Self.now.addingTimeInterval(-1800), durationSeconds: 900)

        let snap = try await aggregator(container).snapshot(
            window: .allTime, sort: .default, now: Self.now
        )
        #expect(snap.perBook.count == 1)
        let row = snap.perBook[0]
        #expect(row.isDeleted == true)
        #expect(row.title == "(deleted)")
        #expect(row.readingSecondsInWindow == 900)
        // Highlights/notes cascade-deleted with the Book → counts are 0.
        #expect(row.notesCount == 0)
        #expect(row.highlightsCount == 0)
    }

    // MARK: - Per-window table

    @Test func perBookTableReflectsTheRequestedWindow() async throws {
        let container = try makeContainer()
        let fp = fingerprint("f")
        try seedBook(container, fp: fp, title: "Window Book")
        // One session today (1h ago, 100s), one 20 days ago (200s).
        try seedSession(container, book: fp,
                        startedAt: Self.now.addingTimeInterval(-3600), durationSeconds: 100)
        try seedSession(container, book: fp,
                        startedAt: Self.now.addingTimeInterval(-20 * 86_400), durationSeconds: 200)

        let todaySnap = try await aggregator(container).snapshot(
            window: .today, sort: .default, now: Self.now
        )
        let monthSnap = try await aggregator(container).snapshot(
            window: .last30Days, sort: .default, now: Self.now
        )
        // today's per-book row counts only the 100s session.
        #expect(todaySnap.perBook[0].readingSecondsInWindow == 100)
        // last30Days counts both → 300s.
        #expect(monthSnap.perBook[0].readingSecondsInWindow == 300)
    }

    // MARK: - Corrupt / edge data

    @Test func negativeDurationIsClampedToZero() async throws {
        let container = try makeContainer()
        let fp = fingerprint("g")
        try seedBook(container, fp: fp, title: "Corrupt Book")
        // ReadingSession clamps negatives at the model level — verify the
        // aggregator's total reflects the clamped value (0), not a negative.
        try seedSession(container, book: fp,
                        startedAt: Self.now.addingTimeInterval(-600), durationSeconds: -999)

        let snap = try await aggregator(container).snapshot(
            window: .today, sort: .default, now: Self.now
        )
        #expect(snap.total(for: .today).totalSeconds == 0)
        #expect(snap.lifetimeTotalSeconds == 0)
    }

    @Test func trackingSinceIsEarliestSessionStart() async throws {
        let container = try makeContainer()
        let fp = fingerprint("h")
        try seedBook(container, fp: fp, title: "Tracked Book")
        let oldest = Self.now.addingTimeInterval(-100 * 86_400)
        try seedSession(container, book: fp, startedAt: oldest, durationSeconds: 60)
        try seedSession(container, book: fp,
                        startedAt: Self.now.addingTimeInterval(-3600), durationSeconds: 60)

        let snap = try await aggregator(container).snapshot(
            window: .allTime, sort: .default, now: Self.now
        )
        #expect(snap.trackingSince == oldest)
    }

    // MARK: - Consistency

    @Test func perBookAllTimeSumEqualsAllTimeWindowTotal() async throws {
        let container = try makeContainer()
        let fpA = fingerprint("i"); let fpB = fingerprint("j")
        try seedBook(container, fp: fpA, title: "Alpha")
        try seedBook(container, fp: fpB, title: "Bravo")
        try seedSession(container, book: fpA,
                        startedAt: Self.now.addingTimeInterval(-3600), durationSeconds: 111)
        try seedSession(container, book: fpA,
                        startedAt: Self.now.addingTimeInterval(-7200), durationSeconds: 222)
        try seedSession(container, book: fpB,
                        startedAt: Self.now.addingTimeInterval(-1800), durationSeconds: 333)

        let snap = try await aggregator(container).snapshot(
            window: .allTime, sort: .default, now: Self.now
        )
        // The single-ModelContext-pass invariant: sum of per-book in-window
        // seconds == the allTime window total.
        let perBookSum = snap.perBook.reduce(0) { $0 + $1.readingSecondsInWindow }
        #expect(perBookSum == snap.total(for: .allTime).totalSeconds)
        #expect(perBookSum == 666)
    }

    @Test func thousandSessionsAggregateCorrectly() async throws {
        let container = try makeContainer()
        let fp = fingerprint("k")
        try seedBook(container, fp: fp, title: "Long History")
        let context = ModelContext(container)
        for i in 0..<1000 {
            // All within the last 365 days, 60s each.
            let started = Self.now.addingTimeInterval(-Double(i % 300) * 86_400 - 3600)
            context.insert(ReadingSession(
                bookFingerprint: fp, startedAt: started, durationSeconds: 60
            ))
        }
        try context.save()

        let snap = try await aggregator(container).snapshot(
            window: .last365Days, sort: .default, now: Self.now
        )
        // 1000 sessions × 60s, all within 365d.
        #expect(snap.total(for: .last365Days).totalSeconds == 60_000)
        #expect(snap.total(for: .last365Days).sessionCount == 1000)
        #expect(snap.lifetimeTotalSeconds == 60_000)
    }

    @Test func sortIsAppliedToPerBookTable() async throws {
        let container = try makeContainer()
        let fpA = fingerprint("l"); let fpB = fingerprint("m")
        try seedBook(container, fp: fpA, title: "Zeta")     // less reading
        try seedBook(container, fp: fpB, title: "Aardvark") // more reading
        try seedSession(container, book: fpA,
                        startedAt: Self.now.addingTimeInterval(-3600), durationSeconds: 100)
        try seedSession(container, book: fpB,
                        startedAt: Self.now.addingTimeInterval(-3600), durationSeconds: 500)

        // readingTime desc → Aardvark (500) first.
        let byTime = try await aggregator(container).snapshot(
            window: .allTime,
            sort: ReadingDashboardSort(field: .readingTime, ascending: false), now: Self.now
        )
        #expect(byTime.perBook.map(\.title) == ["Aardvark", "Zeta"])

        // title asc → Aardvark first (alphabetical).
        let byTitle = try await aggregator(container).snapshot(
            window: .allTime,
            sort: ReadingDashboardSort(field: .title, ascending: true), now: Self.now
        )
        #expect(byTitle.perBook.map(\.title) == ["Aardvark", "Zeta"])
    }
}
