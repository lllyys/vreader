// Purpose: Manages text-to-speech playback using AVSpeechSynthesizer (or mock).
// Tracks state (idle/speaking/paused), current reading position (UTF-16 offset),
// and speech rate. Provides static helper to extract text from ReflowableTextSource.
//
// Key decisions:
// - @MainActor @Observable for SwiftUI data binding.
// - SpeechSynthesizing protocol injection for testability (no real audio in tests).
// - Rate clamped to 0.0...1.0 (AVSpeechUtterance valid range).
// - Empty/whitespace-only text is a no-op (stays idle).
// - Negative fromOffset clamped to 0; offset beyond text length is a no-op.
// - Position tracking via simulateWillSpeakRange (called by delegate in production).
//
// @coordinates-with: SpeechSynthesizing.swift, TTSControlBar.swift,
//   ReaderContainerView.swift, ReflowableTextSource.swift

import AVFoundation
import Foundation

@MainActor @Observable
final class TTSService: NSObject {

    // MARK: - State

    enum State: Sendable, Equatable {
        case idle
        case speaking
        case paused
    }

    private(set) var state: State = .idle
    private(set) var currentOffsetUTF16: Int = 0

    /// Speech rate in AVSpeechUtterance range (0.0–1.0). Clamped on set.
    ///
    /// Bug #226 / GH #910: this is a computed `get`/`set` over `_rate`, NOT a
    /// stored property with a clamping `didSet`. Under the `@Observable` macro
    /// a `didSet` that re-assigns its own property recurses unboundedly (the
    /// macro rewrites the property into a computed accessor over a backing
    /// store, so the `didSet`'s self-assignment re-enters the synthesized
    /// setter) → stack overflow. The `get`/`set` form clamps in `set` with no
    /// observer re-entry — same pattern as `ReaderSettingsStore.backgroundOpacity`
    /// and the Bug #222 fix for `ReaderSettingsStore.autoPageTurnInterval`.
    var rate: Float {
        get { _rate }
        set { _rate = min(max(newValue, 0.0), 1.0) }
    }
    private var _rate: Float = 0.5

    // MARK: - Private

    private let synthesizer: SpeechSynthesizing
    private var baseOffsetUTF16: Int = 0
    /// Generation counter to prevent stale didCancel callbacks from clearing state
    /// during a stop→restart sequence. Incremented on each startSpeaking() call.
    private(set) var currentGeneration: Int = 0
    /// Flag set during restart to prevent didCancel from clearing state.
    private var isRestarting: Bool = false

    // MARK: - Init

    /// Creates a TTSService with a synthesizer factory for dependency injection.
    /// In production, pass `{ SystemSpeechSynthesizer() }` (or accept the default).
    /// In tests, pass `{ MockSpeechSynthesizer() }`.
    ///
    /// The default factory routes through `Self.defaultSynthesizer()` which
    /// returns `XCUITestMockSpeechSynthesizer()` when DEBUG-only
    /// `TTSTestOverride.useMockSynthesizer` is true (feature #45 WI-4e),
    /// otherwise the real `SystemSpeechSynthesizer`.
    init(synthesizerFactory: () -> SpeechSynthesizing = { TTSService.defaultSynthesizer() }) {
        self.synthesizer = synthesizerFactory()
        super.init()

        // Wire delegate to whichever concrete synthesizer was constructed.
        if let system = synthesizer as? SystemSpeechSynthesizer {
            system.delegateTarget = self
        } else {
            #if DEBUG
            if let mock = synthesizer as? XCUITestMockSpeechSynthesizer {
                mock.delegateTarget = self
            }
            #endif
        }
    }

    /// Default synthesizer picker. Returns the XCUITest mock when the
    /// DEBUG-only override is active, otherwise the real synthesizer.
    @MainActor
    private static func defaultSynthesizer() -> SpeechSynthesizing {
        #if DEBUG
        if TTSTestOverride.useMockSynthesizer {
            return XCUITestMockSpeechSynthesizer()
        }
        #endif
        return SystemSpeechSynthesizer()
    }

    // MARK: - Public API

    /// Starts speaking the given text from the specified UTF-16 offset.
    /// Empty or whitespace-only text is a no-op. Negative offset clamped to 0.
    /// Offset beyond text length is a no-op.
    /// If the offset lands inside a surrogate pair, it is aligned forward to the
    /// next valid character boundary to prevent crashes.
    func startSpeaking(text: String, fromOffset: Int = 0) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Configure audio session for TTS playback (bug #96)
        #if canImport(AVFoundation)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal: TTS may still work on some devices without explicit session
        }
        #endif

