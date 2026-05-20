// Purpose: Value types for the reading-stats dashboard (feature #58).
//
// All types here are pure value types — no SwiftData, no @MainActor. They are
// the DTOs that cross the ReadingStatsAggregator actor boundary and the inputs
// the ReadingDashboardViewModel renders.
//
// Key decisions:
// - No new SwiftData @Model — the dashboard is read-only over ReadingSession /
//   ReadingStats; these structs are the value-typed projection of those rows.
// - ReadingStatsWindow.dateInterval resolves the calendar PER CALL (passed in)
//   so a long-lived aggregator picks up a timezone/DST change on the next snapshot.
// - windowTotals is an ARRAY in canonical ReadingStatsWindow.allCases order
//   (a dictionary has nondeterministic iteration; tests need a stable order).
// - The per-book sort comparator is a pure static function so it is unit-tested
//   independently of SwiftData.

import Foundation

// MARK: - Time Window

/// The seven rolling time windows the dashboard aggregates over.
/// Window set is fixed by the feature #58 row contract (divergence D2).
enum ReadingStatsWindow: String, CaseIterable, Identifiable, Sendable {
    case today
    case last7Days
    case last30Days
    case last90Days
    case last180Days
    case last365Days
    case allTime

    var id: String { rawValue }

    /// Short label for the window-selector pill bar.
    var label: String {
        switch self {
        case .today: return "Today"
        case .last7Days: return "7d"
        case .last30Days: return "30d"
        case .last90Days: return "90d"
        case .last180Days: return "180d"
        case .last365Days: return "365d"
        case .allTime: return "All"
        }
    }

    /// Number of rolling days for the `lastNDays` windows; nil for `today`/`allTime`.
    private var rollingDays: Int? {
        switch self {
        case .last7Days: return 7
        case .last30Days: return 30
        case .last90Days: return 90
        case .last180Days: return 180
        case .last365Days: return 365
        case .today, .allTime: return nil
        }
    }

    /// The half-open `[start, now)` interval for this window, in the supplied
    /// calendar/timezone.
    ///
    /// - `today` = local-midnight(now) ..< now.
    /// - the rolling `Nd` windows = (now - N·86400s) ..< now.
    /// - `allTime` returns `nil` (no lower bound — count everything).
    ///
    /// Callers MUST use `contains(_:now:calendar:)` for membership tests rather
    /// than `DateInterval.contains(_:)` — `DateInterval` membership is
    /// end-INCLUSIVE, which would wrongly count a session at exactly `now`.
    func dateInterval(now: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .allTime:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .last7Days, .last30Days, .last90Days, .last180Days, .last365Days:
            guard let days = rollingDays else { return nil }
            let start = now.addingTimeInterval(-Double(days) * 86_400)
            return DateInterval(start: start, end: now)
        }
    }

    /// Half-open `[start, now)` membership test for a session anchor date.
    ///
    /// - `allTime` → always true (no lower bound).
    /// - every other window → `start <= date && date < now`. The end is
    ///   EXCLUSIVE, so a session whose anchor is exactly `now` is NOT counted
    ///   (unlike `DateInterval.contains(_:)`, which is end-inclusive).
    func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let interval = dateInterval(now: now, calendar: calendar) else {
            return true // allTime
        }
        return date >= interval.start && date < interval.end
    }
}

// MARK: - Window Total

/// Aggregate reading total for one window.
struct WindowTotal: Sendable, Equatable {
    let window: ReadingStatsWindow
    let totalSeconds: Int
    let sessionCount: Int
}

// MARK: - Per-Book Row

/// One row of the per-book breakdown table.
struct PerBookStatsRow: Sendable, Equatable, Identifiable {
    /// == bookFingerprintKey.
    let id: String
    let bookFingerprintKey: String
    /// Book title; "(deleted)" when no Book row exists for this key.
    let title: String
    /// True when reading sessions/stats exist but the Book row is gone.
    let isDeleted: Bool
    let readingSecondsInWindow: Int
    /// 0 for a deleted book — its notes were cascade-deleted with the Book.
    let notesCount: Int
    /// 0 for a deleted book — same reason.
    let highlightsCount: Int
    let lastReadAt: Date?
}

extension PerBookStatsRow {
    /// Pure sort comparator for the per-book table. Ties break by title
    /// (case-insensitive ascending) so the order is deterministic regardless
    /// of the requested field.
    static func sorted(_ rows: [PerBookStatsRow], by sort: ReadingDashboardSort) -> [PerBookStatsRow] {
        rows.sorted { lhs, rhs in
            let ordered = compare(lhs, rhs, field: sort.field, ascending: sort.ascending)
            if let ordered { return ordered }
            // Tie-break: title, case-insensitive, always ascending.
            let cmp = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return lhs.bookFingerprintKey < rhs.bookFingerprintKey
        }
    }

    /// Returns true if `lhs` should sort before `rhs` for the given field, or
    /// nil when the two are equal on that field (caller applies the tie-break).
    private static func compare(
        _ lhs: PerBookStatsRow, _ rhs: PerBookStatsRow,
        field: ReadingDashboardSortField, ascending: Bool
    ) -> Bool? {
        switch field {
        case .title:
            let cmp = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if cmp == .orderedSame { return nil }
            return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        case .readingTime:
            if lhs.readingSecondsInWindow == rhs.readingSecondsInWindow { return nil }
            return ascending
                ? lhs.readingSecondsInWindow < rhs.readingSecondsInWindow
                : lhs.readingSecondsInWindow > rhs.readingSecondsInWindow
        case .highlights:
            if lhs.highlightsCount == rhs.highlightsCount { return nil }
            return ascending
                ? lhs.highlightsCount < rhs.highlightsCount
                : lhs.highlightsCount > rhs.highlightsCount
        case .notes:
            if lhs.notesCount == rhs.notesCount { return nil }
            return ascending
                ? lhs.notesCount < rhs.notesCount
                : lhs.notesCount > rhs.notesCount
        case .lastRead:
            // Nil rows sink to the bottom regardless of direction — pinned to
            // `stats-followups-artboards.jsx`'s `PerBookTableV2`:
            //   `if (a.lastReadAt === null && b.lastReadAt !== null) return 1;`
            // A book with no recorded sessions is always last; it never floats
            // to the top of a desc/asc sort by being treated as a very-old or
            // very-new date.
            switch (lhs.lastReadAt, rhs.lastReadAt) {
            case (nil, nil):
                return nil
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (l?, r?):
                if l == r { return nil }
                return ascending ? l < r : l > r
            }
        }
    }
}

