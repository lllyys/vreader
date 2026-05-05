// Purpose: `eval` handler for RealDebugBridgeContext (feature #44 DebugBridge).
// Evaluates JS in the active reader's webview and writes the result (or a
// documented error payload) to `Caches/DebugBridge/eval-<bridge>.json`.
// Throws only on infrastructure failures (filesystem write); no-active-
// reader / unsupported-format / JS-exception cases land in the JSON file
// so the host-side waiter has output to read.
// DEBUG-only.
//
// Split out of RealDebugBridgeContext.swift to keep that file under the
// 300-line guideline (feature #44 plan acceptance criterion (g)). Behavior
// is unchanged — same JSON shapes, same error semantics, same logger.

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Evaluate JS in the active reader's webview and ALWAYS write
    /// `Caches/DebugBridge/eval-<bridge>.json` — happy path with `result`
    /// (raw JSON value), error path with `error` string. Throws only on
    /// infrastructure failures (filesystem write); failure modes the
    /// caller cares about (no reader, unsupported format, JS exception)
    /// land in the JSON file so the host-side waiter has output to read.
    func eval(bridge: String, js: String) async throws {
        let probe = DebugReaderRegistry.shared.current
        let outputURL = try Self.snapshotsDirectory()
            .appendingPathComponent("eval-\(bridge).json")

        guard let probe else {
            try Self.writeEvalError(
                outputURL: outputURL,
                bridge: bridge,
                fingerprintKey: nil,
                format: nil,
                error: "no active reader"
            )
            log.error("eval: noActiveReader → eval-\(bridge, privacy: .public).json")
            return
        }

        do {
            let resultData = try await probe.evaluateJavaScript(js)
            // Splice raw JSON value into the result field — JSONSerialization
            // accepts pre-encoded JSON via re-decoding to its native type.
            let resultValue = try JSONSerialization.jsonObject(
                with: resultData,
                options: [.fragmentsAllowed]
            )
            let payload: [String: Any] = [
                "bridge": bridge,
                "ts": ISO8601DateFormatter().string(from: Date()),
                "fingerprintKey": probe.fingerprintKey,
                "format": probe.format,
                "result": resultValue
            ]
            let out = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
            try out.write(to: outputURL, options: .atomic)
            log.info("eval: wrote eval-\(bridge, privacy: .public).json")
        } catch DebugReaderProbeError.evalUnsupported(let fmt) {
            try Self.writeEvalError(
                outputURL: outputURL,
                bridge: bridge,
                fingerprintKey: probe.fingerprintKey,
                format: probe.format,
                error: "eval unsupported for format: \(fmt)"
            )
            log.error("eval: unsupported format \(fmt, privacy: .public)")
        } catch {
            try Self.writeEvalError(
                outputURL: outputURL,
                bridge: bridge,
                fingerprintKey: probe.fingerprintKey,
                format: probe.format,
                error: String(describing: error)
            )
            log.error("eval: failed: \(String(describing: error), privacy: .public)")
        }
    }

    fileprivate static func writeEvalError(
        outputURL: URL,
        bridge: String,
        fingerprintKey: String?,
        format: String?,
        error: String
    ) throws {
        var payload: [String: Any] = [
            "bridge": bridge,
            "ts": ISO8601DateFormatter().string(from: Date()),
            "error": error
        ]
        if let k = fingerprintKey { payload["fingerprintKey"] = k }
        if let f = format { payload["format"] = f }
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: outputURL, options: .atomic)
    }
}

#endif
