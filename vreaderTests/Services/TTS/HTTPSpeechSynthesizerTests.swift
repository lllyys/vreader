// Purpose: Tests for HTTPSpeechSynthesizer (feature #72 WI-3) — the adapter
// wiring HTTPTTSProvider into the SpeechSynthesizing/TTSService path. Covers:
//   - chunkRanges (the original-utterance offset mapping, Gate-2 H3),
//   - TTSService.defaultSynthesizer selection (cloud config → HTTP synth),
//   - the emulated AVSpeechSynthesizerDelegate flow (didStart → per-chunk
//     willSpeakRange → didFinish) driven by a stub provider + stub audio,
//   - failure → didCancel, stop → didCancel + provider.cancel.
//
// A stub TTSProvider returns canned audio instantly; a stub SpeechAudioPlaying
// advances the chunk player deterministically; a recording delegate captures
// the emulated callbacks. No network, no audio hardware.
//
// @coordinates-with: HTTPSpeechSynthesizer.swift, HTTPTTSChunkPlayer.swift,
//   HTTPTTSConfigStore.swift, TTSService.swift, GH #1174

import Testing
import Foundation
import AVFoundation
@testable import vreader

@MainActor
@Suite("HTTPSpeechSynthesizer (Feature #72 WI-3)")
struct HTTPSpeechSynthesizerTests {

    // MARK: - Doubles

    /// Returns canned audio per chunk; records calls + cancellation.
    final class StubProvider: TTSProvider, @unchecked Sendable {
        private(set) var synthCount = 0
        private(set) var cancelled = false
        var shouldThrowOnCall: Int?
        enum E: Error { case boom }
        func synthesize(text: String, voice: String) async throws -> Data {
            let n = synthCount
            synthCount += 1
            if let t = shouldThrowOnCall, n == t { throw E.boom }
            return Data("audio-\(n)".utf8)
        }
        func synthesizeChunked(text: String, voice: String, onChunk: @Sendable (Int, Int, Data) -> Void) async throws {}
        func cancel() { cancelled = true }
        var isCancelled: Bool { cancelled }
    }

    @MainActor
    final class StubAudio: SpeechAudioPlaying {
        var onFinish: (() -> Void)?
        var onFailure: (() -> Void)?
        func play() {}
        func pause() {}
        func resume() {}
        func stop() {}
        func finish() { onFinish?() }
    }

    /// Builds a stub audio per chunk so the test can drive finishes.
    @MainActor
    final class AudioFactory {
        private(set) var built: [StubAudio] = []
        func make(_ data: Data) throws -> SpeechAudioPlaying {
            let a = StubAudio(); built.append(a); return a
        }
    }

