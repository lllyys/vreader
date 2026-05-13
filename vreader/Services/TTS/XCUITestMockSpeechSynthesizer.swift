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
// - Uses DispatchQueue.main.asyncAfter instead of Task to avoid Swift 6
//   Sendable-isolation issues with non-Sendable AVFoundation types
//   crossing into a `Task @MainActor` body. SystemSpeechSynthesizer
//   follows the same non-isolated pattern, so the protocol conformance
//   shape stays consistent.
// - A generation counter invalidates stale dispatched callbacks when
//   speak()/stopSpeaking() is called mid-sequence — newer generation
//   short-circuits older blocks.
// - `pauseSpeaking()` / `continueSpeaking()` flip flags but do NOT
//   suspend the synthetic timeline. Feature 40/41 verification tests do
//   not exercise pause/resume; a future WI extending mock coverage to
//   pause/resume tests must add proper suspension here.
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

    /// Monotonically increments on each speak()/stopSpeaking() — older
    /// dispatched closures check this and exit if no longer current.
    private var generation: Int = 0

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
        // sees didStart. Matches real AVSpeechSynthesizer behavior.
        if isSpeaking {
            generation += 1
            delegateTarget?.speechSynthesizer?(probeSynth, didCancel: avUtterance)
        }

        isSpeaking = true
        isPaused = false
        generation += 1
        let myGeneration = generation

        // AVSpeechUtterance is not Sendable. The mock fires these only
        // on the main thread, so the actual data-race risk is nil; mark
        // explicitly so DispatchQueue closure capture compiles under
        // Swift 6 strict concurrency.
        nonisolated(unsafe) let utteranceCapture = avUtterance

        // Schedule didStart on the next runloop tick so the call returns
        // before any delegate fires (matches real synth behavior + lets
        // TTSService set state = .speaking before willSpeakRange lands).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == myGeneration else { return }
            self.delegateTarget?.speechSynthesizer?(self.probeSynth, didStart: utteranceCapture)
        }

        // Schedule willSpeakRange callbacks across the utterance text in
        // up to 10 slices. NSRange.location advances forward; tests can
        // observe ttsOffsetUTF16 advancing via TTSService's existing
        // willSpeakRange handler.
        let textLength = (avUtterance.speechString as NSString).length
        let sliceCount = max(1, min(10, textLength))
        let sliceWidth = max(1, textLength / sliceCount)

        for i in 0..<sliceCount {
            // 250ms cadence — 10 slices finish ~2.5s after speak().
            let delay = Double(i + 1) * 0.25
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == myGeneration else { return }
                let location = i * sliceWidth
                let length = min(sliceWidth, max(0, textLength - location))
                self.delegateTarget?.speechSynthesizer?(
                    self.probeSynth,
                    willSpeakRangeOfSpeechString: NSRange(location: location, length: length),
                    utterance: utteranceCapture
                )
            }
        }

        // Schedule didFinish just after the last willSpeakRange.
        let finishDelay = Double(sliceCount + 1) * 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + finishDelay) { [weak self] in
            guard let self, self.generation == myGeneration else { return }
            self.isSpeaking = false
            self.isPaused = false
            self.delegateTarget?.speechSynthesizer?(self.probeSynth, didFinish: utteranceCapture)
        }
    }

    @discardableResult
    func pauseSpeaking() -> Bool {
        guard isSpeaking else { return false }
        isPaused = true
        isSpeaking = false
        // NOTE: does not suspend the synthetic timeline. See file header.
        return true
    }

    @discardableResult
    func continueSpeaking() -> Bool {
        guard isPaused else { return false }
        isPaused = false
        isSpeaking = true
        return true
    }

    @discardableResult
    func stopSpeaking() -> Bool {
        // Invalidate any in-flight dispatched closures.
        generation += 1
        isSpeaking = false
        isPaused = false

        // Fire didCancel synchronously. Production didCancel handler
        // (TTSService line 229-244) ignores the utterance parameter, so
        // a placeholder is fine.
        let placeholder = AVSpeechUtterance(string: "")
        delegateTarget?.speechSynthesizer?(probeSynth, didCancel: placeholder)
        return true
    }
}

#endif
