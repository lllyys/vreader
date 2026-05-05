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
    /// timeout so tests can exercise the race without waiting 30s.
    func settleWithTimeout(token: String, timeoutSeconds: TimeInterval) async throws {
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
