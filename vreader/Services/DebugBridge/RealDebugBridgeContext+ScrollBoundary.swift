// Purpose: `scroll-boundary` command handler for the vreader-debug:// scheme
// (feature #71 WI-6b verification harness — drive
// `EPUBContinuousScrollCoordinator.handleBoundarySignal(_:)` CU-free so the
// continuous-scroll forward/backward window extension + eviction can be
// device-verified WITHOUT a real touch scroll). The production
// `continuousScrollObserverJS` is rAF-throttled and rAF is paused on the
// headless/virtual-display test environment, so a synthetic scroll never fires
// a boundary report; this command posts `.debugBridgeScrollBoundaryCommand`
// carrying the visible spine index + the near edge. The live
// `EPUBReaderContainerView` observer builds an `EPUBScrollBoundarySignal` and
// calls `coordinator.handleBoundarySignal` — re-entering the SAME WI-6b
// extension path a real scroll boundary signal hits (no parallel logic).
// DEBUG-only — entire file compiled out of Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+Navigate.swift / +ScrollSheet.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   DebugBridgeNotifications.swift, EPUBReaderContainerView.swift
//   (the .debugBridgeScrollBoundaryCommand observer), RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Feature #71 WI-6b — drive `handleBoundarySignal` for the active
    /// continuous-mode EPUB reader.
    ///
    /// Posts `.debugBridgeScrollBoundaryCommand` carrying the visible
    /// `spineIndex` and the near edge (`near.rawValue`). The live
    /// `EPUBReaderContainerView` observes it, builds an
    /// `EPUBScrollBoundarySignal` (`intraFraction` 1.0 at the bottom / 0.0 at the
    /// top, `nearTopBoundary` / `nearBottomBoundary` set from the edge), and
    /// calls `coordinator.handleBoundarySignal` so the WI-6b window extension +
    /// eviction runs. If no matching continuous-mode EPUB reader is loaded the
    /// URL is silently a no-op (the same posture as `navigate` / `seek` /
    /// `search` / `present`).
    func scrollBoundary(spineIndex: Int, near: DebugCommand.ScrollBoundaryEdge) async throws {
        NotificationCenter.default.post(
            name: .debugBridgeScrollBoundaryCommand,
            object: nil,
            userInfo: ["spineIndex": spineIndex, "near": near.rawValue]
        )
        log.info(
            "scrollBoundary: posted scrollBoundaryCommand spine=\(spineIndex, privacy: .public) near=\(near.rawValue, privacy: .public)"
        )
    }
}

#endif
