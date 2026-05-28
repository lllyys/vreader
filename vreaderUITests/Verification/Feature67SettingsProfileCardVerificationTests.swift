// Purpose: CU-free Gate-5b verification suite for Feature #67 — "Settings
// profile-header card + Stats entry point" (+ WI-5/WI-6 AI-group restyle).
//
// Feature #67 added the design's `ProfileCardLibrary` header card to the top
// of the Settings sheet (three-book-spine glyph, "Your library" serif-italic
// header, a "N books · Nh read this month" subline, and a trailing pill
// "Stats" button), restyled the section rows to the design's colored-icon
// `SettingsIconRow`, and (WI-6, design #1068 Variant A) restyled the AI group
// so the AI Provider + Allow-AI-data-sharing rows are shown only when the
// master "Enable AI Assistant" toggle is on.
//
// This suite drives the app entirely through the XCUITest accessibility API
// (element queries + synthesized taps) — it needs NO computer-use and does
// NOT depend on the DebugBridge `present` URL (which cannot be issued from the
// XCUITest sandbox; Bug #1054). It covers the feature's STRUCTURAL +
// BEHAVIORAL acceptance criteria:
//
//   - Criterion 1 ("profile-header card reachable from Settings"): open
//     Settings → the card's "Your library" header, the "… read this month"
//     subline, and the trailing `settingsProfileStatsButton` pill all exist.
//   - Criterion 2 ("Stats entry point → reading dashboard"): tapping the
//     Stats pill presents feature #58's `ReadingDashboardView`
//     (`readingDashboardView`). This also exercises the cross-feature
//     hand-off (the `.openReadingStatsRequested` notification → presenter →
//     dashboard sheet) end-to-end.
//   - Criterion 3 (WI-6 AI group — Variant A collapse): the master `aiToggle`
//     is always present; the `aiProvidersNavLink` + `consentToggle` rows are
//     present ONLY when AI is enabled, and collapse away when it is disabled.
//
// Out of scope (recorded in the evidence file):
//   - PURE VISUAL fidelity of the card / rows (exact colored-tile fills, the
//     14pt card radius, the three-book-spine glyph geometry) — pixel-level
//     design match is covered by the committed Gate-5a screenshots
//     (`dev-docs/verification/artifacts/feature-67-wi6-*-20260521.png`) and by
//     the unit-level composition/snapshot tests (`SettingsProfileCard`
//     `*ForTesting` seams, `SheetReSkinSnapshotTests`, `SettingsRowPaletteTests`,
//     `AISettingsSectionRestyleTests`). XCUITest asserts presence + behavior,
//     not pixels. The accepted L1 cosmetic-radius delta is non-blocking.
//
// @coordinates-with: SettingsView.swift, SettingsProfileCard.swift,
//   SettingsView+StatsSheet.swift, AISettingsSection.swift,
//   ReadingDashboardView.swift, TestConstants.swift (AccessibilityID)

import XCTest

@MainActor
final class Feature67SettingsProfileCardVerificationTests: XCTestCase {

    override func setUpWithError() throws {
        // Stop at the first failed assertion so a root-cause failure (e.g.
        // "Settings won't open") is not buried under follow-on cascades.
        continueAfterFailure = false
    }

    // MARK: - Accessibility handles (string literals — not in AccessibilityID)

    private let profileStatsButtonID = "settingsProfileStatsButton"
    private let readingDashboardID = "readingDashboardView"
    private let aiToggleID = "aiToggle"
    private let aiProvidersNavLinkID = "aiProvidersNavLink"
    private let consentToggleID = "consentToggle"

    /// The card's fixed serif-italic header (library-identity model, #862
    /// Option A — never a person name). See `SettingsProfileCard.headerText`.
    private let profileHeaderText = "Your library"

    // MARK: - Criterion 1 — profile card present with Stats pill

