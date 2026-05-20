// Purpose: Feature #67 WI-4 — Stats hand-off notification test. Confirms
// that tapping the profile card's Stats button (via the closure
// `SettingsView` wires) posts `Notification.Name.openReadingStatsRequested`
// exactly once with no `userInfo` payload.
//
// This is the wiring assertion the card's own composition test
// (`SettingsProfileCardTests`) deliberately leaves out: the card invokes
// its `onOpenStats` closure (a closure-only seam); the notification
// post belongs to `SettingsView`'s wiring, asserted here.
//
// Rule 10 §5: XCTest because we need `XCTestExpectation` for the
// notification observer's async fulfillment.

import XCTest
@testable import vreader

@MainActor
final class SettingsViewStatsHandoffTests: XCTestCase {

    /// Tapping the Stats action wired by `SettingsView` posts the
    /// hand-off notification exactly once.
    func test_settingsView_statsButton_posts_openReadingStatsRequested() async {
        let view = SettingsView()
        // Resolve the same closure SettingsView wires into
        // SettingsProfileCard's `onOpenStats`. The view exposes it via a
        // testing seam so the wiring is assertable without a render
        // path — mirroring the plan's WI-4 Test catalogue.
        let action = view.statsHandoffActionForTesting

        let exp = expectation(description: "openReadingStatsRequested posted")
        exp.expectedFulfillmentCount = 1

        nonisolated(unsafe) var receivedUserInfo: [AnyHashable: Any]?
        let token = NotificationCenter.default.addObserver(
            forName: .openReadingStatsRequested,
            object: nil,
            queue: .main
        ) { notification in
            receivedUserInfo = notification.userInfo
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        action()

        await fulfillment(of: [exp], timeout: 2.0)
        // The hand-off carries no payload — the dashboard observer just
        // presents its surface.
        XCTAssertNil(receivedUserInfo)
    }

    /// Invoking the action twice posts the notification twice — i.e.
    /// the closure does not silently coalesce. (A user can tap Stats,
    /// dismiss, and tap again; each tap is its own request.)
    func test_settingsView_statsButton_posts_twice_on_two_taps() async {
        let view = SettingsView()
        let action = view.statsHandoffActionForTesting

        let exp = expectation(description: "openReadingStatsRequested posted twice")
        exp.expectedFulfillmentCount = 2

        let token = NotificationCenter.default.addObserver(
            forName: .openReadingStatsRequested,
            object: nil,
            queue: .main
        ) { _ in
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        action()
        action()

        await fulfillment(of: [exp], timeout: 2.0)
    }

    /// The notification name itself matches the architecture-doc Bus
    /// row exactly — the namespaced `vreader.settings.<event>` string.
    func test_openReadingStatsRequested_rawName_isNamespaced() {
        XCTAssertEqual(
            Notification.Name.openReadingStatsRequested.rawValue,
            "vreader.settings.openReadingStatsRequested"
        )
    }
}