    final class RecordingDelegate: NSObject, AVSpeechSynthesizerDelegate {
        nonisolated(unsafe) var started = 0
        nonisolated(unsafe) var finished = 0
        nonisolated(unsafe) var cancelled = 0
        nonisolated(unsafe) var willSpeakLocations: [Int] = []
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { started += 1 }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { finished += 1 }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { cancelled += 1 }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance u: AVSpeechUtterance) {
            willSpeakLocations.append(r.location)
        }
    }

    private func validConfig() -> HTTPTTSConfig {
        HTTPTTSConfig(endpoint: "https://tts.example.com/v1", apiKey: "k", voice: "v")
    }

    /// Yields until `predicate` holds or `maxYields` is exhausted — lets the
    /// @MainActor synthesis Task make progress between the test's steps.
    private func pump(_ maxYields: Int = 200, until predicate: () -> Bool) async {
        var n = 0
        while !predicate() && n < maxYields { await Task.yield(); n += 1 }
    }

    // MARK: - chunkRanges (Gate-2 H3 offset mapping)

    @Test func chunkRanges_mapToOriginalUtterancePreservingWhitespace() {
        // Two sentences separated by a space; chunkText trims, so ranges must be
        // located in the original (not summed from trimmed lengths).
        let text = "Hello world. Goodbye now."
        let chunks = HTTPTTSProvider.chunkText(text)
        let ranges = HTTPSpeechSynthesizer.chunkRanges(in: text, chunks: chunks)
        #expect(ranges.count == chunks.count)
        // The first chunk starts at 0; the second starts AFTER the inter-sentence
        // whitespace (location > first chunk's end), proving no drift.
        #expect(ranges.first?.location == 0)
        if ranges.count >= 2 {
            let ns = text as NSString
            // Each range, when substring'd from the original, contains the
            // chunk's trimmed text.
            for (i, r) in ranges.enumerated() where r.length > 0 {
                let sub = ns.substring(with: r)
                #expect(sub.contains(chunks[i].trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }

    @Test func chunkRanges_unlocatableChunkReusesPreviousStart_noJump() {
        let ranges = HTTPSpeechSynthesizer.chunkRanges(in: "abc", chunks: ["abc", "xyz-not-present"])
        #expect(ranges[0].location == 0)
        #expect(ranges[1].length == 0)               // degenerate → zero-length
        #expect(ranges[1].location >= ranges[0].location)
    }

    // MARK: - TTSService.defaultSynthesizer selection

    @Test func defaultSynthesizer_returnsHTTPSynthWhenConfigValid() {
        let suite = "wi3-sel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        var stored = validConfig(); stored.apiKey = ""
        defaults.set(try! JSONEncoder().encode(stored), forKey: HTTPTTSConfigStore.configKey)
        let store = HTTPTTSConfigStore(defaults: defaults, keychain: KeychainStub(value: "k"))
        let synth = TTSService.defaultSynthesizer(configStore: store)
        #expect(synth is HTTPSpeechSynthesizer)
    }

    @Test func defaultSynthesizer_returnsSystemWhenUnconfigured() {
        let store = HTTPTTSConfigStore(defaults: UserDefaults(suiteName: "wi3-none-\(UUID().uuidString)")!,
                                       keychain: KeychainStub(value: nil))
        let synth = TTSService.defaultSynthesizer(configStore: store)
        #expect(synth is SystemSpeechSynthesizer)
    }

    private struct KeychainStub: HTTPTTSKeychainReading {
        let value: String?
        func readString(forAccount account: String) throws -> String? { value }
    }

    // MARK: - Emulated delegate flow

    @Test func speak_emitsDidStart_perChunkWillSpeak_thenDidFinish() async {
        let provider = StubProvider()
        let audio = AudioFactory()
        let delegate = RecordingDelegate()
        let synth = HTTPSpeechSynthesizer(
            config: validConfig(),
            player: HTTPTTSChunkPlayer(makePlayer: audio.make),
            makeProvider: { _ in provider }
        )
        synth.delegateTarget = delegate
        let text = "First sentence. Second sentence."
        let expectedChunks = HTTPTTSProvider.chunkText(text).count

        let expectedLocations = HTTPSpeechSynthesizer
            .chunkRanges(in: text, chunks: HTTPTTSProvider.chunkText(text))
            .map(\.location)

        synth.speak(AVSpeechUtterance(string: text))
        #expect(delegate.started == 1)                       // didStart synchronous

        // Let the synthesis Task synthesize all chunks + start chunk 0.
        await pump { provider.synthCount >= expectedChunks && audio.built.count >= 1 }
        #expect(delegate.willSpeakLocations == [expectedLocations[0]])

        // Finish each chunk in turn → next chunk starts (+ its willSpeak), and
        // finishing the last fires didFinish. Drive until all chunks are built.
        var i = 0
        while i < expectedChunks {
            await pump { audio.built.count > i }
            audio.built[i].finish()
            i += 1
        }
        await pump { delegate.finished == 1 }
        #expect(delegate.finished == 1)
        #expect(delegate.cancelled == 0)
        // Exact per-chunk willSpeak locations, in order (Gate-4 round-1 M2).
        #expect(delegate.willSpeakLocations == expectedLocations)
    }

    // Gate-4 round-2: after a normal completion the adapter is idle — pause
    // must NOT succeed (synthTask is cleared on the terminal path).
    @Test func afterCompletion_isIdle_pauseReturnsFalse() async {
        let provider = StubProvider()
        let audio = AudioFactory()
        let synth = HTTPSpeechSynthesizer(
            config: validConfig(),
            player: HTTPTTSChunkPlayer(makePlayer: audio.make),
            makeProvider: { _ in provider }
        )
        let text = "Only one sentence."
        let n = HTTPTTSProvider.chunkText(text).count
        synth.speak(AVSpeechUtterance(string: text))
        await pump { provider.synthCount >= n && audio.built.count >= 1 }
        var i = 0
        while i < n { await pump { audio.built.count > i }; audio.built[i].finish(); i += 1 }
        await pump { synth.isSpeaking == false }
        #expect(synth.pauseSpeaking() == false, "idle adapter must not enter a fake paused state")
    }

    // Gate-4 round-1 H1: pausing during the initial synthesis window buffers
    // chunks (no audio starts) until resume.
    @Test func pauseBeforeFirstChunk_buffersUntilResume() async {
        let provider = StubProvider()
        let audio = AudioFactory()
        let synth = HTTPSpeechSynthesizer(
            config: validConfig(),
            player: HTTPTTSChunkPlayer(makePlayer: audio.make),
            makeProvider: { _ in provider }
        )
        synth.speak(AVSpeechUtterance(string: "One. Two."))
        // Pause synchronously, before the synthesis Task has run (no await yet).
        #expect(synth.pauseSpeaking() == true)               // succeeds even pre-playback
        #expect(synth.isPaused)

        await pump { provider.synthCount >= 1 }
        #expect(audio.built.isEmpty, "paused → synthesized chunks buffered, no audio started")

        #expect(synth.continueSpeaking() == true)
        await pump { !audio.built.isEmpty }
        #expect(audio.built.count >= 1, "resume flushes buffered chunks into playback")
        #expect(synth.isPaused == false)
    }

    #if DEBUG
    @Test func defaultSynthesizer_mockTakesPrecedenceOverConfig() {
        // Precedence: DEBUG mock > valid HTTP config > system.
        TTSTestOverride.useMockSynthesizer = true
        defer { TTSTestOverride.useMockSynthesizer = false }
        let suite = "wi3-prec-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        var stored = validConfig(); stored.apiKey = ""
        defaults.set(try! JSONEncoder().encode(stored), forKey: HTTPTTSConfigStore.configKey)
        let store = HTTPTTSConfigStore(defaults: defaults, keychain: KeychainStub(value: "k"))
        let synth = TTSService.defaultSynthesizer(configStore: store)
        #expect(synth is XCUITestMockSpeechSynthesizer)
    }
    #endif

    @Test func synthesisFailure_emitsDidCancel() async {
        let provider = StubProvider()
        provider.shouldThrowOnCall = 0                       // first chunk throws
        let delegate = RecordingDelegate()
        let synth = HTTPSpeechSynthesizer(
            config: validConfig(),
            player: HTTPTTSChunkPlayer(makePlayer: AudioFactory().make),
            makeProvider: { _ in provider }
        )
        synth.delegateTarget = delegate
        synth.speak(AVSpeechUtterance(string: "Boom."))
        await pump { delegate.cancelled == 1 }
        #expect(delegate.cancelled == 1)
        #expect(delegate.finished == 0)
    }

    @Test func stop_cancelsProviderAndEmitsDidCancel() async {
        let provider = StubProvider()
        let delegate = RecordingDelegate()
        let synth = HTTPSpeechSynthesizer(
            config: validConfig(),
            player: HTTPTTSChunkPlayer(makePlayer: AudioFactory().make),
            makeProvider: { _ in provider }
        )
        synth.delegateTarget = delegate
        synth.speak(AVSpeechUtterance(string: "Long enough text here."))
        let wasActive = synth.stopSpeaking()
        #expect(wasActive)
        #expect(provider.cancelled)
        #expect(delegate.cancelled == 1)
    }
}
