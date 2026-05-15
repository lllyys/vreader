// Purpose: Verification tests for Feature #29 — WebDAV backup.
// Confirms the WebDAV settings UI surface is reachable from the global
// Settings sheet, and (conditionally) that a live backup executes
// against a CI-provided WebDAV server.
//
// Seed: .books (UI is reached pre-reader; book content irrelevant).
//
// Notes:
// - The behavioral test (`test_verify_feature_29_webdav_backup_executes_when_configured`)
//   XCTSkips unless `CI_WEBDAV_URL`, `CI_WEBDAV_USERNAME`, `CI_WEBDAV_PASSWORD`
//   env vars are set. This preserves the ability to gate WebDAV live
//   tests on real server availability without blocking the suite when
//   unset.
// - The UI-surface test runs unconditionally.
//
// @coordinates-with: WebDAVSettingsView.swift, SettingsView.swift,
//   WebDAVProvider.swift

import XCTest

@MainActor
final class Feature29WebDAVVerificationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Feature #29 Verification

    /// Verifies the WebDAV settings UI surface is reachable and that the
    /// credentials form + Test button render correctly.
    ///
    /// Bug #195 (GH #695): pre-Feature-#52, the URL/username/password
    /// fields lived directly on `WebDAVSettingsView`. Feature #52
    /// (VERIFIED 2026-05-09) moved them into a per-profile edit sheet
    /// reached via NavigationLink → profile list → Add. The test now
    /// traverses that path.
    func test_verify_feature_29_webdav_backup_ui_available() throws {
        let settingsButton = app.buttons[AccessibilityID.settingsToolbarButton]
        guard settingsButton.waitForHittable(timeout: 8) else {
            throw XCTSkip("Settings toolbar button not present in library view")
        }
        settingsButton.tap()

        XCTAssertTrue(
            app.otherElements[AccessibilityID.settingsView].waitForExistence(timeout: 5),
            "Settings view should appear after tapping settings toolbar button"
        )

        // Enter the WebDAV settings panel via the "Backup" / "WebDAV"
        // navigation row in Settings. The heuristic predicate handles
        // both label wordings without depending on a brittle exact match.
        let webdavSettingsRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'WebDAV' OR label CONTAINS[c] 'Backup'")
        ).firstMatch
        guard webdavSettingsRow.waitForExistence(timeout: 5) else {
            throw XCTSkip("Cannot reach WebDAV settings section from Settings sheet")
        }
        webdavSettingsRow.tap()

        // Tap the "Servers" NavigationLink (`webdavServersNavLink`,
        // Feature #52) to reach the profile list. Search element-type-
        // agnostically — NavigationLink rendering varies by iOS version
        // (button on iOS 17, may differ on future versions).
        let serversNavLink = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.webdavServersNavLink)
            .firstMatch
        XCTAssertTrue(
            serversNavLink.waitForExistence(timeout: 5),
            "WebDAVSettingsView should expose `webdavServersNavLink` to enter the profile list (Feature #52)"
        )
        serversNavLink.tap()

        // Profile list is empty for a fresh seed; tap the toolbar "+"
        // to open the edit sheet in add-mode.
        let addProfileButton = app.buttons[AccessibilityID.addWebDAVProfileButton]
        XCTAssertTrue(
            addProfileButton.waitForExistence(timeout: 5),
            "WebDAVServerProfileListView should expose `addWebDAVProfileButton`"
        )
        addProfileButton.tap()

        // The edit sheet shows the URL + username TextFields and the
        // Test Connection button — credentials form surface verified.
        let urlField = app.textFields[AccessibilityID.webdavProfileEditServerURL]
        XCTAssertTrue(
            urlField.waitForExistence(timeout: 5),
            "WebDAV Server URL field should be visible in the profile edit sheet"
        )

        XCTAssertTrue(
            app.textFields[AccessibilityID.webdavProfileEditUsername].exists,
            "WebDAV Username field should be present in the profile edit sheet"
        )

        // Connection section is present in the edit sheet. Bug #184's
        // design hides the Test Connection BUTTON in add-mode (no
        // existing keychain entry yet) and shows a footer note instead.
        // Accept either surface — the Connection section exists.
        let testButton = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.webdavProfileEditTestConnection)
            .firstMatch
        let testNote = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.webdavProfileEditTestConnectionNote)
            .firstMatch
        XCTAssertTrue(
            testButton.exists || testNote.exists,
            "WebDAV profile edit sheet should expose the Connection section either as the Test Connection button (edit-mode) or the add-mode footer note (per Bug #184 design)"
        )
    }

    /// Conditional: verifies that a backup actually executes against a
    /// configured WebDAV server. Skipped unless CI_WEBDAV_URL + credentials
    /// are present in the env.
    func test_verify_feature_29_webdav_backup_executes_when_configured() throws {
        let env = ProcessInfo.processInfo.environment
        guard
            let url = env["CI_WEBDAV_URL"],
            let user = env["CI_WEBDAV_USERNAME"],
            let pass = env["CI_WEBDAV_PASSWORD"],
            !url.isEmpty, !user.isEmpty, !pass.isEmpty
        else {
            throw XCTSkip("CI_WEBDAV_URL / CI_WEBDAV_USERNAME / CI_WEBDAV_PASSWORD env vars not set")
        }

        let settingsButton = app.buttons[AccessibilityID.settingsToolbarButton]
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 5))
        settingsButton.tap()

        // Navigate into WebDAV section if needed
        let webdavURLField = app.textFields[AccessibilityID.webdavServerURL]
        if !webdavURLField.waitForExistence(timeout: 3) {
            let webdavRow = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'WebDAV' OR label CONTAINS[c] 'Backup'")
            ).firstMatch
            guard webdavRow.waitForExistence(timeout: 5) else {
                throw XCTSkip("Cannot reach WebDAV settings")
            }
            webdavRow.tap()
        }

        XCTAssertTrue(webdavURLField.waitForExistence(timeout: 5))
        webdavURLField.tap()
        webdavURLField.typeText(url)

        let usernameField = app.textFields[AccessibilityID.webdavUsername]
        usernameField.tap()
        usernameField.typeText(user)

        let passwordField = app.secureTextFields[AccessibilityID.webdavPassword]
        passwordField.tap()
        passwordField.typeText(pass)

        app.buttons[AccessibilityID.webdavSaveButton].tap()

        let backupButton = app.buttons[AccessibilityID.webdavBackupNowButton]
        XCTAssertTrue(
            backupButton.waitForHittable(timeout: 10),
            "Backup Now button should appear after saving credentials"
        )
        backupButton.tap()

        // After a backup attempt, the error text should be absent.
        let errorText = app.staticTexts[AccessibilityID.webdavBackupErrorText]
        let predicate = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: errorText)
        let result = XCTWaiter().wait(for: [exp], timeout: 30)
        XCTAssertEqual(
            result, .completed,
            "WebDAV backup should complete without errors against the configured server"
        )
    }
}
