// Purpose: Feature #67 WI-4 — `SettingsView`'s Stats-dashboard sheet
// helpers. Split off `SettingsView.swift` to keep that file under the
// rule-50 ~300-line ceiling.
//
// The dashboard is presented as a sheet from the Settings sheet
// because the design's "Stats" entry-point sits on the profile card
// (`ProfileCardLibrary`). The view observes its own
// `Notification.Name.openReadingStatsRequested` post and presents
// `ReadingDashboardView` lazily over a freshly-built
// `ReadingDashboardViewModel(aggregator: ReadingStatsAggregator(...))`.
//
// @coordinates-with: SettingsView.swift, ReadingDashboardView.swift,
//   ReadingDashboardViewModel.swift, ReadingStatsAggregator.swift,
//   SettingsNotifications.swift

import SwiftUI

extension SettingsView {

    /// Lazily-constructed dashboard sheet content — built off the
    /// shared SwiftData `\.modelContext`'s container so the aggregator
    /// reads the same store the rest of the app uses.
    @ViewBuilder
    var statsSheetContent: some View {
        if let dashboardVM = statsDashboardViewModel {
            ReadingDashboardView(
                viewModel: dashboardVM,
                theme: paperTheme,
                onDismiss: { isShowingStats = false }
            )
        } else {
            // Defensive zero-state — should never render in practice
            // because `presentStatsDashboard()` builds the VM before
            // setting `isShowingStats = true`.
            ProgressView()
                .background(Color(paperTheme.sheetSurfaceColor))
        }
    }

    /// Presents the dashboard sheet. Idempotent — calls after the sheet
    /// is already presented are no-ops; calls after it is dismissed
    /// rebuild a fresh VM.
    func presentStatsDashboard() {
        guard !isShowingStats else { return }
        if statsDashboardViewModel == nil {
            let aggregator = ReadingStatsAggregator(
                modelContainer: modelContext.container
            )
            statsDashboardViewModel = ReadingDashboardViewModel(aggregator: aggregator)
        }
        isShowingStats = true
    }
}
