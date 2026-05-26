// Purpose: Feature #72 WI-4 — high-fidelity integration verification that the
// HTTP cloud-TTS provider is wired end-to-end into read-aloud. Drives the REAL
// stack — `TTSService` → `HTTPSpeechSynthesizer` → `HTTPTTSProvider` (real HTTP
// request building + chunking + status handling) — with only the network
// TRANSPORT (`URLSessionProtocol`) and the audio HARDWARE (`SpeechAudioPlaying`)
// stubbed. Per Feature #72 acceptance criterion 6 + the AGENTS.md close-gate
// exception, this stands in for a live third-party HTTP TTS server (external
// infrastructure not available here): it exercises the SAME code paths a real
// cloud read-aloud would hit, proving the orphaned provider (Bug #270) is now
// actually consumed.
//
// @coordinates-with: TTSService.swift, HTTPSpeechSynthesizer.swift,
//   HTTPTTSProvider.swift, HTTPTTSChunkPlayer.swift, HTTPTTSConfig.swift,
//   dev-docs/verification/feature-72-20260526.md, GH #1174

import Testing
import Foundation
import AVFoundation
@testable import vreader

@MainActor
@Suite("Feature #72 — cloud TTS integration (WI-4)")
struct Feature72CloudTTSIntegrationTests {

    /// Thread-safe recorder for the requests the real provider sends through
    /// the transport seam. `data(for:)` is awaited from the adapter's synthesis
    /// task (not guaranteed main-actor), so access is lock-guarded.
    final class RequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []
        func record(_ request: URLRequest) { lock.lock(); stored.append(request); lock.unlock() }
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    /// Returns canned audio + HTTP 200 for every request (the network transport
    /// seam) and records each `URLRequest`. The real `HTTPTTSProvider` still
    /// builds the request (URL, POST, header, expanded body), checks the
    /// status, and extracts the audio bytes — the recorder lets the test assert
    /// the transport contract directly, not by inference.
    struct StubURLSession: URLSessionProtocol {
        let audio: Data
        let recorder: RequestRecorder
        var statusCode: Int = 200
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            recorder.record(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://x")!,
                statusCode: statusCode, httpVersion: nil, headerFields: nil
            )!
            return (audio, response)
        }
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

    @MainActor
    final class AudioFactory {
        private(set) var built: [StubAudio] = []
        func make(_ data: Data) throws -> SpeechAudioPlaying { let a = StubAudio(); built.append(a); return a }
    }

    private func pump(_ maxYields: Int = 300, until predicate: () -> Bool) async {
        var n = 0
        while !predicate() && n < maxYields { await Task.yield(); n += 1 }
    }