    func test_verify_feature_67_profile_card_present_with_stats_pill() {
        let app = launchApp(seed: .empty, resetPreferences: true)
        openSettings(in: app)

        // The card's serif-italic library header.
        XCTAssertTrue(
            app.staticTexts[profileHeaderText].waitForExistence(timeout: 8),
            "Settings should open with the profile-header card's \"\(profileHeaderText)\" header"
        )

        // The "N books · Nh read this month" subline (book count + month
        // reading-time). With the `.empty` seed it reads "0 books · …", so we
        // assert the stable trailing copy rather than a specific count.
        let subline = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "read this month")
        ).firstMatch
        XCTAssertTrue(
            subline.waitForExistence(timeout: 5),
            "The profile card should render the \"… read this month\" subline"
        )

        // The trailing pill Stats button.
        let stats = app.buttons[profileStatsButtonID]
        XCTAssertTrue(
            stats.waitForExistence(timeout: 5),
            "The profile card should expose the trailing \"Stats\" pill button"
        )
        XCTAssertTrue(stats.isHittable, "The Stats pill should be tappable")
    }

    // MARK: - Criterion 2 — Stats pill opens the reading dashboard (#58)

    func test_verify_feature_67_stats_pill_opens_reading_dashboard() {
        let app = launchApp(seed: .empty, resetPreferences: true)
        openSettings(in: app)

        let stats = app.buttons[profileStatsButtonID]
        XCTAssertTrue(
            stats.waitForExistence(timeout: 8),
            "The profile card's Stats pill should be present before tapping"
        )
        stats.tap()

        // The Stats pill posts `.openReadingStatsRequested`; the presenter
        // builds a `ReadingDashboardViewModel` and presents feature #58's
        // `ReadingDashboardView` as a sheet. Its presence proves the
        // entry-point → dashboard hand-off is wired (no dead control).
        let dashboard = app.otherElements[readingDashboardID]
        let dashboardAny = app.descendants(matching: .any)
            .matching(identifier: readingDashboardID).firstMatch
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 8) || dashboardAny.waitForExistence(timeout: 4),
            "Tapping the Stats pill should present the Reading dashboard "
                + "(feature #58's ReadingDashboardView)"
        )
    }

    // MARK: - Criterion 3 — AI group collapses when AI disabled (WI-6)

    func test_verify_feature_67_ai_group_collapses_when_disabled() {
        let app = launchApp(seed: .empty, resetPreferences: true)
        openSettings(in: app)

        let aiToggle = aiMasterToggle(in: app)
        XCTAssertTrue(
            aiToggle.waitForExistence(timeout: 8),
            "The AI group's master \"Enable AI Assistant\" toggle should always be present"
        )
        scrollToHittable(aiToggle, in: app)

        // Normalize to a known OFF baseline so the assertions are
        // deterministic regardless of the persisted preference.
        if aiToggle.value as? String == "1" {
            aiToggle.tap()
        }

        // OFF → the provider + consent rows are collapsed away (Variant A).
        assertEventuallyAbsent(
            app.descendants(matching: .any).matching(identifier: aiProvidersNavLinkID).firstMatch,
            message: "With AI disabled, the AI Provider row must be hidden (Variant A collapse)"
        )
        assertEventuallyAbsent(
            app.descendants(matching: .any).matching(identifier: consentToggleID).firstMatch,
            message: "With AI disabled, the Allow-AI-data-sharing row must be hidden"
        )

        // ON → both rows appear.
        aiToggle.tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: aiProvidersNavLinkID)
                .firstMatch.waitForExistence(timeout: 5),
            "Enabling AI should reveal the AI Provider row"
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: consentToggleID)
                .firstMatch.waitForExistence(timeout: 5),
            "Enabling AI should reveal the Allow-AI-data-sharing consent row"
        )

        // OFF again → both rows collapse away once more.
        aiToggle.tap()
        assertEventuallyAbsent(
            app.descendants(matching: .any).matching(identifier: aiProvidersNavLinkID).firstMatch,
            message: "Disabling AI again should re-collapse the AI Provider row"
        )
    }

    // MARK: - Helpers

    /// Opens the Settings sheet from the Library toolbar and waits for it.
    private func openSettings(in app: XCUIApplication) {
        let settingsButton = app.buttons[AccessibilityID.settingsToolbarButton]
        XCTAssertTrue(
            settingsButton.waitForExistence(timeout: 12),
            "The Library toolbar should expose the Settings button"
        )
        settingsButton.tap()
        XCTAssertTrue(
            app.otherElements[AccessibilityID.settingsView].waitForExistence(timeout: 8)
                || app.descendants(matching: .any)
                    .matching(identifier: AccessibilityID.settingsView).firstMatch
                    .waitForExistence(timeout: 4),
            "The Settings sheet should present"
        )
    }

    /// The master "Enable AI Assistant" toggle — the `aiToggle` identifier
    /// lands on the underlying switch (`PillSwitch` preserves native switch
    /// a11y). Falls back to an identifier match across any element type if
    /// the switch query misses.
    private func aiMasterToggle(in app: XCUIApplication) -> XCUIElement {
        let asSwitch = app.switches[aiToggleID]
        if asSwitch.exists { return asSwitch }
        return app.descendants(matching: .any).matching(identifier: aiToggleID).firstMatch
    }

    /// Scrolls the Settings form until `element` is hittable (it may sit
    /// below the fold in the scrollable `Form`).
    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    /// Asserts that `element` becomes (or stays) absent within a short window.
    /// SwiftUI removes the collapsed rows from the tree, so we wait for the
    /// `exists == false` predicate rather than a single instantaneous read.
    private func assertEventuallyAbsent(
        _ element: XCUIElement,
        message: String,
        timeout: TimeInterval = 5
    ) {
        let absent = expectation(for: NSPredicate(format: "exists == false"),
                                 evaluatedWith: element)
        let result = XCTWaiter().wait(for: [absent], timeout: timeout)
        XCTAssertEqual(result, .completed, message)
    }
}
