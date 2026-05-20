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

    /// The active user-picked custom range. Non-nil when the user has applied
    /// a Custom range; nil = an enum window is active. Restored from
    /// `PreferenceStoring` at init. WI-6b feature #58.
    private(set) var customRange: ReadingStatsCustomRange?

    /// True when the Custom picker sheet should be presented. Owned here so
    /// the View binds via `$viewModel.isCustomPickerPresented`.
    var isCustomPickerPresented: Bool = false

    /// True when the dashboard is currently driven by `customRange` (so the
    /// pill bar highlights the Custom pill and the hero shows the custom
    /// range's total).
    var isCustomActive: Bool { customRange != nil }

    // MARK: - Dependencies

    private let aggregator: any ReadingStatsAggregating
    private let preferenceStore: (any PreferenceStoring)?

    /// Monotonic request counter. Each `refresh()` claims the next id; a result
    /// is applied only if it is still the latest — so a slow earlier request
    /// (e.g. an older window) can never overwrite a newer one's snapshot.
    private var latestRequestID = 0

    /// `PreferenceStoring` key for the persisted dashboard sort.
    static let sortKey = "stats.dashboardSort"

    /// `PreferenceStoring` key for the persisted custom range (WI-6b).
    static let customRangeKey = "stats.customRange"

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

        // Restore the persisted custom range; a missing or corrupt JSON blob
        // leaves customRange nil (enum windows active). WI-6b feature #58.
        if let raw = preferenceStore?.string(forKey: Self.customRangeKey),
           let data = raw.data(using: .utf8),
           let restored = try? JSONDecoder().decode(ReadingStatsCustomRange.self, from: data) {
            self.customRange = restored
        }
    }

    // MARK: - Loading

    /// Loads (or reloads) the snapshot for the current window + sort.
    /// On failure, populates `errorMessage` and leaves `snapshot` cleared.
    func load() async {
        await refresh()
    }

    /// Switches the active enum window, clears any active Custom range, and
    /// reloads. Tapping a non-Custom pill always exits Custom mode.
    func selectWindow(_ window: ReadingStatsWindow) async {
        activeWindow = window
        if customRange != nil {
            customRange = nil
            preferenceStore?.remove(forKey: Self.customRangeKey)
        }
        await refresh()
    }

    /// Applies a user-picked custom range. The dashboard switches to
    /// custom-range mode (hero + table reflect the range); the previous
    /// enum `activeWindow` is preserved so dismissing Custom returns to it.
    /// WI-6b feature #58.
    func applyCustomRange(_ range: ReadingStatsCustomRange) async {
        customRange = range
        if let data = try? JSONEncoder().encode(range),
           let raw = String(data: data, encoding: .utf8) {
            preferenceStore?.set(raw, forKey: Self.customRangeKey)
        }
        await refresh()
    }

    /// Exits Custom mode and falls back to the current enum `activeWindow`.
    func clearCustomRange() async {
        guard customRange != nil else { return }
        customRange = nil
        preferenceStore?.remove(forKey: Self.customRangeKey)
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
        latestRequestID += 1
        let requestID = latestRequestID
        let requestWindow = activeWindow
        let requestSort = sort
        let requestCustomRange = customRange
        do {
            let result = try await aggregator.snapshot(
                window: requestWindow, sort: requestSort, now: Date(),
                customRange: requestCustomRange
            )
            // Drop the result if a newer refresh started while this one ran —
            // a stale earlier request must not overwrite a fresher snapshot.
            guard requestID == latestRequestID else { return }
            snapshot = result
            errorMessage = nil
        } catch {
            guard requestID == latestRequestID else { return }
            log.error("dashboard snapshot failed: \(String(describing: error), privacy: .public)")
            snapshot = nil
            errorMessage = "Couldn't load reading stats. Pull to retry."
        }
    }
}
