// Purpose: CU-free Gate-5 verification suite for Feature #26 —
// "Text-to-Speech read aloud".
//
// Feature #26 ships TTS read-aloud: the user starts narration from the
// reader's More (⋯) popover "Read aloud" row, a `TTSControlBar` mounts
// at the bottom of the reader with play/pause + stop controls, and the
// `TTSService` state machine drives `.idle → .speaking → .paused →
// .speaking → .idle`.
//
// Why this suite exists — the pause/resume reachability gap:
//   The prior Gate-5 rounds (`feature-26-20260507/09/13-round3.md`,
//   round-4, round-5) verified TTS start + the genuine-speech signal
//   (monotonic `ttsOffsetUTF16`) + stop teardown across TXT / EPUB / MD,
//   but the `TTSControlBar` *pause/resume* button itself was never
//   exercised by automation: round-4/round-5 ran CU-free via the
//   `vreader-debug://tts` DebugBridge command, which only exposes
//   start / stop — there is no `tts?action=pause` URL, so the
//   pause/resume control was physically unreachable. An XCUITest suite
//   drives the app through the accessibility API and CAN synthesize a
//   tap on that button, closing the gap.
//
// What this suite verifies (feature #26 acceptance criteria):
//   - C1 (start): open a seeded book, open the reader More popover, tap
//     the "Read aloud" row → the `TTSControlBar` mounts (its play/pause
//     + Stop controls appear) and the play/pause control is in its
//     "Pause" affordance — i.e. `TTSService` is in `.speaking`.
//   - C2 (pause): tap the control bar's play/pause button while
//     speaking → the button's accessibility label flips from "Pause" to
//     "Resume" (the `TTSService.State`-driven label on `TTSControlBar`'s
//     play/pause `Button`), proving the `.speaking → .paused` transition.
//   - C3 (resume): tap the play/pause button again while paused → the
//     label flips back to "Pause" — the full `.speaking → .paused →
//     .speaking` cycle.
//   - C4 (stop teardown): tap the "Stop reading" button → the whole
//     `TTSControlBar` is removed (play/pause + Stop both gone), proving
//     the `.idle` transition tears the control bar down.
//
// Design / pattern notes:
//   - Launches with `--tts-test-mode` (feature #45 WI-4e): `TTSService`
//     is constructed with `XCUITestMockSpeechSynthesizer` instead of the
//     real `AVSpeechSynthesizer`, because the real synth's audio session
//     does not activate under XCUITest headless mode on the iPhone 17
//     Pro Simulator — the F40/F41 verification suites established this.
//     The mock fires synthetic `didStart` / `willSpeakRange` / `didFinish`
//     delegate callbacks on a self-rescheduling tick that genuinely
//     SUSPENDS while `pauseSpeaking()` holds it, so the paused state is
//     stable for the test's full assertion window rather than racing to
//     `didFinish`.
//   - **Pure XCUITest — no DebugBridge snapshot.** Unlike the F40/F41
//     suites, this suite does NOT read the `vreader-debug://snapshot`
//     `ttsState` JSON. The `TTSService.State` is fully observable from
//     the XCUITest accessibility tree itself: `TTSControlBar`'s
//     play/pause `Button` carries `.accessibilityLabel("Pause")` while
//     `.speaking` and `.accessibilityLabel("Resume")` while `.paused`,
//     and the whole bar unmounts on `.idle`. The button label IS the
//     state machine — observing it needs no out-of-process `simctl`
//     round-trip (which is unreliable from the sandboxed XCUITest
//     runner). Every assertion here is an element query against the
//     live app.
//   - Drives the app entirely through the XCUITest accessibility API
//     (element queries + synthesized taps) — no computer-use. The
//     book-open uses the library card tap, NOT the DebugBridge `open`
//     URL (which cannot reliably commit a NavigationStack push in a
//     headless `simctl openurl` session — see the feature-#54 pilot,
//     `Feature54ReadingModeRemovalVerificationTests`).
//   - **Query by accessibility LABEL, not by per-element identifier.**
//     The feature-#54 / #63 pilots drew this lesson from Bug #214 /
//     #223: a SwiftUI container's `.accessibilityIdentifier` propagates
//     onto — and clobbers — its leaf elements' own identifiers. Both
//     the More popover (`ReaderMorePopover`'s root carries
//     `accessibilityIdentifier("readerMorePopover")`) and the
//     `TTSControlBar` (its root `HStack` carries
//     `accessibilityIdentifier("ttsControlBar")`) do exactly this, so
//     the per-row / per-button identifiers (`readerMoreReadAloud`,
//     `ttsPlayPauseButton`, `ttsStopButton`) do NOT resolve — confirmed
//     by an `app.debugDescription` dump of the live popover, where every
//     row surfaced as `identifier: 'readerMorePopover'`. This suite
//     therefore queries each control by its stable accessibility LABEL,
//     which the container identifier does NOT override:
//       - the "Read aloud" row → `label BEGINSWITH 'Read aloud'`
//       - the play/pause control → label `"Pause"` while speaking,
//         `"Resume"` while paused (set in `TTSControlBar`)
//       - the Stop control → label `"Stop reading"`.
//
// @coordinates-with: TTSControlBar.swift, TTSService.swift,
//   ReaderMorePopover.swift, ReaderMoreMenuRow.swift, ReaderTopChrome.swift,
//   XCUITestMockSpeechSynthesizer.swift, LaunchHelper.swift,
//   TestConstants.swift

