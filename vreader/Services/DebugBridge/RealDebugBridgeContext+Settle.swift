// Purpose: `settle` handler for RealDebugBridgeContext (feature #44 DebugBridge).
// Waits for the active reader to settle, then writes a `ready-<token>.json`
// sentinel file the harness can poll. On timeout OR when no reader is
// presented, writes a sentinel with `error: <reason>` rather than throwing
// — the host-side waiter always has a file to inspect.
// DEBUG-only.
//
// Split out of RealDebugBridgeContext.swift to keep that file under the
// 300-line guideline (feature #44 plan acceptance criterion (g)). Behavior
// is unchanged — same timeout, same payload shape, same logger.

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Wait for the active reader to settle, then write
    /// `Caches/DebugBridge/ready-<token>.json` with the current state.
    /// On settle timeout OR when no reader is presented, writes a sentinel
    /// file with `error: <reason>` rather than throwing — the host-side
    /// waiter always has a file to inspect after its own timeout expires.
    ///
    /// The timeout is enforced by the bridge, not just the probe — a
    /// probe that hangs instead of throwing settleTimeout still produces
    /// the sentinel. Throws only on infrastructure failures (file write).
    func settle(token: String) async throws {
        try await settleWithTimeout(token: token, timeoutSeconds: Self.settleTimeoutSeconds)
    }

    /// Internal test seam — same logic as `settle` but accepts a custom
    /// timeout so tests can exercise the race without waiting 30s. The
    /// optional `webViewWaitSeconds` parameter (Codex Gate-4 round-1 Low
    /// fix) lets tests bound the Stage-2 WebView wait independently of
    /// the Stage-1 probe wait — without it, every webview-not-registered
    /// case would block the test for the full 5-second Stage-2 budget.
    /// Defaults to `Self.webViewWaitSeconds` (5.0) for production callers.
    func settleWithTimeout(
        token: String,
        timeoutSeconds: TimeInterval,
        webViewWaitSeconds: TimeInterval? = nil
    ) async throws {
        // Bug #125: when no reader is registered we still write a sentinel —
        // the verification harness has no way to distinguish "URL accepted but
        // hung" from "URL accepted but no probe to settle on" without a file
        // on disk. Mirror eval's noActiveReader pattern: write the sentinel
        // with error="no active reader" and return without throwing.
        guard let probe = DebugReaderRegistry.shared.current else {
            try writeReadySentinel(
                token: token,
                probe: nil,
                error: "no active reader"
            )
            log.error("settle: ready-\(token, privacy: .public).json with error=no active reader")
            return
        }
        var settleError: String?
        // Stage 1: probe-level render-complete. A probe-layer
        // `.settleTimeout` here is genuinely a probe failure — the
        // sentinel reports `settle timeout` and we do NOT proceed to the
        // Stage 2 WebView gate (the probe is the cause, not a missing
        // WebView slot).
        do {
            try await withSettleTimeout(seconds: timeoutSeconds) {
                try await probe.awaitSettle(timeout: timeoutSeconds)
            }
        } catch DebugReaderProbeError.settleTimeout {
            settleError = "settle timeout"
        } catch SettleTimeoutSentinel.timedOut {
            settleError = "settle timeout"
        } catch {
            settleError = String(describing: error)
        }

        // Stage 2: WebView registration gate. Only entered when Stage 1
        // succeeded. Bug #250: `markReaderSettled` and
        // `setActiveEPUBWebView` fire in lockstep from the same
        // didFinish callback, but the registry's stale-write guard
        // (`expectedReaderToken != token`) can silently reject the
        // WebView write in a same-key reopen race. Without this gate,
        // settle reports success on a registry with an empty WebView
        // slot, and a downstream `vreader-debug://highlight-create`
        // logs `no active EPUB WebView registered`. The wait is bounded
        // (5s) so a malformed fixture still reaches the sentinel path
        // with a precise error string. The error string is distinct
        // (`webview not registered`) so callers can tell apart the
        // probe-layer timeout from the registry-layer gap.
        if settleError == nil {
            let stage2Timeout = webViewWaitSeconds ?? Self.webViewWaitSeconds
            do {
                try await DebugReaderRegistry.shared.awaitWebViewRegistered(
                    for: probe.fingerprintKey,
                    format: probe.format,
                    timeout: stage2Timeout
                )
            } catch DebugReaderProbeError.settleTimeout {
                settleError = "webview not registered"
            } catch {
                settleError = String(describing: error)
            }
        }

        try writeReadySentinel(token: token, probe: probe, error: settleError)
        if let err = settleError {
            log.error("settle: ready-\(token, privacy: .public).json with error=\(err, privacy: .public)")
        } else {
            log.info("settle: wrote ready-\(token, privacy: .public).json")
        }
    }

    /// Default settle timeout. Not URL-configurable in v0; harness can
    /// shorten by triggering its own timeout if needed.
    static var settleTimeoutSeconds: TimeInterval { 30.0 }

    /// Bug #250: bounded additional wait for the format-specific WebView
    /// registration after `probe.awaitSettle` resolves. Kept short — the
    /// happy path completes in <100ms because `setActiveEPUBWebView` and
    /// `markReaderSettled` fire in the same didFinish callback; the wait
    /// only stretches when the stale-write guard rejected the WebView
    /// register, in which case 5s is plenty to surface the failure as a
    /// `webview not registered` sentinel instead of a 30s false-positive.
    static var webViewWaitSeconds: TimeInterval { 5.0 }

    // MARK: - Internal helpers (extension-scoped)

    /// Writes the `ready-<token>.json` sentinel. Probe-shaped fields
    /// (`fingerprintKey`, `format`, `position`) are only included when a
    /// probe was registered — for the no-active-reader case the keys are
    /// omitted so they read as `null` in JSON, matching `DebugSnapshot`'s
    /// "field is partial / unavailable" convention. When `error` is
    /// present, `phase: "unknown"` is also set per the existing
    /// timeout-path shape.
    fileprivate func writeReadySentinel(
        token: String,
        probe: DebugReaderProbe?,
        error: String?
    ) throws {
        var payload: [String: Any] = [
            "token": token,
            "ts": ISO8601DateFormatter().string(from: Date())
        ]
        if let probe {
            payload["fingerprintKey"] = probe.fingerprintKey
            payload["format"] = probe.format
            payload["position"] = probe.currentPositionString as Any
        }
        if let error {
            payload["error"] = error
            payload["phase"] = "unknown"  // probe doesn't yet report a render phase
        }
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        let outputURL = try Self.snapshotsDirectory()
            .appendingPathComponent("ready-\(token).json")
        try data.write(to: outputURL, options: .atomic)
    }

    /// Race a MainActor-isolated operation against a timer; whichever
    /// finishes first wins, the loser is cancelled. Used to bound
    /// settle's awaitSettle even if a probe hangs without honoring its
    /// own timeout parameter. MainActor-isolated by construction so the
    /// operation can capture `@MainActor` references (the probe).
    fileprivate func withSettleTimeout(
        seconds: TimeInterval,
        operation: @escaping @MainActor () async throws -> Void
    ) async throws {
        let work = Task { @MainActor in try await operation() }
        let timer = Task {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            work.cancel()
        }
        defer { timer.cancel() }
        do {
            try await work.value
        } catch is CancellationError {
            throw SettleTimeoutSentinel.timedOut
        }
    }
}

/// Internal sentinel — leaks to caller only as `settleError = "settle timeout"`.
fileprivate enum SettleTimeoutSentinel: Error {
    case timedOut
}

#endif
