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
#if canImport(WebKit)
import WebKit
#endif

/// Read-only handle to the active reader. Conformers are owned by their
/// presenting view; the registry holds a weak reference to avoid retain
/// cycles. AnyObject required so weakness is meaningful.
@MainActor
protocol DebugReaderProbe: AnyObject, Sendable {
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

/// Errors thrown by `DebugReaderRegistry.awaitReader`.
enum DebugReaderRegistryError: Error, Equatable {
    /// No reader matching the requested fingerprintKey registered before
    /// the timeout expired.
    case awaitReaderTimeout(fingerprintKey: String)
}

/// App-process registry of the currently-active reader. Single-entry: the
/// app pushes one reader at a time, so newer registrations replace older.
@MainActor
final class DebugReaderRegistry {
    static let shared = DebugReaderRegistry()
    private weak var activeReader: AnyObject?

    /// Bug #126: weak side-channel ref to the active EPUB webview, paired
    /// with the fingerprintKey of the book it belongs to. Set by
    /// `EPUBWebViewBridgeCoordinator.webView(_:didFinish:)` via
    /// `setActiveEPUBWebView(_:for:)`. Read by `epubWebView(for:)` which
    /// returns the webview only if the requested key matches the stored
    /// key — this guards against a late `didFinish` from an outgoing book
    /// silently evaluating against the new active probe (Codex audit
    /// 2026-05-06, branch `fix/issue-266-epub-jseval-wiring`). Weak —
    /// registry must not keep the webview alive past its host.
    #if canImport(WebKit)
    private weak var activeEPUBWebViewRef: WKWebView?
    private var activeEPUBWebViewKey: String?

    /// Set the active EPUB webview for `fingerprintKey`. Replaces any
    /// previous binding regardless of key — newer wins, mirroring the
    /// `register(_:)` policy for the probe itself.
    func setActiveEPUBWebView(_ webView: WKWebView, for fingerprintKey: String) {
        activeEPUBWebViewRef = webView
        activeEPUBWebViewKey = fingerprintKey
    }

    /// Return the active EPUB webview iff it was registered for
    /// `fingerprintKey`. Returns nil when no webview is registered, when
    /// the registered webview was deallocated (weak ref cleared), or
    /// when the registered key doesn't match.
    func epubWebView(for fingerprintKey: String) -> WKWebView? {
        guard activeEPUBWebViewKey == fingerprintKey else { return nil }
        return activeEPUBWebViewRef
    }

    /// Test seam — visibility into the raw stored ref / key without the
    /// match check. Used by DebugReaderRegistryTests; production code
    /// goes through `epubWebView(for:)` so stale-mismatch protection
    /// stays on the eval path.
    var rawActiveEPUBWebViewKeyForTests: String? { activeEPUBWebViewKey }
    var rawActiveEPUBWebViewForTests: WKWebView? { activeEPUBWebViewRef }

    /// Bug #141: weak side-channel ref to the active Foliate (AZW3/MOBI)
    /// webview. Mirrors the EPUB binding above — same keyed-protection
    /// shape, same lifecycle, just a separate slot because Foliate's
    /// rendering host is independent of `EPUBWebViewBridge`.
    /// Set by `FoliateViewCoordinator.webView(_:didFinish:)` via
    /// `setActiveFoliateWebView(_:for:)`. Read by `foliateWebView(for:)`
    /// which enforces the same fingerprintKey match. Weak.
    private weak var activeFoliateWebViewRef: WKWebView?
    private var activeFoliateWebViewKey: String?

    /// Set the active Foliate webview for `fingerprintKey`. Replaces any
    /// previous binding regardless of key — newer wins, mirroring the
    /// EPUB and probe-registration policies.
    func setActiveFoliateWebView(_ webView: WKWebView, for fingerprintKey: String) {
        activeFoliateWebViewRef = webView
        activeFoliateWebViewKey = fingerprintKey
    }

    /// Return the active Foliate webview iff it was registered for
    /// `fingerprintKey`. Returns nil when no webview is registered, when
    /// the registered webview was deallocated (weak ref cleared), or
    /// when the registered key doesn't match.
    func foliateWebView(for fingerprintKey: String) -> WKWebView? {
        guard activeFoliateWebViewKey == fingerprintKey else { return nil }
        return activeFoliateWebViewRef
    }

    /// Test seam — symmetric to the EPUB pair.
    var rawActiveFoliateWebViewKeyForTests: String? { activeFoliateWebViewKey }
    var rawActiveFoliateWebViewForTests: WKWebView? { activeFoliateWebViewRef }
    #endif

