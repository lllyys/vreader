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
}

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
