// Purpose: Composition tests for StatsPerBookTable — the design's
// sortable per-book breakdown table (`SortablePerBookTable` in
// `vreader-profile-stats.jsx`). Feature #58 WI-6a.
//
// COMPOSITION assertions, not pixel snapshots: the table renders the 4
// designed columns (Book / Time / Hl / Notes), header taps toggle sort
// direction or switch the active column, and the rows expose their
// fingerprint key for sort-output verification.
//
// WI-6c adds the 5th `Last read` column (Alt-1 variant from
// `stats-followups-artboards.jsx`'s `PerBookTableAllFive`) — sortable
// header-tap pattern matching the existing 4 columns. Nil cells render
// as "—" and sink to the bottom of any lastRead sort.

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("StatsPerBookTable composition — feature #58 WI-6a")
@MainActor
struct StatsPerBookTableTests {

    // MARK: - Fixtures

    private func row(
        _ key: String, title: String, seconds: Int,
        highlights: Int = 0, notes: Int = 0,
        lastRead: Date? = nil
    ) -> PerBookStatsRow {
        PerBookStatsRow(
            id: key, bookFingerprintKey: key, title: title, isDeleted: false,
            readingSecondsInWindow: seconds, notesCount: notes,
            highlightsCount: highlights, lastReadAt: lastRead
        )
    }

    private var sampleRows: [PerBookStatsRow] {
        [
            row("pp",   title: "Pride and Prejudice", seconds: 738 * 60, highlights: 47, notes: 18),
            row("bi",   title: "Brief Interviews",     seconds: 587 * 60, highlights: 22, notes: 11),
            row("prag", title: "Pragmatist",           seconds: 332 * 60, highlights: 12, notes:  7)
        ]
    }

    private func makeTable(
        rows: [PerBookStatsRow]? = nil,
        sort: ReadingDashboardSort = .default,
        theme: ReaderThemeV2 = .paper,
        onSort: @escaping (ReadingDashboardSort) -> Void = { _ in }
    ) -> StatsPerBookTable {
        StatsPerBookTable(
            theme: theme,
            rows: rows ?? sampleRows,
            sort: sort,
            onSort: onSort
        )
    }

    // MARK: - Builds

    @Test func buildsForEveryReaderTheme() {
        for theme in ReaderThemeV2.allCases {
            let table = makeTable(theme: theme)
            _ = table.body
        }
    }

    // MARK: - Column set (WI-6c — 5 columns including last-read)

    /// The table exposes the 5 sortable columns in render order: the
    /// 4 originally-designed columns plus the WI-6c `lastRead` 5th column
    /// (`PerBookTableAllFive` variant from `stats-followups-artboards.jsx`).
    @Test func exposesTheFiveSortableColumns() {
        let table = makeTable()
        let fields = table.sortableFieldsForTesting
        #expect(fields == [.title, .readingTime, .highlights, .notes, .lastRead])
    }

    @Test func columnHeaderLabelsMatchTheDesign() {
        // Pinned to `vreader-profile-stats.jsx` SortablePerBookTable + the
        // `stats-followups-artboards.jsx` PerBookTableAllFive Read column.
        #expect(StatsPerBookTable.headerLabel(for: .title) == "Book")
        #expect(StatsPerBookTable.headerLabel(for: .readingTime) == "Time")
        #expect(StatsPerBookTable.headerLabel(for: .highlights) == "Hl")
        #expect(StatsPerBookTable.headerLabel(for: .notes) == "Notes")
        #expect(StatsPerBookTable.headerLabel(for: .lastRead) == "Read")
    }

    /// Tapping the new `Read` header for an inactive column makes it active
    /// in `desc` — same toggle semantics as the other 4 columns.
    @Test func tappingLastReadHeaderActivatesItDescending() {
        var observed: ReadingDashboardSort?
        let table = makeTable(
            sort: ReadingDashboardSort(field: .readingTime, ascending: false),
            onSort: { observed = $0 }
        )
        table.headerTapForTesting(.lastRead)
        #expect(observed == ReadingDashboardSort(field: .lastRead, ascending: false))
    }

    /// Re-tapping the active `Read` header flips direction — symmetric with
    /// the other 4 columns' toggle behaviour.
    @Test func togglingActiveLastReadColumnFlipsDirection() {
        var observed: ReadingDashboardSort?
        let table = makeTable(
            sort: ReadingDashboardSort(field: .lastRead, ascending: false),
            onSort: { observed = $0 }
        )
        table.headerTapForTesting(.lastRead)
        #expect(observed == ReadingDashboardSort(field: .lastRead, ascending: true))
    }

    /// Body builds cleanly when the rows carry mixed nil + non-nil
    /// `lastReadAt` — the 5th column must render "—" for nil cells
    /// without crashing the view.
    @Test func bodyBuildsWithMixedLastReadValues() {
        let mixedRows = [
            row("pp",   title: "Pride and Prejudice", seconds: 738 * 60, lastRead: Date(timeIntervalSince1970: 1_700_000_000)),
            row("ghost", title: "Ghost Book", seconds: 0, lastRead: nil),
        ]
        let table = makeTable(rows: mixedRows)
        _ = table.body
        #expect(table.rowsForTesting.count == 2)
    }

    // MARK: - Sort header tap behaviour

    /// Tapping a header for an inactive column makes it active in `desc`
    /// (the design's default direction).
    @Test func tappingInactiveColumnSetsItDescending() {
        var observed: ReadingDashboardSort?
        let table = makeTable(
            sort: ReadingDashboardSort(field: .readingTime, ascending: false),
            onSort: { observed = $0 }
        )
        table.headerTapForTesting(.notes)
        #expect(observed == ReadingDashboardSort(field: .notes, ascending: false))
    }

    /// Tapping the active column toggles the direction.
    @Test func tappingActiveColumnTogglesDirection() {
        var observed: ReadingDashboardSort?
        let table = makeTable(
            sort: ReadingDashboardSort(field: .readingTime, ascending: false),
            onSort: { observed = $0 }
        )
        table.headerTapForTesting(.readingTime)
        #expect(observed == ReadingDashboardSort(field: .readingTime, ascending: true))
    }

    @Test func togglingTwiceReturnsToOriginalDirection() {
        var observed: ReadingDashboardSort?
        let table = makeTable(
            sort: ReadingDashboardSort(field: .readingTime, ascending: false),
            onSort: { observed = $0 }
        )
        table.headerTapForTesting(.readingTime)
        // Re-create with the observed sort to simulate the new state.
        let next = makeTable(
            sort: observed!,
            onSort: { observed = $0 }
        )
        next.headerTapForTesting(.readingTime)
        #expect(observed == ReadingDashboardSort(field: .readingTime, ascending: false))
    }

    // MARK: - Row rendering

    @Test func rendersOneRowPerInputRow() {
        let table = makeTable()
        #expect(table.rowsForTesting.count == sampleRows.count)
    }

    @Test func rowsRenderInTheProvidedOrder() {
        // The table does NOT re-sort; the VM has already sorted via
        // ReadingStatsAggregator. The view renders the order it was given.
        let table = makeTable(rows: sampleRows.reversed())
        #expect(
            table.rowsForTesting.map(\.bookFingerprintKey) ==
            sampleRows.reversed().map(\.bookFingerprintKey)
        )
    }

    @Test func emptyRowSetBuilds() {
        let table = makeTable(rows: [])
        _ = table.body
        #expect(table.rowsForTesting.isEmpty)
    }
}
