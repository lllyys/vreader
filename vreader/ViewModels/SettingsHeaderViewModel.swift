// Purpose: @MainActor @Observable view model that fetches the Settings
// profile card's two numbers — the library book count and the current
// calendar month's reading seconds — off the persistence layer. Keeps
// `SettingsView` itself a thin composition. Feature #67 WI-3.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration — the project's
//   view-model pattern (`LibraryViewModel`, `ReadingDashboardViewModel`).
// - The persistence boundary is injected as the narrow read-only
//   `LibraryStatsReading` protocol, so tests substitute a mock without
//   a SwiftData store.
// - `load(persistence:)` takes an OPTIONAL boundary — `\.persistenceActor`
//   is itself an optional Environment key (`nil` in previews/tests), so
//   `SettingsView` passes whatever the Environment holds. A `nil`
//   boundary is the "no data" path → zeros, the same as an empty library.
// - `load` is idempotent — last-write-wins via a monotonic request id
//   (the `ReadingDashboardViewModel.latestRequestID` precedent), so a
//   `.task` re-run when the sheet re-appears is safe and a slow earlier
//   load cannot overwrite a newer one.
// - A boundary failure leaves the counts at zero (the card shows
//   "0 books · 0h" gracefully) — it does not crash and it logs.
//
// @coordinates-with: LibraryStatsReading.swift, MonthBoundary.swift,
//   SettingsProfileCard.swift, SettingsView.swift

import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "Settings")

/// Fetches the Settings profile card's book count + this-month reading
/// seconds.
@Observable
@MainActor
final class SettingsHeaderViewModel {

    // MARK: - Observable state

    /// The number of books in the library. Zero before the first
    /// successful `load`, and after a failed or `nil`-boundary load.
    private(set) var bookCount: Int = 0

    /// The reading seconds accumulated in the current calendar month.
    private(set) var monthReadingSeconds: Int = 0

    // MARK: - Private

    /// Monotonic request counter. Each `load` claims the next id; its
    /// result is applied only if it is still the latest — so a slow
    /// earlier load cannot overwrite a newer one's values.
    private var latestRequestID = 0

    // MARK: - Init

    /// Constructs an empty view model. `SettingsView` owns it as
    /// `@State` and calls `load` from a `.task`.
    init() {}

    // MARK: - Loading

    /// Loads the book count + this-month reading seconds from
    /// `persistence`.
    ///
    /// A `nil` boundary (or a boundary that throws) leaves both counts
    /// at zero — the card renders "0 books · 0h" gracefully, the same
    /// as a genuinely empty library. Safe to call repeatedly
    /// (last-write-wins).
    func load(persistence: (any LibraryStatsReading)?) async {
        latestRequestID += 1
        let requestID = latestRequestID

        guard let persistence else {
            applyIfCurrent(requestID: requestID, books: 0, seconds: 0)
            return
        }

        do {
            let month = MonthBoundary.currentMonth(containing: Date())
            let books = try await persistence.countLibraryBooks()
            let seconds = try await persistence.sumReadingSeconds(in: month)
            applyIfCurrent(requestID: requestID, books: books, seconds: seconds)
        } catch {
            log.error(
                "settings header load failed: \(String(describing: error), privacy: .public)"
            )
            applyIfCurrent(requestID: requestID, books: 0, seconds: 0)
        }
    }

    /// Applies a load result only when it is still the most recent
    /// request — drops a stale earlier load.
    private func applyIfCurrent(requestID: Int, books: Int, seconds: Int) {
        guard requestID == latestRequestID else { return }
        bookCount = books
        monthReadingSeconds = seconds
    }
}
