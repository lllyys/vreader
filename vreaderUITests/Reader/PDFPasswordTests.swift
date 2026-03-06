// WI-UI-8: PDF Password Prompt — UI Elements and Interaction
//
// Tests verify the PDF password prompt view's UI elements, button states,
// and accessibility.
//
// NOTE: The password prompt is a standalone view (PDFPasswordPromptView).
// In the current app state, it is only shown when a PDFReaderContainerView
// enters the .password state, which requires a real encrypted PDF file URL.
// These tests assume direct access to the password prompt is possible
// (e.g., via a test-only launch argument or a seeded encrypted PDF).
//
// TODO: When the reader navigation pipeline is complete and a password-protected
// PDF fixture is wired, remove the skip guards and run these tests end-to-end.

import XCTest

@MainActor
final class PDFPasswordTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Attempts to navigate to the password-protected PDF.
    /// Throws XCTSkip if the prompt is not reachable in the current app state.
    private func navigateToPasswordProtectedPDF() throws {
        tapBook(titled: "Protected PDF", in: app)

        let prompt = app.otherElements[AccessibilityID.pdfPasswordPrompt]
        if !prompt.waitForExistence(timeout: 5) {
            throw XCTSkip("PDF password prompt not reachable in placeholder state")
        }
    }

    // MARK: - Tests

    func testPasswordPromptShowsAllElements() throws {
        try navigateToPasswordProtectedPDF()

        let passwordField = app.secureTextFields[AccessibilityID.pdfPasswordField]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 3), "Password field should exist")

        let cancelButton = app.buttons[AccessibilityID.pdfPasswordCancel]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3), "Cancel button should exist")

        let unlockButton = app.buttons[AccessibilityID.pdfPasswordSubmit]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 3), "Unlock button should exist")

        // Lock icon and text
        let explanationText = app.staticTexts["This PDF is password protected"]
        XCTAssertTrue(explanationText.waitForExistence(timeout: 3), "Explanation text should exist")
    }

    func testUnlockButtonDisabledWhenEmpty() throws {
        try navigateToPasswordProtectedPDF()

        let unlockButton = app.buttons[AccessibilityID.pdfPasswordSubmit]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 3))
        XCTAssertFalse(
            unlockButton.isEnabled,
            "Unlock button should be disabled when password field is empty"
        )
    }

    func testUnlockButtonEnabledAfterTyping() throws {
        try navigateToPasswordProtectedPDF()

        let passwordField = app.secureTextFields[AccessibilityID.pdfPasswordField]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 3))
        passwordField.tap()
        passwordField.typeText("test123")

        let unlockButton = app.buttons[AccessibilityID.pdfPasswordSubmit]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 3))
        XCTAssertTrue(
            unlockButton.isEnabled,
            "Unlock button should be enabled after typing a password"
        )
    }

    func testCancelButtonIsHittable() throws {
        try navigateToPasswordProtectedPDF()

        let cancelButton = app.buttons[AccessibilityID.pdfPasswordCancel]
        XCTAssertTrue(
            cancelButton.waitForHittable(timeout: 3),
            "Cancel button should be hittable"
        )
    }

    func testPasswordFieldIsFocusable() throws {
        try navigateToPasswordProtectedPDF()

        let passwordField = app.secureTextFields[AccessibilityID.pdfPasswordField]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 3))
        passwordField.tap()

        // After tapping, the keyboard should appear
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 3),
            "Keyboard should appear when password field is focused"
        )
    }

    func testPasswordPromptTouchTargets() throws {
        try navigateToPasswordProtectedPDF()

        let cancelButton = app.buttons[AccessibilityID.pdfPasswordCancel]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(
            cancelButton.frame.height, 44,
            "Cancel button should meet 44pt minimum touch target"
        )

        let unlockButton = app.buttons[AccessibilityID.pdfPasswordSubmit]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(
            unlockButton.frame.height, 44,
            "Unlock button should meet 44pt minimum touch target"
        )
    }

    func testPasswordPromptAccessibilityAudit() throws {
        try navigateToPasswordProtectedPDF()

        auditCurrentScreen(app: app)
    }
}
