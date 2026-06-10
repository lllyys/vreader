// Purpose: Feature #96 WI-2 — pure presentation helpers for the diagnostics
// log viewer: the functional level→tint mapping and the day-bucketing of
// entries. Both are SwiftUI-free pure logic so they unit-test without a render
// path (the `SheetSectionContract` / `SettingsRowPalette` precedent).
//
// Pinned to the committed design bundle at
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
// (`diagLevelColor` + `DiagLogList` day headers).
//
// Key decisions:
// - **Level tint is functional, not decorative** (design): error = warm red,
//   info = cool blue, everything else (debug / notice / undefined) = the
//   theme's secondary `sub` color. `.fault` groups with `.error` (more severe,
//   same error family); `.notice` groups with `.neutral` per the design's
//   literal "only error & info are colored" mapping.
// - **Level FILTER buckets** mirror the design's four level chips
//   (All / Errors / Debug / Info). `errors` includes `.fault` so a fault is
//   never hidden behind the Errors chip.
// - **Day grouping is `now`/`calendar`-injected** so it tests deterministically
//   (no `Date()` / `Calendar.current` read inside).
//
// @coordinates-with: DiagnosticsLogViewModel.swift, DiagnosticsLogRow.swift,
//   DiagnosticsLogEntry.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`

import Foundation

/// The viewer's functional color family for one entry's level (design
/// `diagLevelColor`). The view resolves a concrete `Color` from this + the
/// theme; the enum itself is render-free so it unit-tests cleanly.
enum DiagnosticsLevelTint: Equatable, Sendable {
    /// Warm red — `error` / `fault`.
    case error
    /// Cool blue — `info`.
    case info
    /// The theme's secondary `sub` color — `debug` / `notice` / `undefined`.
    case neutral
}

extension DiagnosticsLevel {
    /// The viewer tint for this level (design `diagLevelColor`).
    var viewerTint: DiagnosticsLevelTint {
        switch self {
        case .error, .fault:        return .error
        case .info:                 return .info
        case .debug, .notice, .undefined: return .neutral
        }
    }
}

/// The four level-filter chips on the viewer (design `DiagFilterBar`).
enum DiagnosticsLevelFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case errors
    case debug
    case info

    /// The chip's display label.
    var label: String {
        switch self {
        case .all:    return "All"
        case .errors: return "Errors"
        case .debug:  return "Debug"
        case .info:   return "Info"
        }
    }

    /// Whether an entry of `level` passes this filter. `errors` includes
    /// `.fault` so a fault is never hidden behind the Errors chip.
    func matches(_ level: DiagnosticsLevel) -> Bool {
        switch self {
        case .all:    return true
        case .errors: return level == .error || level == .fault
        case .debug:  return level == .debug
        case .info:   return level == .info
        }
    }
}

/// One entry paired with a STABLE identity for the viewer's list. Two
/// value-equal `DiagnosticsLogEntry`s (same date/level/category/message) must
/// still expand independently, so identity is a caller-assigned `id` (the
/// entry's position in the filtered list) — NOT `Equatable`-derived.
struct IdentifiedDiagnosticsEntry: Identifiable, Equatable, Sendable {
    let id: Int
    let entry: DiagnosticsLogEntry
}

/// One day-bucket of entries for the viewer's grouped list (design
/// `DiagLogList` day headers). `entries` are newest-first within the day.
struct DiagnosticsDaySection: Identifiable, Equatable, Sendable {
    /// Stable id — the start-of-day timestamp's description.
    let id: String
    /// The relative word for today/yesterday, else `nil` (older days show only
    /// the date label).
    let relativeWord: String?
    /// The `d MMMM` date label (e.g. "10 June").
    let dateLabel: String
    /// Entries on this day, newest-first, each carrying its stable identity.
    let entries: [IdentifiedDiagnosticsEntry]

    /// The composed header (design "Today · 10 June").
    var header: String {
        relativeWord.map { "\($0) · \(dateLabel)" } ?? dateLabel
    }
}

/// Buckets entries into newest-first day sections for the viewer.
enum DiagnosticsDayGrouper {
    /// Groups identity-tagged `entries` (any order) into day sections, newest
    /// day first and newest entry first within each day. `now` decides
    /// Today/Yesterday; `calendar` is injected for deterministic tests.
    static func sections(
        from entries: [IdentifiedDiagnosticsEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> [DiagnosticsDaySection] {
        guard !entries.isEmpty else { return [] }

        let dateLabelFormatter = DateFormatter()
        dateLabelFormatter.calendar = calendar
        dateLabelFormatter.locale = calendar.locale ?? Locale.current
        dateLabelFormatter.dateFormat = "d MMMM"

        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)

        // Bucket by start-of-day.
        var buckets: [Date: [IdentifiedDiagnosticsEntry]] = [:]
        for item in entries {
            let dayStart = calendar.startOfDay(for: item.entry.date)
            buckets[dayStart, default: []].append(item)
        }

        // Newest day first.
        return buckets.keys.sorted(by: >).map { dayStart in
            let dayEntries = buckets[dayStart]!.sorted { $0.entry.date > $1.entry.date }
            let relativeWord: String?
            if dayStart == todayStart {
                relativeWord = "Today"
            } else if dayStart == yesterdayStart {
                relativeWord = "Yesterday"
            } else {
                relativeWord = nil
            }
            return DiagnosticsDaySection(
                id: String(dayStart.timeIntervalSinceReferenceDate),
                relativeWord: relativeWord,
                dateLabel: dateLabelFormatter.string(from: dayStart),
                entries: dayEntries
            )
        }
    }
}
