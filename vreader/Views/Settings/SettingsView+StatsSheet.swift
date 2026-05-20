// Purpose: Feature #67 WI-4 — `SettingsView`'s Stats-dashboard sheet
// helpers. Split off `SettingsView.swift` to keep that file under the
// rule-50 ~300-line ceiling.
//
// The dashboard is presented as a sheet from the Settings sheet
// because the design's "Stats" entry-point sits on the profile card
// (`ProfileCardLibrary`). The view observes its own
// `Notification.Name.openReadingStatsRequested` post and asks the
// `SettingsStatsPresenter` (`@Observable`) to allocate a fresh
// `ReadingDashboardViewModel` over the `\.modelContext` container's
// aggregator on each open, then drops the VM on dismiss so the next
// open starts from the design's default entry state (Today window,
// no custom range).
//
// @coordinates-with: SettingsView.swift, ReadingDashboardView.swift,
//   ReadingDashboardViewModel.swift, ReadingStatsAggregator.swift,
//   SettingsNotifications.swift

import SwiftUI
import SwiftData

/// State machine for `SettingsView`'s Stats-dashboard sheet, factored
/// out of the View so the open / no-op-on-duplicate / dismiss / reopen
/// behavior is unit-testable without a `@State` install. Owns the
/// `isShowing` flag and the lazily-allocated `ReadingDashboardViewModel`;
/// the call site supplies the per-open VM builder so production can
/// close over the `\.modelContext` container without the presenter
/// type itself reaching into the SwiftUI Environment.
@Observable
@MainActor
final class SettingsStatsPresenter {

    /// Whether the dashboard sheet should currently be presented. The
    /// View binds `.sheet(isPresented:)` to this.
    var isShowing: Bool = false

    /// The currently-active dashboard view model. Non-nil only while
    /// the sheet is presented — `dismiss()` clears it so the next
    /// `present(build:)` allocates a fresh one with entry-state
    /// semantics.
    private(set) var dashboardViewModel: ReadingDashboardViewModel?

    init() {}

    /// Opens the dashboard. Idempotent — a second call while
    /// `isShowing == true` is a no-op so a rapid double-fire of
    /// `.openReadingStatsRequested` does not rebuild the VM. The
    /// `build` closure is invoked exactly once per genuine open and
    /// is the seam tests substitute (production passes a closure that
    /// constructs a `ReadingDashboardViewModel` over a fresh
    /// `ReadingStatsAggregator(modelContainer:)`).
    func present(build: () -> ReadingDashboardViewModel) {
        guard !isShowing else { return }
        dashboardViewModel = build()
        isShowing = true
    }

    /// Closes the dashboard and clears the VM so the next
    /// `present(build:)` allocates a fresh presenter (default window,
    /// no custom range).
    func dismiss() {
        isShowing = false
        dashboardViewModel = nil
    }

    /// Called by the `.sheet(isPresented:)`'s `onDismiss:` closure to
    /// keep state consistent after a swipe-dismiss (which bypasses
    /// the dashboard's own Done button → `dismiss()` path).
    func handleSheetOnDismiss() {
        dashboardViewModel = nil
    }
}

extension SettingsView {

    /// Lazily-constructed dashboard sheet content — built off the
    /// shared SwiftData `\.modelContext`'s container so the aggregator
    /// reads the same store the rest of the app uses.
    @ViewBuilder
    var statsSheetContent: some View {
        if let dashboardVM = statsPresenter.dashboardViewModel {
            ReadingDashboardView(
                viewModel: dashboardVM,
                theme: paperTheme,
                onDismiss: { statsPresenter.dismiss() }
            )
        } else {
            // Defensive zero-state — should never render in practice
            // because `present()` builds the VM before flipping
            // `isShowing = true`.
            ProgressView()
                .background(Color(paperTheme.sheetSurfaceColor))
        }
    }

    /// Production VM builder — closes over the `\.modelContext`
    /// container so each `present` opens the dashboard over the same
    /// SwiftData store the rest of the app uses.
    func makeProductionStatsViewModel() -> ReadingDashboardViewModel {
        ReadingDashboardViewModel(
            aggregator: ReadingStatsAggregator(modelContainer: modelContext.container)
        )
    }
}