import XCTest

@MainActor
final class Feature26TextToSpeechVerificationTests: XCTestCase {

    // MARK: - Launch

    /// Launches with the given seed, `--reset-preferences` for a known
    /// UserDefaults state (Bug #152), and `--tts-test-mode` so
    /// `TTSService` uses `XCUITestMockSpeechSynthesizer` (feature #45
    /// WI-4e — the real synth's audio session does not activate under
    /// XCUITest headless mode).
    private func launch(seed: TestSeedState) -> XCUIApplication {
        launchApp(
            seed: seed,
            resetPreferences: true,
            extraLaunchArguments: ["--tts-test-mode"]
        )
    }

    // MARK: - Element queries (by label — see file header)

    /// The More popover's "Read aloud" row. The popover's root
    /// `.accessibilityIdentifier("readerMorePopover")` clobbers the
    /// row's own `readerMoreReadAloud` identifier, so the row is queried
    /// by its accessibility label. The label is composed of the row's
    /// title ("Read aloud") plus a state-dependent sub-line, so a
    /// `BEGINSWITH` match on "Read aloud" is stable whether the row's
    /// sub-line reads "Start text-to-speech" or "Playing · System voice".
    private func readAloudRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Read aloud'")
        ).firstMatch
    }

    /// The `TTSControlBar` play/pause control. The control bar's root
    /// `.accessibilityIdentifier("ttsControlBar")` clobbers the button's
    /// `ttsPlayPauseButton` identifier, so it is queried by label:
    /// `TTSControlBar` sets the label to "Pause" while speaking and
    /// "Resume" while paused. Matching either label resolves the single
    /// play/pause button in any non-idle state.
    private func playPauseButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label == 'Pause' OR label == 'Resume'")
        ).firstMatch
    }

    /// The play/pause button restricted to its `.speaking`-state label
    /// "Pause" — used to assert the control is offering the Pause
    /// affordance (i.e. `TTSService` is `.speaking`).
    private func pauseAffordance(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Pause'")).firstMatch
    }

    /// The play/pause button restricted to its `.paused`-state label
    /// "Resume" — used to assert the control is offering the Resume
    /// affordance (i.e. `TTSService` is `.paused`).
    private func resumeAffordance(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Resume'")).firstMatch
    }

    /// The `TTSControlBar` Stop control, queried by its accessibility
    /// label "Stop reading" (the `ttsStopButton` identifier is clobbered
    /// by the control bar's container identifier).
    private func stopButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label == 'Stop reading'")
        ).firstMatch
    }

    // MARK: - Helpers

    /// Opens the first (and only) seeded book and waits for the reader
    /// chrome. The card tap is retried because a first tap can land
    /// before the library `LazyVGrid` finishes its initial layout pass —
    /// the same legitimate timing race handled in
    /// `Feature54ReadingModeRemovalVerificationTests.openSeededBook`. The
    /// `readerBackButton` wait window is generous (30 s) because an EPUB
    /// book's WKWebView first render can be slow under a loaded host.
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
            if card.waitForExistence(timeout: 20) {
                if card.waitForHittable(timeout: 10) || card.exists { card.tap() }
            } else if row.waitForExistence(timeout: 3) {
                if row.waitForHittable(timeout: 10) || row.exists { row.tap() }
            }
            if backButton.waitForExistence(timeout: 30) { return true }
        }
        return false
    }

    /// Ensures the reader top chrome is visible so the ⋯ More button is
    /// hittable. The chrome auto-hides; a content tap toggles it back on.
    /// Mirrors `ensureChromeVisible` in the feature-#54 / #63 pilots.
    private func ensureChromeVisible(in app: XCUIApplication) {
        let moreButton = app.buttons["readerMoreButton"]
        if moreButton.waitForExistence(timeout: 5) { return }
        app.tap()
        _ = moreButton.waitForExistence(timeout: 8)
    }

    /// Opens the reader More (⋯) popover and taps the "Read aloud" row,
    /// which calls `startTTS()`. Feature #60's chrome re-skin moved TTS
    /// start out of a dedicated speaker button into this More-popover
    /// row — there is no longer a `readerTTSButton` in production.
    ///
    /// - Returns: `true` once the `TTSControlBar`'s play/pause control
    ///   has mounted — i.e. TTS started and the control bar is on screen.
    @discardableResult
    private func startReadAloud(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        ensureChromeVisible(in: app)

        let moreButton = app.buttons["readerMoreButton"]
        XCTAssertTrue(
            moreButton.waitForHittable(timeout: 15),
            "Reader More (⋯) button should be hittable once the top " +
            "chrome is visible",
            file: file, line: line
        )
        moreButton.tap()

        let row = readAloudRow(in: app)
        XCTAssertTrue(
            row.waitForHittable(timeout: 12),
            "The More popover should show a hittable \"Read aloud\" row " +
            "— feature #26's TTS start surface after the feature-#60 " +
            "chrome re-skin (queried by label, see file header)",
            file: file, line: line
        )
        row.tap()

        // `startTTS()` loads the book text on a Task, then
        // `TTSService.startSpeaking` mounts the control bar. With
        // `--tts-test-mode` the mock fires `didStart` on the next
        // runloop tick, so the bar appears within ~1 s of the tap;
        // allow a generous window for the cold text-load Task.
        return playPauseButton(in: app).waitForExistence(timeout: 25)
    }

    /// Runs feature #26's full TTS lifecycle — start → pause → resume →
    /// stop — for the book seeded by `seed`, asserting the
    /// `TTSControlBar` state machine via the play/pause control's
    /// accessibility label and the bar's mount/dismount. `formatName`
    /// labels the failure messages.
    private func runTTSLifecycle(
        seed: TestSeedState,
        formatName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let app = launch(seed: seed)
        XCTAssertTrue(
            openSeededBook(in: app),
            "[\(formatName)] the seeded book should open into the reader",
            file: file, line: line
        )

        // C1 — start. The control bar mounts and offers the "Pause"
        // affordance (TTSService is .speaking).
        XCTAssertTrue(
            startReadAloud(in: app),
            "[\(formatName)] C1: tapping the More popover's \"Read " +
            "aloud\" row should mount the TTSControlBar (play/pause " +
            "control visible)",
            file: file, line: line
        )
        XCTAssertTrue(
            pauseAffordance(in: app).waitForExistence(timeout: 8),
            "[\(formatName)] C1: while speaking, the play/pause control " +
            "should show the \"Pause\" affordance — TTSService is in " +
            "the .speaking state",
            file: file, line: line
        )

        // C2 — pause. The play/pause control's label flips to "Resume"
        // (TTSService .speaking → .paused).
        pauseAffordance(in: app).tap()
        XCTAssertTrue(
            resumeAffordance(in: app).waitForExistence(timeout: 8),
            "[\(formatName)] C2: tapping the play/pause button while " +
            "speaking should flip its label to \"Resume\" — the " +
            ".speaking → .paused transition",
            file: file, line: line
        )
        // The "Pause" affordance must be gone — the single play/pause
        // control cannot be in both states at once.
        XCTAssertFalse(
            pauseAffordance(in: app).exists,
            "[\(formatName)] C2: the \"Pause\" affordance must be gone " +
            "once TTS is paused (the control shows \"Resume\")",
            file: file, line: line
        )

        // C3 — resume. The label flips back to "Pause" (.paused →
        // .speaking) — the full pause/resume cycle.
        resumeAffordance(in: app).tap()
        XCTAssertTrue(
            pauseAffordance(in: app).waitForExistence(timeout: 8),
            "[\(formatName)] C3: tapping the play/pause button while " +
            "paused should flip its label back to \"Pause\" — the " +
            ".paused → .speaking transition completing the cycle",
            file: file, line: line
        )

        // C4 — stop teardown. The whole control bar unmounts (.idle).
        let stop = stopButton(in: app)
        XCTAssertTrue(
            stop.waitForExistence(timeout: 8),
            "[\(formatName)] C4: the control bar's Stop button should " +
            "be present",
            file: file, line: line
        )
        stop.tap()
        XCTAssertTrue(
            playPauseButton(in: app).waitForDisappearance(timeout: 12),
            "[\(formatName)] C4: tapping Stop should tear the " +
            "TTSControlBar down — the play/pause control should no " +
            "longer exist (TTSService is .idle)",
            file: file, line: line
        )
        XCTAssertTrue(
            stopButton(in: app).waitForDisappearance(timeout: 8),
            "[\(formatName)] C4: the Stop button should also be gone " +
            "once the control bar is torn down",
            file: file, line: line
        )
    }

    // MARK: - C1-C4 — TXT (native text reader)

    /// Full TTS lifecycle on the TXT reader: start → pause → resume →
    /// stop. Drives the actual `TTSControlBar` play/pause + Stop
    /// controls — the pause/resume reachability gap the prior CU-free
    /// rounds could not close (feature #26 acceptance criteria C1-C4).
    func test_verify_feature_26_txt_start_pause_resume_stop_cycle() throws {
        runTTSLifecycle(seed: .warAndPeace, formatName: "TXT")
    }

    // MARK: - C1-C4 — MD (native Markdown reader)

    /// Full TTS lifecycle on the Markdown reader. Confirms feature #26's
    /// TTS read-aloud + the `TTSControlBar` pause/resume controls work
    /// on the Markdown engine (`MDReaderContainerView`), a separate
    /// render path from TXT.
    func test_verify_feature_26_md_start_pause_resume_stop_cycle() throws {
        runTTSLifecycle(seed: .mdMultiPage, formatName: "MD")
    }

    // MARK: - C1-C4 — EPUB (native WKWebView reader)

    /// Full TTS lifecycle on the EPUB reader: start → pause → resume →
    /// stop. Confirms feature #26's TTS read-aloud + the `TTSControlBar`
    /// pause/resume controls work on the EPUB engine (a WKWebView render
    /// path), not just the native text readers — closing the EPUB half
    /// of the pause/resume reachability gap.
    ///
    /// Known environmental flake (NOT a feature or test-logic defect):
    /// on the iOS 26.4 Simulator the runner can log
    /// `Class UIAccessibilityLoaderWebShared is implemented in both
    /// WebCore.axbundle and WebKit.axbundle … mysterious crashes` and
    /// the test runner can crash in *teardown* — after this test's TTS
    /// assertions have all already executed — when the EPUB WKWebView's
    /// accessibility bundle unloads. The remedy is a re-run; the test
    /// itself is deterministic. If this surfaces, run the EPUB case in
    /// isolation rather than treating it as a #26 regression.
    func test_verify_feature_26_epub_start_pause_resume_stop_cycle() throws {
        runTTSLifecycle(seed: .epubFixture, formatName: "EPUB")
    }
}
