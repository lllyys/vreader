// Purpose: Feature #58 WI-6a — the design's `FullStatsDashboard`
// (`vreader-profile-stats.jsx`). Wraps the dashboard in the shared
// `ReaderSheetChrome` "Stats" sheet, composing the
// `StatsTimeWindowBar` + hero serif total + `StatsPerBookTable`.
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-profile-stats.jsx` (`FullStatsDashboard`).
//
// Key decisions:
// - **D4-A layout**: ONE hero serif total for the *active* window +
//   the pill bar. NOT 7 simultaneous cards (the row's old "as cards"
//   prose was superseded by the committed design — rule 51).
// - **D1-A entry point**: the dashboard is presented as a SHEET from
//   the Settings profile-card's Stats button. The user-facing wiring
//   (`SettingsView` presents `ReadingDashboardView`) ships in feature
//   #67 WI-4, which is hard-blocked on this WI-6a reaching `DONE` —
//   the standard mutual-dependency knot. This file ships the
//   presentable surface; #67 wires it up.
// - **The view owns no data.** It binds to a `ReadingDashboardViewModel`
//   (WI-4) and lets the VM drive the aggregator. `onDismiss` is supplied
//   by the presenter (SettingsView in #67) so the sheet's chrome Done
//   button works without this file knowing about the parent sheet.
// - **Hero formatting** uses `ReadingTimeFormatter.formatDuration`
//   (WI-3) so the format matches the rest of the app.
// - **Composition seams** (`heroDurationTextForTesting`,
//   `selectWindowForTesting`, `selectSortForTesting`) expose the
//   render contract for unit tests.
//
// @coordinates-with: ReadingDashboardViewModel.swift,
//   ReadingStatsAggregator.swift, ReadingStatsModels.swift,
//   StatsTimeWindowBar.swift, StatsPerBookTable.swift,
//   ReadingTimeFormatter.swift, ReaderSheetChrome.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-profile-stats.jsx`

import SwiftUI

/// The reading-stats dashboard — design `FullStatsDashboard`. Presents
/// itself in a `ReaderSheetChrome` "Stats" sheet over the active theme.
struct ReadingDashboardView: View {

    /// Pinned to the design — `FullStatsDashboard` chrome title in
    /// `vreader-profile-stats.jsx` (`<Sheet … title="Reading" …>`). The
    /// Stats *button* (in `ProfileCardLibrary`) is labelled "Stats"; the
    /// *sheet* it opens is titled "Reading" per the design bundle.
    static let sheetTitle = "Reading"

    @Bindable private var viewModel: ReadingDashboardViewModel
    private let theme: ReaderThemeV2
    private let onDismiss: () -> Void

    init(
        viewModel: ReadingDashboardViewModel,
        theme: ReaderThemeV2,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.theme = theme
        self.onDismiss = onDismiss
    }

    // MARK: - Testing seams

    /// The hero's formatted duration string — what the user sees as the
    /// big serif total. Zero when the snapshot is nil.
    var heroDurationTextForTesting: String {
        let totalSeconds = viewModel.snapshot?.total(for: viewModel.activeWindow).totalSeconds ?? 0
        return ReadingTimeFormatter.formatDuration(totalSeconds: totalSeconds)
    }

    /// Simulate a pill tap on the time-window bar.
    func selectWindowForTesting(_ window: ReadingStatsWindow) {
        Task { await viewModel.selectWindow(window) }
    }

    /// Simulate a header tap on the per-book table.
    func selectSortForTesting(_ newSort: ReadingDashboardSort) {
        Task { await viewModel.selectSort(newSort) }
    }

    // MARK: - Body

    var body: some View {
        ReaderSheetChrome(
            theme: theme,
            title: Self.sheetTitle,
            trailing: {
                Button("Done") { onDismiss() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(theme.accentColor))
                    .accessibilityIdentifier("readingDashboardDoneButton")
            }
        ) {
            content
        }
        .accessibilityIdentifier("readingDashboardView")
        .task {
            // Load the initial snapshot when the sheet first appears. The
            // VM idempotently re-runs the aggregator on each load() call.
            if viewModel.snapshot == nil && viewModel.errorMessage == nil {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                StatsTimeWindowBar(
                    theme: theme,
                    value: viewModel.activeWindow,
                    onChange: { window in
                        Task { await viewModel.selectWindow(window) }
                    }
                )

                heroSection
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color(theme.ruleColor))
                    .frame(height: 0.5)

                StatsPerBookTable(
                    theme: theme,
                    rows: viewModel.snapshot?.perBook ?? [],
                    sort: viewModel.sort,
                    onSort: { newSort in
                        Task { await viewModel.selectSort(newSort) }
                    }
                )
            }
        }
        .background(Color(theme.paperColor))
    }

    @ViewBuilder
    private var heroSection: some View {
        let durationText = heroDurationTextForTesting
        VStack(alignment: .leading, spacing: 4) {
            Text("Reading time, \(activeWindowSublabel)")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Color(theme.subColor))
            Text(durationText)
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(Color(theme.inkColor))
                .accessibilityIdentifier("readingDashboardHeroTotal")
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(theme.subColor))
                    .accessibilityIdentifier("readingDashboardError")
            }
        }
    }

    /// Subtitle copy under the hero — pinned to the design
    /// `FullStatsDashboard` (`vreader-profile-stats.jsx`):
    ///     `Reading time, {TIME_WINDOWS.label.toLowerCase()}`
    /// i.e. the window pill's own label, lowercased. The result reads as
    /// "Reading time, today" / "Reading time, 7d" / "Reading time, 30d"
    /// / etc. — matching the design verbatim.
    private var activeWindowSublabel: String {
        viewModel.activeWindow.label.lowercased()
    }
}
