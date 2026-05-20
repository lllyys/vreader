// Purpose: Composition tests for StatsPerBookTable — the design's
// sortable per-book breakdown table (`SortablePerBookTable` in
// `vreader-profile-stats.jsx`). Feature #58 WI-6a.
//
// COMPOSITION assertions, not pixel snapshots: the table renders the 4
// designed columns (Book / Time / Hl / Notes), header taps toggle sort
// direction or switch the active column, and the rows expose their
// fingerprint key for sort-output verification.
//
// Per the D3-B resolution (GH #665 2026-05-20), the 5th `last-read`
// column is DEFERRED to WI-6c (blocked on GH #1059 needs-design). The
// table therefore exposes 4 columns only.

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
        highlights: Int = 0, notes: Int = 0
    ) -> PerBookStatsRow {
        PerBookStatsRow(
            id: key, bookFingerprintKey: key, title: title, isDeleted: false,
            readingSecondsInWindow: seconds, notesCount: notes,
            highlightsCount: highlights, lastReadAt: nil
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

    // MARK: - Column set (D3-B: ship the design's 4 columns; last-read deferred)

    /// The table exposes exactly the 4 designed columns. `last-read` is
    /// deferred to WI-6c (GH #1059 needs-design).
    @Test func exposesTheFourDesignedColumns() {
        let table = makeTable()
        let fields = table.sortableFieldsForTesting
        #expect(fields == [.title, .readingTime, .highlights, .notes])
    }

    @Test func columnHeaderLabelsMatchTheDesign() {
        // Pinned to `vreader-profile-stats.jsx` SortablePerBookTable:
        //   Book / Time / Hl / Notes
        #expect(StatsPerBookTable.headerLabel(for: .title) == "Book")
        #expect(StatsPerBookTable.headerLabel(for: .readingTime) == "Time")
        #expect(StatsPerBookTable.headerLabel(for: .highlights) == "Hl")
        #expect(StatsPerBookTable.headerLabel(for: .notes) == "Notes")
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
