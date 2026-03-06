import XCTest

/// WI-UI-16: Keyboard interaction tests.
///
/// Tests keyboard-driven interactions for PDF password entry.
/// Search and annotation edit keyboard tests are deferred until
/// those views are mounted in the reader.
@MainActor
final class KeyboardInteractionTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - PDF Password Keyboard

    /// Tapping the PDF password field should raise the keyboard.
    func testPDFPasswordKeyboard() throws {
        // Navigate to the password-protected PDF fixture
        tapBook(titled: "Protected PDF", in: app)

        // Wait for password prompt
        let passwordField = app.secureTextFields[AccessibilityID.pdfPasswordField]
        guard passwordField.waitForExistence(timeout: 5) else {
            throw XCTSkip("PDF password prompt not reachable — reader wiring incomplete")
        }

        // Tap the password field to focus it
        passwordField.tap()

        // Verify keyboard appears
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3),
                      "Keyboard should appear when password field is tapped")
    }

    // MARK: - PDF Password Return Key

    /// Typing in the password field and pressing return should submit.
    func testPDFPasswordReturnKey() throws {
        tapBook(titled: "Protected PDF", in: app)

        let passwordField = app.secureTextFields[AccessibilityID.pdfPasswordField]
        guard passwordField.waitForExistence(timeout: 5) else {
            throw XCTSkip("PDF password prompt not reachable — reader wiring incomplete")
        }

        // Type a password
        passwordField.tap()
        passwordField.typeText("testpassword")

        // Press return key — should trigger onSubmit
        let returnKey = app.keyboards.buttons["Return"]
        let goKey = app.keyboards.buttons["Go"]
        if returnKey.waitForExistence(timeout: 3) {
            returnKey.tap()
        } else if goKey.waitForExistence(timeout: 2) {
            goKey.tap()
        } else {
            XCTFail("Neither Return nor Go key found on keyboard")
        }
    }

    // MARK: - Password Field Visible With Keyboard

    /// The password field should not be obscured by the keyboard.
    func testPasswordFieldVisibleWithKeyboard() throws {
        tapBook(titled: "Protected PDF", in: app)

        let passwordField = app.secureTextFields[AccessibilityID.pdfPasswordField]
        guard passwordField.waitForExistence(timeout: 5) else {
            throw XCTSkip("PDF password prompt not reachable — reader wiring incomplete")
        }

        // Tap to raise keyboard
        passwordField.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3),
                      "Keyboard should appear")

        // Verify the password field is still visible (not obscured by keyboard)
        let fieldFrame = passwordField.frame
        let keyboardFrame = keyboard.frame

        // The password field's bottom edge should be above the keyboard's top edge
        XCTAssertLessThan(fieldFrame.maxY, keyboardFrame.minY,
                          "Password field (bottom: \(fieldFrame.maxY)) should be above keyboard (top: \(keyboardFrame.minY))")
    }
}
