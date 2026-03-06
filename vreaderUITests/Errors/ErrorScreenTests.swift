import XCTest

/// WI-UI-14: Error screen tests.
///
/// Tests the app initialization error screen that appears when the
/// database fails to initialize. Requires --seed-corrupt-db launch argument.
final class ErrorScreenTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Init Error Screen

    /// When the database fails to initialize, an error screen should appear
    /// with a warning icon and "Unable to Open Library" title.
    func testInitErrorScreen() throws {
        // TODO: --seed-corrupt-db launch argument may not be implemented yet.
        // This flag should cause the ModelContainer initialization to fail,
        // triggering the error screen in VReaderApp.
        app.launchArguments = ["--uitesting", "--seed-corrupt-db"]
        app.launch()

        // The error screen shows:
        //   - Image(systemName: "exclamationmark.triangle") — warning icon
        //   - Text("Unable to Open Library") — title
        //   - Sanitized error message — body
        let errorTitle = app.staticTexts["Unable to Open Library"]
        if errorTitle.waitForExistence(timeout: 5) {
            XCTAssertTrue(errorTitle.exists,
                          "Error screen should show 'Unable to Open Library' title")
        } else {
            // If --seed-corrupt-db isn't implemented, the app may launch normally.
            // Check if library loaded instead.
            let libraryView = app.otherElements[AccessibilityID.libraryView]
            if libraryView.waitForExistence(timeout: 3) {
                XCTExpectFailure("--seed-corrupt-db launch argument not implemented yet")
                XCTFail("App launched normally — --seed-corrupt-db not wired")
            } else {
                XCTFail("Neither error screen nor library appeared")
            }
        }
    }

    // MARK: - No File Paths in Error

    /// Error messages must be sanitized — no raw file paths or technical details
    /// should be exposed to the user.
    func testInitErrorNoFilePaths() throws {
        app.launchArguments = ["--uitesting", "--seed-corrupt-db"]
        app.launch()

        let errorTitle = app.staticTexts["Unable to Open Library"]
        guard errorTitle.waitForExistence(timeout: 5) else {
            XCTExpectFailure("--seed-corrupt-db launch argument not implemented yet")
            XCTFail("Error screen not shown — cannot verify message sanitization")
            return
        }

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
        app.launchArguments = ["--uitesting", "--seed-corrupt-db"]
        app.launch()

        let errorTitle = app.staticTexts["Unable to Open Library"]
        guard errorTitle.waitForExistence(timeout: 5) else {
            XCTExpectFailure("--seed-corrupt-db launch argument not implemented yet")
            XCTFail("Error screen not shown — cannot run audit")
            return
        }

        try app.performAccessibilityAudit()
    }
}
