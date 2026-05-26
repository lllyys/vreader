// Purpose: `ai` command handler for the vreader-debug:// scheme
// (Bug #255 verification harness AI-action driver). Posts
// `.debugBridgeAIAction`; the presented AI sheet's observer
// (AIReaderPanel, Bug #255 wiring) invokes the SAME view-model path the
// chrome buttons trigger (`AISummaryTabView.runSummarize` /
// `AIChatView.sendMessage` / `TranslationPanel.translate`), so the
// AI-response-card render states become CU-free verifiable via
// `snapshot` + `eval`. There is no parallel AI call. DEBUG-only —
// entire file compiled out of Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+Present.swift / +Provider.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   DebugBridgeNotifications.swift, AIReaderPanel.swift,
//   DebugAIActionEffect.swift, RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Bug #255 — fire an AI action on the presented AI sheet from outside
    /// the chrome.
    ///
    /// Posts `.debugBridgeAIAction` with `action` (the `AIActionKind`
    /// rawValue) plus the optional `scope` (a `SummaryScope` rawValue — the
    /// parser has already mapped the URL-friendly `book` to `bookSoFar`) and
    /// optional `text` (chat message / translate language override).
    /// `AIReaderPanel` observes the notification when it's presented; it
    /// resolves a `DebugAIActionEffect` and applies it by invoking the SAME
    /// view-model path the chrome buttons take. If no AI sheet is presented,
    /// the URL is silently a no-op (the same posture as `present` / `tts` /
    /// `search`).
    ///
    /// `scope` and `text` are omitted from `userInfo` when nil so observers
    /// can fall back to the panel's current scope / target language without
    /// relying on a sentinel value.
    func aiAction(action: DebugCommand.AIActionKind, scope: SummaryScope?, text: String?) async throws {
        // Bug #271: a fresh translate produces a new `TranslationResultCard`,
        // so forget any unconsumed `scroll-sheet` target — otherwise a scroll
        // requested for a prior translate whose card never mounted would replay
        // onto this translate's card on `.onAppear`. The verifier issues
        // `scroll-sheet` AFTER this action, so the legit target is recorded
        // after this clear and survives.
        if action == .translate {
            DebugBridgeScrollSheetState.shared.pendingTarget = nil
        }
        var userInfo: [AnyHashable: Any] = ["action": action.rawValue]
        if let scope {
            userInfo["scope"] = scope.rawValue
        }
        if let text {
            userInfo["text"] = text
        }
        NotificationCenter.default.post(
            name: .debugBridgeAIAction,
            object: nil,
            userInfo: userInfo
        )
        log.info(
            "aiAction: posted notification action=\(action.rawValue, privacy: .public) scope=\(scope?.rawValue ?? "nil", privacy: .public) text=\(text != nil ? "set" : "nil", privacy: .public)"
        )
    }
}

#endif
