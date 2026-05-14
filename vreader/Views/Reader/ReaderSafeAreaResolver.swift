// Purpose: Single source of truth for "what is the device's top safe area
// inset, regardless of SwiftUI layout state". `GeometryReader { proxy }`
// inside a parent that applies `.ignoresSafeArea(.top)` returns
// `proxy.safeAreaInsets.top = 0` (bug #73 origin). The TXT/MD readers'
// chrome-overlay container does exactly that wrap, so `proxy` is unreliable
// for the Dynamic Island compensation Bug #179 needs.
//
// This helper reads `UIWindow.safeAreaInsets.top` from the foreground active
// scene's key window — the device-level truth that survives SwiftUI's
// `.ignoresSafeArea` and the initial-render race where `proxy` hasn't
// measured yet.
//
// @coordinates-with TXTReaderContainerView.swift, TXTTextViewBridge.swift,
//   TXTChunkedReaderBridge.swift, ReaderChromeBar.swift

#if canImport(UIKit)
import UIKit

enum ReaderSafeAreaResolver {
    /// Last non-zero top safe area observed across any foreground (active or
    /// inactive) window scene. Acts as the cache that bridges the
    /// `.foregroundActive`-only warmup gap and the SwiftUI initial-render gap
    /// where neither `proxy.safeAreaInsets.top` nor a scene lookup yet
    /// returns the device's real DI inset.
    ///
    /// `@MainActor` ensures sequential reads/writes — every reader path here
    /// runs on main (SwiftUI body, `makeUIView`, `updateUIView`).
    @MainActor
    private static var lastKnownNonZeroTop: CGFloat = 0

    /// Best-effort top safe-area inset from any foreground scene's windows.
    ///
    /// Active-first: if at least one `.foregroundActive` scene exists, we
    /// trust its value — even when that value is `0`. Returning a stale `59`
    /// from a paused secondary window would over-inset the active reader
    /// in landscape / Stage Manager (Codex audit `019e2893` round 2 finding).
    /// `.foregroundInactive` is consulted only when there is no active scene
    /// (e.g. activation warmup before any scene promotes). The cache is the
    /// final fallback when neither pass yields a usable scene.
    ///
    /// Within each pass we walk every window (not just key window) and take
    /// the maximum `safeAreaInsets.top` — Stage Manager / Split View can
    /// present multiple windows of which the hosting one may not be
    /// `isKeyWindow` at the exact moment of evaluation.
    @MainActor
    static var windowSafeAreaTop: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        let activeScenes = scenes.filter { $0.activationState == .foregroundActive }
        if !activeScenes.isEmpty {
            let value = maxTopInset(across: activeScenes)
            if value > 0 { lastKnownNonZeroTop = value }
            return value
        }

        let inactiveScenes = scenes.filter { $0.activationState == .foregroundInactive }
        if !inactiveScenes.isEmpty {
            let value = maxTopInset(across: inactiveScenes)
            if value > 0 {
                lastKnownNonZeroTop = value
                return value
            }
            // Inactive observed 0 but the cache may carry a prior good value;
            // prefer cache here because inactive == warmup window, not "user
            // is genuinely in a zero-safe-area orientation right now".
            return lastKnownNonZeroTop
        }

        return lastKnownNonZeroTop
    }

    @MainActor
    private static func maxTopInset(across scenes: [UIWindowScene]) -> CGFloat {
        var best: CGFloat = 0
        for scene in scenes {
            for window in scene.windows {
                best = max(best, window.safeAreaInsets.top)
            }
        }
        return best
    }

    /// Combine a GeometryReader-derived value with the window's actual safe area.
    ///
    /// Used by Bug #179 fix path: the TXT/MD readers' GeometryReader returns
    /// `proxy.safeAreaInsets.top = 0` either momentarily on initial render
    /// (before layout measures) or across the chapter-nav rebuild gap when
    /// SwiftUI swaps the bridge identity (`loadingView` → fresh
    /// `TXTTextViewBridge`). Falling back to `windowSafeAreaTop` guarantees
    /// the textView's first line clears the Dynamic Island even before
    /// SwiftUI has finished its first layout pass.
    ///
    /// `combine(_:_:)` keeps the merge math pure-function and testable;
    /// production callers use `topInsetWithFallback(_:)` which queries the
    /// resolver.
    static func combine(_ geometryReaderValue: CGFloat, _ windowValue: CGFloat) -> CGFloat {
        max(max(0, geometryReaderValue), max(0, windowValue))
    }

    @MainActor
    static func topInsetWithFallback(_ geometryReaderValue: CGFloat) -> CGFloat {
        let windowValue = windowSafeAreaTop
        // Opportunistic cache: a positive proxy value is just as legitimate
        // a "device has a real safe area" signal as a positive window probe,
        // so use it to seed the cache when the window probe is empty.
        if geometryReaderValue > 0, windowValue == 0 {
            lastKnownNonZeroTop = geometryReaderValue
        }
        return combine(geometryReaderValue, windowValue)
    }
}
#endif