    @Test func cloudTTS_drivesReadAloudThroughTheRealStack() async {
        let endpoint = "https://tts.example.com/v1/speak"
        let config = HTTPTTSConfig(
            endpoint: endpoint,
            apiKey: "secret", voice: "en-US-JennyNeural",
            // Production-matching placeholders: HTTPTTSProvider expands the
            // uppercase {{TEXT}} / {{VOICE}} tokens (buildCustomRequest).
            provider: .custom(
                headers: ["X-Api-Key": "secret"],
                bodyTemplate: "{\"text\":\"{{TEXT}}\",\"voice\":\"{{VOICE}}\"}"
            )
        )
        // REAL provider against a stubbed, request-recording transport.
        let recorder = RequestRecorder()
        let provider = HTTPTTSProvider(
            config: config,
            urlSession: StubURLSession(audio: Data("AUDIO".utf8), recorder: recorder)
        )
        let audio = AudioFactory()
        // REAL adapter + REAL chunk player; only the audio backend is stubbed.
        let synth = HTTPSpeechSynthesizer(
            config: config,
            player: HTTPTTSChunkPlayer(makePlayer: audio.make),
            makeProvider: { _ in provider }
        )
        // REAL TTSService driving the cloud synthesizer.
        let service = TTSService(synthesizerFactory: { synth })

        let text = "Cloud sentence one. Cloud sentence two."
        let chunks = HTTPTTSProvider.chunkText(text)
        let chunkCount = chunks.count
        #expect(chunkCount >= 2)

        service.startSpeaking(text: text, fromOffset: 0)
        #expect(service.state == .speaking)

        // The real provider hits the stub transport per chunk; the adapter feeds
        // each synthesized blob into the player → a stub-audio instance per
        // chunk. `built.count == chunkCount` proves every chunk traversed the
        // cloud path (TTSService → adapter → HTTPTTSProvider → transport).
        await pump { audio.built.count >= 1 }
        #expect(!audio.built.isEmpty, "the cloud path produced playable audio (not the on-device voice)")

        // Drive each chunk to completion → its successor's audio starts →
        // onChunkStarted → a chunk-range willSpeakRange → TTSService updates
        // currentOffsetUTF16. A LATER chunk's range starts past 0 in the
        // original text, so the offset must advance beyond its initial 0 —
        // proving the cloud path actually drives the reader's progress (not
        // just that it played silently).
        var maxOffset = 0
        var i = 0
        while i < chunkCount {
            await pump { audio.built.count > i }
            // Let any pending willSpeakRange Task hop land before sampling.
            await pump(40) { service.currentOffsetUTF16 > maxOffset }
            maxOffset = max(maxOffset, service.currentOffsetUTF16)
            audio.built[i].finish()
            i += 1
        }
        await pump { service.state == .idle }
        maxOffset = max(maxOffset, service.currentOffsetUTF16)

        #expect(audio.built.count == chunkCount, "every text chunk was synthesized via the cloud provider")
        #expect(maxOffset > 0, "a later chunk's willSpeakRange advanced the reader offset past 0 via the cloud path")
        #expect(service.state == .idle, "read-aloud completes (didFinish) through the cloud path")

        // Direct transport-contract assertions: every chunk made one real
        // HTTPTTSProvider → URLSessionProtocol round-trip with the production
        // request shape (POST to the configured endpoint, custom header, and
        // the per-chunk text expanded into the body template). This is what
        // makes the test high-fidelity rather than inferring the cloud path
        // from playback alone.
        let requests = recorder.requests
        #expect(requests.count == chunkCount, "one HTTP request per chunk hit the transport")
        #expect(requests.allSatisfy { $0.httpMethod == "POST" }, "provider POSTs each chunk")
        #expect(requests.allSatisfy { $0.url?.absoluteString == endpoint }, "requests target the configured endpoint")
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Api-Key") == "secret" }, "custom header is sent")
        // Each request body carries its chunk's text, expanded via {{TEXT}}.
        let bodies = requests.map { String(data: $0.httpBody ?? Data(), encoding: .utf8) ?? "" }
        for chunk in chunks {
            let needle = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(bodies.contains { $0.contains(needle) }, "request body carried the chunk text: \(needle)")
        }
    }

    @Test func cloudSynthesisFailure_stopsCleanlyToIdle() async {
        // Acceptance C5: a failing cloud request (HTTP 500) must not wedge the
        // state machine — the adapter surfaces didCancel and TTSService returns
        // to idle. Drives the real provider error path (httpError) end-to-end.
        let config = HTTPTTSConfig(
            endpoint: "https://tts.example.com/v1/speak",
            apiKey: "secret", voice: "v",
            provider: .custom(headers: [:], bodyTemplate: "{\"text\":\"{{TEXT}}\"}")
        )
        let recorder = RequestRecorder()
        let provider = HTTPTTSProvider(
            config: config,
            urlSession: StubURLSession(audio: Data("AUDIO".utf8), recorder: recorder, statusCode: 500)
        )
        let audio = AudioFactory()
        let synth = HTTPSpeechSynthesizer(
            config: config,
            player: HTTPTTSChunkPlayer(makePlayer: audio.make),
            makeProvider: { _ in provider }
        )
        let service = TTSService(synthesizerFactory: { synth })

        service.startSpeaking(text: "This will fail. Then stop.", fromOffset: 0)
        #expect(service.state == .speaking)

        // The first chunk's synthesis throws httpError(500) → adapter
        // handleSynthesisFailure → didCancel → state returns to idle.
        await pump { service.state == .idle }
        #expect(service.state == .idle, "a cloud synthesis failure stops cleanly to idle, not wedged in .speaking")
        #expect(audio.built.isEmpty, "no audio plays when synthesis fails")
        #expect(!recorder.requests.isEmpty, "the failure happened on a real transport round-trip, not before the request")
    }

    @Test func unconfigured_fallsBackToOnDeviceSynthesizer() {
        // No persisted config → defaultSynthesizer returns the on-device synth,
        // i.e. cloud wiring never hijacks the default path.
        let store = HTTPTTSConfigStore(
            defaults: UserDefaults(suiteName: "f72-int-\(UUID().uuidString)")!,
            keychain: StubKeychain(value: nil)
        )
        #expect(TTSService.defaultSynthesizer(configStore: store) is SystemSpeechSynthesizer)
    }

    private struct StubKeychain: HTTPTTSKeychainReading {
        let value: String?
        func readString(forAccount account: String) throws -> String? { value }
    }
}
