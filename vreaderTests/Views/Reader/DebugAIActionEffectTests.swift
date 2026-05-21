// Purpose: Tests for DebugAIActionEffect — the pure mapping from a
// DebugBridge `ai` command's (AIActionKind, scope, text) to the AI-panel
// action effect (Bug #255 verification harness). Pins the fidelity
// invariant: each effect names the SAME tab + action the production chrome
// triggers (`AISummaryTabView.runSummarize` / `AIChatView.sendMessage` /
// `TranslationPanel.translate`), so the harness exercises the real button
// path (no parallel AI logic).

#if DEBUG

import XCTest
@testable import vreader

final class DebugAIActionEffectTests: XCTestCase {

    // MARK: - summarize → .summarize(scope:) on the Summarize tab

    func test_resolve_summarizeNoScope_carriesNilScopeOnSummarizeTab() {
        let effect = DebugAIActionEffect.resolve(action: .summarize, scope: nil, text: nil)
        XCTAssertEqual(effect, .summarize(scope: nil))
        XCTAssertEqual(effect.tab, .summarize)
    }

    func test_resolve_summarizeWithEachScope_carriesScope() {
        let cases: [SummaryScope] = [.section, .chapter, .bookSoFar]
        for scope in cases {
            let effect = DebugAIActionEffect.resolve(action: .summarize, scope: scope, text: nil)
            XCTAssertEqual(effect, .summarize(scope: scope),
                           "summarize scope \(scope) must carry through")
            XCTAssertEqual(effect.tab, .summarize)
        }
    }

    func test_resolve_summarizeIgnoresText() {
        // `text` is meaningless for summarize — the scope chip drives it.
        let effect = DebugAIActionEffect.resolve(action: .summarize, scope: .chapter, text: "ignored")
        XCTAssertEqual(effect, .summarize(scope: .chapter))
    }

    // MARK: - chat → .chat(message:) on the Chat tab

    func test_resolve_chatWithText_carriesMessageOnChatTab() {
        let effect = DebugAIActionEffect.resolve(action: .chat, scope: nil, text: "who is the narrator?")
        XCTAssertEqual(effect, .chat(message: "who is the narrator?"))
        XCTAssertEqual(effect.tab, .chat)
    }

    func test_resolve_chatNilText_carriesEmptyMessage() {
        // The parser rejects chat with no text, so the resolver never sees nil
        // in production — but the mapper must be total. A nil text maps to an
        // empty message (which the VM's sendMessage silently ignores), never
        // a crash.
        let effect = DebugAIActionEffect.resolve(action: .chat, scope: nil, text: nil)
        XCTAssertEqual(effect, .chat(message: ""))
        XCTAssertEqual(effect.tab, .chat)
    }

    // MARK: - translate → .translate(targetLanguage:) on the Translate tab

    func test_resolve_translateNoText_carriesNilTargetLanguageOnTranslateTab() {
        let effect = DebugAIActionEffect.resolve(action: .translate, scope: nil, text: nil)
        XCTAssertEqual(effect, .translate(targetLanguage: nil))
        XCTAssertEqual(effect.tab, .translate)
    }

    func test_resolve_translateWithText_carriesTargetLanguageOverride() {
        let effect = DebugAIActionEffect.resolve(action: .translate, scope: nil, text: "Spanish")
        XCTAssertEqual(effect, .translate(targetLanguage: "Spanish"))
        XCTAssertEqual(effect.tab, .translate)
    }

    // MARK: - exhaustiveness

    func test_resolve_everyActionKind_resolvesToAnEffect() {
        // No AIActionKind falls through to a nil/crash — every case maps.
        for action in DebugCommand.AIActionKind.allCases {
            _ = DebugAIActionEffect.resolve(action: action, scope: nil, text: nil)
        }
    }
}

#endif
