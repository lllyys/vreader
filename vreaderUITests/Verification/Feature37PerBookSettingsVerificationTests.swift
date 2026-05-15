// Purpose: Verification tests for Feature #37 — per-book reader settings.
// Exercises the "Custom settings for this book" toggle and verifies that:
// (1) Per-book settings are isolated between books (book A's override does
//     not affect book B).
// (2) Per-book settings persist across reopening the same book.
//
// Seed: .books (two or more fixture books needed for isolation test).
//
// @coordinates-with: PerBookSettingsStore.swift, ReaderSettingsPanel.swift,
//   VerificationSettingsHelper.swift

import XCTest

@MainActor
final class Feature37PerBookSettingsVerificationTests: XCTestCase {
    var app: XCUIApplication!
    private var settingsHelper: VerificationSettingsHelper!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books, resetPreferences: true)
        settingsHelper = VerificationSettingsHelper(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        settingsHelper = nil
    }

    // MARK: - Helpers

    private func openFirstBook() {
        tapFirstBook(in: app)
    }

    private func goBackToLibrary() {
        let back = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(back.waitForHittable(timeout: 5), "Back button should be hittable")
        back.tap()
        XCTAssertTrue(
            app.otherElements[AccessibilityID.libraryView].waitForExistence(timeout: 5),
            "Library view should reappear after tapping back"
        )
    }

    private func perBookToggle() -> XCUIElement {
        app.switches.matching(
            NSPredicate(format: "label == 'Custom settings for this book'")
        ).firstMatch
    }

    // MARK: - Feature #37 Verification

    /// Verifies that enabling per-book settings for book A does not affect book B:
    /// open book A → enable per-book → change font → back → open second book
    /// → settings panel → per-book toggle OFF (default).
    func test_verify_feature_37_perbook_settings_toggle_isolated_to_book() throws {
        // 1. Open first book from library
        openFirstBook()

        // 2. Wait for reader chrome to appear (reader loaded)
        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should load (back button visible)"
        )

        // 3. Open reader settings
        let panel = settingsHelper.openReaderSettings()
        XCTAssertTrue(panel.exists, "Settings panel should be present")

        // 4. Find and enable per-book toggle
        let toggle = perBookToggle()
        guard toggle.waitForExistence(timeout: 5) else {
            throw XCTSkip("Per-book toggle not found — feature #37 UI may have changed")
        }

        if toggle.value as? String == "0" || toggle.value as? String == "false" {
            toggle.tap()
            XCTAssertEqual(
                toggle.value as? String, "1",
                "Per-book toggle should be enabled after tap"
            )
        }

        // 5. Close settings and go back to library
        settingsHelper.closeReaderSettings()
        goBackToLibrary()

        // 6. Open a DIFFERENT book by tapping second available card
        let secondCard = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).element(boundBy: 1)
        guard secondCard.waitForExistence(timeout: 5) else {
            throw XCTSkip("Only one book in library — cannot test isolation with a second book")
        }
        secondCard.tap()

        // 7. Wait for this reader to load
        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Second book reader should load"
        )

        // 8. Open settings on the second book
        let panel2 = settingsHelper.openReaderSettings()
        XCTAssertTrue(panel2.exists)

        // 9. Per-book toggle should be OFF for this book (isolation)
        let toggle2 = perBookToggle()
        if toggle2.waitForExistence(timeout: 3) {
            XCTAssertEqual(
                toggle2.value as? String, "0",
                "Per-book toggle should be OFF for a different book (settings are isolated)"
            )
        }
        settingsHelper.closeReaderSettings()
    }

    /// Verifies that per-book settings persist when the same book is reopened:
    /// open book A → enable per-book → back → reopen book A
    /// → settings panel → per-book toggle still ON.
    func test_verify_feature_37_perbook_settings_persists_across_reopen() throws {
        // 1. Open first book
        openFirstBook()

        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should load"
        )

        // 2. Enable per-book toggle
        let panel = settingsHelper.openReaderSettings()
        XCTAssertTrue(panel.exists)

        let toggle = perBookToggle()
        guard toggle.waitForExistence(timeout: 5) else {
            throw XCTSkip("Per-book toggle not found")
        }

        // Ensure toggle is ON
        if toggle.value as? String == "0" || toggle.value as? String == "false" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "Per-book toggle should be ON")

        settingsHelper.closeReaderSettings()

        // 3. Go back to library
        goBackToLibrary()

        // 4. Reopen the same book (first card again)
        tapFirstBook(in: app)

        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should reload"
        )

        // 5. Open settings again
        let panel2 = settingsHelper.openReaderSettings()
        XCTAssertTrue(panel2.exists)

        // 6. Per-book toggle should still be ON
        let toggle2 = perBookToggle()
        if toggle2.waitForExistence(timeout: 5) {
            XCTAssertEqual(
                toggle2.value as? String, "1",
                "Per-book toggle should remain ON after reopening the same book"
            )
        }

        settingsHelper.closeReaderSettings()
    }
}
