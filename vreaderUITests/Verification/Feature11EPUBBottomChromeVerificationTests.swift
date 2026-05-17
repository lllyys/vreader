// Purpose: Regression verification for Bug #214 / GH #834 — the EPUB
// reader-container `.accessibilityIdentifier("epubReaderContainer")` must
// NOT propagate onto and clobber `ReaderBottomChrome`'s toolbar button
// identifiers.
//
// Bug #214 is the same root cause as Bug #209 / GH #804 Cause B (fixed
// there for TXT/MDReaderContainerView): a container `.accessibilityIdentifier`
// applied at `body` level propagates onto every descendant accessibility
// element. Applied to the whole EPUB `body` ZStack it also reached the
// `ReaderBottomChrome` sibling, so `app.buttons["readerDisplayButton"]` /
// `["readerNotesButton"]` resolved to `epubReaderContainer` instead. The
// fix scopes the identifier to the content `Group`.
//
// Why a dedicated test: the existing Verification plan never opens an
// EPUB and then resolves the reader bottom-chrome buttons —
// Feature21/28/37 use TXT books and Feature11's highlight tests stop at
// the WebView selection menu. So the clobber was real but uncaught.
//
// Seed: `.epubFixture` — the bundled `mini-epub3.epub` seeded in-process
// as a single real, openable EPUB (the `.books` launch seed only carries
// metadata-only EPUB records with no backing file, which never open —
// Bug #209 Cause A). This is the EPUB analogue of `.twoBooks`.
//
// @coordinates-with: EPUBReaderContainerView.swift, ReaderBottomChrome.swift,
//   ReaderChromeButton.swift, TestSeeder.swift (seedMiniEPUB)

import XCTest

@MainActor
final class Feature11EPUBBottomChromeVerificationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // `.epubFixture` seeds the bundled mini-epub3.epub in-process as a
        // single real, openable EPUB book.
        app = launchApp(seed: .epubFixture, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Opens the seeded EPUB book and waits for the EPUB reader to load.
    /// Returns `false` if the book card or reader did not appear.
    ///
    /// The `.epubFixture` seed makes the EPUB a guaranteed-openable book,
    /// so a `false` here is a real regression (seed plumbing, launch-arg
    /// handling, or reader navigation) — callers fail hard, they do NOT
    /// `XCTSkip`.
    ///
    /// The card tap is retried: a first tap can land before the library's
    /// LazyVGrid finishes its initial layout pass (the card exists in the
    /// accessibility tree but is not yet hittable / wired to navigation),
    /// so the tap is a no-op and the reader never pushes. Re-tapping a
    /// hittable card recovers that legitimate timing race.
    private func openEPUB() -> Bool {
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        guard card.waitForExistence(timeout: 20) else { return false }

        let backButton = app.buttons[AccessibilityID.readerBackButton]
        // Up to 3 tap attempts — the reader's back button appears as soon
        // as navigation pushes the reader (it is not gated on EPUB parse),
        // so a 20s window per attempt is generous for a cold simulator.
        for _ in 0..<3 {
            if card.waitForHittable(timeout: 8) {
                card.tap()
            } else if card.exists {
                card.tap()
            }
            if backButton.waitForExistence(timeout: 20) {
                return true
            }
        }
        return false
    }

    /// Ensures the reader chrome is visible (the bottom toolbar is hidden
    /// when chrome is toggled off). A content tap toggles chrome.
    private func ensureChromeVisible() {
        let displayButton = app.buttons[AccessibilityID.readerSettingsButton]
        if displayButton.waitForExistence(timeout: 3) { return }
        // Chrome may be hidden — tap the content area to toggle it on.
        app.tap()
        _ = displayButton.waitForExistence(timeout: 5)
    }

    // MARK: - Bug #214 Verification

    /// Bug #214 regression: with an EPUB book open, the reader
    /// bottom-chrome buttons must resolve as `app.buttons` by their own
    /// identifiers. Before the fix, the body-level
    /// `.accessibilityIdentifier("epubReaderContainer")` propagated onto
    /// the `ReaderBottomChrome` descendants, so these queries resolved to
    /// `epubReaderContainer` and the buttons could not be found.
    func test_verify_bug_214_epub_bottom_chrome_buttons_resolve() throws {
        XCTAssertTrue(
            openEPUB(),
            "The seeded mini-epub3 EPUB should open into the reader — " +
            "a failure here is a seed/launch-arg/navigation regression, " +
            "not an environmental skip"
        )
        ensureChromeVisible()

        // The Display button (`readerDisplayButton`) and Notes button
        // (`readerNotesButton`) are the two `ReaderBottomChrome` toolbar
        // buttons Bug #214's clobber broke.
        let displayButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(
            displayButton.waitForExistence(timeout: 10),
            "Bug #214: readerDisplayButton should resolve as a button — " +
            "the epubReaderContainer identifier must not propagate onto " +
            "the ReaderBottomChrome toolbar"
        )

        let notesButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        XCTAssertTrue(
            notesButton.waitForExistence(timeout: 10),
            "Bug #214: readerNotesButton should resolve as a button — " +
            "the epubReaderContainer identifier must not propagate onto " +
            "the ReaderBottomChrome toolbar"
        )

        // The container's own identifier must NOT have leaked onto a
        // button. If it had, a button carrying `epubReaderContainer`
        // would exist — the precise clobber symptom.
        let clobberedButton = app.buttons[AccessibilityID.epubReaderContainer]
        XCTAssertFalse(
            clobberedButton.exists,
            "Bug #214: no button should carry the epubReaderContainer " +
            "identifier — that is the propagation clobber symptom"
        )
    }

    /// Bug #214 follow-through: the Display button still opens the
    /// reader settings panel. Proves the un-clobbered identifier is
    /// wired to a live, tappable control — not just present in the tree.
    func test_verify_bug_214_epub_display_button_opens_settings_panel() throws {
        XCTAssertTrue(
            openEPUB(),
            "The seeded mini-epub3 EPUB should open into the reader — " +
            "a failure here is a seed/launch-arg/navigation regression, " +
            "not an environmental skip"
        )
        ensureChromeVisible()

        let displayButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(
            displayButton.waitForHittable(timeout: 10),
            "Bug #214: readerDisplayButton should be hittable on an open EPUB"
        )
        displayButton.tap()

        let panel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "Tapping the EPUB reader Display button should open the " +
            "reader settings panel"
        )
    }
}
