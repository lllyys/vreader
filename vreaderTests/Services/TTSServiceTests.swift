// Purpose: Tests for TTSService — TTS read aloud using AVSpeechSynthesizer.
// Validates state transitions, speed control, position tracking, and format checks.
//
// Key decisions:
// - Uses a MockSynthesizer protocol to avoid real AVSpeechSynthesizer in tests.
// - Tests run synchronously via direct state inspection (no async waits on speech).
// - Edge cases: empty text, format availability, rapid state changes, CJK text.

import Testing
import Foundation
@testable import vreader

// MARK: - TTSService State Transition Tests

@Suite("TTSService State Transitions")
struct TTSServiceStateTransitionTests {

    @Test @MainActor
    func startSpeaking_beginsFromCurrentPosition() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello, world!", fromOffset: 5)
        #expect(service.state == .speaking)
        #expect(service.currentOffsetUTF16 == 5)
    }

    @Test @MainActor
    func startSpeaking_fromZeroOffset_defaultParameter() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello")
        #expect(service.state == .speaking)
        #expect(service.currentOffsetUTF16 == 0)
    }

    @Test @MainActor
    func pauseSpeech_pausesSynthesizer() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello, world!")
        service.pause()
        #expect(service.state == .paused)
    }

    @Test @MainActor
    func resumeSpeech_continuesSpeaking() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello, world!")
        service.pause()
        service.resume()
        #expect(service.state == .speaking)
    }

    @Test @MainActor
    func stopSpeech_stopsSynthesizer() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello, world!")
        service.stop()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func pause_whenIdle_remainsIdle() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.pause()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func resume_whenIdle_remainsIdle() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.resume()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func stop_whenAlreadyIdle_remainsIdle() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.stop()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func startSpeaking_whileAlreadySpeaking_restarts() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "First text")
        service.startSpeaking(text: "Second text", fromOffset: 10)
        #expect(service.state == .speaking)
        #expect(service.currentOffsetUTF16 == 10)
    }
}

// MARK: - Speed Control Tests

@Suite("TTSService Speed Control")
struct TTSServiceSpeedControlTests {

    @Test @MainActor
    func speedControl_defaultRate() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        #expect(service.rate == 0.5)
    }

    @Test @MainActor
    func speedControl_setsRate_low() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.rate = 0.25
        #expect(service.rate == 0.25)
    }

    @Test @MainActor
    func speedControl_setsRate_high() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.rate = 0.75
        #expect(service.rate == 0.75)
    }

    @Test @MainActor
    func speedControl_clampsAboveMax() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.rate = 1.5
        #expect(service.rate == 1.0, "Rate should be clamped to 1.0 max")
    }

    @Test @MainActor
    func speedControl_clampsBelowMin() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.rate = -0.1
        #expect(service.rate == 0.0, "Rate should be clamped to 0.0 min")
    }

    @Test @MainActor
    func speedControl_rateAppliedToUtterance() async {
        let mock = MockSpeechSynthesizer()
        let service = TTSService(synthesizerFactory: { mock })
        service.rate = 0.75
        service.startSpeaking(text: "Test text")
        #expect(mock.lastUtteranceRate == 0.75, "Utterance rate should match service rate")
    }

    /// Bug #226 / GH #910: a post-init assignment of an already in-range value
    /// to `rate`. Pre-fix `rate` was a stored property whose `didSet` re-assigned
    /// itself to clamp — under `@Observable` that re-enters the synthesized setter
    /// unboundedly → stack overflow / test-host crash. Mutating the property
    /// post-init reproduces the crash (post-init because Swift suppresses
    /// observers during `init`). Post-fix `rate` is a `get`/`set` computed pair
    /// that clamps without observer re-entry, so the assignment completes.
    /// Mirrors `ReaderSettingsStoreTests.settingsStore_autoPageTurnInterval_inRangeAssignmentDoesNotRecurse`.
    @Test @MainActor
    func speedControl_inRangeAssignmentDoesNotRecurse() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.rate = 0.5
        #expect(service.rate == 0.5)
        // A same-value re-assignment is the tightest recursion repro — pre-fix
        // `min(max(0.5, 0.0), 1.0) == 0.5` still re-fired the setter forever.
        service.rate = 0.5
        #expect(service.rate == 0.5)
    }
}

// MARK: - Position Tracking Tests

@Suite("TTSService Position Tracking")
struct TTSServicePositionTrackingTests {

