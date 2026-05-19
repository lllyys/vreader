// Purpose: Gate-5 verification for Feature #25 — "Configurable tap zones".
//
// IMPORTANT — feature scope changed under this verification's feet.
// Feature #25 originally shipped a Tap Zones section in `ReaderSettingsPanel`
// (3 pickers: left / center / right → `TapAction`) whose configured actions
// were dispatched by a `TapZoneModifier` overlay (`tapZoneOverlay()`). That
// overlay was ALWAYS installed only on the Unified (SwiftUI-native scroll)
// render path — Bug #162 / GH #482 confirmed it was a no-op on every native
// renderer (TXT / MD / EPUB / PDF / AZW3), which post their own
// `.readerContentTapped` unconditionally and ignore `TapZoneConfig`.
//
// Feature #54 ("Remove Native/Unified reading mode toggle") then deleted the
// Unified mode entirely:
//   - WI-3 (PR #883) deleted `ReaderUnifiedDispatch.swift` — the SOLE
//     `tapZoneOverlay(...)` install site.
//   - WI-4 (PR #886) removed the Tap Zones section AND the `TapZoneStore`
//     wiring from `ReaderSettingsPanel` + `ReaderContainerView`.
// (See the feature #54 row in docs/features.md and the regression-guard
// suite `ReaderSettingsPanelTapZonesGateTests`.)
//
// Net result on origin/main: feature #25's user-facing capability NO LONGER
// SHIPS. The `TapZoneConfig` / `TapZoneStore` / `TapZoneModifier` *types*
// survive as dead code (still unit-tested by `TapZoneTests.swift`), but
// `tapZoneOverlay()` is applied to no view, no settings UI exposes the
// pickers, and no reader zones synthesized taps by horizontal position.
//
// Because there is no in-reader tap-zone behaviour left to exercise, this
// suite cannot verify "tap right zone → next page" etc. — that contract was
// retired. What it CAN verify, CU-free via pure XCUITest, is the current
// observable truth backing the `partial` evidence file
// (`dev-docs/verification/feature-25-20260519.md`): the reader settings
// panel opens and renders content, but exposes NO Tap Zones configuration
// section, across the three formats that have DebugBridge seed fixtures
// (TXT / MD / EPUB). This is the load-bearing fact for the determination
// that feature #25 must be re-classified rather than flipped to VERIFIED.
//
// Seeds: .warAndPeace (TXT), .mdMultiPage (MD), .epubFixture (EPUB) — the
// three formats with real openable bundled fixtures (PDF / AZW3 lack them,
// Bug #209 harness gap).
//
// CU-free: XCUITest synthesizes its own taps + swipes; no computer-use.
// Lesson reused from #54 / #63 / #26 pilots — query reader/panel surfaces
// by element TYPE and accessibility LABEL, not by clobbered container
// identifiers (Bug #214).
//
// @coordinates-with: ReaderSettingsPanel.swift, ReaderContainerView.swift,
//   TapZoneOverlay.swift, TapZoneConfig.swift, VerificationSettingsHelper.swift

import XCTest

@MainActor
final class Feature25TapZonesVerificationTests: XCTestCase {

    /// Section header strings the original feature #25 Tap Zones UI used.
    /// `ReaderSettingsPanel` no longer renders any of these after feature
    /// #54 WI-4. The suite asserts their ABSENCE.
    private static let retiredTapZoneLabels = [
        "Tap Zones",
        "Left Zone",
        "Center Zone",
        "Right Zone",
    ]

    // MARK: - Helpers

