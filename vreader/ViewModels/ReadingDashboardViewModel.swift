// Purpose: ViewModel for the reading-stats dashboard (feature #58).
//
// Owns the active time window + per-book sort, drives the ReadingStatsAggregator,
// exposes the resulting snapshot, and persists the sort selection so it survives
// app launches.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration (mirrors LibraryViewModel).
// - The aggregator is injected via the ReadingStatsAggregating protocol so tests
//   substitute a mock.
// - The sort persists via PreferenceStoring under "stats.dashboardSort", mirroring
//   LibraryViewModel's "library.sortOrder" precedent. The window does NOT persist
//   — a fresh dashboard always opens on "Today" (the default), matching the
//   committed design's hero default.
// - An aggregator failure surfaces as `errorMessage` rather than crashing.
//
// @coordinates-with: ReadingStatsAggregator.swift, ReadingStatsModels.swift,
//   PreferenceStore.swift

import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "ReadingStats")

@Observable
@MainActor
final class ReadingDashboardViewModel {

    // MARK: - Observable state

    /// The most recent dashboard render, or nil before the first load / after an error.
    private(set) var snapshot: ReadingDashboardSnapshot?

    /// A user-facing error string when the last load failed; nil otherwise.
    private(set) var errorMessage: String?

    /// The window the per-book table is currently showing.
    private(set) var activeWindow: ReadingStatsWindow = .today

    /// The active per-book table sort. Restored from `PreferenceStoring` at init.
    private(set) var sort: ReadingDashboardSort = .default

    // MARK: - Dependencies

    private let aggregator: any ReadingStatsAggregating
    private let preferenceStore: (any PreferenceStoring)?

    /// `PreferenceStoring` key for the persisted dashboard sort.
    static let sortKey = "stats.dashboardSort"

    // MARK: - Init

    init(
        aggregator: any ReadingStatsAggregating,
        preferenceStore: (any PreferenceStoring)? = nil
    ) {
        self.aggregator = aggregator
        self.preferenceStore = preferenceStore

        // Restore the persisted sort; a missing or corrupt value falls back to default.
        if let raw = preferenceStore?.string(forKey: Self.sortKey),
           let restored = ReadingDashboardSort(storageString: raw) {
            self.sort = restored
        }
    }

    // MARK: - Loading

    /// Loads (or reloads) the snapshot for the current window + sort.
    /// On failure, populates `errorMessage` and leaves `snapshot` cleared.
    func load() async {
        await refresh()
    }

    /// Switches the active window and reloads the per-book table for it.
    func selectWindow(_ window: ReadingStatsWindow) async {
        activeWindow = window
        await refresh()
    }

    /// Changes the per-book sort, persists it, and reloads the table.
    func selectSort(_ newSort: ReadingDashboardSort) async {
        sort = newSort
        preferenceStore?.set(newSort.storageString, forKey: Self.sortKey)
        await refresh()
    }

    // MARK: - Private

    private func refresh() async {
        do {
            let result = try await aggregator.snapshot(
                window: activeWindow, sort: sort, now: Date()
            )
            snapshot = result
            errorMessage = nil
        } catch {
            log.error("dashboard snapshot failed: \(String(describing: error), privacy: .public)")
            snapshot = nil
            errorMessage = "Couldn't load reading stats. Pull to retry."
        }
    }
}
