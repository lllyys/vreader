// Purpose: Protocol abstracting AVSpeechSynthesizer for testability.
// Allows injecting a mock in unit tests while using the real synthesizer in production.
//
// Key decisions:
// - Minimal surface: speak, pause, resume, stop + state queries.
// - SpeechUtteranceProtocol wraps AVSpeechUtterance for the same reason.
// - Protocols are not @MainActor — synthesizer can be used from any context.
//
// @coordinates-with: TTSService.swift

import AVFoundation

/// Protocol for utterance configuration, abstracting AVSpeechUtterance.
protocol SpeechUtteranceProtocol {
    var speechString: String { get }
    var rate: Float { get set }
    var pitchMultiplier: Float { get set }
    var volume: Float { get set }
}

/// Protocol abstracting AVSpeechSynthesizer for dependency injection.
protocol SpeechSynthesizing: AnyObject {
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }

    func speak(_ utterance: SpeechUtteranceProtocol)
    @discardableResult func pauseSpeaking() -> Bool
    @discardableResult func continueSpeaking() -> Bool
    @discardableResult func stopSpeaking() -> Bool
}

// MARK: - AVFoundation Conformances

/// AVSpeechUtterance already has speechString, rate, pitchMultiplier, volume.
/// This extension just declares conformance — no new implementations needed.
extension AVSpeechUtterance: SpeechUtteranceProtocol {}

// MARK: - XCUITest override flag

#if DEBUG
/// Feature #45 WI-4e. Set to `true` by `VReaderApp.init` when the
/// `--tts-test-mode` launch arg is present. Read by `TTSService` at
/// construction time to choose between `SystemSpeechSynthesizer` and
/// `XCUITestMockSpeechSynthesizer`. The flag is written exactly once per
/// process at App.init (defensively, both branches) and read on the
/// same MainActor in TTSService.init — no cross-actor write contention.
@MainActor
enum TTSTestOverride {
    static var useMockSynthesizer: Bool = false
}
#endif

/// Wrapper that adapts AVSpeechSynthesizer to SpeechSynthesizing protocol.
/// AVSpeechSynthesizer's speak() takes AVSpeechUtterance, not our protocol,
/// so we wrap it.
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing {
    let synthesizer = AVSpeechSynthesizer()

    /// Delegate forwarding: TTSService sets this to receive callbacks.
    weak var delegateTarget: AVSpeechSynthesizerDelegate? {
        didSet { synthesizer.delegate = delegateTarget }
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }
    var isPaused: Bool { synthesizer.isPaused }

    func speak(_ utterance: SpeechUtteranceProtocol) {
        if let avUtterance = utterance as? AVSpeechUtterance {
            synthesizer.speak(avUtterance)
        }
    }

    @discardableResult
    func pauseSpeaking() -> Bool {
        synthesizer.pauseSpeaking(at: .immediate)
    }

    @discardableResult
    func continueSpeaking() -> Bool {
        synthesizer.continueSpeaking()
    }

    @discardableResult
    func stopSpeaking() -> Bool {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
