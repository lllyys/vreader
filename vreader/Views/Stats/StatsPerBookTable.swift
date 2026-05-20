// Purpose: Feature #58 WI-6a/WI-6c — the design's sortable per-book table
// (`SortablePerBookTable` in `vreader-profile-stats.jsx`, extended in
// WI-6c with the 5th `Last read` column per the design follow-up at
// `stats-followups-artboards.jsx`'s `PerBookTableAllFive` variant).
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-profile-stats.jsx` (`SortablePerBookTable`) +
// `stats-followups-artboards.jsx` (`PerBookTableAllFive` for the `Read`
// column treatment + nil-to-bottom sort rule).
//
// Key decisions:
// - **5 sortable columns: Book / Time / Hl / Notes / Read.** WI-6c added
//   the 5th `Read` (last-read) column once the design follow-up landed in
//   PR #1060 (GH #1059 D3-B resolution). The Alt-1 always-5-columns
//   variant was chosen over the canonical sort-menu variant because
//   the existing 4 columns already use header-tap sorting; threading
//   a separate sort-menu surface would have been a larger redesign
//   than the brief allowed.
// - **No internal sort state — the VM owns the sort.** The table
//   renders the rows in the order it was given. Tapping a header
//   invokes `onSort` with the new desired sort; the VM persists it via
//   `PreferenceStoring` and asks the aggregator to re-sort. The table
//   never reorders rows on its own.
// - **Toggle semantics**: tapping the active column flips
//   `ascending`; tapping an inactive column sets it active in `desc`
//   (the design's default direction).
// - **Nil last-read rendering**: a row with `lastReadAt == nil` renders
//   the `Read` cell as `—` (the design's empty marker for books with
//   no recorded sessions). The sort comparator sinks these rows to the
//   bottom regardless of direction.
// - **Composition seams** (`sortableFieldsForTesting`, `rowsForTesting`,
//   `headerTapForTesting`, plus the static `headerLabel(for:)`) expose
//   the render contract for unit tests.
//
// @coordinates-with: ReadingDashboardView.swift, ReadingStatsModels.swift,
//   ReadingTimeFormatter.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx`,
//   `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`

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

    // MARK: - Sortable fields (WI-6c — 5 columns including last-read)

    /// The 5 designed columns, in render order.
    static let sortableFields: [ReadingDashboardSortField] = [
        .title, .readingTime, .highlights, .notes, .lastRead
    ]

    /// The header label for each column, pinned to the JSX design.
    /// `Read` is the WI-6c addition (`stats-followups-artboards.jsx`'s
    /// `PerBookTableAllFive` header).
    static func headerLabel(for field: ReadingDashboardSortField) -> String {
        switch field {
        case .title:       return "Book"
        case .readingTime: return "Time"
        case .highlights:  return "Hl"
        case .notes:       return "Notes"
        case .lastRead:    return "Read"
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
        HStack(spacing: 8) {
            headerButton(.title, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerButton(.readingTime, alignment: .trailing)
                .frame(width: 56, alignment: .trailing)
            headerButton(.highlights, alignment: .trailing)
                .frame(width: 32, alignment: .trailing)
            headerButton(.notes, alignment: .trailing)
                .frame(width: 38, alignment: .trailing)
            headerButton(.lastRead, alignment: .trailing)
                .frame(width: 52, alignment: .trailing)
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
        HStack(spacing: 8) {
            Text(row.title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(theme.inkColor))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ReadingTimeFormatter.formatDuration(totalSeconds: row.readingSecondsInWindow))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(theme.inkColor))
                .frame(width: 56, alignment: .trailing)
                .accessibilityIdentifier("statsPerBookTime-\(row.bookFingerprintKey)")
            Text("\(row.highlightsCount)")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 32, alignment: .trailing)
                .accessibilityIdentifier("statsPerBookHl-\(row.bookFingerprintKey)")
            Text("\(row.notesCount)")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 38, alignment: .trailing)
                .accessibilityIdentifier("statsPerBookNotes-\(row.bookFingerprintKey)")
            Text(Self.lastReadCellText(for: row.lastReadAt))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(row.lastReadAt == nil ? theme.subColor : theme.inkColor))
                .lineLimit(1)
                .frame(width: 52, alignment: .trailing)
                .accessibilityIdentifier("statsPerBookLastRead-\(row.bookFingerprintKey)")
        }
        .accessibilityIdentifier("statsPerBookRow-\(row.bookFingerprintKey)")
    }

    /// Compact cell text for the `Last read` column — pinned to the design's
    /// Alt-1 `PerBookTableAllFive` row tokens (`stats-followups-artboards.jsx`,
    /// `ROWS_WITH_LASTREAD`): `2h`, `1d`, `3d`, `5w`, `8mo`, `2y`. Nil renders
    /// as the empty marker `—`.
    ///
    /// Distinct from `ReadingTimeFormatter.formatRelativeLastRead` (which
    /// produces verbose Library-row strings like "Just now", "Yesterday",
    /// "12m ago") because the Alt-1 column is borderline-narrow at 402pt and
    /// breaks at sub-360pt widths (design note in `stats-followups-artboards.jsx`).
    /// Bucket boundaries match the Library formatter exactly so the two
    /// surfaces stay in sync; only the rendering is shortened.
    static func lastReadCellText(for date: Date?, relativeTo now: Date = Date()) -> String {
        guard let date else { return "—" }
        let elapsed = now.timeIntervalSince(date)
        // A future timestamp (clock skew between the position write and the
        // render) is the same case the Library formatter treats as "Just now";
        // here we shorten it to "0m" so the cell always fits.
        if elapsed < 60 { return "0m" }

        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)m" }

        let hours = Int(elapsed / 3_600)
        if hours < 24 { return "\(hours)h" }

        let days = Int(elapsed / 86_400)
        if days < 7 { return "\(days)d" }

        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }

        // Year boundary keyed on actual days, NOT `months >= 12` —
        // `days / 30` for the 360..364d range floors to 12 even though
        // `days / 365` floors to 0, producing the spurious "0y" token
        // Codex Gate-4 round-2 flagged. Gate the year branch on the
        // raw day count instead, so 360..364d stays in the months
        // bucket and only ≥365d emits a "Ny" token.
        if days < 365 {
            return "\(days / 30)mo"
        }
        return "\(days / 365)y"
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
