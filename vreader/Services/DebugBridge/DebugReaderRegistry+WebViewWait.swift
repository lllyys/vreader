// Purpose: WebView-registration gate for DebugReaderRegistry (bug #250).
// After a probe's `awaitSettle` resolves, the bridge's `settle` handler uses
// this gate to confirm — for the WebView-backed formats (EPUB, AZW3/MOBI) —
// that the format-specific WebView slot has been populated by the
// per-coordinator `didFinish` callback. Without this, settle can return
// success on a probe whose `markReaderSettled` fired in lockstep with
// `setActiveEPUBWebView` being silently dropped by the stale-write guard
// (`expectedReaderToken != token`), and a downstream
// `vreader-debug://highlight-create` URL then races into a registry with an
// empty WebView slot — the highlight observer logs
// `no active EPUB WebView registered for <key>` and the highlight is never
// created.
//
// Polling is the right shape here (not a continuation-style waiter): the
// WebView ref is a stored weak reference set on the @MainActor, the wait is
// bounded to a few seconds, and a poll keeps the registry's mutable state
// monomorphic — no second waiter dict to coordinate with the existing
// `awaitReader` / `awaitReaderSettled` machinery, and no extra teardown
// path to manage in `reset` / `unregister`. The pool of legal formats that
// need this gate is small (only "epub" / "azw3" map to a non-nil WebView
// slot today; everything else short-circuits via `formatRequiresWebView`),
// so the gate is also a no-op for the formats that wouldn't satisfy it
// anyway (TXT/MD/PDF).
//
// @coordinates-with DebugReaderRegistry.swift, DebugReaderRegistry+Settle.swift,
//   RealDebugBridgeContext+Settle.swift
// DEBUG-only.

#if DEBUG

import Foundation
#if canImport(WebKit)
import WebKit
#endif

extension DebugReaderRegistry {

    /// Whether the given format requires a WebView slot in the registry to
    /// be populated before settle reports success. Only EPUB (handled by
    /// `EPUBWebViewBridgeCoordinator`) and AZW3 / MOBI (Foliate) host their
    /// content in a WKWebView and use the registry's WebView slot for
    /// downstream eval / highlight-create commands. TXT / MD / PDF read
    /// their text directly from Swift and have no WebView dependency, so
    /// the gate is a no-op for them.
    ///
    /// `format` is normalized to lowercase before matching — `probe.format`
    /// carries the raw `book.format` value (`ReaderContainerView.swift`
    /// constructs the adapter with `format: book.format`), and historical
    /// rows can carry mixed case (`"EPUB"`, `"AZW3"`). The reader dispatch
    /// path already lowercases via `BookFormat(rawValue: book.format
    /// .lowercased())`; this helper must do the same or it would silently
    /// skip the gate for any mixed-case row.
    static func formatRequiresWebView(_ format: String) -> Bool {
        // Foliate is the single host for the AZW3 family per
        // `FormatCapabilities` (azw3, azw, mobi, prc). Match the lower-
        // case strings the snapshot path emits.
        switch format.lowercased() {
        case "epub", "azw3", "azw", "mobi", "prc":
            return true
        default:
            return false
        }
    }

    /// Return `true` if the WebView slot the given `format` is gated on
    /// has been populated for `fingerprintKey` AND the active
    /// `expectedReaderToken` matches the slot's stored token (Codex
    /// Gate-4 round-1 High fix). The token check closes a same-key
    /// reopen race: outgoing reader A and incoming reader B share a
    /// `fingerprintKey`; A's slot can persist past A's `unregister` when
    /// `activeReader === reader` is false (B already took over), so the
    /// slot's *key* matches B but its *token* still belongs to A. A
    /// token-agnostic check would falsely report "registered" while
    /// `epubWebView(for:token:)` (the production accessor) returns nil.
    ///
    /// Returns `false` for any format that doesn't require a WebView (per
    /// `formatRequiresWebView`) — the gate is a no-op shape that lets the
    /// caller treat this as "not applicable, skip the wait".
    func hasActiveWebView(for fingerprintKey: String, format: String) -> Bool {
        #if canImport(WebKit)
        guard Self.formatRequiresWebView(format) else { return false }
        switch format.lowercased() {
        case "epub":
            // Token-keyed match — see `epubWebView(for:token:)` for the
            // production-equivalent guard.
            guard activeEPUBWebViewKeyInternal == fingerprintKey,
                  rawActiveEPUBWebViewForTests != nil,
                  let activeToken = rawActiveEPUBWebViewTokenForTests,
                  expectedReaderTokenForTests == activeToken
            else { return false }
            return true
        case "azw3", "azw", "mobi", "prc":
            guard activeFoliateWebViewKeyInternal == fingerprintKey,
                  rawActiveFoliateWebViewForTests != nil,
                  let activeToken = rawActiveFoliateWebViewTokenForTests,
                  expectedReaderTokenForTests == activeToken
            else { return false }
            return true
        default:
            return false
        }
        #else
        return false
        #endif
    }

    /// Bounded poll waiting for `hasActiveWebView(for:format:)` to become
    /// true. The poll interval is small enough (50ms) that on the happy
    /// path (where `setActiveEPUBWebView` / `setActiveFoliateWebView` has
    /// already fired by the time settle reaches this gate) the wait is
    /// effectively zero; the wait grows only when the WebView slot is
    /// genuinely lagging or stale-token-mismatched — exactly the scenarios
    /// bug #250 names.
    ///
    /// Throws `DebugReaderProbeError.settleTimeout` if the deadline expires
    /// before the slot is populated AND matches the expected token. The
    /// bridge's `+Settle.swift` catch-block maps that to the
    /// `webview not registered` sentinel error so callers see a different
    /// field value than the `settle timeout` (probe layer) and
    /// `no active reader` (registration layer) paths.
    func awaitWebViewRegistered(
        for fingerprintKey: String,
        format: String,
        timeout: TimeInterval
    ) async throws {
        // Fast path: not a WebView format — nothing to wait for.
        guard Self.formatRequiresWebView(format) else { return }
        // Fast path: already registered and token-matched.
        if hasActiveWebView(for: fingerprintKey, format: format) {
            return
        }
        // Non-positive timeout is treated as "report timeout immediately"
        // — mirrors `awaitReaderSettled`'s guard so a misconfigured caller
        // doesn't silently spin.
        guard timeout > 0 else {
            throw DebugReaderProbeError.settleTimeout
        }

        let pollIntervalNS: UInt64 = 50_000_000 // 50ms
        // Codex Gate-4 round-2 Low fix: use ContinuousClock for the
        // deadline so a system-clock change (NTP step, manual time
        // adjustment) doesn't make the poll exit early or hang past the
        // intended budget. Task.sleep is still the right cancellation-
        // aware sleep primitive — the bridge's outer withSettleTimeout
        // race needs to cancel this poll cleanly.
        let clock = ContinuousClock()
        let start = clock.now
        let budget: Duration = .nanoseconds(Int64(timeout * 1_000_000_000))
        while (clock.now - start) < budget {
            if hasActiveWebView(for: fingerprintKey, format: format) {
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNS)
        }
        // Last check after the loop — a slot can flip in the gap between
        // the final deadline test and the timeout. Without this tail
        // check, a flip racing with the deadline reports a false
        // negative.
        if hasActiveWebView(for: fingerprintKey, format: format) {
            return
        }
        throw DebugReaderProbeError.settleTimeout
    }
}

#endif
