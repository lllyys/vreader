// Purpose: Tests for HTTPTTSChunkPlayer (feature #72 WI-2) — sequential
// audio-chunk playback queue. A stub `SpeechAudioPlaying` drives the queue
// deterministically (no real AVAudioPlayer), pinning play-next / pause / resume
// / stop / streaming-enqueue + the generation-token (stale-finish) and
// input-complete (drain ≠ done) semantics from the Gate-4 round-1 fixes.
//
// @coordinates-with: HTTPTTSChunkPlayer.swift, GH #1174 (Feature #72)

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("HTTPTTSChunkPlayer (Feature #72 WI-2)")
struct HTTPTTSChunkPlayerTests {

    @MainActor
    final class StubPlayer: SpeechAudioPlaying {
        var onFinish: (() -> Void)?
        var onFailure: (() -> Void)?
        private(set) var played = false
        private(set) var paused = false
        private(set) var resumed = false
        private(set) var stopped = false
        func play() { played = true }
        func pause() { paused = true }
        func resume() { resumed = true }
        func stop() { stopped = true }
        /// Simulate a successful finish (only advances if still attached).
        func finish() { onFinish?() }
        func failPlayback() { onFailure?() }
    }

    @MainActor
    final class PlayerFactory {
        private(set) var built: [StubPlayer] = []
        var throwOnIndex: Int?
        enum BuildError: Error { case failed }
        func make(_ data: Data) throws -> SpeechAudioPlaying {
            if let t = throwOnIndex, built.count == t { throw BuildError.failed }
            let p = StubPlayer()
            built.append(p)
            return p
        }
    }

    private func chunks(_ n: Int) -> [Data] { (0..<n).map { Data("chunk-\($0)".utf8) } }

    @Test func playsChunksSequentiallyFiringStartedThenFinished() {
        let factory = PlayerFactory()
        var started: [Int] = []
        var finished = false
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.onChunkStarted = { started.append($0) }
        player.onFinished = { finished = true }

        player.play(chunks: chunks(3))  // inputComplete defaults true
        #expect(started == [0])
        factory.built[0].finish()
        #expect(started == [0, 1])
        factory.built[1].finish()
        #expect(started == [0, 1, 2])
        #expect(finished == false)
        factory.built[2].finish()
        #expect(started == [0, 1, 2])
        #expect(finished)
        #expect(player.isPlaying == false)
    }

    @Test func pauseAndResumeMapToCurrentChunkPlayer() {
        let factory = PlayerFactory()
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.play(chunks: chunks(2))
        player.pause()
        #expect(factory.built[0].paused)
        #expect(player.isPaused && !player.isPlaying)
        player.resume()
        #expect(factory.built[0].resumed)
        #expect(!player.isPaused && player.isPlaying)
    }

    // Gate-4 round-1 H1/M3: a late finish from a STOPPED player must NOT advance
    // the queue NOR fire onFinished.
    @Test func stop_thenStaleFinish_doesNotAdvanceNorFinish() {
        let factory = PlayerFactory()
        var finished = false
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.onFinished = { finished = true }
        player.play(chunks: chunks(3))

        player.stop()
        #expect(factory.built[0].stopped)
        #expect(player.isPlaying == false)

        factory.built[0].finish()           // stale callback (detached + gen bumped)
        #expect(factory.built.count == 1, "stale finish must not build a new chunk")
        #expect(finished == false, "stale finish must not fire onFinished")
    }

    // Gate-4 round-1 H1: a stale finish from the OLD queue must not skip into a
    // newly started (replacement) queue.
    @Test func replacePlay_thenStaleFinishFromOldQueue_cannotSkipNewChunk0() {
        let factory = PlayerFactory()
        var started: [Int] = []
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.onChunkStarted = { started.append($0) }
        player.play(chunks: chunks(2))      // builds player[0]
        let stale = factory.built[0]

        player.play(chunks: chunks(2))      // replace → builds player[1] (new chunk 0)
        stale.finish()                      // stale finish from the replaced queue
        // The new queue must still be at its chunk 0 (not skipped to chunk 1).
        #expect(started == [0, 0], "replacement started chunk 0; stale finish must not advance it")
    }

    // Gate-4 round-1 H2: streaming — draining the queue is NOT completion;
    // onFinished waits for markInputComplete().
    @Test func streaming_drainBeforeInputComplete_doesNotFinishPrematurely() {
        let factory = PlayerFactory()
        var finished = false
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.onFinished = { finished = true }

        player.play(chunks: chunks(1), inputComplete: false)  // streaming
        factory.built[0].finish()           // queue drained, but input not complete
        #expect(finished == false, "drain before input-complete must not finish")
        #expect(player.isPlaying == false)

        player.enqueue(Data("late".utf8))    // a late chunk resumes playback
        #expect(factory.built.count == 2)
        factory.built[1].finish()
        #expect(finished == false)           // still not marked complete
        player.markInputComplete()           // now done → fires
        #expect(finished)
    }

    @Test func markInputComplete_whileStillPlaying_finishesOnLastChunk() {
        let factory = PlayerFactory()
        var finished = false
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.onFinished = { finished = true }
        player.play(chunks: chunks(2), inputComplete: false)
        player.markInputComplete()           // input done, but chunks still playing
        #expect(finished == false)
        factory.built[0].finish()
        factory.built[1].finish()
        #expect(finished, "onFinished fires once the last chunk finishes after input-complete")
    }

    // Gate-4 round-2: onFinished fires at most once even if markInputComplete()
    // is called repeatedly after the queue has drained.
    @Test func markInputComplete_isIdempotent_finishesOnce() {
        let factory = PlayerFactory()
        var finishCount = 0
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.onFinished = { finishCount += 1 }
        player.play(chunks: chunks(1), inputComplete: false)
        factory.built[0].finish()           // drained, not complete
        player.markInputComplete()           // fires once
        player.markInputComplete()           // must NOT re-fire
        player.markInputComplete()
        #expect(finishCount == 1)
    }

    @Test func emptyChunksWithInputComplete_firesFinishedImmediately() {
        let factory = PlayerFactory()
        var finished = false
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.onFinished = { finished = true }
        player.play(chunks: [])
        #expect(finished)
        #expect(factory.built.isEmpty)
    }

    @Test func buildFailureFiresOnError_andStopsCleanly() {
        let factory = PlayerFactory()
        factory.throwOnIndex = 0
        var errored = false
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.onError = { _ in errored = true }
        player.play(chunks: chunks(2))
        #expect(errored)
        #expect(player.isPlaying == false)
    }

    // Gate-4 round-1 M2: an UNsuccessful finish routes to onError, not advance.
    @Test func unsuccessfulFinish_firesOnError_doesNotAdvance() {
        let factory = PlayerFactory()
        var errored = false
        var started: [Int] = []
        let player = HTTPTTSChunkPlayer(makePlayer: factory.make)
        player.onError = { _ in errored = true }
        player.onChunkStarted = { started.append($0) }
        player.play(chunks: chunks(2))
        factory.built[0].failPlayback()
        #expect(errored)
        #expect(started == [0], "an unsuccessful finish must not advance to chunk 1")
        #expect(player.isPlaying == false)
    }
}
