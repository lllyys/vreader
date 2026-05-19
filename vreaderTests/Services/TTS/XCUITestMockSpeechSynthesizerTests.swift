// Purpose: Tests for XCUITestMockSpeechSynthesizer — a DEBUG-only
// AVSpeechSynthesizer replacement that fires synthetic delegate callbacks
// on a deterministic timeline so XCUITest verification can observe
// ttsState transitions and ttsOffsetUTF16 advancement without a real
// audio session. Feature #45 WI-4e.

#if DEBUG

import Testing
import Foundation
import AVFoundation
@testable import vreader

@MainActor
@Suite("XCUITestMockSpeechSynthesizer")
final class XCUITestMockSpeechSynthesizerTests {

    // MARK: - Test delegate that counts callbacks

    final class RecordingDelegate: NSObject, AVSpeechSynthesizerDelegate {
        var didStartCount = 0
        var willSpeakRangeCount = 0
        var didFinishCount = 0
        var didCancelCount = 0
        var lastUtteranceText: String?

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                               didStart utterance: AVSpeechUtterance) {
            didStartCount += 1
            lastUtteranceText = utterance.speechString
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                               willSpeakRangeOfSpeechString characterRange: NSRange,
                               utterance: AVSpeechUtterance) {
            willSpeakRangeCount += 1
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                               didFinish utterance: AVSpeechUtterance) {
            didFinishCount += 1
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                               didCancel utterance: AVSpeechUtterance) {
            didCancelCount += 1
        }
    }

    // MARK: - Tests

    @Test func speakFiresDidStartPromptly() async throws {
        let mock = XCUITestMockSpeechSynthesizer()
        let delegate = RecordingDelegate()
        mock.delegateTarget = delegate

        let utterance = AVSpeechUtterance(string: "Hello world.")
        mock.speak(utterance)

        // Bug #236: wait for the actual didStart signal — the mock fires
        // it via DispatchQueue.main.async, which lags under CPU contention.
        await pollUntil { delegate.didStartCount == 1 }
        #expect(delegate.didStartCount == 1)
        #expect(delegate.lastUtteranceText == "Hello world.")
        #expect(mock.isSpeaking == true)
    }

    @Test func speakFiresWillSpeakRangeMultipleTimes() async throws {
        let mock = XCUITestMockSpeechSynthesizer()
        let delegate = RecordingDelegate()
        mock.delegateTarget = delegate

        let utterance = AVSpeechUtterance(
            string: "The quick brown fox jumps over the lazy dog."
        )
        mock.speak(utterance)

        // Bug #236: wait for ≥2 willSpeakRange callbacks to actually fire
        // rather than guessing a fixed duration — the synthetic timeline
        // runs on wall-clock dispatch that lags under CPU contention.
        await pollUntil { delegate.willSpeakRangeCount >= 2 }
        #expect(delegate.willSpeakRangeCount >= 2,
                "Expected ≥2 willSpeakRange callbacks, got \(delegate.willSpeakRangeCount)")
    }

    @Test func speakCompletesWithDidFinish() async throws {
        let mock = XCUITestMockSpeechSynthesizer()
        let delegate = RecordingDelegate()
        mock.delegateTarget = delegate

        let utterance = AVSpeechUtterance(string: "Short.")
        mock.speak(utterance)

        // Bug #236: the mock's synthetic timeline runs on wall-clock
        // DispatchQueue.main.asyncAfter, which lags under CPU contention.
        // Wait for the actual didFinish signal rather than guessing a
        // fixed sleep duration (the old `Task.sleep(3.5s)` elapsed before
        // the timeline reached didFinish under load → flaky).
        await pollUntil { delegate.didFinishCount == 1 }
        #expect(delegate.didFinishCount == 1)
        #expect(delegate.didCancelCount == 0)
        #expect(mock.isSpeaking == false)
    }

    @Test func stopSpeakingFiresDidCancelAndHaltsCallbacks() async throws {
        let mock = XCUITestMockSpeechSynthesizer()
        let delegate = RecordingDelegate()
        mock.delegateTarget = delegate

        let utterance = AVSpeechUtterance(string: "This is a longer sentence with several words.")
        mock.speak(utterance)

        // Wait briefly for didStart + maybe one willSpeakRange to land.
        try await Task.sleep(nanoseconds: 400_000_000) // 400ms
        let willSpeakBeforeStop = delegate.willSpeakRangeCount

        _ = mock.stopSpeaking()

        // After stop: didCancel fires; no further willSpeakRange or didFinish.
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        #expect(delegate.didCancelCount == 1, "Expected 1 didCancel, got \(delegate.didCancelCount)")
        #expect(delegate.didFinishCount == 0, "didFinish must not fire after stop")
        #expect(mock.isSpeaking == false)

        // Wait the rest of the would-be timeline — willSpeakRange count must not grow much.
        // Allow at most one in-flight callback racing with stop (typical bound: 0–1).
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        #expect(delegate.willSpeakRangeCount <= willSpeakBeforeStop + 1,
                "willSpeakRange should not advance after stop (before=\(willSpeakBeforeStop), after=\(delegate.willSpeakRangeCount))")
    }

    @Test func secondSpeakCancelsFirst() async throws {
        let mock = XCUITestMockSpeechSynthesizer()
        let delegate = RecordingDelegate()
        mock.delegateTarget = delegate

        let first = AVSpeechUtterance(string: "First utterance text content.")
        mock.speak(first)

        // Bug #236: wait for the first utterance's didStart to actually
        // land before the second speak(). The mock fires didStart via
        // DispatchQueue.main.async behind a generation guard — a fixed
        // sleep can elapse before it under CPU contention, and the second
        // speak() would then bump the generation and short-circuit the
        // still-pending first didStart (→ didStartCount stuck at 1).
        await pollUntil { delegate.didStartCount == 1 }

        let second = AVSpeechUtterance(string: "Second utterance text content.")
        mock.speak(second)

        // didCancel + isSpeaking flip synchronously inside speak(), so
        // assert them immediately after the second speak() returns.
        #expect(delegate.didCancelCount >= 1, "First utterance should have been cancelled by second speak")
        #expect(mock.isSpeaking == true)

        // The second utterance's didStart is delivered via
        // DispatchQueue.main.async — wait for the actual signal rather
        // than guessing a fixed duration.
        await pollUntil { delegate.didStartCount == 2 }
        #expect(delegate.didStartCount == 2)
    }
}

#endif