    /// Per-key waiters added by `awaitReader(fingerprintKey:timeout:)`.
    /// Each waiter carries a UUID token so timeouts remove by identity, not
    /// by first-match — eliminating the race where two callers waiting on
    /// the same key with different timeouts resume the wrong continuation.
    private struct Waiter {
        let token: UUID
        let continuation: CheckedContinuation<DebugReaderProbe, Error>
    }
    private var waiters: [String: [Waiter]] = [:]

    private init() {}

    /// The active reader, if any.
    var current: DebugReaderProbe? {
        activeReader as? DebugReaderProbe
    }

    /// Register `reader` as the active reader. Replaces any previous entry.
    /// Resumes every awaiter whose `fingerprintKey` matches.
    func register(_ reader: DebugReaderProbe) {
        activeReader = reader
        // Resume all waiters whose key matches the new reader's key.
        let key = reader.fingerprintKey
        if let bucket = waiters[key], !bucket.isEmpty {
            waiters[key] = nil
            for waiter in bucket {
                waiter.continuation.resume(returning: reader)
            }
        }
    }

    /// Clear the registry if the given probe is the current entry.
    /// No-op if a different probe is now active (e.g., a quick switch
    /// between readers where unregister fires after a new register).
    func unregister(_ reader: DebugReaderProbe) {
        if activeReader === reader as AnyObject {
            activeReader = nil
            #if canImport(WebKit)
            // Bug #126: also drop the EPUB-webview side-channel when its
            // owning probe leaves. The didFinish callback can outlive
            // the SwiftUI host briefly during dismantle; clearing here
            // prevents an outgoing book's webview from being matched
            // against an incoming reader's key.
            if activeEPUBWebViewKey == reader.fingerprintKey {
                activeEPUBWebViewRef = nil
                activeEPUBWebViewKey = nil
            }
            // Bug #141: same protection for the Foliate webview slot.
            if activeFoliateWebViewKey == reader.fingerprintKey {
                activeFoliateWebViewRef = nil
                activeFoliateWebViewKey = nil
            }
            #endif
        }
    }

    /// Test seam — clear all state. Production paths use unregister.
    /// Cancels every pending waiter with timeout for clean teardown.
    func reset() {
        activeReader = nil
        #if canImport(WebKit)
        activeEPUBWebViewRef = nil
        activeEPUBWebViewKey = nil
        activeFoliateWebViewRef = nil
        activeFoliateWebViewKey = nil
        #endif
        let pendingByKey = waiters
        waiters = [:]
        for (key, bucket) in pendingByKey {
            for waiter in bucket {
                waiter.continuation.resume(
                    throwing: DebugReaderRegistryError.awaitReaderTimeout(fingerprintKey: key)
                )
            }
        }
    }

    /// Wait for a reader matching `fingerprintKey` to register.
    ///
    /// If a matching reader is already active, returns it immediately. Otherwise
    /// suspends until a matching `register(_:)` call resumes the waiter or the
    /// timeout fires. Token-based waiter ownership ensures concurrent waiters
    /// on the same key with different timeouts each resume their OWN continuation.
    ///
    /// - Parameters:
    ///   - fingerprintKey: The book's canonical fingerprint key.
    ///   - timeout: How long to wait before throwing `awaitReaderTimeout`.
    /// - Throws: `DebugReaderRegistryError.awaitReaderTimeout(fingerprintKey:)`
    ///   if no matching reader registers in time.
    func awaitReader(
        fingerprintKey: String,
        timeout: TimeInterval
    ) async throws -> DebugReaderProbe {
        // Fast path: a matching reader is already registered.
        if let probe = current, probe.fingerprintKey == fingerprintKey {
            return probe
        }

        let token = UUID()
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.removeAndTimeout(fingerprintKey: fingerprintKey, token: token)
        }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let waiter = Waiter(token: token, continuation: continuation)
                waiters[fingerprintKey, default: []].append(waiter)
            }
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }

    /// Internal: remove a specific waiter (by token) and resume it with a
    /// timeout error. Identified by token so concurrent waiters on the same
    /// key don't resume each other's continuations.
    private func removeAndTimeout(fingerprintKey: String, token: UUID) {
        guard var bucket = waiters[fingerprintKey],
              let idx = bucket.firstIndex(where: { $0.token == token }) else {
            return
        }
        let waiter = bucket.remove(at: idx)
        if bucket.isEmpty {
            waiters[fingerprintKey] = nil
        } else {
            waiters[fingerprintKey] = bucket
        }
        waiter.continuation.resume(
            throwing: DebugReaderRegistryError.awaitReaderTimeout(fingerprintKey: fingerprintKey)
        )
    }
}

#endif
