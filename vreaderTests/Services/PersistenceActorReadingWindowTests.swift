// Purpose: Tests for PersistenceActor's reading-window reads added in
// feature #67 WI-1 — `sumReadingSeconds(in:)` and `countLibraryBooks()`,
// the two queries behind the `LibraryStatsReading` boundary.

import Foundation
import SwiftData
import Testing
@testable import vreader

@Suite("PersistenceActor reading-window reads")
struct PersistenceActorReadingWindowTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func fingerprint(_ seed: String) -> DocumentFingerprint {
        var hex = ""
        let bytes = Array(seed.utf8)
        var i = 0
        while hex.count < 64 {
            hex += String(format: "%02x", bytes[i % bytes.count] &+ UInt8(i))
            i += 1
        }
        return DocumentFingerprint(
            contentSHA256: String(hex.prefix(64)), fileByteCount: 4096, format: .epub
        )
    }

    /// A bounded interval used by the sum tests — [2026-05-01, 2026-06-01) in
    /// absolute time (one calendar month at UTC).
    private var mayInterval: DateInterval {
        DateInterval(
            start: Date(timeIntervalSince1970: 1_777_651_200), // 2026-05-01 00:00 UTC
            end: Date(timeIntervalSince1970: 1_780_329_600)    // 2026-06-01 00:00 UTC
        )
    }

    private func makeBook(_ seed: String) -> Book {
        Book(
            fingerprint: fingerprint(seed),
            title: "Book \(seed)",
            provenance: ImportProvenance(
                source: .filesApp, importedAt: Date(), originalURLBookmarkData: nil
            )
        )
    }

    // MARK: - sumReadingSeconds(in:)

    @Test func sumReadingSecondsEmptyStoreReturnsZero() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let total = try await actor.sumReadingSeconds(in: mayInterval)
        #expect(total == 0)
    }

    @Test func sumReadingSecondsSumsSessionsInsideTheInterval() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Three sessions whose startedAt falls inside May 2026.
        for (i, duration) in [600, 1200, 300].enumerated() {
            context.insert(ReadingSession(
                bookFingerprint: fingerprint("inside\(i)"),
                startedAt: Date(timeIntervalSince1970: 1_777_651_200 + Double(i) * 86_400),
                durationSeconds: duration
            ))
        }
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let total = try await actor.sumReadingSeconds(in: mayInterval)
        #expect(total == 600 + 1200 + 300)
    }

    @Test func sumReadingSecondsExcludesSessionsOutsideTheInterval() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Inside May.
        context.insert(ReadingSession(
            bookFingerprint: fingerprint("in"),
            startedAt: Date(timeIntervalSince1970: 1_777_651_200 + 86_400),
            durationSeconds: 500
        ))
        // Before May (April).
        context.insert(ReadingSession(
            bookFingerprint: fingerprint("before"),
            startedAt: Date(timeIntervalSince1970: 1_777_651_200 - 86_400),
            durationSeconds: 999
        ))
        // After May (June).
        context.insert(ReadingSession(
            bookFingerprint: fingerprint("after"),
            startedAt: Date(timeIntervalSince1970: 1_780_329_600 + 86_400),
            durationSeconds: 888
        ))
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let total = try await actor.sumReadingSeconds(in: mayInterval)
        #expect(total == 500)
    }

    @Test func sumReadingSecondsBoundarySessionsCountedByStartedAt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // startedAt exactly at the interval start → included.
        context.insert(ReadingSession(
            bookFingerprint: fingerprint("start"),
            startedAt: mayInterval.start,
            durationSeconds: 111
        ))
        // startedAt exactly at the (exclusive) interval end → excluded.
        context.insert(ReadingSession(
            bookFingerprint: fingerprint("end"),
            startedAt: mayInterval.end,
            durationSeconds: 222
        ))
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let total = try await actor.sumReadingSeconds(in: mayInterval)
        #expect(total == 111)
    }

    @Test func sumReadingSecondsOverLargeHistoryDoesNotOverflow() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // 1,200 sessions, each near Int.max / 1200 would overflow a naive Int
        // sum — use a large-but-safe per-session value so the running total
        // exceeds Int32 range and exercises the Int64 accumulation.
        let perSession = 2_000_000
        for i in 0..<1_200 {
            context.insert(ReadingSession(
                bookFingerprint: fingerprint("bulk\(i)"),
                startedAt: Date(timeIntervalSince1970: 1_777_651_200 + Double(i % 28) * 86_400),
                durationSeconds: perSession
            ))
        }
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let total = try await actor.sumReadingSeconds(in: mayInterval)
        #expect(total == 1_200 * perSession)
    }

    // MARK: - countLibraryBooks()

    @Test func countLibraryBooksEmptyStoreReturnsZero() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let count = try await actor.countLibraryBooks()
        #expect(count == 0)
    }

    @Test func countLibraryBooksReturnsSeededRowCount() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        for i in 0..<7 {
            context.insert(makeBook("book\(i)"))
        }
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let count = try await actor.countLibraryBooks()
        #expect(count == 7)
    }
}
