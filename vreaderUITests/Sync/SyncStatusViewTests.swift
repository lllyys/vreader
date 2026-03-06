import XCTest

/// WI-UI-13: Sync status view tests.
///
/// Tests the sync status badge visibility based on feature flag state.
/// Specific sync states (idle, syncing, error, offline) require ViewModel
/// state injection and are deferred to unit tests.
final class SyncStatusViewTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Sync Disabled

    /// When sync feature flag is OFF (default), no sync badge should be visible.
    func testSyncDisabledHidesBadge() throws {
        app.launchArguments = ["--uitesting", "--seed-books"]
        app.launch()

        // Wait for library to load
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should appear")

        // Sync status elements should not be present when sync is disabled.
        // SyncStatusView renders nothing when monitor.status == .disabled.
        let syncTexts = ["Synced", "Syncing…", "Sync Error", "Offline", "Sync Off"]
        for text in syncTexts {
            let element = app.staticTexts[text]
            XCTAssertFalse(element.exists,
                           "Sync text '\(text)' should not be visible when sync is disabled")
        }
    }

    // MARK: - Sync Enabled

    /// When sync feature flag is ON, the sync status area should be present.
    func testSyncEnabledShowsBadge() throws {
        app.launchArguments = ["--uitesting", "--seed-books", "--enable-sync"]
        app.launch()

        // Wait for library to load
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should appear")

        // When sync is enabled, the SyncStatusView should render.
        // Default state is .idle which shows "Synced" text.
        // However, the actual initial state depends on SyncStatusMonitor
        // initialization. We check that at least some sync status element exists.
        // Use a lenient check — sync status may not render immediately
        // if the monitor hasn't initialized yet.
        // Check for any sync-related text appearing on screen.
        let syncTextsToFind = ["Synced", "Syncing", "sync"]
        var found = false
        for text in syncTextsToFind {
            if app.staticTexts[text].waitForExistence(timeout: 2) {
                found = true
                break
            }
        }
        if !found {
            XCTFail("Sync status indicator should be present when sync is enabled")
        }
    }

    // MARK: - Accessibility Audit

    /// The library view with sync enabled should pass accessibility audit.
    func testSyncAccessibilityAudit() throws {
        app.launchArguments = ["--uitesting", "--seed-books", "--enable-sync"]
        app.launch()

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should appear")

        try app.performAccessibilityAudit()
    }
}
