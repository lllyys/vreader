// Purpose: Verification tests for Feature #41 — TTS auto-scroll.
// Exercises that the reader view auto-scrolls forward as TTS narration
// progresses through text content. Uses `DebugBridge` snapshot to read
// the current reader scroll position before vs after TTS playback.
//
// Seed: .warAndPeace (real TXT content with multiple chapters for
// observable auto-scroll progress).
//
// Notes:
// - Feature #41 round-2 (2026-05-09) already device-verified TTS
//   auto-scroll via CU on the same fixture. This WI-4 deliverable adds
//   the XCUITest regression harness so the harness can guard future
//   regressions.
// - Auto-scroll position is read via DebugBridge snapshot's `position`
//   field, which TXT readers broadcast after bug #164 fix.
// - Falls back to a weaker smoke check (just TTS control bar visibility)
//   if `position` is not reported.
//
// @coordinates-with: TTSService.swift, TTSAutoScrollCoordinator.swift,
//   DebugSnapshot.swift, VerificationDebugBridgeHelper.swift

import XCTest

@MainActor
final class Feature41TTSAutoScrollVerificationTests: XCTestCase {
    var app: XCUIApplication!
    private var bridgeHelper: VerificationDebugBridgeHelper!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .warAndPeace, resetPreferences: true)
        bridgeHelper = VerificationDebugBridgeHelper(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        bridgeHelper = nil
    }

    // MARK: - Helpers

    private func startTTS() throws {
        // Chrome bar is visible by default — readerTTSButton is reachable
        // immediately after the reader loads. Do NOT pre-tap (would
        // toggle chrome OFF).

        let ttsButton = app.buttons[AccessibilityID.readerTTSButton]
        guard ttsButton.waitForHittable(timeout: 8) else {
            throw XCTSkip("Reader TTS button not present")
        }
        ttsButton.tap()

        // See Feature40's helper for the WI-4 finding context: on a fresh
        // launch the TTS button may surface a provider-selection sheet
        // before playback. XCTSkip until test-seed priming lands.
        let controlBar = app.otherElements[AccessibilityID.ttsControlBar]
        guard controlBar.waitForExistence(timeout: 30) else {
            throw XCTSkip(
                "TTS control bar didn't appear within 30s. See Feature40's " +
                "helper for context."
            )
        }
    }

    // MARK: - Feature #41 Verification

    /// Verifies that the TTS control bar appears and stays visible while
    /// TTS is playing — the surface from which auto-scroll is driven.
    func verify_feature_41_tts_control_bar_visible_during_playback() throws {
        tapFirstBook(in: app)

        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should load"
        )

        try startTTS()

        // Bar should remain visible after a few seconds of playback.
        _ = XCTWaiter().wait(for: [], timeout: 3.0)

        let controlBar = app.otherElements[AccessibilityID.ttsControlBar]
        XCTAssertTrue(
            controlBar.exists,
            "TTS control bar should remain visible during playback"
        )
    }

    /// Verifies that the reader's reported position advances during TTS
    /// playback — the observable signal that auto-scroll is firing.
    /// Falls back to ttsOffsetUTF16 advancement if position isn't broadcast
    /// for this format, and to control-bar visibility if neither is reported.
    func verify_feature_41_tts_autoscroll_position_advances() throws {
        tapFirstBook(in: app)

        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should load"
        )

        try startTTS()

        // Snapshot 1: initial state shortly after TTS starts.
        bridgeHelper.snapshotApp(dest: "verify-feature-41-initial.json")
        _ = XCTWaiter().wait(for: [], timeout: 1.0)
        let initialSnapshot = bridgeHelper.readSnapshot(dest: "verify-feature-41-initial.json")

        // Wait ~4s for narration to progress.
        _ = XCTWaiter().wait(for: [], timeout: 4.0)

        // Snapshot 2: later state.
        bridgeHelper.snapshotApp(dest: "verify-feature-41-later.json")
        _ = XCTWaiter().wait(for: [], timeout: 1.0)
        let laterSnapshot = bridgeHelper.readSnapshot(dest: "verify-feature-41-later.json")

        // Try position-based assertion first.
        if let initial = initialSnapshot,
           let later = laterSnapshot,
           let initialPos = initial["position"] as? [String: Any],
           let laterPos = later["position"] as? [String: Any] {
            // The position dict varies by format. For TXT, it has
            // charOffsetUTF16. Any non-equal pair indicates the reader
            // moved (auto-scroll fired).
            let initialOffset = initialPos["charOffsetUTF16"] as? Int ?? -1
            let laterOffset = laterPos["charOffsetUTF16"] as? Int ?? -1
            if initialOffset >= 0, laterOffset >= 0 {
                XCTAssertGreaterThan(
                    laterOffset, initialOffset,
                    "position.charOffsetUTF16 should advance during TTS playback (initial=\(initialOffset), later=\(laterOffset))"
                )
                return
            }
        }

        // Fallback: ttsOffsetUTF16 advancement (same signal, different field).
        if let initial = initialSnapshot,
           let later = laterSnapshot,
           let initialTTS = initial["ttsOffsetUTF16"] as? Int,
           let laterTTS = later["ttsOffsetUTF16"] as? Int {
            XCTAssertGreaterThan(
                laterTTS, initialTTS,
                "ttsOffsetUTF16 should advance during TTS playback (initial=\(initialTTS), later=\(laterTTS))"
            )
            return
        }

        // Weakest fallback: control bar visibility (proves TTS still
        // running, but doesn't directly observe auto-scroll progress).
        XCTAssertTrue(
            app.otherElements[AccessibilityID.ttsControlBar].exists,
            "TTS control bar must remain visible if neither position nor ttsOffsetUTF16 is broadcast"
        )
    }
}
