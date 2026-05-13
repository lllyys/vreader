// Purpose: `snapshot` handler for RealDebugBridgeContext (feature #44 DebugBridge).
// Builds a state snapshot from the active reader (when present) plus
// reader-settings/highlight-count and writes it as JSON to the app
// container's Caches directory so the host-side harness can read it via
// `xcrun simctl get_app_container <udid> com.vreader.app data`.
// DEBUG-only.
//
// Split out of RealDebugBridgeContext.swift to keep that file under the
// 300-line guideline (feature #44 plan acceptance criterion (g)). Behavior
// is unchanged — same JSON schema, same partial-fields semantics.

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Build a state snapshot and write the JSON to
    /// `Library/Caches/DebugBridge/{dest}` in the app container.
    /// `dest` is a parser-validated basename (`[A-Za-z0-9._-]{1,64}`,
    /// no slashes, no dot-only sequences). Path traversal is structurally
    /// impossible.
    ///
    /// Reader-derived fields (currentBookId, format, position) are
    /// populated from `DebugReaderRegistry.shared.current` when a reader
    /// is presented. Without an active reader they remain nil and stay
    /// in the `partial` array. `selection` always stays in `partial` —
    /// selection probe lands when readers expose their selection state.
    func snapshot(dest: String, lastErrorMessage: String?) async throws {
        let store = ReaderSettingsStore(defaults: userDefaults)
        let highlightCount = try await totalHighlightCount()
        let probe = DebugReaderRegistry.shared.current

        // Schema v2 reader-derived fields (feature #49 WI-1 +
        // feature #45 WI-4c-c). Resolve once so partial-array logic
        // and snapshot init agree.
        let ttsState = probe?.currentTTSState
        let ttsOffsetUTF16 = probe?.currentTTSOffsetUTF16

        // Build `partial` dynamically. A reader-derived field stays
        // partial when the probe can't supply a value:
        // - currentBookId/format require a probe at all
        // - position additionally requires the probe to have wired a
        //   positionProvider (default adapter has none)
        // - selection is always partial in v0
        // - ttsState/ttsOffsetUTF16 are partial when the probe has no
        //   ttsProbe closure wired (or when no probe is registered)
        // - settingsProvenance is always partial until feature #50 wires
        //   per-format hosts
        var partial: [String] = ["selection", "settingsProvenance"]
        if probe == nil {
            partial.append(contentsOf: ["currentBookId", "format", "position"])
        } else if probe?.currentPositionString == nil {
            partial.append("position")
        }
        if ttsState == nil { partial.append("ttsState") }
        if ttsOffsetUTF16 == nil { partial.append("ttsOffsetUTF16") }

        let snap = DebugSnapshot(
            schemaVersion: DebugSnapshot.currentSchemaVersion,
            ts: ISO8601DateFormatter().string(from: Date()),
            currentBookId: probe?.fingerprintKey,
            format: probe?.format,
            position: probe?.currentPositionString,
            theme: themeName(from: store.theme),
            fontSize: Int(store.typography.fontSize),
            selection: nil,
            highlightCount: highlightCount,
            renderPhase: "idle",
            lastError: lastErrorMessage,
            partial: partial,
            ttsState: ttsState,
            ttsOffsetUTF16: ttsOffsetUTF16
        )

        let data = try DebugSnapshot.encoder.encode(snap)
        let outputURL = try Self.snapshotsDirectory().appendingPathComponent(dest)
        try data.write(to: outputURL, options: .atomic)
        log.info("snapshot: wrote \(data.count) bytes to \(dest, privacy: .public)")
    }

    /// Output directory in the app container — readable from the host via
    /// `xcrun simctl get_app_container <udid> com.vreader.app data`.
    /// Created on first call; idempotent.
    static func snapshotsDirectory() throws -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugBridge", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    fileprivate func themeName(from theme: ReaderTheme) -> String {
        switch theme {
        case .light: return "light"
        case .sepia: return "sepia"
        case .dark: return "dark"
        }
    }

    fileprivate func totalHighlightCount() async throws -> Int {
        try await persistence.countAllHighlights()
    }
}

#endif
