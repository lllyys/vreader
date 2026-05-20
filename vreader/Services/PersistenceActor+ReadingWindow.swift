// Purpose: Extension adding the two windowed reads behind the
// `LibraryStatsReading` boundary (feature #67 WI-1) — a calendar-window
// reading-seconds sum and a library book count. Reused later by the
// feature #58 dashboard; introduced here minimally for the Settings
// profile card.
//
// Key decisions:
// - `sumReadingSeconds(in:)` filters `ReadingSession` rows store-side
//   with a `#Predicate` on the stored `startedAt` `Date` — SwiftData
//   evaluates the predicate in the store, so a long history is not
//   materialized into memory just to be summed.
// - The interval is half-open: `startedAt >= start && startedAt < end`.
//   A session whose `startedAt` equals the exclusive `end` belongs to
//   the next window.
// - The sum accumulates in `Int64` and clamps each `durationSeconds`
//   to `>= 0` — defensive, matching `ReadingStats.recompute`. (A
//   negative `durationSeconds` is not constructible through
//   `ReadingSession`'s clamping `init`/`updateDuration`, so the clamp
//   is belt-and-suspenders, not a tested corruption path.)
// - `countLibraryBooks()` resolves a `FetchDescriptor<Book>` via
//   `ModelContext.fetchCount(_:)`, so it returns the count without
//   materializing `Book` rows — unlike `fetchAllLibraryBooks()`, which
//   builds a `LibraryBookItem` per row.
// - Each method opens its own `ModelContext(modelContainer)` — the
//   established `PersistenceActor+Stats` pattern. Methods run on the
//   `PersistenceActor` actor (the conformance below makes the actor a
//   `LibraryStatsReading`).
//
// @coordinates-with: PersistenceActor.swift, LibraryStatsReading.swift,
//   ReadingSession.swift, Book.swift

import Foundation
import SwiftData

extension PersistenceActor: LibraryStatsReading {

    /// Sums `durationSeconds` over every `ReadingSession` whose
    /// `startedAt` falls within `interval` (`[start, end)`).
    ///
    /// The `#Predicate` filters at the store, so only the in-window rows
    /// are fetched. The running total uses `Int64` and clamps each
    /// duration to `>= 0`; the result is narrowed back to `Int`.
    func sumReadingSeconds(in interval: DateInterval) async throws -> Int {
        let context = ModelContext(modelContainer)
        let start = interval.start
        let end = interval.end
        let predicate = #Predicate<ReadingSession> { session in
            session.startedAt >= start && session.startedAt < end
        }
        let sessions = try context.fetch(
            FetchDescriptor<ReadingSession>(predicate: predicate)
        )
        var total: Int64 = 0
        for session in sessions {
            total += Int64(max(0, session.durationSeconds))
        }
        // Clamp to Int's range — a sum that genuinely exceeds Int.max
        // (≈292 billion years of reading) is not reachable, but the
        // narrowing is made explicit rather than trapping.
        return Int(min(total, Int64(Int.max)))
    }

    /// The number of `Book` rows in the library.
    ///
    /// Resolved with `fetchCount(_:)` so no `Book` row is materialized.
    func countLibraryBooks() async throws -> Int {
        let context = ModelContext(modelContainer)
        return try context.fetchCount(FetchDescriptor<Book>())
    }
}
