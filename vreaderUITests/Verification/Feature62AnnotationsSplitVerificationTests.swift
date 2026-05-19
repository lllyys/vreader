// Purpose: CU-free Gate-5 verification suite for feature #62 — the
// annotations-panel split. Confirms the unified 4-tab
// `AnnotationsPanelView` is replaced by two sheets routed from the
// reader bottom chrome:
//   - the Contents button opens `TOCSheet` — book-titled, Contents +
//     Bookmarks tabs.
//   - the Notes button opens `HighlightsSheet` — titled "Annotations",
//     the four All/Highlights/Notes/Bookmarks filter chips + the
//     designed Share/export button.
// It also verifies the two are distinct, mutually-exclusive sheets and
// that each surface shows the designed `AnnotationsEmptyStateView`.
//
// Seed: `.epubFixture` (`mini-epub3.epub`) — a real, openable EPUB.
// The reader bottom chrome (the Contents / Notes buttons) only renders
// once a book's content actually loads, so the `.books` seed (whose
// fixtures are metadata-only — no backing file, "The file could not be
// found"; Bug #209 / #214) cannot reach the chrome. `.epubFixture`
// opens a real reader. The fixture carries no annotations, so this
// exercises the structural split + the designed empty states; the
// annotation-populated card-stream rendering is unit-verified by
// `HighlightsSheetTests` / `AnnotationStreamBuilderTests`.
//
// Pattern notes (mirrors `Feature63SearchPanelVerificationTests`):
//   - Drives the app through the XCUITest accessibility API only — no
//     computer-use, no DebugBridge `open` URL (which cannot reliably
//     commit a NavigationStack push in a headless `simctl openurl`
//     session).
//   - `openSeededBook` retries the card tap — a first tap can land
//     before the library `LazyVGrid` finishes its initial layout pass.
//   - The reader chrome auto-hides; a content tap (`app.tap()`) reveals
//     it so the Contents / Notes buttons become hittable.
//   - `TOCSheet` / `HighlightsSheet` set `.accessibilityElement(children:
//     .contain)` on their root, so the sheet container resolves via
//     `otherElements`; tabs / chips / the export button are `Button`s
//     queried at app level by that type (a SwiftUI container identifier
//     is not a reliable nested query handle — Bug #214 / #223 lesson).
//
// @coordinates-with: TOCSheet.swift, HighlightsSheet.swift,
//   AnnotationsSheetRoute.swift, ReaderContainerView.swift,
//   AnnotationsEmptyStateView.swift, TestSeeder.swift, LaunchHelper.swift

import XCTest

@MainActor
final class Feature62AnnotationsSplitVerificationTests: XCTestCase {

    // MARK: - Test lifecycle

    /// Launches with the `.epubFixture` seed (`mini-epub3.epub` — a real,
    /// openable EPUB) and `--reset-preferences` so the run starts from a
    /// known UserDefaults state (Bug #152).
    private func launch() -> XCUIApplication {
        launchApp(seed: .epubFixture, resetPreferences: true)
    }

    // MARK: - Helpers

    /// Opens the seeded EPUB book and waits for the reader chrome. The
    /// card tap is retried because a first tap can land before the
    /// library `LazyVGrid` finishes its initial layout pass — the same
    /// timing race handled in `Feature63SearchPanelVerificationTests`.
    @discardableResult
    private func openSeededBook(in app: XCUIApplication) -> Bool {
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        ).firstMatch
        let backButton = app.buttons[AccessibilityID.readerBackButton]

