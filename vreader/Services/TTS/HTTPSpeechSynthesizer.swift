// Purpose: Feature #72 WI-3 — the `SpeechSynthesizing` adapter that lets the
// live read-aloud path (`TTSService`) speak via the HTTP cloud-TTS provider
// instead of the on-device voice. It is the piece that finally WIRES the
// orphaned `HTTPTTSProvider` (Bug #270) into playback.
//
// Flow per `speak(utterance)`:
//   1. Split the utterance into sentence chunks (`HTTPTTSProvider.chunkText`,
//      the SAME chunker the provider uses) + compute each chunk's UTF-16 range
//      in the ORIGINAL utterance (forward `range(of:)` scan, so the trimmed
//      chunk text doesn't drift the offsets — Gate-2 H3).
//   2. Build a FRESH provider (Gate-2 H4: `HTTPTTSProvider.cancel()` is sticky).
//   3. In a `@MainActor` Task, `await provider.synthesize(chunk)` per chunk
//      (ordered; the await hops off-main, the enqueue lands back on main) and
//      `enqueue` each audio blob into the `HTTPTTSChunkPlayer`; `markInputComplete`
//      after the last.
//   4. Emulate the `AVSpeechSynthesizerDelegate` callbacks `TTSService` consumes
//      (it only uses `willSpeakRange.location`, `didFinish`, `didCancel`): a
//      chunk-range `willSpeakRange` as each chunk's audio starts, `didFinish`
//      when the complete input drains, `didCancel` on stop / synthesis failure
//      (Gate-2 H5 — no new error UI; a clean stop returns the state machine to
//      idle).
//
// Audio session is owned by `TTSService` (Gate-2 M1); this adapter never
// touches `AVAudioSession`.
//
// @coordinates-with: SpeechSynthesizing.swift, HTTPTTSChunkPlayer.swift,
//   HTTPTTSProvider.swift, HTTPTTSConfig.swift, TTSService.swift

import Foundation
import AVFoundation
import OSLog

/// Conforms to the (non-isolated) `SpeechSynthesizing` protocol like
/// `SystemSpeechSynthesizer` does, but its dependencies (`HTTPTTSChunkPlayer`)
/// are `@MainActor`. `TTSService` (the only caller) is `@MainActor`, so every
/// protocol method is invoked on the main actor — the thin `MainActor.assumeIsolated`
/// wrappers below bridge into the `@MainActor` implementations without making
/// the protocol itself `@MainActor` (which would ripple into the XCUITest mock's
/// timer logic). `@unchecked Sendable`: all mutable state is touched only on the
/// main actor.
final class HTTPSpeechSynthesizer: NSObject, SpeechSynthesizing, @unchecked Sendable {

    private static let log = Logger(subsystem: "com.vreader.app", category: "HTTPSpeechSynthesizer")

    /// `TTSService` sets this to receive the emulated delegate callbacks.
    weak var delegateTarget: AVSpeechSynthesizerDelegate?

    var isSpeaking: Bool { MainActor.assumeIsolated { !wantsPaused && player.isPlaying } }
    var isPaused: Bool { MainActor.assumeIsolated { wantsPaused } }

    private let config: HTTPTTSConfig
    private let player: HTTPTTSChunkPlayer
    private let makeProvider: (HTTPTTSConfig) -> TTSProvider
    /// A throwaway `AVSpeechSynthesizer` used only as the `sender` argument the
    /// `AVSpeechSynthesizerDelegate` methods require (we never speak through it).
    private let probeSynth = AVSpeechSynthesizer()

    private var provider: TTSProvider?
    private var synthTask: Task<Void, Never>?
    /// Bumped on each `speak`/`stop` so a finishing task only clears `synthTask`
    /// if it is still the current one (Gate-4 round-2: avoids a stale task
    /// nil-ing a newer speak's task, and avoids a completed task leaving
    /// `synthTask != nil` — which would fake an "active" adapter).
    private var synthGeneration = 0
    private var currentUtterance: AVSpeechUtterance?
    private var chunkRanges: [NSRange] = []
    /// Pause intent. Set by `pauseSpeaking()`; honored even DURING the initial
    /// network-synthesis window (before the first chunk plays) — Gate-4 round-1
    /// H1. While paused, synthesized chunks are buffered rather than enqueued so
    /// audio never starts behind a "paused" UI; `continueSpeaking()` flushes them.
    private var wantsPaused = false
    private var bufferedChunks: [Data] = []
    private var synthesisComplete = false

    @MainActor
    init(
        config: HTTPTTSConfig,
        player: HTTPTTSChunkPlayer = HTTPTTSChunkPlayer(),
        makeProvider: @escaping (HTTPTTSConfig) -> TTSProvider = { HTTPTTSProvider(config: $0) }
    ) {
        self.config = config
        self.player = player
        self.makeProvider = makeProvider
        super.init()
    }

    // MARK: - SpeechSynthesizing (main-actor-bridged)

    func speak(_ utterance: SpeechUtteranceProtocol) {
        // Pass only the Sendable speech string across the isolation bridge
        // (AVSpeechUtterance / SpeechUtteranceProtocol are not Sendable); the
        // @MainActor side reconstructs an AVSpeechUtterance for the delegate
        // (identity isn't required — TTSService's handlers use the range/state,
        // mirroring XCUITestMockSpeechSynthesizer's own utterance captures).
        let text = utterance.speechString
        MainActor.assumeIsolated { performSpeak(text: text) }
    }

    @discardableResult
    func pauseSpeaking() -> Bool { MainActor.assumeIsolated { performPause() } }

    @discardableResult
    func continueSpeaking() -> Bool { MainActor.assumeIsolated { performContinue() } }

    @discardableResult
    func stopSpeaking() -> Bool { MainActor.assumeIsolated { performStop() } }

