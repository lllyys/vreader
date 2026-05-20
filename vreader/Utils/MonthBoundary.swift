// Purpose: Pure helper computing the current calendar month's
// `DateInterval` — the [month-start, next-month-start) span — in the
// user's time zone. Feeds the Settings profile-card "Nh read this
// month" subline (feature #67).
//
// Key decisions:
// - "This month" means a *calendar* month, not a rolling 30-day window
//   (the design says "this month"; feature #58's aggregator separately
//   offers a deliberate `30d` rolling window — a different thing).
// - The `Calendar` is injectable so the math is deterministic and
//   unit-testable with a fixed time zone; production passes
//   `Calendar.current`.
// - The returned interval's `end` is the first instant of the *next*
//   month, i.e. exclusive — a session whose `startedAt` equals `end`
//   belongs to next month, not this one.
//
// @coordinates-with: SettingsHeaderViewModel.swift,
//   PersistenceActor+ReadingWindow.swift

import Foundation

/// Calendar-month interval math for the Settings profile card.
enum MonthBoundary {

    /// The calendar-month `DateInterval` that contains `date`.
    ///
    /// The interval runs `[first-instant-of-month, first-instant-of-next-month)`
    /// in `calendar`'s time zone. `end` is exclusive.
    ///
    /// - Parameters:
    ///   - date: any instant within the month of interest.
    ///   - calendar: the calendar (and thus time zone) to resolve month
    ///     boundaries in. Defaults to `.current`.
    /// - Returns: the containing calendar month as a positive-width interval.
    static func currentMonth(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        // `dateInterval(of:for:)` returns the calendar-month span containing
        // `date` — start at the month's first instant, duration the full
        // month (DST-aware). It is the canonical Foundation primitive for
        // this and never yields a negative-width interval.
        if let interval = calendar.dateInterval(of: .month, for: date) {
            return interval
        }

        // Defensive fallback — `dateInterval(of:for:)` only returns nil for
        // dates outside the calendar's representable range, which cannot
        // occur for a `Date` produced by the running system. Reconstruct the
        // month span from date components so the function is still total.
        let startComponents = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: startComponents) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: max(start, end))
    }
}
