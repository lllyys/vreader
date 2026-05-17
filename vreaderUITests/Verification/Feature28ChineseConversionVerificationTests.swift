// Purpose: Verification tests for Feature #28 — Chinese text conversion
// (Simplified ↔ Traditional). Confirms the "Chinese Text" segmented picker
// is present in the reader settings panel.
//
// Seed: .warAndPeace — a real-file TXT fixture that opens into a working
// reader (the .books seed's fixtures are metadata-only and fail to open —
// Bug #209 / GH #804). The picker is rendered regardless of book content;
// the disabled-vs-enabled state depends on format + reading mode.
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
        app = launchApp(seed: .warAndPeace, resetPreferences: true)
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
    ///
    /// Bug #194 (GH #694): the prior shape of this test looked for a
    /// `staticTexts["Chinese Text"]` section header. Production renders
    /// the picker with `Picker("Chinese Text", ...).pickerStyle(.segmented)`
    /// — the "Chinese Text" string is the picker's label, NOT a section
    /// header, and `.pickerStyle(.segmented)` hides the label so it never
    /// appears as a static text. The test now queries the stable
    /// `chineseTextPicker` accessibility identifier wired in production
    /// via `app.descendants(matching:.any).matching(identifier:).firstMatch`
    /// — same pattern as Bug #193's OPDS fix.
    func test_verify_feature_28_chinese_text_picker_present() throws {
        tapFirstBook(in: app)

        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should load"
        )

        let panel = settingsHelper.openReaderSettings()
        XCTAssertTrue(panel.exists, "Reader settings panel should be present")

        // Scroll up to bring the Chinese conversion section into view if needed.
        // The picker is below the fold for some formats; up to 6 swipes is
        // sufficient for the current panel layout.
        let picker = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.chineseTextPicker)
            .firstMatch
        for _ in 0..<6 {
            if picker.exists { break }
            panel.swipeUp()
        }

        XCTAssertTrue(
            picker.waitForExistence(timeout: 3),
            "Chinese Text picker (id=\(AccessibilityID.chineseTextPicker)) should be present in the reader settings panel"
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
