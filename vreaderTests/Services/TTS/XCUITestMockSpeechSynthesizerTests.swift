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

        // didStart hops through Task @MainActor — give one runloop tick.
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
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

        // Wait long enough for ≥2 callbacks at the synthetic cadence.
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
        #expect(delegate.willSpeakRangeCount >= 2,
                "Expected ≥2 willSpeakRange callbacks within 1.5s, got \(delegate.willSpeakRangeCount)")
    }

    @Test func speakCompletesWithDidFinish() async throws {
        let mock = XCUITestMockSpeechSynthesizer()
        let delegate = RecordingDelegate()
        mock.delegateTarget = delegate

        let utterance = AVSpeechUtterance(string: "Short.")
        mock.speak(utterance)

        // Mock's full synthetic timeline finishes within ~3s for short text.
        try await Task.sleep(nanoseconds: 3_500_000_000) // 3.5s
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

        try await Task.sleep(nanoseconds: 300_000_000) // 300ms

        let second = AVSpeechUtterance(string: "Second utterance text content.")
        mock.speak(second)

        // After second speak: first should have cancelled, second should be speaking.
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        #expect(delegate.didCancelCount >= 1, "First utterance should have been cancelled by second speak")
        #expect(mock.isSpeaking == true)
        // didStart was called twice (once per utterance).
        #expect(delegate.didStartCount == 2)
    }
}

#endif
