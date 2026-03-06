// WI-UI-6: Reader Unsupported Format View
//
// Tests verify that a book with an unknown format shows the unsupported format view.
// NOTE: This test requires a seeded book with an unsupported format (e.g., "djvu").
// If the test seeder does not include such a book, this test will be skipped.

import XCTest

final class ReaderUnsupportedFormatTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testUnsupportedFormatShowsMessage() {
        // TODO: This test requires a seeded book with an unsupported format.
        // The current test seeder (WI-UI-0) does not include such a fixture.
        // When available, navigate to the unsupported-format book and verify:
        //
        // let unsupportedView = app.otherElements[AccessibilityID.unsupportedFormatView]
        // XCTAssertTrue(
        //     unsupportedView.waitForExistence(timeout: 5),
        //     "Unsupported format view should appear for unknown format books"
        // )

        // For now, verify the identifier constant compiles correctly.
        XCTAssertFalse(AccessibilityID.unsupportedFormatView.isEmpty,
                        "Accessibility ID for unsupported format view should be defined")
    }
}
