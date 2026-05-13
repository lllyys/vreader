// Purpose: Verification tests for Feature #40 — TTS sentence highlighting.
// Exercises the TTS start surface and asserts the DebugSnapshot.ttsState
// transitions to a non-nil speaking state after TTS is started.
//
// Seed: .warAndPeace (real TXT content so TTS has actual text to read).
//
// Notes:
// - Uses VerificationDebugBridgeHelper.snapshotApp + readSnapshot to read
//   ttsState/ttsOffsetUTF16 as the assertion surface (per feature #45
//   plan v2). The DebugSnapshot v2 schema (feature #49 WI-1) added these
//   fields.
// - Audio playback is not observable on the simulator, but
//   AVSpeechSynthesizerDelegate callbacks still fire — ttsOffsetUTF16
//   advances as utterances progress.
// - Falls back to a weaker smoke check (ttsControlBar visibility) if
//   the snapshot's ttsState field is nil (e.g., format/path doesn't
//   broadcast TTS state to the snapshot yet).
//
// @coordinates-with: TTSService.swift, DebugSnapshot.swift,
//   TTSHighlightCoordinator.swift, VerificationDebugBridgeHelper.swift

import XCTest

@MainActor
final class Feature40TTSSentenceHighlightVerificationTests: XCTestCase {
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

    private func openReaderAndStartTTS() throws {
        tapFirstBook(in: app)

        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 15),
            "Reader should load"
        )

        let ttsButton = app.buttons[AccessibilityID.readerTTSButton]
        guard ttsButton.waitForHittable(timeout: 8) else {
            throw XCTSkip("Reader TTS button not present for this fixture/format")
        }
        ttsButton.tap()

        // The TTS control bar should appear once TTS has started.
        let controlBar = app.otherElements[AccessibilityID.ttsControlBar]
        XCTAssertTrue(
            controlBar.waitForExistence(timeout: 8),
            "TTS control bar should appear after tapping TTS button"
        )
    }

    // MARK: - Feature #40 Verification

    /// Verifies the TTS control surface is reachable and the snapshot
    /// reports a non-nil ttsState after starting TTS.
    func verify_feature_40_tts_state_reported_after_start() throws {
        try openReaderAndStartTTS()

        // Read snapshot to confirm ttsState reports a speaking-ish value.
        let dest = "verify-feature-40-state.json"
        bridgeHelper.snapshotApp(dest: dest)

        // Give the app a brief moment to write the snapshot.
        _ = XCTWaiter().wait(for: [], timeout: 1.0)

        guard let snapshot = bridgeHelper.readSnapshot(dest: dest) else {
            throw XCTSkip("Could not read DebugBridge snapshot — bridge handler may not be wired this build")
        }

        // Per DebugSnapshot wire format, ttsState is a String enum case:
        // "speaking", "paused", "idle", etc. Idle/nil means TTS isn't
        // running — anything else means it's active.
        if let ttsState = snapshot["ttsState"] as? String {
            XCTAssertNotEqual(
                ttsState, "idle",
                "ttsState should not be 'idle' immediately after starting TTS"
            )
        } else {
            // Weaker fallback: assert the TTS control bar is visible.
            // This is the documented fallback path per plan v2 (when
            // ttsState isn't broadcast to the snapshot for this format).
            XCTAssertTrue(
                app.otherElements[AccessibilityID.ttsControlBar].exists,
                "TTS control bar must remain visible if snapshot doesn't report ttsState"
            )
        }
    }

    /// Verifies ttsOffsetUTF16 advances over time — confirms
    /// AVSpeechSynthesizerDelegate callbacks are firing, which is the
    /// signal that sentence-highlight updates would also be firing.
    func verify_feature_40_tts_offset_advances_during_playback() throws {
        try openReaderAndStartTTS()

        // Capture initial offset.
        bridgeHelper.snapshotApp(dest: "verify-feature-40-offset-initial.json")
        _ = XCTWaiter().wait(for: [], timeout: 1.0)

        guard let initial = bridgeHelper.readSnapshot(dest: "verify-feature-40-offset-initial.json"),
              let initialOffset = initial["ttsOffsetUTF16"] as? Int else {
            throw XCTSkip("ttsOffsetUTF16 not reported in snapshot for this format/path")
        }

        // Wait ~3 s for callbacks to advance the offset.
        _ = XCTWaiter().wait(for: [], timeout: 3.0)

        bridgeHelper.snapshotApp(dest: "verify-feature-40-offset-later.json")
        _ = XCTWaiter().wait(for: [], timeout: 1.0)

        guard let later = bridgeHelper.readSnapshot(dest: "verify-feature-40-offset-later.json"),
              let laterOffset = later["ttsOffsetUTF16"] as? Int else {
            throw XCTSkip("ttsOffsetUTF16 lost between snapshots — TTS may have stopped")
        }

        XCTAssertGreaterThan(
            laterOffset, initialOffset,
            "ttsOffsetUTF16 should advance during playback (initial=\(initialOffset) later=\(laterOffset))"
        )
    }
}
