// Purpose: Active-reader registry for the DebugBridge (feature #44). Tracks
// the currently-presented ReaderContainerView so settle/eval/snapshot can
// query its state, await render-settle events, or evaluate JS in its
// webview. DEBUG-only.
//
// Lifecycle: ReaderContainerView creates a probe in @State, registers it on
// `.onAppear`, and unregisters on `.onDisappear`. The registry holds a weak
// reference so a forgotten unregister doesn't keep the view alive. Only one
// reader is active at a time (vreader pushes a single reader onto the
// NavigationStack); concurrent registration replaces the previous probe.

#if DEBUG

import Foundation

/// Read-only handle to the active reader. Conformers are owned by their
/// presenting view; the registry holds a weak reference to avoid retain
/// cycles. AnyObject required so weakness is meaningful.
@MainActor
protocol DebugReaderProbe: AnyObject {
    /// Canonical fingerprint key of the book currently displayed.
    var fingerprintKey: String { get }
    /// Format name as used in DebugSnapshot ("txt", "md", "pdf", "epub", "azw3").
    var format: String { get }
    /// Current position as a string (CFI / page number / UTF-16 offset).
    /// Nil when no position is available yet (loading, etc.).
    var currentPositionString: String? { get }
    /// Wait for the reader to reach a settled render state, OR throw a
    /// timeout. Per-format implementations decide what "settled" means.
    /// V0 may simply sleep for a small interval as a placeholder.
    func awaitSettle(timeout: TimeInterval) async throws
    /// Evaluate JS in the active webview, if the reader is a webview-backed
    /// format (EPUB / AZW3 via Foliate). Throws `evalUnsupported` for
    /// non-webview readers (TXT / MD / PDF). Returns raw JSON bytes
    /// representing the JS expression's value (`null`, `42`, `"hello"`,
    /// `[1,2]`, `{...}`). Implementations must serialize via
    /// JSONSerialization so the bridge can splat the value into eval
    /// output without double-encoding.
    func evaluateJavaScript(_ script: String) async throws -> Data

    // MARK: - Schema v2 accessors (feature #49 WI-1)
    //
    // These are default-implemented so existing adopters (e.g.
    // `DebugReaderProbeAdapter`) compile without changes. Per-format hosts
    // override when they have richer state to surface (feature #50 will wire
    // these for the per-format snapshot enrichment).

    /// Current TTS state name (`DebugSnapshot.TTSStateValue`). Nil means no
    /// TTS state available — either no service wired, or the host doesn't
    /// surface TTS yet.
    var currentTTSState: String? { get }

    /// Current TTS UTF-16 offset within the active book. Nil when not in a
    /// TTS-capable state.
    var currentTTSOffsetUTF16: Int? { get }

    /// Render phase name (`DebugSnapshot.RenderPhaseValue`). Default is
    /// `idle`; per-format hosts override during loading / rendering / settle
    /// transitions.
    var currentRenderPhase: String { get }

    /// Settings provenance — `"global"` or `"perBook"` from
    /// `DebugSnapshot.SettingsProvenanceValue`. Nil when the host doesn't
    /// surface this distinction yet.
    var currentSettingsProvenance: String? { get }
}

// Default implementations so existing adopters compile without per-host
// changes. Per-format hosts (TXT/EPUB/Foliate/PDF) override during
// feature #50 to wire real values.
extension DebugReaderProbe {
    var currentTTSState: String? { nil }
    var currentTTSOffsetUTF16: Int? { nil }
    var currentRenderPhase: String { DebugSnapshot.RenderPhaseValue.idle }
    var currentSettingsProvenance: String? { nil }
}

#if DEBUG
// DEBUG-only mapping from TTSService.State to the snapshot wire value.
// Lives next to the protocol because both are DEBUG-only.
extension TTSService.State {
    var publicName: String {
        switch self {
        case .idle:     return DebugSnapshot.TTSStateValue.idle
        case .speaking: return DebugSnapshot.TTSStateValue.speaking
        case .paused:   return DebugSnapshot.TTSStateValue.paused
        }
    }
}
#endif

/// Errors thrown by `DebugReaderProbe.evaluateJavaScript`.
enum DebugReaderProbeError: Error, Equatable {
    case evalUnsupported(format: String)
    case settleTimeout
}

/// App-process registry of the currently-active reader. Single-entry: the
/// app pushes one reader at a time, so newer registrations replace older.
@MainActor
final class DebugReaderRegistry {
    static let shared = DebugReaderRegistry()
    private weak var activeReader: AnyObject?

    private init() {}

    /// The active reader, if any.
    var current: DebugReaderProbe? {
        activeReader as? DebugReaderProbe
    }

    /// Register `reader` as the active reader. Replaces any previous entry.
    func register(_ reader: DebugReaderProbe) {
        activeReader = reader
    }

    /// Clear the registry if the given probe is the current entry.
    /// No-op if a different probe is now active (e.g., a quick switch
    /// between readers where unregister fires after a new register).
    func unregister(_ reader: DebugReaderProbe) {
        if activeReader === reader as AnyObject {
            activeReader = nil
        }
    }

    /// Test seam — clear all state. Production paths use unregister.
    func reset() {
        activeReader = nil
    }
}

#endif
