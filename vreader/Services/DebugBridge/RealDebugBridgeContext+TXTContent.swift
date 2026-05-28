// Purpose: `txt-content` handler for RealDebugBridgeContext (bug #1218
// DebugBridge). Writes the active TXT reader's currently-rendered
// (post-conversion) text to `Caches/DebugBridge/<dest>` as JSON so the
// host-side harness can read it via
// `xcrun simctl get_app_container <udid> com.vreader.app data`.
// DEBUG-only.
//
// Why this exists: iOS 26 SwiftUI flattens the chunked TXT reader's inner
// cells into the container, whose accessibility VALUE is the load-bearing
// `restoredOffset:N chapterMode:… chapters:K` state probe (read by
// TXTHighlightGesture / TXTChapterModeHighlight / PositionPersistence
// tests). CU-free XCUITest therefore cannot read the *rendered text
// content*, which blocks Feature #28 (verifying Simp→Trad conversion is
// applied to reader content). This command mirrors `snapshot(dest:)`
// end-to-end and is the CU-free read path for that verification.
//
// Split out as its own extension file (mirroring `+Snapshot.swift` /
// `+Eval.swift`) to keep RealDebugBridgeContext.swift under the 300-line
// guideline. Same "always write a file" contract as eval/snapshot:
// throws only on a filesystem-write failure.

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Write the active TXT reader's currently-rendered (post-conversion)
    /// text to `Library/Caches/DebugBridge/{dest}` in the app container.
    /// `dest` is a parser-validated basename (`[A-Za-z0-9._-]{1,64}`, no
    /// slashes, no dot-only sequences). Path traversal is structurally
    /// impossible.
    ///
    /// Always writes a file (mirrors the eval/snapshot "always write" so the
    /// host-side waiter has output to read):
    /// - No active reader → `{"error": "no active reader", "ts": …}`.
    /// - Active reader → `{"ts", "fingerprintKey", "format", "text", "available"}`
    ///   where `text` is the rendered text or JSON `null`, and `available`
    ///   is whether the host wired the rendered text (TXT only today).
    ///
    /// Throws only on an infrastructure failure (filesystem write).
    func txtContent(dest: String) async throws {
        let probe = DebugReaderRegistry.shared.current
        let outputURL = try Self.snapshotsDirectory().appendingPathComponent(dest)
        let ts = ISO8601DateFormatter().string(from: Date())

        guard let probe else {
            let payload: [String: Any] = ["error": "no active reader", "ts": ts]
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
            try data.write(to: outputURL, options: .atomic)
            log.error("txt-content: noActiveReader → \(dest, privacy: .public)")
            return
        }

        // Codex Gate-4 (Medium): the rendered-text probe is a TXT-only
        // capability. Gate availability on the active format so a future host
        // that populates `currentRenderedText` for another format can't be
        // misread as TXT content. Non-TXT → text:null, available:false.
        let isTXT = probe.format.lowercased() == "txt"
        let renderedText = isTXT ? probe.currentRenderedText : nil
        let payload: [String: Any] = [
            "ts": ts,
            "fingerprintKey": probe.fingerprintKey,
            "format": probe.format,
            "text": renderedText ?? NSNull(),
            "available": renderedText != nil
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        )
        try data.write(to: outputURL, options: .atomic)
        log.info("txt-content: wrote \(dest, privacy: .public)")
    }
}

#endif
