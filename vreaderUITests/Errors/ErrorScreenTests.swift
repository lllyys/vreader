import XCTest

/// WI-UI-14: Error screen tests.
///
/// Tests the app initialization error screen that appears when the
/// database fails to initialize. Uses seed: .corruptDB launch argument.
@MainActor
final class ErrorScreenTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .corruptDB)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Init Error Screen

    /// When the database fails to initialize, an error screen should appear
    /// with a warning icon and "Unable to Open Library" title.
    func testInitErrorScreen() throws {
        // The error screen shows:
        //   - Image(systemName: "exclamationmark.triangle") — warning icon
        //   - Text("Unable to Open Library") — title
        //   - Sanitized error message — body
        let errorTitle = app.staticTexts["Unable to Open Library"]
        XCTAssertTrue(
            errorTitle.waitForExistence(timeout: 5),
            "Error screen should show 'Unable to Open Library' title when launched with corruptDB seed"
        )
    }

    // MARK: - No File Paths in Error

    /// Error messages must be sanitized — no raw file paths or technical details
    /// should be exposed to the user.
    func testInitErrorNoFilePaths() throws {
        let errorTitle = app.staticTexts["Unable to Open Library"]
        XCTAssertTrue(
            errorTitle.waitForExistence(timeout: 5),
            "Error screen should appear for corrupt DB"
        )

        // Collect all visible text on the error screen
        let allTexts = app.staticTexts.allElementsBoundByIndex
        for text in allTexts {
            let label = text.label

            // File paths contain "/" — error messages should not
            let containsPath = label.contains("/Users/")
                || label.contains("/var/")
                || label.contains("/Library/")
                || label.contains("/tmp/")
                || label.contains(".sqlite")
                || label.contains(".store")

            XCTAssertFalse(containsPath,
                           "Error message should not contain file paths. Found: \(label)")
        }
    }

    // MARK: - Accessibility Audit

    /// The error screen should pass the iOS 17+ accessibility audit.
    func testInitErrorAccessibilityAudit() throws {
        let errorTitle = app.staticTexts["Unable to Open Library"]
        XCTAssertTrue(
            errorTitle.waitForExistence(timeout: 5),
            "Error screen should appear for corrupt DB"
        )

        try app.performAccessibilityAudit()
    }
}
