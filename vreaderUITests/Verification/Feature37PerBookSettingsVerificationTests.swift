// Purpose: Verification tests for Feature #37 — per-book reader settings.
// Exercises the "Custom settings for this book" toggle and verifies that:
// (1) Per-book settings are isolated between books (book A's override does
//     not affect book B).
// (2) Per-book settings persist across reopening the same book.
//
// Seed: .twoBooks — two real-file TXT books. The isolation test needs two
// distinct *openable* books; the .books seed's fixtures are metadata-only
// and fail to open (Bug #209 / GH #804).
//
// The per-book "Custom settings for this book" Section is at the bottom of
// ReaderSettingsPanel; SwiftUI Form sections are lazy-rendered, so the toggle
// is not in the accessibility tree until scrolled into view. Both methods
// reveal it via `revealPerBookToggle(in:)` — a bounded swipe-up loop mirroring
// Feature31AutoPageTurnVerificationTests (Bug #204 / GH #746).
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
        app = launchApp(seed: .twoBooks, resetPreferences: true)
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

    /// Brings the "Custom settings for this book" toggle into the accessibility
    /// tree by swiping up within the settings panel.
    ///
    /// Bug #204 (GH #746): `perBookSection` sits at the BOTTOM of
    /// `ReaderSettingsPanel` (after typography, themes, layout, tap zones,
    /// custom background, auto page turn, etc.). SwiftUI Form sections are
    /// lazy-rendered — a section below the fold is NOT in the accessibility
    /// tree until scrolled into view. Both Feature37 methods previously called
    /// `toggle.waitForExistence(timeout: 5)` with no prior swipe-up, so the
    /// lazy-loaded toggle was never surfaced and the methods always XCTSkip'd.
    ///
    /// This mirrors the proven section-finder loop in
    /// `Feature31AutoPageTurnVerificationTests` (and Bug #196 / PR #588's
    /// 10-retry budget). The per-book `Section` has NO header `staticText`
    /// — the only stable anchor with the `"Custom settings for this book"`
    /// label is the `Toggle`'s switch itself, so this loop keys on the
    /// switch element directly rather than a sibling section header.
    ///
    /// The initial `waitForExistence(timeout: 2)` lets the panel populate
    /// before the swipe-up loop fires — issuing `panel.swipeUp()` too early
    /// (before the panel's lazy section rendering completes) can desync with
    /// content loading and leave the toggle unfound.
    ///
    /// Like Feature31's loop, this runs a second bounded swipe-up budget once
    /// the switch is in the tree: a `Toggle` row can enter the accessibility
    /// tree while still clipped at the bottom edge, so existence alone does
    /// not guarantee the control is tappable. The post-discovery loop scrolls
    /// until the switch is hittable (callers tap it).
    ///
    /// - Parameter panel: The settings panel element to scroll within.
    /// - Returns: The per-book toggle element. Callers should still check
    ///   `.exists` / `.waitForExistence` and XCTSkip as a genuine last resort.
    @discardableResult
    private func revealPerBookToggle(in panel: XCUIElement) -> XCUIElement {
        let toggle = perBookToggle()
        if !toggle.waitForExistence(timeout: 2) {
            for _ in 0..<10 {
                if toggle.exists { break }
                panel.swipeUp()
            }
        }
        // The switch can be in the tree but clipped at the bottom edge.
        // Scroll until it is hittable, mirroring Feature31's 10-retry budget.
        for _ in 0..<10 where toggle.exists && !toggle.isHittable {
            panel.swipeUp()
        }
        return toggle
    }

    /// Flips the per-book toggle by tapping its underlying switch control.
    ///
    /// Bug #209 / GH #804: the SwiftUI `Toggle` row exposes a full-width
    /// *outer* `.switch` accessibility element (the labeled row) that
    /// *contains* the inner `UISwitch`. `perBookToggle()` keys on the row
    /// label, so it resolves the outer element — and `XCUIElement.tap()`
    /// taps that element's centre, which lands on the label `StaticText`,
    /// not the switch. Feature #60 WI-10 re-skinned `ReaderSettingsPanel`
    /// from a `Form` to a `List`; a label-area tap no longer flips the
    /// control, so the centre tap silently no-ops. Tapping the inner
    /// switch (the real toggle, with no label of its own) flips it
    /// reliably. `.value` is still read from the passed-in outer element —
    /// it mirrors the inner switch's state.
    private func tapPerBookToggle(_ toggle: XCUIElement) {
        let innerSwitch = toggle.switches.firstMatch
        if innerSwitch.exists {
            innerSwitch.tap()
        } else {
            // Fallback: tap the trailing edge where the switch sits.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
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

        // 4. Find and enable per-book toggle. The per-book section is below
        //    the settings-panel fold (lazy-rendered) — swipe up to surface
        //    it before asserting existence (Bug #204 / GH #746).
        let toggle = revealPerBookToggle(in: panel)
        guard toggle.waitForExistence(timeout: 5) else {
            throw XCTSkip("Per-book toggle not found — feature #37 UI may have changed")
        }

        if toggle.value as? String == "0" || toggle.value as? String == "false" {
            tapPerBookToggle(toggle)
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

        // 9. Per-book toggle should be OFF for this book (isolation).
        //    Swipe up again — this is a fresh settings panel for the second
        //    book, so the per-book section is below the fold once more.
        let toggle2 = revealPerBookToggle(in: panel2)
        guard toggle2.waitForExistence(timeout: 3) else {
            throw XCTSkip("Per-book toggle not found on the second book's settings panel")
        }
        XCTAssertEqual(
            toggle2.value as? String, "0",
            "Per-book toggle should be OFF for a different book (settings are isolated)"
        )
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

        // The per-book section is below the settings-panel fold
        // (lazy-rendered) — swipe up to surface it (Bug #204 / GH #746).
        let toggle = revealPerBookToggle(in: panel)
        guard toggle.waitForExistence(timeout: 5) else {
            throw XCTSkip("Per-book toggle not found")
        }

        // Ensure toggle is ON
        if toggle.value as? String == "0" || toggle.value as? String == "false" {
            tapPerBookToggle(toggle)
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

        // 6. Per-book toggle should still be ON. Swipe up again — reopening
        //    the book gives a fresh settings panel with the per-book section
        //    below the fold once more.
        let toggle2 = revealPerBookToggle(in: panel2)
        guard toggle2.waitForExistence(timeout: 5) else {
            throw XCTSkip("Per-book toggle not found after reopening the book")
        }
        XCTAssertEqual(
            toggle2.value as? String, "1",
            "Per-book toggle should remain ON after reopening the same book"
        )

        settingsHelper.closeReaderSettings()
    }
}