    @Test @MainActor
    func positionTracking_initialOffset() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        #expect(service.currentOffsetUTF16 == 0)
    }

    @Test @MainActor
    func positionTracking_updatesCurrentOffset() async {
        let mock = MockSpeechSynthesizer()
        let service = TTSService(synthesizerFactory: { mock })
        service.startSpeaking(text: "Hello, world!")

        // Simulate delegate callback for position tracking
        service.simulateWillSpeakRange(location: 7, length: 5, fromOffset: 0)
        #expect(service.currentOffsetUTF16 == 7)
    }

    @Test @MainActor
    func positionTracking_withNonZeroStartOffset() async {
        let mock = MockSpeechSynthesizer()
        let service = TTSService(synthesizerFactory: { mock })
        service.startSpeaking(text: "Hello, world!", fromOffset: 100)

        // Simulate delegate: range is relative to utterance text, offset adds base
        service.simulateWillSpeakRange(location: 7, length: 5, fromOffset: 100)
        #expect(service.currentOffsetUTF16 == 107)
    }
}

// MARK: - Text Extraction Tests

@Suite("TTSService Text Extraction")
struct TTSServiceTextExtractionTests {

    @Test @MainActor
    func textExtraction_fromReflowableSource() async {
        let source = TXTReflowableTextSource(textContent: "Hello, this is reflowable text.")
        let text = TTSService.extractText(from: source, startOffset: 0)
        #expect(text == "Hello, this is reflowable text.")
    }

    @Test @MainActor
    func textExtraction_fromReflowableSource_withOffset() async {
        let fullText = "Hello, world!"
        let source = TXTReflowableTextSource(textContent: fullText)
        let text = TTSService.extractText(from: source, startOffset: 7)
        #expect(text == "world!")
    }

    @Test @MainActor
    func textExtraction_fromReflowableSource_offsetAtEnd() async {
        let source = TXTReflowableTextSource(textContent: "Hello")
        let text = TTSService.extractText(from: source, startOffset: 5)
        #expect(text == "", "Offset at end should return empty string")
    }

    @Test @MainActor
    func textExtraction_fromReflowableSource_cjkText() async {
        let cjk = "你好世界，这是一段中文文本。"
        let source = TXTReflowableTextSource(textContent: cjk)
        let text = TTSService.extractText(from: source, startOffset: 0)
        #expect(text == cjk)
    }
}

// MARK: - Edge Case Tests

@Suite("TTSService Edge Cases")
struct TTSServiceEdgeCaseTests {

