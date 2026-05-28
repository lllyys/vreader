// Purpose: DEBUG-only `scroll-boundary` observer for EPUBReaderContainerView
// (feature #71 WI-6b verification harness). The `scroll-boundary` DebugBridge
// command (`RealDebugBridgeContext+ScrollBoundary.swift`) posts
// `.debugBridgeScrollBoundaryCommand` carrying the visible spine index + near
// edge; this modifier builds the SAME `EPUBScrollBoundarySignal` the
// rAF-throttled `continuousScrollObserverJS` would and calls
// `EPUBContinuousScrollCoordinator.handleBoundarySignal` directly — bypassing
// the rAF observer (rAF is paused on the headless/virtual-display test
// environment, so a synthetic touch scroll never fires a boundary report).
// Re-enters the SAME WI-6b window-extension + eviction path a real boundary
// signal hits (no parallel logic). Continuous mode only
// (`continuousScrollConfig != nil`).
//
// Lives in its own `ViewModifier` (mirroring
// `EPUBReaderContainerView+DebugBridgeHighlight.swift`) so the EPUB body stays
// within the Swift type-checker's complexity budget. Entire file compiled out
// of Release builds via `#if DEBUG`; the Release stub supplies an
// `EmptyModifier` so DebugBridge symbols never leak.
//
// @coordinates-with EPUBReaderContainerView.swift,
//   EPUBContinuousScrollCoordinator.swift, DebugBridgeNotifications.swift,
//   RealDebugBridgeContext+ScrollBoundary.swift

import SwiftUI

#if !DEBUG
// Release stub: the body of EPUBReaderContainerView references
// `debugBridgeScrollBoundaryObserverModifier`; we provide an `EmptyModifier`
// here so Release builds compile without any DebugBridge symbols.
#if canImport(UIKit)
extension EPUBReaderContainerView {
    var debugBridgeScrollBoundaryObserverModifier: EmptyModifier {
        EmptyModifier()
    }
}
#endif
#endif

#if DEBUG
#if canImport(UIKit)

extension EPUBReaderContainerView {

    /// The `ViewModifier` that observes `.debugBridgeScrollBoundaryCommand`
    /// and dispatches into `handleDebugScrollBoundaryCommand`. The body reads
    /// this property unconditionally; the Release stub above supplies an
    /// `EmptyModifier` so DebugBridge symbols never leak into release builds.
    var debugBridgeScrollBoundaryObserverModifier: some ViewModifier {
        EPUBDebugBridgeScrollBoundaryObserver(
            onCommand: { spineIndex, near in
                handleDebugScrollBoundaryCommand(spineIndex: spineIndex, near: near)
            }
        )
    }

    /// Handle a `.debugBridgeScrollBoundaryCommand` notification by building the
    /// SAME `EPUBScrollBoundarySignal` the rAF-throttled JS observer would and
    /// calling `coordinator.handleBoundarySignal`. `intraFraction` is 1.0 at the
    /// bottom edge / 0.0 at the top; `nearTopBoundary` / `nearBottomBoundary` are
    /// set from the edge (`top` ⇒ extend backward, `bottom` ⇒ extend forward).
    /// No-op outside continuous mode (`continuousScrollConfig == nil`) — paged
    /// mode has no coordinator.
    @MainActor
    func handleDebugScrollBoundaryCommand(spineIndex: Int, near: String) {
        guard let config = continuousScrollConfig else { return }
        let signal = EPUBScrollBoundarySignal(
            visibleSpineIndex: spineIndex,
            intraFraction: near == "bottom" ? 1.0 : 0.0,
            nearTopBoundary: near == "top",
            nearBottomBoundary: near == "bottom"
        )
        Task { await config.coordinator.handleBoundarySignal(signal) }
    }
}

/// Local `ViewModifier` mirroring the EPUB `DebugBridgeHighlightObserver`
/// shape. Parses the notification's `(spineIndex, near)` userInfo and forwards
/// to `onCommand`. Kept local to this file so the EPUB body's observer chain
/// stays off the main `body` type-check path.
private struct EPUBDebugBridgeScrollBoundaryObserver: ViewModifier {
    let onCommand: (_ spineIndex: Int, _ near: String) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeScrollBoundaryCommand)
        ) { notification in
            guard let spineIndex = notification.userInfo?["spineIndex"] as? Int,
                  let near = notification.userInfo?["near"] as? String else { return }
            onCommand(spineIndex, near)
        }
    }
}

#endif
#endif
