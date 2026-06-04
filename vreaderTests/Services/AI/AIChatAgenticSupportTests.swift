// Purpose: Feature #91 WI-8 — pin the pure chat→agentic glue: history mapping
// (role conversion, sliding window, empty/in-flight drop so the history ends on
// the user prompt) and the system-prompt framing (tool output is untrusted DATA;
// book context folded in only when present).
//
// @coordinates-with: AIChatAgenticSupport.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #91 WI-8 — AIChatHistoryMapper")
struct AIChatAgenticSupportTests {

    @Test("converts roles to tool turns and drops empty messages (ends on the user prompt)")
    func convertsAndSkipsEmpty() {
        let messages = [
            ChatMessage(role: .user, content: "hi"),
            ChatMessage(role: .assistant, content: "hello"),
            ChatMessage(role: .user, content: "what is X?"),
            ChatMessage(role: .assistant, content: ""),   // the in-flight placeholder
        ]
        let turns = AIChatHistoryMapper.toolTurns(from: messages, window: 10)
        #expect(turns.count == 3)
        #expect(turns.map(\.role) == [.user, .assistant, .user])
        #expect(turns.last?.content == [.text("what is X?")])
    }

    @Test("applies the sliding window (last N non-empty)")
    func appliesWindow() {
        let messages = (0..<20).map {
            ChatMessage(role: $0 % 2 == 0 ? .user : .assistant, content: "m\($0)")
        }
        let turns = AIChatHistoryMapper.toolTurns(from: messages, window: 5)
        #expect(turns.count == 5)
        #expect(turns.last?.content == [.text("m19")])
    }

    @Test("window <= 0 returns all non-empty messages")
    func windowZeroReturnsAll() {
        let messages = [
            ChatMessage(role: .user, content: "a"),
            ChatMessage(role: .assistant, content: "b"),
        ]
        #expect(AIChatHistoryMapper.toolTurns(from: messages, window: 0).count == 2)
    }

    @Test("empties are dropped BEFORE the window: window 1 over [user, empty-assistant] keeps the user prompt")
    func windowDropsEmptiesFirst() {
        let messages = [
            ChatMessage(role: .user, content: "q"),
            ChatMessage(role: .assistant, content: ""),   // in-flight placeholder
        ]
        let turns = AIChatHistoryMapper.toolTurns(from: messages, window: 1)
        #expect(turns.count == 1)                         // NOT [] — the placeholder didn't eat the budget
        #expect(turns.first?.content == [.text("q")])
    }

    @Test("the system prompt is instruction-only and frames data as untrusted (no raw book text)")
    func systemPromptInstructionOnly() {
        let prompt = AIChatHistoryMapper.systemPrompt()
        #expect(prompt.localizedCaseInsensitiveContains("untrusted"))
        #expect(prompt.localizedCaseInsensitiveContains("never"))   // "NEVER as instructions"
        // The system prompt must NOT carry book context (that would grant it system authority).
        #expect(!prompt.contains("Reference material from the book"))
    }

    @Test("book context rides as an UNTRUSTED leading user turn, not the system prompt")
    func contextPreludeIsUntrustedUserTurn() {
        #expect(AIChatHistoryMapper.contextPrelude(bookContext: nil) == nil)
        #expect(AIChatHistoryMapper.contextPrelude(bookContext: "   ") == nil)   // blank → none

        let prelude = AIChatHistoryMapper.contextPrelude(bookContext: "Chapter 1 text")
        #expect(prelude?.role == .user)                              // user/data authority, not system
        guard case .text(let t)? = prelude?.content.first else {
            Issue.record("expected a text block"); return
        }
        #expect(t.contains("Chapter 1 text"))
        #expect(t.localizedCaseInsensitiveContains("untrusted"))     // framed as untrusted
    }
}