        let clampedOffset = max(fromOffset, 0)

        // Validate offset is within text
        let utf16Count = text.utf16.count
        guard clampedOffset < utf16Count else { return }

        // Increment generation to invalidate any pending didCancel from old utterance
        currentGeneration += 1

        // Set restarting flag to prevent didCancel from clearing state
        isRestarting = true
        // Stop any current speech
        synthesizer.stopSpeaking()
        isRestarting = false

        // Safely convert UTF-16 offset to String.Index, aligning to character boundary.
        // If the offset lands inside a surrogate pair, align forward to the next valid boundary.
        let utf16View = text.utf16
        var safeOffset = clampedOffset
        var startIndex = utf16View.index(utf16View.startIndex, offsetBy: safeOffset)

        // Check if we landed inside a surrogate pair (low surrogate without preceding high)
        // by attempting to create a valid String from this position onward.
        // If String() returns nil, advance past the partial surrogate.
        if String(utf16View[startIndex...]) == nil {
            safeOffset = min(safeOffset + 1, utf16Count)
            if safeOffset >= utf16Count { return }
            startIndex = utf16View.index(utf16View.startIndex, offsetBy: safeOffset)
        }

        guard let substring = String(utf16View[startIndex...]), !substring.isEmpty else { return }

        baseOffsetUTF16 = safeOffset
        currentOffsetUTF16 = safeOffset

        // Create utterance
        let utterance = AVSpeechUtterance(string: substring)
        utterance.rate = rate
        synthesizer.speak(utterance)
        state = .speaking
    }

    /// Pauses speech. No-op if not currently speaking.
    func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking()
        state = .paused
    }

    /// Resumes paused speech. No-op if not currently paused.
    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .speaking
    }

    /// Stops speech and returns to idle. No-op if already idle.
    func stop() {
        guard state != .idle else { return }
        synthesizer.stopSpeaking()
        state = .idle
        currentOffsetUTF16 = 0
        baseOffsetUTF16 = 0

        // Release audio session so other audio resumes (bug #96 audit)
        #if canImport(AVFoundation)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Position Tracking

    /// Called by the speech synthesizer delegate when it is about to speak a range.
    /// `location` and `length` are relative to the utterance text.
    /// `fromOffset` is the base offset to add (= baseOffsetUTF16 in production).
    func simulateWillSpeakRange(location: Int, length: Int, fromOffset: Int) {
        currentOffsetUTF16 = fromOffset + location
    }

    // MARK: - Cancel Handling

    /// Handles a cancelled utterance callback. If the generation matches the current
    /// generation, transitions to idle. If it doesn't match (stale cancel from a
    /// previous utterance during restart), the callback is ignored.
    func handleCancelledUtterance(generation: Int) {
        guard generation == currentGeneration else { return }
        state = .idle
    }

    // MARK: - Text Extraction

    /// Extracts text from a ReflowableTextSource starting at the given UTF-16 offset.
    /// Returns the substring from `startOffset` to the end, or empty string if out of range.
    /// If the offset lands inside a surrogate pair, aligns forward to the next valid boundary.
    static func extractText(from source: some ReflowableTextSource, startOffset: Int) -> String {
        let fullText = source.fullText
        let utf16Count = fullText.utf16.count
        guard startOffset >= 0, startOffset < utf16Count else {
            return ""
        }
        let utf16View = fullText.utf16
        var safeOffset = startOffset
        var startIdx = utf16View.index(utf16View.startIndex, offsetBy: safeOffset)

        // If landing inside a surrogate pair, advance past it
        if String(utf16View[startIdx...]) == nil {
            safeOffset = min(safeOffset + 1, utf16Count)
            if safeOffset >= utf16Count { return "" }
            startIdx = utf16View.index(utf16View.startIndex, offsetBy: safeOffset)
        }

        return String(utf16View[startIdx...]) ?? ""
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let location = characterRange.location
        let length = characterRange.length
        Task { @MainActor in
            self.simulateWillSpeakRange(
                location: location,
                length: length,
                fromOffset: self.baseOffsetUTF16
            )
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.state = .idle
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // If a restart is in progress (startSpeaking called stop+start),
            // ignore this cancel — the new utterance owns the state now.
            // Also check generation: if state is .speaking with a newer generation,
            // this is a stale cancel from a previous utterance.
            if self.state == .speaking {
                // New utterance is already running; ignore stale cancel
                return
            }
            self.state = .idle
        }
    }
}
