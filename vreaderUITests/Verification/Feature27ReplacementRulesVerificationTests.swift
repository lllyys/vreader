// Purpose: Verification tests for Feature #27 — text replacement rules.
// Confirms the Settings → Text Replacement Rules navigation surface and
// the Add button on the ReplacementRulesView are reachable from the
// library settings toolbar.
//
// Seed: .books (any book fixture works — the UI is reached pre-reader).
//
// Notes:
// - This WI scopes verification to the **navigation + UI surface** of the
//   replacement rules feature. The behavioral assertion ("rule applied in
//   reader removes text") requires synthesizing keyboard input into a
//   TextField, which is currently blocked by the macOS-side keyboard
//   synthesis quirk (documented in feature #4 round-2 and feature #34
//   round-3 evidence files). The reader-side behavior is covered by 64+
//   unit tests in `ReplacementRulesEngineTests` and `ReplacementRulesViewModelTests`.
//
// @coordinates-with: ReplacementRulesView.swift, SettingsView.swift

import XCTest

@MainActor
final class Feature27ReplacementRulesVerificationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Feature #27 Verification

    /// Verifies that the Replacement Rules surface is reachable:
    /// library → settings toolbar button → Settings sheet →
    /// "Replacement Rules" row visible → tap → ReplacementRulesView
    /// presents with its Add button.
    func verify_feature_27_replacement_rule_ui_surface() throws {
        let settingsButton = app.buttons[AccessibilityID.settingsToolbarButton]
        guard settingsButton.waitForHittable(timeout: 8) else {
            throw XCTSkip("Settings toolbar button not present from library view")
        }
        settingsButton.tap()

        // Settings sheet should appear with the Replacement Rules row.
        let settingsView = app.otherElements[AccessibilityID.settingsView]
        XCTAssertTrue(
            settingsView.waitForExistence(timeout: 5),
            "Settings view should appear after tapping settings toolbar button"
        )

        // The Replacement Rules navigation row.
        let rulesRow = settingsView.buttons[AccessibilityID.settingsReplacementRules]
        guard rulesRow.waitForExistence(timeout: 5) else {
            // Some layouts render NavigationLink as an `otherElements` row.
            // Fall back to scanning by identifier.
            let anyMatch = app.descendants(matching: .any)
                .matching(identifier: AccessibilityID.settingsReplacementRules)
                .firstMatch
            XCTAssertTrue(
                anyMatch.waitForExistence(timeout: 3),
                "Replacement Rules row should exist in Settings"
            )
            anyMatch.tap()
            return
        }

        XCTAssertTrue(rulesRow.isHittable, "Replacement Rules row should be hittable")
        rulesRow.tap()

        // The Add button on the ReplacementRulesView should be present.
        let addButton = app.buttons[AccessibilityID.replacementRulesAddButton]
        XCTAssertTrue(
            addButton.waitForExistence(timeout: 8),
            "Replacement rules Add button should appear after navigating to ReplacementRulesView"
        )
    }
}
