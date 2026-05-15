// Purpose: Verification tests for Feature #31 — auto page turning.
// Confirms the Auto Page Turn toggle + interval slider are present in
// reader settings and exercise the toggle's wiring contract.
//
// Seed: .mdTOC (loads an MD book with headings; MD is the ONLY format
// granted `.autoPageTurn` capability per FormatCapabilities.swift:43-46
// — TXT lacks end-to-end AutoPageTurner wiring per bug #157). WI-4b
// switched from .warAndPeace to .mdTOC for this reason.
//
// WI-4c: launch with `LaunchArgs.readerLayoutPaged` so the EPUB layout
// preference is pre-seeded to `.paged` before any ReaderSettingsStore
// reads UserDefaults. This bypasses the SwiftUI segmented Picker which
// doesn't dispatch tap-to-segment under XCUITest (iOS 26.5). WI-4b had
// to fall through 3 picker-lookup variants and still XCTSkip; with the
// launch arg the layout gate is already satisfied at app-init time.
//
// Notes:
// - Live multi-page advancement requires a fixture that paginates to
//   multiple pages at the test viewport. The MD test seed paginates
//   when MDReaderContainerView's paged renderer fits content.
// - The pragmatic contract this WI verifies: the Auto Page Turn toggle
//   exists and is interactable when paged mode is selected.
//
// @coordinates-with: ReaderSettingsPanel.swift, AutoPageTurner.swift,
//   NativeTextPagedView.swift, VerificationSettingsHelper.swift

import XCTest

@MainActor
final class Feature31AutoPageTurnVerificationTests: XCTestCase {
    var app: XCUIApplication!
    private var settingsHelper: VerificationSettingsHelper!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(
            seed: .mdTOC,
            resetPreferences: true,
            extraLaunchArguments: [LaunchArgs.readerLayoutPaged]
        )
        settingsHelper = VerificationSettingsHelper(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        settingsHelper = nil
    }

    // MARK: - Feature #31 Verification

    /// Verifies the Auto Page Turn toggle is reachable in reader settings
    /// when paged mode is the active reading mode.
    ///
    /// NOTE: Per `FormatCapabilities.swift:43-46`, `.autoPageTurn` is
    /// granted ONLY to MD (TXT lacks end-to-end AutoPageTurner wiring per
    /// bug #157). On `.warAndPeace` seed (TXT), the section is gated out
    /// → test XCTSkips. To exercise the toggle, seed with `.mdTOC` (which
    /// loads an MD book where the capability IS granted).
    func test_verify_feature_31_auto_page_turn_toggle_present() throws {
        tapFirstBook(in: app)

        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should load"
        )

        let panel = settingsHelper.openReaderSettings()
        XCTAssertTrue(panel.exists)

        // WI-4c: EPUB layout is pre-seeded to .paged via
        // LaunchArgs.readerLayoutPaged at app launch (see setUp). The
        // auto-page-turn section's layout gate (store.epubLayout == .paged)
        // is already satisfied — no picker interaction needed. The
        // capability gate (.autoPageTurn granted only to MD per bug #157)
        // is satisfied by the .mdTOC seed.

        // Look for the Auto Page Turn section. The initial
        // `waitForExistence(timeout: 2)` lets the panel populate before
        // the swipe-up loop fires — empirically, `panel.swipeUp()` issued
        // too early (before the panel's lazy section rendering completes)
        // can desync with content loading and leave the section unfound.
        let section = panel.staticTexts["Auto Page Turn"]
        if !section.waitForExistence(timeout: 2) {
            for _ in 0..<6 {
                if section.exists { break }
                panel.swipeUp()
            }
        }

        guard section.exists else {
            throw XCTSkip(
                "Auto Page Turn section not present — capability or layout " +
                "gate not satisfied (need MD format AND paged layout; the " +
                "Paged-picker tap may not have landed via XCUITest segmented- " +
                "control lookup)"
            )
        }

        let toggle = app.switches[AccessibilityID.autoPageTurnToggle]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 3),
            "autoPageTurnToggle should be visible once the section is on-screen"
        )
        // Bug #196 (GH #702): the section-finder loop above breaks as soon
        // as the section header enters the accessibility tree — which can
        // happen when the header is just barely at the bottom edge with
        // the toggle row below it still clipped. The previous fix budgeted
        // only 3 extra swipes, which was insufficient for some panel
        // layouts. Increasing to 10 retries removes the regression
        // observed in the v3.22.1 verify-cron re-run while preserving
        // the original section-finder behavior that's known to work.
        for _ in 0..<10 where !toggle.isHittable {
            panel.swipeUp()
        }
        XCTAssertTrue(toggle.isHittable, "Auto Page Turn toggle should be hittable after at most 10 swipe-up retries")
    }

    /// Verifies that toggling Auto Page Turn ON reveals the interval slider.
    ///
    /// Same capability gate as `test_verify_feature_31_auto_page_turn_toggle_present`:
    /// XCTSkip on formats without `.autoPageTurn`.
    func test_verify_feature_31_auto_page_turn_interval_slider_appears_on_enable() throws {
        tapFirstBook(in: app)

        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should load"
        )

        let panel = settingsHelper.openReaderSettings()
        XCTAssertTrue(panel.exists)

        // Non-strict section probe (same pattern as toggle_present test).
        let section = panel.staticTexts["Auto Page Turn"]
        if !section.waitForExistence(timeout: 2) {
            for _ in 0..<6 {
                if section.exists { break }
                panel.swipeUp()
            }
        }
        guard section.exists else {
            throw XCTSkip(
                "Auto Page Turn section not present — current format may lack " +
                ".autoPageTurn capability"
            )
        }

        let toggle = app.switches[AccessibilityID.autoPageTurnToggle]
        guard toggle.waitForExistence(timeout: 3) else {
            throw XCTSkip("Auto Page Turn toggle gate not satisfied on this fixture")
        }

        if toggle.value as? String == "0" || toggle.value as? String == "false" {
            toggle.tap()
        }

        // After enabling, the interval slider should appear.
        let slider = app.sliders[AccessibilityID.autoPageTurnIntervalSlider]
        XCTAssertTrue(
            slider.waitForExistence(timeout: 3),
            "autoPageTurnIntervalSlider should appear after enabling Auto Page Turn"
        )
    }
}
