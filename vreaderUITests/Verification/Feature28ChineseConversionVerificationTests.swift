// Purpose: Verification tests for Feature #28 — Chinese text conversion
// (Simplified ↔ Traditional). Confirms the "Chinese Text" segmented picker
// is present in the reader settings panel.
//
// Seed: .books (the picker is rendered regardless of book content — the
// disabled-vs-enabled state depends on format + reading mode).
//
// Notes:
// - The conversion-applied-to-reader-content test requires a CJK TXT
//   fixture, which is NOT currently in DebugFixtureCatalog. We use
//   XCTSkip in that case and leave a fixture-request follow-up.
// - The UI-surface test runs unconditionally: the "Chinese Text" picker
//   should always render in the reader settings panel (it may be disabled
//   for certain format/mode combinations per
//   `ReaderSettingsPanel.chineseConversionDisableReason`).
//
// @coordinates-with: ReaderSettingsPanel.swift, ChineseTextConverter.swift,
//   VerificationSettingsHelper.swift

import XCTest

@MainActor
final class Feature28ChineseConversionVerificationTests: XCTestCase {
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

    // MARK: - Feature #28 Verification

    /// Verifies the Chinese Text segmented picker is present in the
    /// reader settings panel. The picker may be disabled depending on the
    /// format/mode, but its presence is the contract under test.
    func test_verify_feature_28_chinese_text_picker_present() throws {
        tapFirstBook(in: app)

        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should load"
        )

        let panel = settingsHelper.openReaderSettings()
        XCTAssertTrue(panel.exists, "Reader settings panel should be present")

        // Scroll until the Chinese Text section header appears.
        // The section may be below the fold; helper swipes up to find it.
        settingsHelper.scrollToSection("Chinese Text", in: panel, maxSwipes: 6)

        let header = panel.staticTexts["Chinese Text"]
        XCTAssertTrue(
            header.exists,
            "Chinese Text section header should be present in the reader settings panel"
        )

        settingsHelper.closeReaderSettings()
    }

    /// Verifies that Simp→Trad conversion is applied to reader content.
    /// Requires a CJK TXT fixture in DebugFixtureCatalog; skipped otherwise.
    func test_verify_feature_28_conversion_applies_to_reader_content() throws {
        // Conservative: skip unconditionally until a CJK fixture is bundled.
        // Tracked as a fixture-request follow-up against feature #45 / #28.
        throw XCTSkip(
            "CJK TXT fixture not present in DebugFixtureCatalog. " +
            "war-and-peace.txt has only English content; no Simp→Trad conversion " +
            "would be observable. Re-enable after a CJK fixture lands."
        )
    }
}
