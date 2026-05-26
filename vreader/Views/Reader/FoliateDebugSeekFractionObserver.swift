// Purpose: Bug #267 — DEBUG-only `ViewModifier` that bridges the verification
// harness's `seek?fraction=` command to the live Foliate reader. It observes
// `.debugBridgeSeekFraction` (posted by `RealDebugBridgeContext.seekFraction`)
// and re-posts `.foliateRequestSeekFraction` — the SAME channel the
// bottom-chrome scrubber uses (`FoliateSpikeView` → `readerAPI.goToFraction`)
// — injecting this container's `fingerprintKey`, because the spike's seek
// observer filters by key. The DebugBridge handler can't supply the key (it
// doesn't know the active book), so the container, which does, injects it.
//
// The ENTIRE type is `#if DEBUG`-gated, and its call site in
// `FoliateBilingualContainerView` is gated to match, so no symbol leaks into
// Release (rule 50 §11; Bug #254 lesson). `verify-release-no-debugbridge.sh`
// must continue to pass.
//
// @coordinates-with: FoliateBilingualContainerView.swift (call site),
//   RealDebugBridgeContext+Seek.swift, DebugBridgeNotifications.swift,
//   FoliateSpikeView.swift (.foliateRequestSeekFraction observer)

#if DEBUG

import SwiftUI

/// Forwards `.debugBridgeSeekFraction` → `.foliateRequestSeekFraction` with the
/// active book's `fingerprintKey` so the spike's key-filtered seek observer
/// fires.
struct FoliateDebugSeekFractionObserver: ViewModifier {
    let fingerprintKey: String

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeSeekFraction)
        ) { notification in
            Self.forward(notification, fingerprintKey: fingerprintKey)
        }
    }

    /// Forwards a `.debugBridgeSeekFraction` notification to the spike's
    /// key-filtered `.foliateRequestSeekFraction` observer, injecting
    /// `fingerprintKey`. Extracted as a static so the load-bearing hop (the
    /// key injection the spike filters on) is unit-testable without a SwiftUI
    /// hosting context. No-op when the notification carries no `fraction`.
    static func forward(_ notification: Notification, fingerprintKey: String) {
        guard let fraction = notification.userInfo?["fraction"] as? Double else { return }
        NotificationCenter.default.post(
            name: .foliateRequestSeekFraction,
            object: nil,
            userInfo: ["fraction": fraction, "fingerprintKey": fingerprintKey]
        )
    }
}

#endif
