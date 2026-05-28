// Purpose: `scroll-sheet` command handler for the vreader-debug:// scheme
// (Bug #271 verification harness — scroll the active presented sheet's
// scrollable content so below-fold content becomes CU-free capturable). Posts
// `.debugBridgeScrollSheet`; the presented sheet's observer (today
// `TranslationResultCard`, Feature #65 row-11 verification) drives its
// `ScrollViewReader` proxy to the requested top/bottom anchor — no parallel
// scroll logic. `detent=large` (Bug #256) reveals the larger AI sheet, but the
// tall auto-extracted ORIGINAL card alone exceeds even the `.large` height, so
// the accent translation card needs a scroll to come into view. DEBUG-only —
// entire file compiled out of Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+Present.swift / +Seek.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   DebugBridgeNotifications.swift, TranslationResultCard.swift
//   (the .debugBridgeScrollSheet observer), RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

/// Bug #271 — DEBUG-only replay buffer for the most-recently-requested
/// `scroll-sheet` target. The Translate-tab result card
/// (`TranslationResultCard`) only mounts once translation completes, so a
/// scroll requested *before* that — by a verifier that doesn't first poll the
/// AI panel's state — would be lost by the fire-and-forget notification alone
/// (no observer is mounted to receive it). Recording the target here lets the
/// card's observer replay it on `.onAppear`, making the harness
/// order-independent: the verifier may issue `scroll-sheet` before OR after the
/// result card mounts and the scroll still lands. Last-write-wins; the observer
/// clears it on apply so a stale target never re-scrolls a later card.
///
/// Lives in the Services layer (alongside `DebugCommand`) and holds only a pure
/// `DebugCommand.ScrollTarget` — no SwiftUI import — so the View-layer observer
/// reads it in the normal View→Services direction.
@MainActor
final class DebugBridgeScrollSheetState {
    static let shared = DebugBridgeScrollSheetState()
    /// The target awaiting a result card to apply it to, or nil when none is
    /// pending (no request yet, or the last one was already applied).
    var pendingTarget: DebugCommand.ScrollTarget?
    private init() {}
}

extension RealDebugBridgeContext {

    /// Bug #271 — scroll the active presented sheet's scrollable content to
    /// `target` (top / bottom).
    ///
    /// Records `target` in `DebugBridgeScrollSheetState` (the replay buffer for
    /// the not-yet-mounted case) and posts `.debugBridgeScrollSheet` (the live
    /// already-mounted case). The presented sheet's observer (today
    /// `TranslationResultCard`) maps the target to a `ScrollViewReader`
    /// `scrollTo(_:anchor:)` against its own top/bottom anchor — so the harness
    /// drives the real scroll path (no parallel scroll logic) and the
    /// previously below-fold content becomes capturable via
    /// `simctl io screenshot`. If no scrollable sheet ever observes it, the URL
    /// is silently a no-op (the same posture as `present` / `tts` / `search`).
    func scrollSheet(target: DebugCommand.ScrollTarget) async throws {
        DebugBridgeScrollSheetState.shared.pendingTarget = target
        NotificationCenter.default.post(
            name: .debugBridgeScrollSheet,
            object: nil,
            userInfo: ["to": target.rawValue]
        )
        log.info("scroll-sheet: posted scrollSheet notification to=\(target.rawValue, privacy: .public)")
    }
}

#endif
