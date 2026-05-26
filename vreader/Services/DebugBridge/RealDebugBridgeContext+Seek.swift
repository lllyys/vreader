// Purpose: `seek` command handler for the vreader-debug:// scheme (Bug #267
// verification harness — drive the active Foliate reader to a fractional
// position). Posts `.debugBridgeSeekFraction`; the live
// `FoliateBilingualContainerView` observer forwards it to the SAME
// `.foliateRequestSeekFraction` channel the bottom-chrome scrubber uses
// (`readerAPI.goToFraction`), injecting its own `fingerprintKey` (the spike's
// seek observer filters by key). This lets the harness reach a distinguishable
// non-start position so Bug #265's save→reopen→restore round-trip can be told
// apart from a default open-at-start. DEBUG-only — entire file compiled out of
// Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+Present.swift / +Provider.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   DebugBridgeNotifications.swift, FoliateBilingualContainerView+Position.swift
//   (the .debugBridgeSeekFraction observer), RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Bug #267 — drive the active Foliate reader to `fraction` (0...1).
    ///
    /// Posts `.debugBridgeSeekFraction` carrying the clamped fraction. The live
    /// `FoliateBilingualContainerView` observes it when an AZW3/MOBI book is
    /// open and re-posts `.foliateRequestSeekFraction` with its own
    /// `fingerprintKey` so the spike's key-filtered seek observer fires and
    /// evaluates `readerAPI.goToFraction(<fraction>)`. If no Foliate reader is
    /// loaded, the URL is silently a no-op (the same posture as
    /// `present` / `tts` / `search`).
    func seekFraction(fraction: Double) async throws {
        let clamped = min(max(fraction, 0), 1)
        NotificationCenter.default.post(
            name: .debugBridgeSeekFraction,
            object: nil,
            userInfo: ["fraction": clamped]
        )
        log.info("seek: posted seekFraction notification fraction=\(clamped, privacy: .public)")
    }
}

#endif
