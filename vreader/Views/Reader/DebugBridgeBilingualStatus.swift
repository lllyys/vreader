// Purpose: Feature #77 — DEBUG-only readout writer for the `bilingual?action=status`
// command. Each per-format bilingual host calls this with its live
// `BilingualReadingViewModel`; it serializes the readiness/in-flight state to
// `Caches/DebugBridge/<dest>.json` so a CU-free verifier can confirm bilingual
// is configured + see how many translation units are in flight (the loading
// shimmer's source signal).
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with: ReaderDebugBridgeBilingualObserver.swift,
//   RealDebugBridgeContext+Snapshot.swift (snapshotsDirectory),
//   BilingualReadingViewModel.swift

#if DEBUG

import Foundation

enum DebugBridgeBilingualStatus {

    /// Writes the bilingual VM's state to `Caches/DebugBridge/<dest>`.
    @MainActor
    static func write(dest: String, engine: String, vm: BilingualReadingViewModel?) {
        let payload: [String: Any] = [
            "engine": engine,
            "hasVM": vm != nil,
            "isEnabled": vm?.isEnabled ?? false,
            "aiConfigured": vm?.aiConfigured ?? false,
            "target": vm?.targetLanguage ?? "",
            "granularity": vm?.granularity.rawValue ?? "",
            "inFlight": vm?.inFlightUnits.count ?? 0,
        ]
        guard let dir = try? RealDebugBridgeContext.snapshotsDirectory(),
              let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
              ) else { return }
        try? data.write(to: dir.appendingPathComponent(dest), options: .atomic)
    }
}

#endif
