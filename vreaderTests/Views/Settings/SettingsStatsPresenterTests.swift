// Purpose: Feature #67 WI-4 — `SettingsStatsPresenter` state-machine
// tests. The presenter owns the "Stats sheet open / no-op-on-duplicate
// / dismiss / fresh-VM-on-reopen" behavior that lives behind the
// notification-bus hand-off; the tests pin that behavior without
// installing a SwiftUI `@State` view hierarchy or constructing a
// real `ReadingStatsAggregator` (no SwiftData ModelContainer needed).
//
// Audit-driven: the WI-4 Gate-4 audit (Codex thread `019e457e`, round 1)
// flagged a stale-VM bug — `present()` was only allocating when the VM
// was nil, and `dismiss()` never cleared it, so reopen reused the
// previous window/sort/custom-range state. The presenter refactor
// (this WI) makes `present(build:)` always re-allocate after a
// dismiss; these tests pin that contract.

import Testing
import Foundation
@testable import vreader

@Suite("SettingsStatsPresenter — feature #67 WI-4")
@MainActor
struct SettingsStatsPresenterTests {

    /// Builds a stub `ReadingDashboardViewModel` over a deterministic
    /// no-op aggregator that returns an empty snapshot. Avoids the
    /// `ReadingStatsAggregator(modelContainer:)` path which would
    /// require a SwiftData container at unit-test time.
    private static func makeStubViewModel() -> ReadingDashboardViewModel {
        ReadingDashboardViewModel(aggregator: StubStatsAggregator())
    }

    /// In-memory aggregator that returns an empty snapshot for any
    /// window — sufficient to construct a `ReadingDashboardViewModel`.
    final class StubStatsAggregator: ReadingStatsAggregating, @unchecked Sendable {
        func snapshot(
            window: ReadingStatsWindow,
            sort: ReadingDashboardSort,
            now: Date,
            customRange: ReadingStatsCustomRange?
        ) async throws -> ReadingDashboardSnapshot {
            ReadingDashboardSnapshot(
                windowTotals: [],
                activeWindow: window,
                perBook: [],
                lifetimeTotalSeconds: 0,
                trackingSince: nil,
                customRangeBreakdown: nil
            )
        }
    }

    // MARK: - Initial state

    @Test func freshPresenter_isClosed_withNoViewModel() {
        let presenter = SettingsStatsPresenter()
        #expect(presenter.isShowing == false)
        #expect(presenter.dashboardViewModel == nil)
    }

    // MARK: - First present

    @Test func firstPresent_setsIsShowing_andBuildsViewModel() {
        let presenter = SettingsStatsPresenter()
        var buildCount = 0
        presenter.present {
            buildCount += 1
            return Self.makeStubViewModel()
        }
        #expect(presenter.isShowing == true)
        #expect(presenter.dashboardViewModel != nil)
        #expect(buildCount == 1)
    }

    // MARK: - Idempotent open (no-op on duplicate present)

    @Test func secondPresent_whileShowing_isNoOp() {
        let presenter = SettingsStatsPresenter()
        let firstVM = Self.makeStubViewModel()
        presenter.present { firstVM }

        var buildCalled = false
        presenter.present {
            buildCalled = true
            return Self.makeStubViewModel()
        }

        // Build was NOT invoked the second time — the guard is in
        // effect. The VM identity stays.
        #expect(buildCalled == false)
        #expect(presenter.dashboardViewModel === firstVM)
        #expect(presenter.isShowing == true)
    }

    // MARK: - Dismiss

    @Test func dismiss_clearsIsShowing_andViewModel() {
        let presenter = SettingsStatsPresenter()
        presenter.present { Self.makeStubViewModel() }
        #expect(presenter.dashboardViewModel != nil)

        presenter.dismiss()
        #expect(presenter.isShowing == false)
        #expect(presenter.dashboardViewModel == nil)
    }

    // MARK: - Reopen after dismiss (fresh VM)

    @Test func reopen_afterDismiss_buildsFreshViewModel() {
        let presenter = SettingsStatsPresenter()
        let firstVM = Self.makeStubViewModel()
        let secondVM = Self.makeStubViewModel()

        presenter.present { firstVM }
        presenter.dismiss()
        #expect(presenter.dashboardViewModel == nil)

        presenter.present { secondVM }
        // After a dismiss, the next present builds a NEW VM — not
        // the prior firstVM (entry-state semantics).
        #expect(presenter.dashboardViewModel === secondVM)
        #expect(presenter.dashboardViewModel !== firstVM)
    }

    // MARK: - Swipe-dismiss path

    @Test func handleSheetOnDismiss_clearsViewModel() {
        // The `.sheet(isPresented:)` `onDismiss:` closure fires when
        // the user swipes the sheet down (bypassing the dashboard's
        // own Done button). The presenter clears the VM so the next
        // `present(build:)` allocates fresh.
        let presenter = SettingsStatsPresenter()
        presenter.present { Self.makeStubViewModel() }
        // Simulate the iOS sheet's native dismiss flipping the
        // binding to false: the View's `.sheet`'s `isPresented`
        // resets, then `onDismiss` fires `handleSheetOnDismiss()`.
        presenter.isShowing = false
        presenter.handleSheetOnDismiss()

        #expect(presenter.dashboardViewModel == nil)
        // And a follow-up present allocates a brand-new VM.
        let nextVM = Self.makeStubViewModel()
        presenter.present { nextVM }
        #expect(presenter.dashboardViewModel === nextVM)
    }

    // MARK: - Double-fire notification — only one rebuild

    @Test func rapidDoubleFire_ofPresent_buildsOnlyOnce() {
        // Models the user double-tapping the Stats pill before the
        // sheet animation finishes — the notification publisher
        // posts twice, but `present(build:)` is guarded.
        let presenter = SettingsStatsPresenter()
        var builds = 0
        let builder: () -> ReadingDashboardViewModel = {
            builds += 1
            return Self.makeStubViewModel()
        }
        presenter.present(build: builder)
        presenter.present(build: builder)
        presenter.present(build: builder)

        #expect(builds == 1)
        #expect(presenter.isShowing == true)
    }
}
