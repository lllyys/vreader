// Purpose: DEBUG-only AVSpeechSynthesizer replacement for XCUITest
// verification. Implements `SpeechSynthesizing` and fires synthetic
// AVSpeechSynthesizerDelegate callbacks on a deterministic timeline so
// the production TTSService's state machine transitions to .speaking,
// advances ttsOffsetUTF16, and reaches .idle without requiring a real
// audio session (which fails to activate under XCUITest headless mode
// on iPhone 17 Pro Simulator).
//
// Feature #45 WI-4e. Wired via `TTSTestOverride.useMockSynthesizer`
// (set by `--tts-test-mode` launch arg in VReaderApp.init).
//
// Key decisions:
// - Owns an `AVSpeechSynthesizer` instance solely as a typing tag for
//   the delegate callbacks. `speak()` is never called on it; no audio
//   ever plays.
// - The synthetic timeline is a single self-rescheduling tick rather
//   than a batch of `DispatchQueue.main.asyncAfter` calls scheduled at
//   speak() time. Each tick checks `isPaused`: when paused it reschedules
//   itself WITHOUT advancing, so the willSpeakRange / didFinish sequence
//   genuinely suspends — `pauseSpeaking()` holds the timeline and
//   `continueSpeaking()` resumes it from the same slice. This lets
//   XCUITest verification suites assert a real pause → resume → stop
//   cycle (feature #26 Gate-5 verification) without the timeline racing
//   to `didFinish` while the test is parked in the paused state.
// - Uses DispatchQueue.main.asyncAfter instead of Task to avoid Swift 6
//   Sendable-isolation issues with non-Sendable AVFoundation types
//   crossing into a `Task @MainActor` body. SystemSpeechSynthesizer
//   follows the same non-isolated pattern, so the protocol conformance
//   shape stays consistent.
// - A generation counter invalidates stale dispatched ticks when
//   speak()/stopSpeaking() is called mid-sequence — newer generation
//   short-circuits older blocks.
//
// Thread safety: all state mutations and delegate fires happen on the
// main DispatchQueue. Property reads from other threads (e.g. a test
// asserting `mock.isSpeaking`) are read-only and serialize through the
// implicit main-queue happens-before with `DispatchQueue.main.async`.
//
// @coordinates-with: SpeechSynthesizing.swift, TTSService.swift,
//   VReaderApp.swift (TestLaunchConfig.ttsTestMode)

#if DEBUG

import AVFoundation
import Foundation

final class XCUITestMockSpeechSynthesizer: NSObject, SpeechSynthesizing, @unchecked Sendable {

    // MARK: - Public state (matches SystemSpeechSynthesizer semantics)

    var isSpeaking: Bool = false
    var isPaused: Bool = false

    /// Delegate receives synthetic AVSpeechSynthesizerDelegate callbacks.
    /// TTSService.init wires this to itself, mirroring the
    /// SystemSpeechSynthesizer path.
    weak var delegateTarget: AVSpeechSynthesizerDelegate?

    // MARK: - Internal

    /// Used only as the `_ synthesizer:` parameter passed to delegate
    /// methods. Never has `speak()` called on it.
    private let probeSynth = AVSpeechSynthesizer()

    /// The utterance currently being "spoken" — retained so that a
    /// superseding `speak()` or a `stopSpeaking()` can fire `didCancel`
    /// with the *actual* cancelled utterance rather than a stand-in,
    /// matching real `AVSpeechSynthesizer` delegate semantics.
    /// `nil` while idle.
    private var currentUtterance: AVSpeechUtterance?

    /// Monotonically increments on each speak()/stopSpeaking() — older
    /// dispatched ticks check this and exit if no longer current.
    private var generation: Int = 0

    /// The cadence of one synthetic willSpeakRange slice. The unpaused
    /// timeline runs for `tickInterval * maxSliceCount` ≈ 30 s before
    /// the terminal didFinish — long enough for an XCUITest verification
    /// suite to fire several DebugBridge snapshots, tap pause / resume,
    /// and observe the offset advancing, all while the synthesizer is
    /// still in the `.speaking` state. (The earlier 2.75 s timeline was
    /// too short: a snapshot-polling assertion racing it could see the
    /// state flip to `.idle` mid-test. The Feature 40 / 41 suites only
    /// need the offset to *have advanced* and the state to be non-idle
    /// shortly after start — both still hold with the longer timeline.)
    private static let tickInterval: TimeInterval = 0.5

    /// Number of synthetic willSpeakRange slices a `speak()` emits, when
    /// the utterance has at least this many UTF-16 code units. Short
    /// utterances emit fewer slices (one per code unit).
    private static let maxSliceCount = 60

    // MARK: - SpeechSynthesizing

