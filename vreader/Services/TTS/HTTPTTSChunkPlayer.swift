// Purpose: Feature #72 WI-2 — sequential audio-chunk playback queue for the
// HTTP cloud-TTS path. The `HTTPSpeechSynthesizer` adapter (WI-3) feeds it the
// per-sentence audio `Data` chunks `HTTPTTSProvider.synthesizeChunked` returns
// (streaming: chunks arrive over time); this plays them back-to-back via an
// `AVAudioPlayer` (behind a `SpeechAudioPlaying` seam so the queue logic is
// unit-testable without audio hardware), firing `onChunkStarted(index)` as each
// chunk begins (the adapter turns that into a chunk-range `willSpeakRange`) and
// `onFinished` once the LAST chunk of a COMPLETE input has played.
//
// Key decisions:
// - **Audio session is NOT managed here** (Gate-2 M1): `TTSService` owns
//   `AVAudioSession`. This player only plays/pauses/stops `AVAudioPlayer`s.
// - **One `AVAudioPlayer` per chunk**, advanced on `audioPlayerDidFinishPlaying`.
// - **Generation token** (Gate-4 round-1 H1): every chunk's `onFinish` closure
//   captures the generation at start; `stop()`/`play()` bump it so a LATE finish
//   from a stopped/replaced player can never advance the queue or fire
//   `onFinished`. The old player's `onFinish` is also detached on stop/replace.
// - **Drain ≠ complete** (Gate-4 round-1 H2): because chunks stream in via
//   `enqueue`, draining the queue does NOT mean the input is done. `onFinished`
//   fires only when the queue drains AND `markInputComplete()` has been called
//   (or `play(chunks:)` declared the input already complete).
// - **`SpeechAudioPlaying` seam** with explicit success/failure: a chunk that
//   finishes UNsuccessfully routes to `onError` (Gate-4 round-1 M2), not a
//   silent advance.
//
// @coordinates-with: HTTPSpeechSynthesizer.swift (WI-3 consumer),
//   HTTPTTSProvider.swift (chunk source), TTSService.swift (audio session owner)

import Foundation
import AVFoundation
import OSLog

/// The audio-backend seam a `HTTPTTSChunkPlayer` plays one chunk through.
/// Production wraps `AVAudioPlayer`; tests stub it to advance deterministically.
@MainActor
protocol SpeechAudioPlaying: AnyObject {
    /// Invoked when this chunk's playback finishes SUCCESSFULLY (drives the
    /// queue to the next chunk). Not called on `stop()`.
    var onFinish: (() -> Void)? { get set }
    /// Invoked when this chunk's playback finishes UNSUCCESSFULLY (decode /
    /// playback error) — routes to the queue's error path, not an advance.
    var onFailure: (() -> Void)? { get set }
    func play()
    func pause()
    func resume()
    func stop()
}

/// Plays a sequence of audio `Data` chunks back-to-back. `@MainActor`.
@MainActor
final class HTTPTTSChunkPlayer {

    private static let log = Logger(subsystem: "com.vreader.app", category: "HTTPTTSChunkPlayer")

    private let makePlayer: @MainActor (Data) throws -> SpeechAudioPlaying

    private var queue: [Data] = []
    private var index = 0
    private var current: SpeechAudioPlaying?
    /// Bumped on `stop()`/`play()` so a late `onFinish` from a stopped/replaced
    /// player (which captured the prior generation) is ignored.
    private var generation = 0
    /// Whether all input chunks have been enqueued. `onFinished` fires only
    /// when the queue drains AND this is true.
    private var inputComplete = false
    /// One-shot guard so `onFinished` fires at most once per playback
    /// (Gate-4 round-2: a repeated `markInputComplete()` / a drain after a
    /// already-completed run must not re-fire). Reset by `play()` / `stop()`.
    private var completionDelivered = false

    private(set) var isPlaying = false
    private(set) var isPaused = false

    /// Fired with the chunk index as each chunk's audio STARTS.
    var onChunkStarted: ((Int) -> Void)?
    /// Fired once the LAST chunk of a complete input has finished. NOT on stop.
    var onFinished: (() -> Void)?
    /// Fired on a chunk build failure or an unsuccessful playback finish.
    var onError: ((Error) -> Void)?

