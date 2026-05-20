// Purpose: Feature #58 WI-6a — the design's sortable per-book table
// (`SortablePerBookTable` in `vreader-profile-stats.jsx`).
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-profile-stats.jsx` (`SortablePerBookTable`).
//
// Key decisions:
// - **4 sortable columns: Book / Time / Hl / Notes.** The design's
//   `SortablePerBookTable` renders these 4 columns; per the D3-B
//   resolution (GH #665 2026-05-20) a 5th `last-read` column is
//   DEFERRED to WI-6c (blocked on GH #1059 needs-design).
// - **No internal sort state — the VM owns the sort.** The table
//   renders the rows in the order it was given. Tapping a header
//   invokes `onSort` with the new desired sort; the VM persists it via
//   `PreferenceStoring` and asks the aggregator to re-sort. The table
//   never reorders rows on its own.
// - **Toggle semantics**: tapping the active column flips
//   `ascending`; tapping an inactive column sets it active in `desc`
//   (the design's default direction).
// - **Composition seams** (`sortableFieldsForTesting`, `rowsForTesting`,
//   `headerTapForTesting`, plus the static `headerLabel(for:)`) expose
//   the render contract for unit tests.
//
// @coordinates-with: ReadingDashboardView.swift, ReadingStatsModels.swift,
//   ReadingTimeFormatter.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx`

import SwiftUI

/// The design's sortable per-book table.
struct StatsPerBookTable: View {

    private let theme: ReaderThemeV2
    private let rows: [PerBookStatsRow]
    private let sort: ReadingDashboardSort
    private let onSort: (ReadingDashboardSort) -> Void

    init(
        theme: ReaderThemeV2,
        rows: [PerBookStatsRow],
        sort: ReadingDashboardSort,
        onSort: @escaping (ReadingDashboardSort) -> Void
    ) {
        self.theme = theme
        self.rows = rows
        self.sort = sort
        self.onSort = onSort
    }

    // MARK: - Sortable fields (D3-B: 4 columns — last-read deferred to WI-6c)

    /// The 4 designed columns, in render order.
    static let sortableFields: [ReadingDashboardSortField] = [
        .title, .readingTime, .highlights, .notes
    ]

    /// The header label for each column, pinned to the JSX design.
    static func headerLabel(for field: ReadingDashboardSortField) -> String {
        switch field {
        case .title:       return "Book"
        case .readingTime: return "Time"
        case .highlights:  return "Hl"
        case .notes:       return "Notes"
        }
    }

    // MARK: - Testing seams

    var sortableFieldsForTesting: [ReadingDashboardSortField] {
        Self.sortableFields
    }

    var rowsForTesting: [PerBookStatsRow] { rows }

    /// Simulate a header tap — re-computes the new sort and invokes `onSort`.
    func headerTapForTesting(_ field: ReadingDashboardSortField) {
        onSort(nextSort(after: field))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(height: 0.5)
            ForEach(rows) { row in
                bodyRow(row)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                Rectangle()
                    .fill(Color(theme.ruleColor).opacity(0.5))
                    .frame(height: 0.5)
            }
        }
        .accessibilityIdentifier("statsPerBookTable")
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 12) {
            headerButton(.title, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerButton(.readingTime, alignment: .trailing)
                .frame(width: 68, alignment: .trailing)
            headerButton(.highlights, alignment: .trailing)
                .frame(width: 44, alignment: .trailing)
            headerButton(.notes, alignment: .trailing)
                .frame(width: 56, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func headerButton(
        _ field: ReadingDashboardSortField,
        alignment: HorizontalAlignment
    ) -> some View {
        let active = sort.field == field
        Button {
            onSort(nextSort(after: field))
        } label: {
            HStack(spacing: 3) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(Self.headerLabel(for: field).uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(active
                        ? Color(theme.inkColor)
                        : Color(theme.subColor))
                if active {
                    Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(active
                            ? Color(theme.inkColor)
                            : Color(theme.subColor))
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("statsPerBookHeader-\(field.rawValue)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - Row

    @ViewBuilder
    private func bodyRow(_ row: PerBookStatsRow) -> some View {
        HStack(spacing: 12) {
            Text(row.title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(theme.inkColor))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ReadingTimeFormatter.formatDuration(totalSeconds: row.readingSecondsInWindow))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(theme.inkColor))
                .frame(width: 68, alignment: .trailing)
                .accessibilityIdentifier("statsPerBookTime-\(row.bookFingerprintKey)")
            Text("\(row.highlightsCount)")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 44, alignment: .trailing)
                .accessibilityIdentifier("statsPerBookHl-\(row.bookFingerprintKey)")
            Text("\(row.notesCount)")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 56, alignment: .trailing)
                .accessibilityIdentifier("statsPerBookNotes-\(row.bookFingerprintKey)")
        }
        .accessibilityIdentifier("statsPerBookRow-\(row.bookFingerprintKey)")
    }

    // MARK: - Sort math

    /// Produce the new sort after tapping the header for `field`.
    /// - Tapping the active column flips `ascending`.
    /// - Tapping an inactive column makes it active in `desc`.
    private func nextSort(after field: ReadingDashboardSortField) -> ReadingDashboardSort {
        if sort.field == field {
            return ReadingDashboardSort(field: field, ascending: !sort.ascending)
        } else {
            return ReadingDashboardSort(field: field, ascending: false)
        }
    }
}
