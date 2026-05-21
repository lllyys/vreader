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

    /// Bug #142: token of the currently-active reader. Set by
    /// `setExpectedReaderToken(_:)` from `ReaderContainerView.onAppear`
    /// before `register(_:)`, cleared on unregister/reset. Any incoming
    /// `setActive*WebView(_:for:token:)` call whose token doesn't match
    /// the expected token is treated as a stale didFinish from an
    /// outgoing reader and silently ignored — preventing the new
    /// reader's binding from being clobbered by a late navigation
    /// callback on a same-key webview.
    private var expectedReaderToken: UUID?

    /// Set the expected per-reader token. Pass `nil` to clear.
    func setExpectedReaderToken(_ token: UUID?) {
        expectedReaderToken = token
    }

    /// Test seam — the currently-expected token (or nil). Also read by
    /// `DebugReaderRegistry+Settle.swift`'s stale-write guard (the same
    /// module; `private` would hide it from that extension file).
    var expectedReaderTokenForTests: UUID? { expectedReaderToken }

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
    /// Bug #142: per-reader instance token. UUID generated by
    /// `ReaderContainerView.onAppear` and threaded into the bridges.
    /// Required to disambiguate the same-book reopen race: when a book
    /// is closed and quickly reopened, a late `didFinish` from the
    /// outgoing webview can re-register itself under the same
    /// `fingerprintKey` AFTER the new probe registers its webview.
    /// Adding a token to the binding closes that race — both the key
    /// AND the token must match for `epubWebView(for:token:)` to
    /// return the cached webview.
    private var activeEPUBWebViewToken: UUID?

    /// Set the active EPUB webview for `fingerprintKey` + per-reader
    /// `token`. Rejected (silently) when an `expectedReaderToken` is
    /// set and the incoming token doesn't match — the call is a stale
    /// didFinish from an outgoing reader and must not clobber the
    /// current reader's binding (bug #142 race).
    func setActiveEPUBWebView(_ webView: WKWebView, for fingerprintKey: String, token: UUID) {
        if let expected = expectedReaderToken, expected != token {
            return // stale didFinish; ignore
        }
        activeEPUBWebViewRef = webView
        activeEPUBWebViewKey = fingerprintKey
        activeEPUBWebViewToken = token
    }

    /// Return the active EPUB webview iff it was registered for the
    /// requested `fingerprintKey` AND `token`. Returns nil when either
    /// fails to match, or when the registered webview was deallocated.
    /// The token argument distinguishes a freshly-mounted reader from
    /// any leftover binding from a same-key but earlier reader instance
    /// (bug #142 race).
    func epubWebView(for fingerprintKey: String, token: UUID) -> WKWebView? {
        guard activeEPUBWebViewKey == fingerprintKey,
              activeEPUBWebViewToken == token else { return nil }
        return activeEPUBWebViewRef
    }

    /// Test seam — visibility into the raw stored ref / key / token
    /// without match checks. Production code goes through the keyed
    /// + token-checked accessor.
    var rawActiveEPUBWebViewKeyForTests: String? { activeEPUBWebViewKey }
    var rawActiveEPUBWebViewForTests: WKWebView? { activeEPUBWebViewRef }
    var rawActiveEPUBWebViewTokenForTests: UUID? { activeEPUBWebViewToken }

    /// Bug #250: read-only key accessor used by `+WebViewWait.swift` (a
    /// sibling extension file) to confirm the EPUB slot's key matches a
    /// requested fingerprintKey without requiring the caller to provide a
    /// token. Token-keyed reads stay on `epubWebView(for:token:)`. Marked
    /// `internal` so the extension can read it; production code outside
    /// the registry's extension family must continue to go through
    /// `epubWebView(for:token:)`.
    var activeEPUBWebViewKeyInternal: String? { activeEPUBWebViewKey }

    /// Bug #141: weak side-channel ref to the active Foliate (AZW3/MOBI)
    /// webview. Same keyed + per-reader-token protection as the EPUB
    /// binding above (bug #142). Set by `FoliateViewCoordinator` and
    /// `FoliateSpikeView.Coordinator` via `setActiveFoliateWebView`.
    private weak var activeFoliateWebViewRef: WKWebView?
    private var activeFoliateWebViewKey: String?
    private var activeFoliateWebViewToken: UUID?

    /// Set the active Foliate webview for `fingerprintKey` + per-reader
    /// `token`. Same stale-write protection as the EPUB pair.
    func setActiveFoliateWebView(_ webView: WKWebView, for fingerprintKey: String, token: UUID) {
        if let expected = expectedReaderToken, expected != token {
            return // stale didFinish; ignore
        }
        activeFoliateWebViewRef = webView
        activeFoliateWebViewKey = fingerprintKey
        activeFoliateWebViewToken = token
    }

    /// Return the active Foliate webview iff both `fingerprintKey` and
    /// `token` match. Same race protection as the EPUB pair.
    func foliateWebView(for fingerprintKey: String, token: UUID) -> WKWebView? {
        guard activeFoliateWebViewKey == fingerprintKey,
              activeFoliateWebViewToken == token else { return nil }
        return activeFoliateWebViewRef
    }

    /// Test seam — symmetric to the EPUB triplet.
    var rawActiveFoliateWebViewKeyForTests: String? { activeFoliateWebViewKey }
    var rawActiveFoliateWebViewForTests: WKWebView? { activeFoliateWebViewRef }
    var rawActiveFoliateWebViewTokenForTests: UUID? { activeFoliateWebViewToken }

    /// Bug #250: read-only key accessor used by `+WebViewWait.swift` for
    /// the Foliate (AZW3/MOBI) slot. Same posture as
    /// `activeEPUBWebViewKeyInternal` — token-keyed reads stay on
    /// `foliateWebView(for:token:)`.
    var activeFoliateWebViewKeyInternal: String? { activeFoliateWebViewKey }
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

    /// Bug #141: render-settled state, keyed by `(fingerprintKey, token)`.
    /// `markReaderSettled` records a key here and resumes any settle
    /// waiters; `awaitReaderSettled` fast-paths when its key is present.
    /// Stored here (extensions can't add stored properties) but the
    /// settle methods live in `DebugReaderRegistry+Settle.swift`.
    /// `internal` so the extension can read/mutate it.
    struct SettleKey: Hashable {
        let fingerprintKey: String
        let token: UUID
    }
    var settledKeys: Set<SettleKey> = []

    /// Bug #141: per-`SettleKey` waiters added by `awaitReaderSettled`.
    /// Each carries a UUID token so a timeout removes its OWN waiter, not
    /// a first-match — same race protection as the `awaitReader` `Waiter`.
    struct SettleWaiter {
        let token: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    var settleWaiters: [SettleKey: [SettleWaiter]] = [:]

    private init() {}

    /// Test seam — construct an isolated registry instance that does NOT
    /// share state with `shared`. Swift Testing runs `@Test` methods in
    /// parallel; suites that exercised the singleton via `shared.reset()`
    /// could have one test's `reset()` wipe another concurrently-suspended
    /// test's `settleWaiters` (bug #227 — `awaitReaderSettled` resumed with
    /// a spurious `.settleTimeout`). Each test taking its own instance
    /// removes the shared mutable state entirely. Production code paths
    /// always go through `shared`; this factory is only for tests.
    static func makeIsolatedForTests() -> DebugReaderRegistry {
        DebugReaderRegistry()
    }

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
        // Bug #141 (Codex Medium): settle state is keyed by
        // `(fingerprintKey, token)`, not by probe identity. When reader A
        // is replaced by reader B for the SAME book before A's
        // `onDisappear` fires, `activeReader === reader` is false for A,
        // so the block below is skipped — and A's pending settle waiters
        // would leak until timeout. Clear the outgoing probe's settle
        // state UNCONDITIONALLY here, preserving only the currently-
        // expected token's state (that token belongs to the incoming
        // reader B; A's own token never equals it). When A IS still the
        // active reader (normal close, nothing replaced it), the
        // `if` block below clears everything for the key anyway.
        clearSettleState(
            forFingerprintKey: reader.fingerprintKey,
            preservingToken: expectedReaderToken
        )
        if activeReader === reader as AnyObject {
            activeReader = nil
            // Bug #142: drop the expected reader token in lockstep with
            // the probe leaving. setExpectedReaderToken(nil) on its own
            // would also work, but bundling the clear here keeps the
            // probe + token lifecycles aligned.
            expectedReaderToken = nil
            #if canImport(WebKit)
            // Bug #126: also drop the EPUB-webview side-channel when its
            // owning probe leaves. The didFinish callback can outlive
            // the SwiftUI host briefly during dismantle; clearing here
            // prevents an outgoing book's webview from being matched
            // against an incoming reader's key.
            if activeEPUBWebViewKey == reader.fingerprintKey {
                activeEPUBWebViewRef = nil
                activeEPUBWebViewKey = nil
                activeEPUBWebViewToken = nil
            }
            // Bug #141: same protection for the Foliate webview slot.
            if activeFoliateWebViewKey == reader.fingerprintKey {
                activeFoliateWebViewRef = nil
                activeFoliateWebViewKey = nil
                activeFoliateWebViewToken = nil
            }
            #endif
            // Bug #141: the leaving probe IS the active reader and
            // nothing replaced it — clear ALL render-settled state +
            // pending settle waiters for its key (no token preserved).
            // A settled flag from an outgoing reader must not fast-path a
            // freshly-mounted reader on the same key; pending waiters are
            // resumed with timeout so
            // an in-flight `settle` doesn't hang past the reader's life.
            clearSettleState(forFingerprintKey: reader.fingerprintKey)
        }
    }

    /// Test seam — clear all state. Production paths use unregister.
    /// Cancels every pending waiter with timeout for clean teardown.
    func reset() {
        activeReader = nil
        expectedReaderToken = nil
        #if canImport(WebKit)
        activeEPUBWebViewRef = nil
        activeEPUBWebViewKey = nil
        activeEPUBWebViewToken = nil
        activeFoliateWebViewRef = nil
        activeFoliateWebViewKey = nil
        activeFoliateWebViewToken = nil
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
        // Bug #141: drop all render-settled state + resume every pending
        // settle waiter with a timeout error (mirrors the awaitReader
        // waiter teardown above).
        settledKeys = []
        let pendingSettle = settleWaiters
        settleWaiters = [:]
        for (_, bucket) in pendingSettle {
            for waiter in bucket {
                waiter.continuation.resume(throwing: DebugReaderProbeError.settleTimeout)
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
