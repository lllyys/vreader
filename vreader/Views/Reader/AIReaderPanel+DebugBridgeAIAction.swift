// Purpose: DEBUG-only wiring that fires an AI action on the presented AI
// sheet from the `.debugBridgeAIAction` notification (Bug #255 verification
// harness). The observer on `AIReaderPanel` calls `handleDebugAIAction`,
// which resolves a `DebugAIActionEffect`, switches the panel to the
// effect's tab, and invokes the SAME view-model path the chrome buttons
// take (`AISummaryTabView.runSummarize` / `AIChatView.sendCurrentMessage` /
// `TranslationPanel.requestTranslation`) — so the harness drives the real
// button path (no parallel AI call) and the AI-response-card render states
// become CU-free verifiable via `snapshot` + `eval`.
//
// The observer lives on `AIReaderPanel` (not `ReaderContainerView`) because
// the panel holds the locator / full book text / chapter bounds / format /
// target language each action needs. `.onReceive` only delivers to a
// mounted view, so when the AI sheet isn't presented the URL is silently a
// no-op (mirrors `present` / `tts` / `search`).
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with: AIReaderPanel.swift, DebugAIActionEffect.swift,
//   AIAssistantViewModel.swift, AITranslationViewModel.swift,
//   AIChatViewModel.swift, RealDebugBridgeContext+AIAction.swift,
//   DebugBridgeNotifications.swift

#if DEBUG

import SwiftUI
import OSLog

/// Dedicated `ViewModifier` for the Bug #255 AI-action observer. Mirrors
/// `ReaderDebugBridgePresentObserver` — extracting the `.onReceive` keeps
/// the SwiftUI body inside the type-inference budget.
struct ReaderDebugBridgeAIActionObserver: ViewModifier {
    let onCommand: (_ action: String, _ scope: String?, _ text: String?) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeAIAction)
        ) { notification in
            guard let action = notification.userInfo?["action"] as? String else { return }
            let scope = notification.userInfo?["scope"] as? String
            let text = notification.userInfo?["text"] as? String
            onCommand(action, scope, text)
        }
    }
}

extension AIReaderPanel {

    /// Handle a `.debugBridgeAIAction` notification by firing the AI action
    /// through the SAME view-model path the chrome buttons take. Resolves a
    /// `DebugAIActionEffect` from `(action, scope, text)`, switches the panel
    /// to the effect's tab (so `snapshot` reflects the action's surface),
    /// and invokes:
    ///
    /// - `.summarize(scope)` → sets the scope on the view model (the chip
    ///   tap's `viewModel.setScope`), then runs the SAME in-flight-guarded
    ///   `viewModel.summarize(locator:fullText:format:scope:chapterBounds:)`
    ///   call `AISummaryTabView.runSummarize` makes — over the panel's full
    ///   book text + chapter bounds.
    /// - `.chat(message)` → `chatViewModel.sendMessage(message)` (the
    ///   `AIChatView` send button's path; empty is a view-model no-op).
    /// - `.translate(targetLanguage)` → `translationViewModel.translate(...)`
    ///   (the `TranslationPanel` pill's path); a nil override uses the view
    ///   model's current `targetLanguage` (the pre-selected default).
    ///
    /// An unrecognized `action` string (shouldn't happen — the parser
    /// validates `AIActionKind`) is ignored.
    @MainActor
    func handleDebugAIAction(action: String, scope: String?, text: String?) {
        let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")
        guard let kind = DebugCommand.AIActionKind(rawValue: action) else {
            log.error("aiAction observer: unknown action=\(action, privacy: .public)")
            return
        }
        // The parser maps the URL-friendly `book` → `bookSoFar`, so the
        // notification carries a `SummaryScope` rawValue. A nil / unknown
        // value resolves to "no scope override" (use the panel's current
        // scope chip) rather than crashing.
        let resolvedScope = scope.flatMap(SummaryScope.init(rawValue:))
        log.info(
            "aiAction observer: action=\(action, privacy: .public) scope=\(resolvedScope?.rawValue ?? "nil", privacy: .public) text=\(text != nil ? "set" : "nil", privacy: .public)"
        )

        let effect = DebugAIActionEffect.resolve(action: kind, scope: resolvedScope, text: text)
        // Land on the same tab the chrome would for this action, so a
        // post-action `snapshot` reflects the right surface.
        selectedTab = effect.tab

        switch effect {
        case .summarize(let scopeOverride):
            // Mirror the Summarize chip tap: set the scope on the view model
            // (only when the URL supplied one — otherwise keep the panel's
            // current chip), then run the SAME guarded summarize call
            // `AISummaryTabView.runSummarize` makes.
            if let scopeOverride {
                viewModel.setScope(scopeOverride)
            }
            // In-flight guard — identical to `AISummaryTabView.runSummarize`:
            // a re-fire while a request is already loading/streaming is a
            // no-op so an older response can't overwrite a newer one.
            switch viewModel.state {
            case .loading, .streaming:
                return
            case .idle, .complete, .error, .featureDisabled, .consentRequired:
                break
            }
            Task {
                await viewModel.summarize(
                    locator: locator,
                    fullText: fullTextContent,
                    format: format,
                    scope: viewModel.selectedScope,
                    chapterBounds: chapterBounds
                )
                // Feature #90 WI-3 (Gate-4 round-2): mirror
                // `AISummaryTabView.runSummarize` — `summarize` resets the
                // translation to `.none`, so re-kick it here too, otherwise a
                // DEBUG `ai?action=summarize` with Single/Bilingual selected
                // (e.g. the CU-free Gate-5 verification path) would render
                // original-only. No-op for `.originalOnly`; op-token guarded.
                await viewModel.refreshSummaryTranslationIfNeeded()
            }

        case .chat(let message):
            // Mirror the Chat send button precisely: `AIChatView`'s `canSend`
            // gate disables Send while `isLoading` (and on empty input), and
            // `AIChatViewModel.sendMessage` does NOT coalesce concurrent
            // callers. Without this guard two rapid `ai?action=chat` fires
            // could start overlapping chat requests the chrome button cannot
            // trigger — the same in-flight hazard `runSummarize` guards
            // against. Empty input is a VM no-op (matches `canSend`'s
            // non-empty check), so only the `isLoading` arm needs guarding.
            guard !chatViewModel.isLoading else { return }
            Task {
                await chatViewModel.sendMessage(message)
            }

        case .translate(let targetLanguage):
            // Mirror the Translate pill tap: pass the target language
            // straight through to `translate(...)`. A nil override uses the
            // view model's current `targetLanguage` (the pre-selected
            // default, the same language the rail shows selected on open).
            let language = targetLanguage ?? translationViewModel.targetLanguage
            Task {
                await translationViewModel.translate(
                    originalText: textContent,
                    locator: locator,
                    format: format,
                    targetLanguage: language
                )
            }
        }
    }
}

#endif