    // MARK: - @MainActor implementations

    @MainActor
    private func performSpeak(text: String) {
        let av = AVSpeechUtterance(string: text)
        // Cancel any in-flight utterance first (fires didCancel for the outgoing
        // one), then begin the new one.
        _ = performStop()

        currentUtterance = av
        let textChunks = HTTPTTSProvider.chunkText(text)
        chunkRanges = Self.chunkRanges(in: text, chunks: textChunks)

        let provider = makeProvider(config)
        self.provider = provider

        player.onChunkStarted = { [weak self] index in
            guard let self, let utterance = self.currentUtterance,
                  index < self.chunkRanges.count else { return }
            self.delegateTarget?.speechSynthesizer?(
                self.probeSynth,
                willSpeakRangeOfSpeechString: self.chunkRanges[index],
                utterance: utterance
            )
        }
        player.onFinished = { [weak self] in
            guard let self, let utterance = self.currentUtterance else { return }
            self.currentUtterance = nil
            self.delegateTarget?.speechSynthesizer?(self.probeSynth, didFinish: utterance)
        }
        player.onError = { [weak self] _ in self?.fireDidCancel() }
        // Streaming: chunks are enqueued as synthesis produces them.
        player.play(chunks: [], inputComplete: false)

        delegateTarget?.speechSynthesizer?(probeSynth, didStart: av)

        let voice = config.voice
        synthGeneration &+= 1
        let gen = synthGeneration
        synthTask = Task { [weak self] in
            do {
                for chunk in textChunks {
                    try Task.checkCancellation()
                    let data = try await provider.synthesize(text: chunk, voice: voice)
                    try Task.checkCancellation()
                    self?.acceptSynthesizedChunk(data)
                }
                self?.markSynthesisComplete()
            } catch is CancellationError {
                // performStop() already tore everything down.
            } catch {
                Self.log.error("HTTP synthesis failed: \(String(describing: error), privacy: .public)")
                self?.handleSynthesisFailure()
            }
            self?.clearSynthTask(gen: gen)
        }
    }

    /// Clears `synthTask` on a task's terminal path, but only if it is still the
    /// current generation (a stale task must not nil a newer speak's task).
    @MainActor
    private func clearSynthTask(gen: Int) {
        if gen == synthGeneration { synthTask = nil }
    }

    /// Buffers a synthesized chunk while paused, else hands it to the player.
    @MainActor
    private func acceptSynthesizedChunk(_ data: Data) {
        if wantsPaused {
            bufferedChunks.append(data)
        } else {
            player.enqueue(data)
        }
    }

    /// Records synthesis completion; defers the player's `markInputComplete`
    /// until any buffered chunks have been flushed (on resume).
    @MainActor
    private func markSynthesisComplete() {
        synthesisComplete = true
        if !wantsPaused { player.markInputComplete() }
    }

    @MainActor
    private func performPause() -> Bool {
        // Honor pause even during the initial network window (before the first
        // chunk plays): record the intent + buffer further chunks. Always
        // succeeds while an utterance is in flight so TTSService's state stays
        // consistent (Gate-4 round-1 H1).
        guard !wantsPaused, synthTask != nil || player.isPlaying else { return false }
        wantsPaused = true
        if player.isPlaying { player.pause() }
        return true
    }

    @MainActor
    private func performContinue() -> Bool {
        guard wantsPaused else { return false }
        wantsPaused = false
        // Flush chunks that arrived while paused, then resume.
        let pending = bufferedChunks
        bufferedChunks = []
        for chunk in pending { player.enqueue(chunk) }
        if player.isPaused { player.resume() }
        if synthesisComplete { player.markInputComplete() }
        return true
    }

    @MainActor
    private func performStop() -> Bool {
        let wasActive = player.isPlaying || player.isPaused || synthTask != nil || wantsPaused
        synthGeneration &+= 1 // invalidate the in-flight task's terminal clearSynthTask
        synthTask?.cancel()
        synthTask = nil
        provider?.cancel()
        provider = nil
        player.stop()
        wantsPaused = false
        bufferedChunks = []
        synthesisComplete = false
        if wasActive { fireDidCancel() }
        return wasActive
    }

    // MARK: - Private

    @MainActor
    private func handleSynthesisFailure() {
        player.stop()
        fireDidCancel()
    }

    /// Fires `didCancel` for the current utterance once, then clears it.
    @MainActor
    private func fireDidCancel() {
        guard let utterance = currentUtterance else { return }
        currentUtterance = nil
        delegateTarget?.speechSynthesizer?(probeSynth, didCancel: utterance)
    }

    /// Computes each chunk's UTF-16 `NSRange` in the ORIGINAL utterance. The
    /// chunker trims whitespace from each chunk, so ranges are found by a
    /// forward `range(of:)` scan from the previous chunk's end (preserving the
    /// skipped whitespace) rather than by summing trimmed chunk lengths
    /// (Gate-2 H3). A chunk that can't be located reuses the previous start
    /// (zero-length) so highlight/scroll never jumps to a wrong offset.
    static func chunkRanges(in original: String, chunks: [String]) -> [NSRange] {
        let ns = original as NSString
        var ranges: [NSRange] = []
        var searchStart = 0
        for chunk in chunks {
            let needle = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty, searchStart <= ns.length else {
                ranges.append(NSRange(location: min(searchStart, ns.length), length: 0))
                continue
            }
            let scan = NSRange(location: searchStart, length: ns.length - searchStart)
            let found = ns.range(of: needle, options: [], range: scan)
            if found.location != NSNotFound {
                ranges.append(found)
                searchStart = found.location + found.length
            } else {
                ranges.append(NSRange(location: searchStart, length: 0))
            }
        }
        return ranges
    }
}
