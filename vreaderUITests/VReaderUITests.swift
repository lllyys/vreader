// Purpose: Smoke tests verifying the app launches and shows the library view.
// Uses launch helper and accessibility ID constants from WI-UI-1 infrastructure.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, ContentView.swift

import XCTest

@MainActor
final class VReaderUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .empty)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Verifies the app launches successfully and the library view is present.
    func testAppLaunchesAndShowsLibrary() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should appear after app launch"
        )
    }
}