    /// Opens the first library book, waits for the reader, taps the Display
    /// button, and returns the reader settings panel. Uses a longer,
    /// retry-tolerant wait than `VerificationSettingsHelper.openReaderSettings`
    /// — the panel is slow to realize on a cold simulator (first-launch
    /// SwiftUI `List` lazy section build), and a 5 s wait flakes. Fails the
    /// test (not skips) if the reader or panel never appears — those are
    /// real harness regressions, not feature-#25 gaps.
    private func openReaderSettingsPanel(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        tapFirstBook(in: app)
        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 25),
            "Reader should load (readerBackButton present)",
            file: file, line: line
        )
        let displayButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(
            displayButton.waitForHittable(timeout: 10),
            "Reader Display button should be hittable",
            file: file, line: line
        )
        displayButton.tap()
        let panel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 20),
            "Reader settings panel should appear after tapping Display",
            file: file, line: line
        )
        return panel
    }

    /// Single bounded pass over the settings panel. Asserts in one walk:
    ///  - the panel is genuinely populated (the surviving "Theme" section
    ///    header is reachable) — guards against a vacuous "no Tap Zones"
    ///    pass when the panel failed to load;
    ///  - NONE of the retired Tap Zones labels appear at any scroll offset.
    ///
    /// SwiftUI `List` sections are lazily realized, so the swipe-up loop
    /// walks the whole panel to realize any below-fold section before the
    /// re-checks. A fixed swipe budget (no per-iteration `debugDescription`
    /// fingerprint) keeps accessibility-snapshot load low — heavy snapshot
    /// traffic was the cause of the `testmanagerd` timeouts on the first
    /// authoring run.
    private func walkPanelAssertingNoTapZones(
        in panel: XCUIElement,
        format: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var sawTheme = panel.staticTexts["Theme"].exists

        // Probe before any scroll — a Tap Zones section, if it existed,
        // could equally be above the fold.
        assertRetiredLabelsAbsent(in: panel, format: format, phase: "pre-scroll",
                                  file: file, line: line)

        // Fixed-budget walk: 10 swipe-ups is enough to traverse the whole
        // ReaderSettingsPanel List on iPhone 17 Pro.
        for _ in 0..<10 {
            if !sawTheme, panel.staticTexts["Theme"].exists { sawTheme = true }
            assertRetiredLabelsAbsent(in: panel, format: format, phase: "scrolling",
                                      file: file, line: line)
            panel.swipeUp()
        }
        // Final post-scroll check at the bottom of the panel.
        if !sawTheme, panel.staticTexts["Theme"].exists { sawTheme = true }
        assertRetiredLabelsAbsent(in: panel, format: format, phase: "post-scroll",
                                  file: file, line: line)

        XCTAssertTrue(
            sawTheme,
            "[\(format)] settings panel should render at least the 'Theme' " +
            "section — confirms the panel populated (not an empty stub), so " +
            "the absent-Tap-Zones assertions are meaningful, not vacuous",
            file: file, line: line
        )
    }

    /// Asserts none of the retired feature-#25 Tap Zones labels are present
    /// in the panel's accessibility tree at the current scroll offset.
    private func assertRetiredLabelsAbsent(
        in panel: XCUIElement,
        format: String,
        phase: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for label in Self.retiredTapZoneLabels {
            XCTAssertFalse(
                panel.staticTexts[label].exists,
                "[\(format)] '\(label)' must not appear in reader settings " +
                "(\(phase)) — feature #54 WI-4 removed feature #25's Tap " +
                "Zones section",
                file: file, line: line
            )
        }
    }

    // MARK: - Tests

    /// TXT reader: the settings panel renders content but exposes no Tap
    /// Zones configuration section.
    func test_verify_feature_25_no_tap_zones_section_in_txt_reader() throws {
        let app = launchApp(seed: .warAndPeace, resetPreferences: true)
        let panel = openReaderSettingsPanel(in: app)
        walkPanelAssertingNoTapZones(in: panel, format: "TXT")
    }

    /// MD reader (multi-page fixture — the format/fixture combination prior
    /// rounds 5/6 were blocked waiting for): the settings panel renders but
    /// exposes no Tap Zones configuration section.
    func test_verify_feature_25_no_tap_zones_section_in_md_reader() throws {
        let app = launchApp(seed: .mdMultiPage, resetPreferences: true)
        let panel = openReaderSettingsPanel(in: app)
        walkPanelAssertingNoTapZones(in: panel, format: "MD")
    }

    /// EPUB reader: the settings panel renders but exposes no Tap Zones
    /// configuration section. EPUB was the format prior rounds verified
    /// the (now-deleted) center-zone dispatch against in Unified mode.
    func test_verify_feature_25_no_tap_zones_section_in_epub_reader() throws {
        let app = launchApp(seed: .epubFixture, resetPreferences: true)
        let panel = openReaderSettingsPanel(in: app)
        walkPanelAssertingNoTapZones(in: panel, format: "EPUB")
    }

    /// Cross-format synthesized-tap probe. Feature #25's premise was that a
    /// tap's HORIZONTAL POSITION selects an action. With the overlay gone,
    /// taps in the reader content area are positionally uniform — every
    /// in-content tap routes to the bridge's own `.readerContentTapped`
    /// (chrome toggle), independent of x. This test documents that observed
    /// behaviour CU-free: a synthesized coordinate tap at the right third of
    /// the reader and one at the left third produce the SAME chrome
    /// transition (toggle), i.e. there is no left/right page-turn zoning.
    ///
    /// It asserts on `readerBackButton` visibility as the chrome proxy: the
    /// back button is part of the top reader chrome, so its appearance /
    /// disappearance tracks the chrome toggle the content tap drives.
    func test_verify_feature_25_taps_are_positionally_uniform_no_zoning() throws {
        let app = launchApp(seed: .epubFixture, resetPreferences: true)
        tapFirstBook(in: app)

        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 20),
            "Reader should load with chrome visible (back button present)"
        )

        // Coordinate taps are relative to the app window. The reader content
        // sits below the top chrome and above the bottom chrome; ~0.45
        // vertical is safely inside the content area for all three formats.
        let leftThird = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.17, dy: 0.45)
        )
        let rightThird = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.83, dy: 0.45)
        )

        // Baseline: chrome is visible.
        XCTAssertTrue(backButton.exists, "Chrome should start visible")

        // Tap the RIGHT third. If feature #25's zoning were live, the
        // default config maps right → nextPage (NOT a chrome toggle). With
        // the overlay removed this is a plain content tap → chrome toggles.
        rightThird.tap()
        let chromeHidAfterRightTap = backButton.waitForDisappearance(timeout: 4)
        XCTAssertTrue(
            chromeHidAfterRightTap,
            "Right-third tap toggled chrome OFF — i.e. it routed to the " +
            "bridge's content-tap, NOT a right-zone 'next page' action. " +
            "Confirms feature #25's positional zoning is no longer wired."
        )

        // Tap the LEFT third. Default config maps left → previousPage. With
        // no zoning, this is again a plain content tap → chrome toggles back
        // ON. Same effect as the right tap = positionally uniform.
        leftThird.tap()
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 4),
            "Left-third tap toggled chrome back ON — same chrome-toggle " +
            "effect as the right-third tap. Taps are positionally uniform; " +
            "there is no left/right page-turn zoning (feature #54 retired it)."
        )
    }
}