    func speak(_ utterance: SpeechUtteranceProtocol) {
        guard let avUtterance = utterance as? AVSpeechUtterance else {
            // Production callers always pass AVSpeechUtterance. Silently
            // no-op for unexpected wrapper types — matches
            // SystemSpeechSynthesizer.
            return
        }

        // If something was already speaking, cancel it first so the
        // first utterance's delegate sees didCancel before the second
        // sees didStart. Matches real AVSpeechSynthesizer behavior —
        // including firing didCancel for the OUTGOING utterance, not the
        // new one.
        if isSpeaking || isPaused {
            generation += 1
            let outgoing = currentUtterance ?? avUtterance
            nonisolated(unsafe) let outgoingCapture = outgoing
            delegateTarget?.speechSynthesizer?(probeSynth, didCancel: outgoingCapture)
        }

        isSpeaking = true
        isPaused = false
        currentUtterance = avUtterance
        generation += 1
        let myGeneration = generation

        // AVSpeechUtterance is not Sendable. The mock fires these only
        // on the main thread, so the actual data-race risk is nil; mark
        // explicitly so DispatchQueue closure capture compiles under
        // Swift 6 strict concurrency.
        nonisolated(unsafe) let utteranceCapture = avUtterance

        let textLength = (avUtterance.speechString as NSString).length
        let sliceCount = max(1, min(Self.maxSliceCount, textLength))
        let sliceWidth = max(1, textLength / sliceCount)

        // Schedule didStart on the next runloop tick so the call returns
        // before any delegate fires (matches real synth behavior + lets
        // TTSService set state = .speaking before willSpeakRange lands).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == myGeneration else { return }
            self.delegateTarget?.speechSynthesizer?(self.probeSynth, didStart: utteranceCapture)
        }

        // Drive the willSpeakRange + didFinish sequence via a single
        // self-rescheduling tick. `scheduleTick` checks `isPaused` on
        // every fire — a paused timeline reschedules without advancing,
        // so the sequence genuinely suspends until `continueSpeaking()`.
        scheduleTick(
            sliceIndex: 0,
            sliceCount: sliceCount,
            sliceWidth: sliceWidth,
            textLength: textLength,
            generation: myGeneration,
            utterance: utteranceCapture
        )
    }

    /// Fires one synthetic willSpeakRange slice (or the terminal
    /// didFinish) after `tickInterval`, then reschedules itself for the
    /// next slice. While `isPaused` is true the tick reschedules WITHOUT
    /// advancing `sliceIndex`, so the timeline holds at the current
    /// position. A stale generation short-circuits the whole chain.
    private func scheduleTick(
        sliceIndex: Int,
        sliceCount: Int,
        sliceWidth: Int,
        textLength: Int,
        generation myGeneration: Int,
        utterance: AVSpeechUtterance
    ) {
        // AVSpeechUtterance is not Sendable; the mock fires every
        // delegate callback on the main queue, so the capture is safe.
        nonisolated(unsafe) let utteranceCapture = utterance
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tickInterval) { [weak self] in
            guard let self, self.generation == myGeneration else { return }

            // Paused: hold the timeline — reschedule the SAME slice.
            if self.isPaused {
                self.scheduleTick(
                    sliceIndex: sliceIndex,
                    sliceCount: sliceCount,
                    sliceWidth: sliceWidth,
                    textLength: textLength,
                    generation: myGeneration,
                    utterance: utteranceCapture
                )
                return
            }

            if sliceIndex < sliceCount {
                // Fire this willSpeakRange slice. NSRange.location
                // advances forward; tests observe ttsOffsetUTF16
                // advancing via TTSService's willSpeakRange handler.
                let location = sliceIndex * sliceWidth
                let length = min(sliceWidth, max(0, textLength - location))
                self.delegateTarget?.speechSynthesizer?(
                    self.probeSynth,
                    willSpeakRangeOfSpeechString: NSRange(location: location, length: length),
                    utterance: utteranceCapture
                )
                self.scheduleTick(
                    sliceIndex: sliceIndex + 1,
                    sliceCount: sliceCount,
                    sliceWidth: sliceWidth,
                    textLength: textLength,
                    generation: myGeneration,
                    utterance: utteranceCapture
                )
            } else {
                // All slices consumed → terminal didFinish.
                self.isSpeaking = false
                self.isPaused = false
                self.currentUtterance = nil
                self.delegateTarget?.speechSynthesizer?(self.probeSynth, didFinish: utteranceCapture)
            }
        }
    }

    @discardableResult
    func pauseSpeaking() -> Bool {
        guard isSpeaking else { return false }
        isPaused = true
        isSpeaking = false
        // The next scheduled tick observes `isPaused` and reschedules
        // without advancing, so the synthetic timeline genuinely
        // suspends here until `continueSpeaking()`.
        return true
    }

    @discardableResult
    func continueSpeaking() -> Bool {
        guard isPaused else { return false }
        isPaused = false
        isSpeaking = true
        // The already-scheduled tick observes `isPaused == false` on its
        // next fire and resumes advancing from the held slice.
        return true
    }

    @discardableResult
    func stopSpeaking() -> Bool {
        // Nothing in flight → no-op, matching real AVSpeechSynthesizer
        // (`stopSpeaking(at:)` returns false and fires no delegate
        // callback when the synthesizer is idle).
        guard isSpeaking || isPaused else { return false }

        // Invalidate any in-flight dispatched ticks.
        generation += 1
        isSpeaking = false
        isPaused = false

        // Fire didCancel synchronously for the actual in-flight
        // utterance (faithful delegate semantics).
        let cancelled = currentUtterance ?? AVSpeechUtterance(string: "")
        currentUtterance = nil
        nonisolated(unsafe) let cancelledCapture = cancelled
        delegateTarget?.speechSynthesizer?(probeSynth, didCancel: cancelledCapture)
        return true
    }
}

#endif