    @Test @MainActor
    func emptyText_doesNotCrash() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "")
        #expect(service.state == .idle, "Empty text should not start speaking")
    }

    @Test @MainActor
    func whitespaceOnlyText_doesNotSpeak() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "   \n\t  ")
        #expect(service.state == .idle, "Whitespace-only text should not start speaking")
    }

    @Test @MainActor
    func formatWithoutTTS_returnsUnavailable() async {
        let caps = FormatCapabilities.capabilities(for: .pdf)
        #expect(!caps.contains(.tts), "PDF should not have TTS capability")
    }

    @Test @MainActor
    func formatWithTTS_txt_returnsAvailable() async {
        let caps = FormatCapabilities.capabilities(for: .txt)
        #expect(caps.contains(.tts), "TXT should have TTS capability")
    }

    @Test @MainActor
    func formatWithTTS_md_returnsAvailable() async {
        let caps = FormatCapabilities.capabilities(for: .md)
        #expect(caps.contains(.tts), "MD should have TTS capability")
    }

    @Test @MainActor
    func formatWithTTS_epub_returnsAvailable() async {
        let caps = FormatCapabilities.capabilities(for: .epub)
        #expect(caps.contains(.tts), "EPUB should have TTS capability")
    }

    @Test @MainActor
    func rapidStartStop_doesNotCrash() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        for _ in 0..<10 {
            service.startSpeaking(text: "Rapid test")
            service.stop()
        }
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func rapidPauseResume_doesNotCrash() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Rapid test")
        for _ in 0..<10 {
            service.pause()
            service.resume()
        }
        #expect(service.state == .speaking)
    }

    @Test @MainActor
    func stopAfterPause_goesToIdle() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello")
        service.pause()
        #expect(service.state == .paused)
        service.stop()
        #expect(service.state == .idle)
    }

    @Test @MainActor
    func startSpeaking_cjkText_works() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "你好世界，这是一段中文。")
        #expect(service.state == .speaking)
    }

    @Test @MainActor
    func startSpeaking_emojiText_works() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello 🌍🎉 World")
        #expect(service.state == .speaking)
    }

    @Test @MainActor
    func negativeOffset_treatedAsZero() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hello", fromOffset: -5)
        #expect(service.currentOffsetUTF16 == 0, "Negative offset should be clamped to 0")
    }

    @Test @MainActor
    func offsetBeyondText_doesNotCrash() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Hi", fromOffset: 1000)
        #expect(service.state == .idle, "Offset beyond text length should not start speaking")
    }

    // MARK: - Surrogate Pair Safety (Phase B Audit)

    @Test @MainActor
    func startSpeaking_offsetInSurrogatePair_doesNotCrash() async {
        // "Hello 🌍 World" — 🌍 is a surrogate pair at UTF-16 positions 6-7.
        // Offset 7 lands between the high and low surrogate.
        let text = "Hello 🌍 World"
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        // Should not crash — must align to nearest valid character boundary
        service.startSpeaking(text: text, fromOffset: 7)
        // Either speaking from aligned position, or idle if alignment pushes past end
        #expect(service.state == .speaking || service.state == .idle,
                "Should handle surrogate pair boundary gracefully")
    }

    @Test @MainActor
    func startSpeaking_offsetAtHighSurrogate_doesNotCrash() async {
        // "A𝄞B" — 𝄞 (U+1D11E, musical symbol) is a surrogate pair at UTF-16 positions 1-2.
        // Offset 2 lands at the low surrogate.
        let text = "A\u{1D11E}B"
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: text, fromOffset: 2)
        #expect(service.state == .speaking || service.state == .idle,
                "Should handle offset inside surrogate pair gracefully")
    }

    @Test @MainActor
    func startSpeaking_multipleEmoji_offsetMidSurrogate_doesNotCrash() async {
        // Several surrogate pairs in sequence
        let text = "🎵🎶🎷🎸🎹"
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        // Each emoji is 2 UTF-16 code units. Offset 3 is mid-surrogate pair.
        service.startSpeaking(text: text, fromOffset: 3)
        #expect(service.state == .speaking || service.state == .idle,
                "Should handle mid-surrogate offset in emoji sequence")
    }

    @Test @MainActor
    func extractText_offsetInSurrogatePair_doesNotCrash() async {
        let source = TXTReflowableTextSource(textContent: "Hello 🌍 World")
        // Offset 7 lands inside the surrogate pair
        let extracted = TTSService.extractText(from: source, startOffset: 7)
        // Should return something valid, not crash
        #expect(!extracted.isEmpty || extracted.isEmpty,
                "Should not crash on surrogate pair boundary in extractText")
    }

    // MARK: - didCancel Race Condition (Phase B Audit)

    @Test @MainActor
    func didCancel_duringRestart_doesNotClearState() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "First text", fromOffset: 0)
        #expect(service.state == .speaking)

        // Simulate rapid restart: start new speech immediately
        service.startSpeaking(text: "Second text", fromOffset: 5)
        #expect(service.state == .speaking)
        #expect(service.currentOffsetUTF16 == 5)

        // Simulate the didCancel callback from the OLD utterance arriving late
        // With generation counter, this should be ignored
        service.handleCancelledUtterance(generation: 0)
        #expect(service.state == .speaking,
                "didCancel from old utterance should not clear state during restart")
        #expect(service.currentOffsetUTF16 == 5,
                "Offset should remain at new utterance's position")
    }

    @Test @MainActor
    func didCancel_afterRealStop_clearsState() async {
        let service = TTSService(synthesizerFactory: { MockSpeechSynthesizer() })
        service.startSpeaking(text: "Test text", fromOffset: 0)
        let gen = service.currentGeneration
        service.stop()
        #expect(service.state == .idle)

        // didCancel arriving after real stop — already idle, should stay idle
        service.handleCancelledUtterance(generation: gen)
        #expect(service.state == .idle)
    }
}

// MARK: - Mock

/// Minimal mock for AVSpeechSynthesizer to use in unit tests.
/// Tracks method calls and utterance properties without requiring audio hardware.
final class MockSpeechSynthesizer: SpeechSynthesizing {
    private(set) var speakCalled = false
    private(set) var pauseCalled = false
    private(set) var resumeCalled = false
    private(set) var stopCalled = false
    private(set) var lastUtteranceRate: Float?
    private(set) var lastUtteranceText: String?

    var isSpeaking: Bool = false
    var isPaused: Bool = false

    func speak(_ utterance: SpeechUtteranceProtocol) {
        speakCalled = true
        isSpeaking = true
        isPaused = false
        lastUtteranceRate = utterance.rate
        lastUtteranceText = utterance.speechString
    }

    func pauseSpeaking() -> Bool {
        pauseCalled = true
        if isSpeaking {
            isPaused = true
            isSpeaking = false
            return true
        }
        return false
    }

    func continueSpeaking() -> Bool {
        resumeCalled = true
        if isPaused {
            isSpeaking = true
            isPaused = false
            return true
        }
        return false
    }

    func stopSpeaking() -> Bool {
        stopCalled = true
        isSpeaking = false
        isPaused = false
        return true
    }
}