// MARK: - Sort

/// The five sortable per-book table columns.
///
/// The first four columns match the committed `SortablePerBookTable` design;
/// `lastRead` is the WI-6c addition (GH #1059 D3-B follow-up, design source
/// `stats-followups-artboards.jsx`'s `PerBookTableAllFive` variant).
enum ReadingDashboardSortField: String, CaseIterable, Sendable, Codable {
    case title
    case readingTime
    case highlights
    case notes
    case lastRead
}

/// The active dashboard sort — a field plus a direction. `Codable` so it can
/// round-trip through `PreferenceStoring` as a compact string.
///
/// The custom inits live in an extension so the compiler still synthesizes
/// both the memberwise init and `Codable` conformance for the struct body.
struct ReadingDashboardSort: Sendable, Equatable, Codable {
    var field: ReadingDashboardSortField
    var ascending: Bool

    static let `default` = ReadingDashboardSort(field: .readingTime, ascending: false)

    /// Compact `"field:dir"` string for `PreferenceStoring` (e.g. "readingTime:desc").
    var storageString: String {
        "\(field.rawValue):\(ascending ? "asc" : "desc")"
    }
}

extension ReadingDashboardSort {
    /// Parses a `storageString`. Returns nil for any malformed input.
    init?(storageString: String) {
        let parts = storageString.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let field = ReadingDashboardSortField(rawValue: String(parts[0]))
        else { return nil }
        switch parts[1] {
        case "asc": self.init(field: field, ascending: true)
        case "desc": self.init(field: field, ascending: false)
        default: return nil
        }
    }
}

// MARK: - Snapshot

/// One immutable dashboard render.
///
/// Carries totals for ALL seven windows (cheap — seven small structs) so a
/// window-pill tap need not re-hit the actor; the per-book table is computed
/// for `activeWindow` only (the table is the expensive part).
///
/// The `windowTotals` invariant — exactly seven entries, one per
/// `ReadingStatsWindow`, in canonical `allCases` order — is enforced BY THE
/// INITIALIZER: the only init normalizes its input (missing window zero-filled,
/// duplicate's first occurrence wins, input order ignored). There is no way to
/// construct a malformed snapshot, so WI-2/WI-4 consumers can rely on the shape.
struct ReadingDashboardSnapshot: Sendable, Equatable {
    /// Exactly seven windows, in canonical `ReadingStatsWindow.allCases` order
    /// — guaranteed by `init`.
    let windowTotals: [WindowTotal]
    let activeWindow: ReadingStatsWindow
    /// Per-book rows for `activeWindow`, already sorted per the requested sort.
    let perBook: [PerBookStatsRow]
    let lifetimeTotalSeconds: Int
    let trackingSince: Date?

    /// The sole initializer. `windowTotals` is NORMALIZED to exactly seven
    /// entries in canonical order regardless of what is passed: a missing
    /// window is zero-filled, a duplicate window keeps its first occurrence,
    /// and input order is discarded. Malformed construction is impossible.
    init(
        windowTotals: [WindowTotal],
        activeWindow: ReadingStatsWindow,
        perBook: [PerBookStatsRow],
        lifetimeTotalSeconds: Int,
        trackingSince: Date?
    ) {
        let byWindow = Dictionary(
            windowTotals.map { ($0.window, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.windowTotals = ReadingStatsWindow.allCases.map { window in
            byWindow[window] ?? WindowTotal(window: window, totalSeconds: 0, sessionCount: 0)
        }
        self.activeWindow = activeWindow
        self.perBook = perBook
        self.lifetimeTotalSeconds = lifetimeTotalSeconds
        self.trackingSince = trackingSince
    }

    /// Total for a window. Always present (the init guarantees all seven).
    func total(for window: ReadingStatsWindow) -> WindowTotal {
        windowTotals.first { $0.window == window }
            ?? WindowTotal(window: window, totalSeconds: 0, sessionCount: 0)
    }
}

// MARK: - Actor-Boundary Records

/// Value-typed projection of a `ReadingSession` @Model row — crosses the
/// PersistenceActor boundary (never return @Model). Used by the WI-5 backup
/// collector. `Codable` for the backup payload.
struct ReadingSessionRecord: Sendable, Equatable, Codable {
    let sessionId: UUID
    /// == DocumentFingerprint.canonicalKey.
    let bookFingerprintKey: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let pagesRead: Int?
    let wordsRead: Int?
    let startLocator: Locator?
    let endLocator: Locator?
    let deviceId: String
    let isRecovered: Bool
}

/// Value-typed projection of a `ReadingStats` @Model row.
struct ReadingStatsRecord: Sendable, Equatable, Codable {
    let bookFingerprintKey: String
    let totalReadingSeconds: Int
    let sessionCount: Int
    let lastReadAt: Date?
    let averagePagesPerHour: Double?
    let averageWordsPerMinute: Double?
    let totalPagesRead: Int?
    let totalWordsRead: Int?
    let longestSessionSeconds: Int
}
