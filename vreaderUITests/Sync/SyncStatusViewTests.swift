import XCTest

/// WI-UI-13: Sync status view tests.
///
/// Tests the sync status badge visibility based on feature flag state.
/// Specific sync states (idle, syncing, error, offline) require ViewModel
/// state injection and are deferred to unit tests.
@MainActor
final class SyncStatusViewTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Sync Disabled

    /// When sync feature flag is OFF (default), no sync badge should be visible.
    func testSyncDisabledHidesBadge() throws {
        app = launchApp(seed: .books)

        // Wait for library to load
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should appear")

        // SyncStatusView renders nothing when sync is disabled.
        // Check that the "Synced" accessibility label is absent.
        let syncElement = app.otherElements.matching(
            NSPredicate(format: "label == 'Synced'")
        ).firstMatch
        XCTAssertFalse(syncElement.exists,
                       "Sync status should not be visible when sync is disabled")
    }

    // MARK: - Sync Enabled

    /// When sync feature flag is ON, the sync status area should be present.
    func testSyncEnabledShowsBadge() throws {
        app = launchApp(seed: .books, enableSync: true)

        // Wait for library to load
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should appear")

        // When sync is enabled, the SyncStatusView renders with .idle status
        // which produces an accessibility label of "Synced".
        // The element has accessibilityElement(children: .ignore) so it appears
        // as a single element in the accessibility tree.
        let syncElement = app.otherElements.matching(
            NSPredicate(format: "label == 'Synced'")
        ).firstMatch
        XCTAssertTrue(
            syncElement.waitForExistence(timeout: 5),
            "Sync status indicator should be present when sync is enabled"
        )
    }

    // MARK: - Accessibility Audit

    /// The library view with sync enabled should pass accessibility audit.
    func testSyncAccessibilityAudit() {
        app = launchApp(seed: .books, enableSync: true)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should appear")

        auditCurrentScreen(app: app)
    }
}
