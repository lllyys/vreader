// Purpose: DEBUG-only wiring that surfaces the active TXT/MD reader's persisted
// locate-bloom counters into the DebugBridge probe (feature #74). The locate
// "bloom" is a ~1.5s sub-second wash-lift that cannot be screenshot/video-
// captured on the Screen-Sharing virtual display, so the DebugBridge reads the
// counters back instead — proving the bloom FIRED through the real render path.
// `HighlightableTextView` posts `(count, peakIntensity)` on
// `.debugBridgeLandingBloomChanged` each play + tick; this observer caches the
// latest tuple so `DebugReaderProbeAdapter.landingBloomProbe` reads it, and the
// snapshot then reports `landingBloomCount` / `landingBloomPeakIntensity`.
//
// Factored into a dedicated `ViewModifier` (same precedent as
// `ReaderDebugBridgeRenderedTextObserver`) so adding the observer doesn't push
// `ReaderContainerView.body` over SwiftUI's type-inference budget. Entire file
// compiled out of Release via `#if DEBUG`.
//
// @coordinates-with ReaderContainerView.swift (the `.modifier(...)` attaches
//   this and wires `debugProbe?.landingBloomProbe`), HighlightableTextView.swift
//   (posts `.debugBridgeLandingBloomChanged`), DebugBridgeNotifications.swift,
//   RealDebugBridgeContext+Snapshot.swift (the consumer of the probe accessors).

#if DEBUG

import SwiftUI

/// Dedicated `ViewModifier` for the feature #74 locate-bloom readback observer.
/// Mirrors `ReaderDebugBridgeRenderedTextObserver` — extracting the `.onReceive`
/// keeps the SwiftUI body inside the type-inference budget.
struct ReaderDebugBridgeLandingBloomObserver: ViewModifier {
    /// Called with the posted `(count, peakIntensity)`. The host caches it so
    /// `DebugReaderProbeAdapter.landingBloomProbe` can read it back at snapshot
    /// time. No fingerprintKey gate: a locate bloom only fires on the
    /// currently-active TXT/MD reader (the same reader the probe is registered
    /// for), so the latest post is always the active reader's.
    let onBloom: (_ count: Int, _ peakIntensity: Double) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeLandingBloomChanged)
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let count = userInfo["count"] as? Int,
                  let peak = userInfo["peakIntensity"] as? Double else { return }
            onBloom(count, peak)
        }
    }
}

#endif