        for _ in 0..<3 {
            if card.waitForExistence(timeout: 15) {
                if card.waitForHittable(timeout: 8) || card.exists { card.tap() }
            } else if row.waitForExistence(timeout: 3) {
                if row.waitForHittable(timeout: 8) || row.exists { row.tap() }
            }
            if backButton.waitForExistence(timeout: 20) { return true }
        }
        return false
    }

    /// Makes the reader bottom chrome visible. The chrome auto-hides on
    /// load; a content tap toggles it back on so a bottom-chrome button
    /// becomes hittable. Mirrors `openSearchSheet`'s reveal in the
    /// feature-#63 verification suite.
    private func ensureChromeVisible(
        in app: XCUIApplication,
        anchorButton id: String
    ) -> XCUIElement {
        let button = app.buttons[id]
        if !button.waitForExistence(timeout: 3) {
            app.tap()
        }
        return button
    }

    /// Opens `TOCSheet` via the Contents bottom-chrome button.
    @discardableResult
    private func openTOCSheet(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let contents = ensureChromeVisible(
            in: app, anchorButton: AccessibilityID.readerContentsButton
        )
        XCTAssertTrue(
            contents.waitForHittable(timeout: 10),
            "Reader Contents button should be hittable (chrome visible)",
            file: file, line: line
        )
        contents.tap()

        let sheet = app.otherElements[AccessibilityID.tocSheet]
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "The Contents button should open TOCSheet",
            file: file, line: line
        )
        return sheet
    }

    /// Opens `HighlightsSheet` via the Notes bottom-chrome button.
    @discardableResult
    private func openHighlightsSheet(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let notes = ensureChromeVisible(
            in: app, anchorButton: AccessibilityID.readerAnnotationsButton
        )
        XCTAssertTrue(
            notes.waitForHittable(timeout: 10),
            "Reader Notes button should be hittable (chrome visible)",
            file: file, line: line
        )
        notes.tap()

        let sheet = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "The Notes button should open HighlightsSheet",
            file: file, line: line
        )
        return sheet
    }

    // MARK: - The split — Contents → TOCSheet

    /// Acceptance: the bottom-chrome Contents button opens `TOCSheet`,
    /// NOT the unified panel. The sheet carries the Contents + Bookmarks
    /// tabs.
    func test_verify_feature_62_contents_button_opens_toc_sheet() throws {
        let app = launch()
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )
        openTOCSheet(in: app)

        // The Contents + Bookmarks tabs are present (Button type — the
        // sheet's `.contain` propagates the identifier onto the leaf).
        XCTAssertTrue(
            app.buttons[AccessibilityID.tocSheetContentsTab].waitForExistence(timeout: 5),
            "TOCSheet should carry the Contents tab"
        )
        XCTAssertTrue(
            app.buttons[AccessibilityID.tocSheetBookmarksTab].exists,
            "TOCSheet should carry the Bookmarks tab"
        )
    }

    // MARK: - The split — Notes → HighlightsSheet

    /// Acceptance: the bottom-chrome Notes button opens `HighlightsSheet`,
    /// titled "Annotations", with the four filter chips and the designed
    /// export button.
    func test_verify_feature_62_notes_button_opens_highlights_sheet() throws {
        let app = launch()
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )
        openHighlightsSheet(in: app)

        // All four filter chips are present.
        for chip in [
            AccessibilityID.highlightsSheetFilterAll,
            AccessibilityID.highlightsSheetFilterHighlights,
            AccessibilityID.highlightsSheetFilterNotes,
            AccessibilityID.highlightsSheetFilterBookmarks,
        ] {
            XCTAssertTrue(
                app.buttons[chip].waitForExistence(timeout: 5),
                "HighlightsSheet should carry the \(chip) filter chip"
            )
        }

        // The designed Share/export button is present in the trailing slot.
        XCTAssertTrue(
            app.buttons[AccessibilityID.annotationsExportButton].waitForExistence(timeout: 5),
            "HighlightsSheet should carry the export button"
        )
    }

    // MARK: - The two sheets are distinct surfaces

    /// Acceptance: Contents and Notes open two DIFFERENT sheets — the
    /// design's whole point (one honest title per job-to-be-done). After
    /// dismissing one and opening the other, the other sheet's identity
    /// resolves and the first is gone.
    func test_verify_feature_62_contents_and_notes_are_distinct_sheets() throws {
        let app = launch()
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )

        // Open TOCSheet, confirm, dismiss.
        let tocSheet = openTOCSheet(in: app)
        tocSheet.swipeDown()
        _ = tocSheet.waitForDisappearance(timeout: 5)

        // Open HighlightsSheet — a DIFFERENT sheet identity.
        openHighlightsSheet(in: app)
        // TOCSheet must NOT be present (the two are mutually exclusive).
        XCTAssertFalse(
            app.otherElements[AccessibilityID.tocSheet].exists,
            "TOCSheet must not be present while HighlightsSheet is open"
        )
    }

    // MARK: - Empty states (WI-2 designed empty states)

    /// Acceptance: with no annotations (the `mini-epub3` fixture carries
    /// none) `HighlightsSheet` shows the designed `AnnotationsEmptyStateView`,
    /// not a `ContentUnavailableView`.
    func test_verify_feature_62_empty_states_resolve() throws {
        let app = launch()
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )
        openHighlightsSheet(in: app)

        // HighlightsSheet — the All filter empty state. `AnnotationsEmptyStateView`
        // carries its identifier on a `.accessibilityElement(children:
        // .contain)` container, which surfaces as an `otherElements`
        // element — query by that type.
        XCTAssertTrue(
            app.otherElements[AccessibilityID.highlightsEmptyState]
                .waitForExistence(timeout: 5),
            "HighlightsSheet All filter should show the designed empty state"
        )

        // The Bookmarks chip's empty state.
        app.buttons[AccessibilityID.highlightsSheetFilterBookmarks].tap()
        XCTAssertTrue(
            app.otherElements[AccessibilityID.highlightsBookmarksEmptyState]
                .waitForExistence(timeout: 5),
            "HighlightsSheet Bookmarks filter should show the bookmarks empty state"
        )
    }
}
