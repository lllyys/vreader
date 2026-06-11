// Purpose: Feature #101 — the once-at-open per-book stats seam the reader
// lifecycle uses to build the combined time readout. Production is
// `PersistenceActor`; tests inject a stub. Kept to ONE read so the reader
// never queries SwiftData per tick (the live total is arithmetic).
//
// @coordinates-with: ReaderLifecycleHelper.swift,
//   PersistenceActor+Stats.swift, ReadingStatsModels.swift

import Foundation

/// Supplies a book's persisted reading-stats record (total seconds +
/// session count drive the in-reader time readout).
protocol BookReadingStatsProviding: Sendable {
    func readingStats(forBookWithKey key: String) async throws -> ReadingStatsRecord?
}