    enum PlaybackError: Error { case chunkPlaybackFailed }

    init(makePlayer: @escaping @MainActor (Data) throws -> SpeechAudioPlaying = { data in
        try AVAudioPlayerBox(data: data)
    }) {
        self.makePlayer = makePlayer
    }

    /// Plays `chunks` from the first. `inputComplete` (default true) means this
    /// is the entire input — pass `false` when streaming chunks in via
    /// `enqueue` + a later `markInputComplete()`.
    func play(chunks: [Data], inputComplete: Bool = true) {
        resetForNewPlayback()
        queue = chunks
        self.inputComplete = inputComplete
        guard !queue.isEmpty else {
            if inputComplete { deliverCompletion() }
            return
        }
        startCurrent()
    }

    /// Appends a streamed chunk. If the queue had drained (idle, not stopped),
    /// resumes from where it left off.
    func enqueue(_ chunk: Data) {
        queue.append(chunk)
        if !isPlaying && !isPaused && index < queue.count {
            startCurrent()
        }
    }

    /// Signals that no more chunks will be enqueued. If the queue has already
    /// drained, fires `onFinished` now; otherwise the last chunk's finish will.
    func markInputComplete() {
        inputComplete = true
        if !isPlaying && !isPaused && index >= queue.count {
            deliverCompletion()
        }
    }

    func pause() {
        guard isPlaying else { return }
        current?.pause()
        isPlaying = false
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        current?.resume()
        isPaused = false
        isPlaying = true
    }

    /// Stops + clears the queue. Idempotent. Never fires `onFinished`.
    func stop() {
        generation &+= 1
        detachCurrent()
        queue = []
        index = 0
        isPlaying = false
        isPaused = false
        inputComplete = false
        completionDelivered = false
    }

    // MARK: - Private

    /// Fires `onFinished` at most once per playback run.
    private func deliverCompletion() {
        guard !completionDelivered else { return }
        completionDelivered = true
        onFinished?()
    }

    private func resetForNewPlayback() {
        generation &+= 1
        detachCurrent()
        index = 0
        isPlaying = false
        isPaused = false
        completionDelivered = false
    }

    /// Detaches the current player's callbacks (so a stale finish can't fire)
    /// and stops it.
    private func detachCurrent() {
        current?.onFinish = nil
        current?.onFailure = nil
        current?.stop()
        current = nil
    }

    private func startCurrent() {
        guard index < queue.count else {
            isPlaying = false
            if inputComplete { deliverCompletion() }
            return
        }
        let gen = generation
        do {
            let player = try makePlayer(queue[index])
            player.onFinish = { [weak self] in self?.handleFinish(gen: gen) }
            player.onFailure = { [weak self] in self?.handleFailure(gen: gen) }
            current = player
            isPlaying = true
            isPaused = false
            player.play()
            onChunkStarted?(index)
        } catch {
            Self.log.error("chunk \(self.index) playback build failed: \(String(describing: error), privacy: .public)")
            isPlaying = false
            onError?(error)
        }
    }

    private func handleFinish(gen: Int) {
        guard gen == generation else { return } // stale (stopped/replaced) → ignore
        index += 1
        current = nil
        startCurrent()
    }

    private func handleFailure(gen: Int) {
        guard gen == generation else { return }
        Self.log.error("chunk \(self.index) playback finished unsuccessfully")
        isPlaying = false
        current = nil
        onError?(PlaybackError.chunkPlaybackFailed)
    }
}

/// Production `SpeechAudioPlaying` backed by `AVAudioPlayer`.
@MainActor
final class AVAudioPlayerBox: NSObject, SpeechAudioPlaying, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    var onFailure: (() -> Void)?
    private let player: AVAudioPlayer

    init(data: Data) throws {
        player = try AVAudioPlayer(data: data)
        super.init()
        player.delegate = self
        player.prepareToPlay()
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func resume() { player.play() }
    func stop() { player.stop() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if flag { self.onFinish?() } else { self.onFailure?() }
        }
    }
}
