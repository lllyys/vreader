// Purpose: Default DebugReaderProbe implementation for ReaderContainerView
// (feature #44 DebugBridge). Holds book identity + format + a position
// closure provided by the container, and wires a v0 settle implementation
// (small fixed delay) plus a "not yet supported" eval default.
//
// Per-format settle hooks (Foliate `relocate` event, TextKit layout
// completion) replace the v0 sleep when those land. Webview-backed
// evaluateJavaScript is wired by EPUB/AZW3 readers via subclassing or
// composition once the active webview is exposed.
// DEBUG-only.
//
// CURRENT STATE: ReaderContainerView always registers a default adapter
// with no jsEvaluator. The eval bridge handler is fully wired (parses,
// validates, writes a JSON result file with raw JSON values) but no
// reader supplies a live evaluator yet, so eval?bridge=foliate against
// real EPUB/AZW3 books always writes
// `{"error": "eval unsupported for format: <fmt>"}`. The live evaluator
// lands when EPUB/AZW3 plugs in here — the bridge plumbing does not
// need to change at that point. Implementers must serialize the JS
// result via JSONSerialization (handle JS undefined → NSNull, Date →
// .toISOString in JS, circular refs → catch and wrap as error string).

#if DEBUG

import Foundation

@MainActor
final class DebugReaderProbeAdapter: DebugReaderProbe {
    let fingerprintKey: String
    let format: String
    private let positionProvider: @MainActor () -> String?

    /// Optional override for awaitSettle. When nil, the adapter sleeps a
    /// small fixed interval (a stand-in until per-format hooks land).
    var settleStrategy: (@MainActor (TimeInterval) async throws -> Void)?

    /// Bug #257: live position string pushed by the host. When set, it takes
    /// precedence over `positionProvider` so `snapshot.position` reflects the
    /// reader's current location (e.g. after an `open?position=N` seek). The
    /// host (`ReaderContainerView`) writes this from its
    /// `.readerPositionDidChange` observer. Nil falls back to `positionProvider`
    /// (which itself defaults to nil), preserving the prior "no position"
    /// posture for hosts that don't wire it.
    var livePositionString: String?

    /// Optional JS evaluator. When nil, evaluateJavaScript throws
    /// `evalUnsupported(format:)` — the default for non-webview readers.
    /// Returns raw JSON bytes of the JS value (see DebugReaderProbe doc).
    var jsEvaluator: (@MainActor (String) async throws -> Data)?

    /// Optional TTS state probe. When set, `currentTTSState` and
    /// `currentTTSOffsetUTF16` delegate to the closure's tuple result.
    /// When nil, both fall back to the protocol's default-nil values.
    /// Wire pattern (feature #45 WI-4c-c): `ReaderContainerView` sets this
    /// to a closure that captures its `TTSService` and reports
    /// `(state.publicName, .idle ? nil : currentOffsetUTF16)`.
    var ttsProbe: (@MainActor () -> (state: String, offsetUTF16: Int?))?

    init(
        fingerprintKey: String,
        format: String,
        positionProvider: @MainActor @escaping () -> String? = { nil }
    ) {
        self.fingerprintKey = fingerprintKey
        self.format = format
        self.positionProvider = positionProvider
    }

    var currentPositionString: String? {
        livePositionString ?? positionProvider()
    }

    var currentTTSState: String? {
        ttsProbe?().state
    }

    var currentTTSOffsetUTF16: Int? {
        ttsProbe?().offsetUTF16
    }

    func awaitSettle(timeout: TimeInterval) async throws {
        if let strategy = settleStrategy {
            try await strategy(timeout)
            return
        }
        // V0 placeholder: 100ms is enough for SwiftUI to commit a frame
        // after the reader finishes its initial layout. Replace with
        // per-format hooks (Foliate relocate, TextKit layout-completed).
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func evaluateJavaScript(_ script: String) async throws -> Data {
        if let evaluator = jsEvaluator {
            return try await evaluator(script)
        }
        throw DebugReaderProbeError.evalUnsupported(format: format)
    }
}

#endif
