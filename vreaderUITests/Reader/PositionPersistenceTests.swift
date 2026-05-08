// Purpose: UI tests for reading position persistence (Bug #24).
// Verifies that the reading position is saved when navigating away
// and restored when reopening the same book.
//
// Uses --seed-position-test to create a real TXT file with scrollable content.
//
// @coordinates-with: TXTReaderContainerView.swift, TXTReaderViewModel.swift,
//   TestSeeder.swift, LaunchHelper.swift

import XCTest

@MainActor
final class PositionPersistenceTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .positionTest)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Returns the `TextView` element carrying the given accessibility
    /// identifier. SwiftUI's `.accessibilityIdentifier` modifier on
    /// `TXTReaderContainerView`'s body propagates to the underlying
    /// UIKit `UITextView` AND cascades to every descendant that lacks
    /// its own identifier (the chrome's Slider, StaticText, Buttons
    /// all carry `txtReaderContainer`). Inner content modifiers like
    /// `.accessibilityIdentifier("txtReaderContent")` are flattened
    /// away in iOS 26.4 SwiftUI, so they don't surface in the
    /// accessibility tree.
    ///
    /// We narrow the query to `textViews` because the host
    /// `UITextView` is the deterministic, correct match for the
    /// container — its bounds cover the full reader pane and its
    /// `value` is what carries `restoredOffset:N`. A bare
    /// `descendants(matching: .any).firstMatch` could non-
    /// deterministically pick a Slider/Button child, which would
    /// make `container.value` and `container.swipeUp()` flaky.
    ///
    /// (Bug #150 + Codex audit round 1)
    private func textViewContainer(withID id: String) -> XCUIElement {
        app.textViews.matching(identifier: id).firstMatch
    }

    // MARK: - Position Persistence

    func testTXTReaderLoadsContent() {
        tapBook(titled: "Position Test Book", in: app)

        // Wait for the reader container to appear.
        let container = textViewContainer(withID: AccessibilityID.txtReaderContainer)
        XCTAssertTrue(
            container.waitForExistence(timeout: 10),
            "TXT reader container should appear"
        )

        // Wait for content to load (loading spinner disappears).
        let loading = app.descendants(matching: .any).matching(identifier: "txtReaderLoading").firstMatch
        if loading.exists {
            XCTAssertTrue(
                loading.waitForDisappearance(timeout: 10),
                "Loading indicator should disappear once content loads"
            )
        }

        // The container's accessibility value carries `restoredOffset:N`
        // ONLY after `.task` has set `initialRestoreOffset`. The
        // sentinel `restoredOffset:none` means the body re-rendered
        // before `initialRestoreOffset` was assigned (no real position
        // payload yet), so accept only a real numeric offset (which
        // includes `0` for a fresh book — that's still a valid
        // restored-from-zero state). Codex audit round 1 explicitly
        // called out the previous `contains("restoredOffset:")`-only
        // check as too weak.
        let value = container.value as? String ?? ""
        XCTAssertTrue(
            value.contains("restoredOffset:") && !value.contains("restoredOffset:none"),
            "Container value should expose a real restoredOffset (numeric or 0, never 'none') once content has loaded; got '\(value)'"
        )
    }

    func testPositionSavedOnNavigateBack() {
        tapBook(titled: "Position Test Book", in: app)

        // Wait for content to load.
        let container = textViewContainer(withID: AccessibilityID.txtReaderContainer)
        XCTAssertTrue(container.waitForExistence(timeout: 10))

        // The container element IS the scrollable UITextView (full-screen
        // bounds), so we swipe directly on it to scroll the document.
        for _ in 0..<5 {
            container.swipeUp()
        }

        // Wait for debounce save to fire (2s debounce + margin).
        sleep(3)

        // Navigate back to library.
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        // Verify library appears.
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library should appear after navigating back"
        )

        // Reopen the same book.
        tapBook(titled: "Position Test Book", in: app)

        // Wait for container to appear and check restore offset.
        let containerAgain = textViewContainer(withID: AccessibilityID.txtReaderContainer)
        XCTAssertTrue(
            containerAgain.waitForExistence(timeout: 10),
            "TXT reader should reopen"
        )

        // Check the accessibility value for restored offset.
        // The container exposes "restoredOffset:N" where N > 0 means position was restored.
        let value = containerAgain.value as? String ?? ""
        XCTAssertTrue(
            value.contains("restoredOffset:") && !value.contains("restoredOffset:0")
                && !value.contains("restoredOffset:none"),
            "Position should be restored to a non-zero offset, got: \(value)"
        )
    }

    func testPositionSurvivesAppRelaunch() {
        // Bug #151 (GH #423) FIXED: when `--uitesting` is set, the
        // SwiftData model store now uses disk-backed configuration for
        // `.positionTest` and `.keepExisting` seeds (the two seeds that
        // exercise terminate-then-relaunch persistence). Other seeds
        // (`.empty`, `.books`, `.corruptDB`) keep the in-memory
        // configuration so test methods stay isolated. See
        // VReaderApp.swift::init() — `needsDiskBackedStore` branch.
        tapBook(titled: "Position Test Book", in: app)

        // Wait for content to load.
        let container = textViewContainer(withID: AccessibilityID.txtReaderContainer)
        XCTAssertTrue(container.waitForExistence(timeout: 10))

        // Scroll directly on the container (it's the UITextView).
        for _ in 0..<5 {
            container.swipeUp()
        }

        // Wait for debounce save.
        sleep(3)

        // Navigate back to ensure close() saves position.
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Relaunch the app (simulates force-kill + cold start).
        // Use .keepExisting to preserve the database (including saved position).
        app.terminate()
        app = launchApp(seed: .keepExisting)

        // Reopen the book.
        tapBook(titled: "Position Test Book", in: app)

        let containerAfterRelaunch = textViewContainer(withID: AccessibilityID.txtReaderContainer)
        XCTAssertTrue(containerAfterRelaunch.waitForExistence(timeout: 10))

        // Verify position was restored.
        let value = containerAfterRelaunch.value as? String ?? ""
        XCTAssertTrue(
            value.contains("restoredOffset:") && !value.contains("restoredOffset:0")
                && !value.contains("restoredOffset:none"),
            "Position should be restored after app relaunch, got: \(value)"
        )
    }
}
