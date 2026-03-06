import XCTest

/// WI-UI-13: File availability badge tests.
///
/// Tests that file availability badges are hidden for locally available books
/// and that accessibility labels are properly set.
@MainActor
final class FileAvailabilityBadgeTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Badge Hidden When Available

    /// Seeded books are local, so no download badge should appear.
    /// FileAvailabilityBadge only renders when state != .available.
    func testBadgeHiddenWhenAvailable() throws {
        // Wait for library to populate
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should appear")

        // Wait for books to load
        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        let firstBook = app.buttons.matching(cardPredicate).firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5),
                      "Seeded books should appear")

        // File availability badge text should not appear for locally available books.
        // Badge shows cloud icons or "Retry" text only for non-available states.
        let retryButton = app.buttons["Retry"]
        XCTAssertFalse(retryButton.exists,
                       "Retry button should not appear for locally available books")
    }

    // MARK: - Accessibility Labels

    /// File availability badges use AccessibilityFormatters.accessibleFileAvailability
    /// for their labels. When badges are hidden (available state), no badge labels exist.
    func testBadgeAccessibilityLabels() throws {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should appear")

        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        let firstBook = app.buttons.matching(cardPredicate).firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5),
                      "Seeded books should appear")

        // For local books, there should be no badge accessibility elements
        // containing download-related labels.
        let downloadLabels = ["Download queued", "Downloading", "Download failed"]
        for label in downloadLabels {
            let element = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", label)
            ).firstMatch
            XCTAssertFalse(element.exists,
                           "Badge label '\(label)' should not exist for local books")
        }
    }
}
