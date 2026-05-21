// Purpose: Bug #255 — the AI-panel effect a DebugBridge `ai` command
// resolves to. Mirrors `DebugPresentSheetEffect`: a pure value type that
// names what `AIReaderPanel` does when a `.debugBridgeAIAction`
// notification arrives, decoupled from the SwiftUI `@State` / view-model
// mutation so the routing decision is unit-testable without a render path.
//
// The fidelity invariant this type pins: `ai?action=X[&scope=Y][&text=Z]`
// resolves to the SAME tab + view-model path the production chrome buttons
// take (`AISummaryTabView.runSummarize` / `AIChatView.sendMessage` /
// `TranslationPanel.translate`). The harness drives the real button path —
// there is no parallel AI call.
//
// DEBUG-only — the DebugBridge harness is compiled out of Release.
//
// @coordinates-with: RealDebugBridgeContext+AIAction.swift, DebugCommand.swift,
//   AIReaderPanel.swift, AISummaryTabView.swift, AIChatView.swift,
//   TranslationPanel.swift, SummaryScope.swift, DebugAIActionEffectTests.swift

#if DEBUG

import Foundation

/// The AI-panel action effect a DebugBridge `ai` command triggers. Case
/// names describe the *panel action*; `AIReaderPanel`'s observer switches on
/// this and invokes the matching view-model path on the matching tab.
enum DebugAIActionEffect: Equatable {
    /// Run the Summarize tab's summary at the given scope (nil → the panel's
    /// current scope). Invokes the SAME path `AISummaryTabView.runSummarize`
    /// takes (set scope, then summarize over the full book text).
    case summarize(scope: SummaryScope?)
    /// Send a chat message on the Chat tab. Invokes the SAME path
    /// `AIChatView.sendCurrentMessage` takes (`AIChatViewModel.sendMessage`).
    /// An empty message is a no-op inside the view model (matches the
    /// chrome's `canSend` guard).
    case chat(message: String)
    /// Run the Translate tab's translation. `targetLanguage` (nil → the
    /// panel's current target language) overrides the language. Invokes the
    /// SAME path `TranslationPanel.requestTranslation` takes
    /// (`AITranslationViewModel.translate`).
    case translate(targetLanguage: String?)

    /// The AI tab this effect runs on. The observer switches the panel to
    /// this tab first (so `snapshot` reflects the action's surface), then
    /// invokes the view-model path.
    var tab: AIReaderTab {
        switch self {
        case .summarize: return .summarize
        case .chat:      return .chat
        case .translate: return .translate
        }
    }

    /// Resolve the panel effect for an `ai` command's `(action, scope, text)`.
    ///
    /// The parser has already validated the action against `AIActionKind`,
    /// the scope against the summarize-only `section`/`chapter`/`book`
    /// vocabulary (mapping `book` → `.bookSoFar`), and required `text` for
    /// chat. This is a total mapping — every `AIActionKind` resolves, with no
    /// crash arm.
    ///
    /// - `summarize`: `scope` carries through (nil → the panel's current
    ///   scope chip); `text` is ignored (the chip drives the summary).
    /// - `chat`: `text` is the message (nil maps to "", a view-model no-op —
    ///   the parser rejects this case in production).
    /// - `translate`: `text` overrides the target language (nil → the panel's
    ///   current target language); `scope` is ignored (rejected by the parser
    ///   for non-summarize anyway).
    static func resolve(
        action: DebugCommand.AIActionKind,
        scope: SummaryScope?,
        text: String?
    ) -> DebugAIActionEffect {
        switch action {
        case .summarize:
            return .summarize(scope: scope)
        case .chat:
            return .chat(message: text ?? "")
        case .translate:
            return .translate(targetLanguage: text)
        }
    }
}

#endif
