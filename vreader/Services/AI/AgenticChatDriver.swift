// Purpose: Feature #91 WI-7 — the bounded agentic loop. Given a pre-resolved
// tool-use provider + a tool registry, it drives: send → if the model requests
// tools, run each via the registry, append the tool_results, re-send → repeat
// until the model returns a final text answer or a hard iteration cap is hit.
//
// Key decisions:
// - ONE pre-resolved provider (Gate-2 Medium): the driver is handed a provider
//   resolved once at loop start, so a provider/model/key change mid-loop cannot
//   straddle the operation. The driver NEVER re-resolves.
// - Off-`@MainActor` (a plain Sendable struct, mirroring #86's off-actor reducer):
//   the `@MainActor` VM (WI-8) awaits it, but the loop itself crosses no UI actor.
// - Lossless assistant turn: a `.toolUse` turn's FULL ordered content blocks
//   (interleaved text + tool_use) are re-appended verbatim — the provider API
//   requires the re-sent assistant turn to carry exactly those blocks.
// - Bounded: `maxIterations` send calls. On the cap, return the model's last
//   assistant text if any, else a graceful message — never an unbounded loop.
// - `usedTools` lets the VM decide citation handling (Gate-2 Medium 3: suppress
//   the "Drew on" stamp on tool-driven replies).
//
// @coordinates-with: AITool.swift (DTOs + AIToolTurn), AIToolRegistry.swift
//   (tool dispatch), AIProvider.swift (the provider's sendToolRequest seam),
//   AIChatViewModel.swift (the WI-8 consumer),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-7)

import Foundation
import OSLog

/// The narrow capability the driver needs from a provider — one tool-use turn.
/// `AIProvider` already vends `sendToolRequest`; WI-8 bridges the resolved
/// provider to this seam. Keeping it narrow makes the driver trivially testable.
protocol ToolUseSending: Sendable {
    func sendToolRequest(_ request: AIToolRequest) async throws -> AIToolTurn
}

/// The outcome of one agentic run.
struct AgenticResult: Sendable, Equatable {
    /// The model's final text answer (or a graceful message if the cap was hit).
    let finalText: String
    /// Whether the loop executed at least one tool (drives citation suppression).
    let usedTools: Bool
}

/// The bounded send → tool → result → re-send loop.
struct AgenticChatDriver: Sendable {

    private static let log = Logger(subsystem: "com.vreader.app", category: "AgenticChatDriver")

    /// Hard cap on provider round-trips (a runaway-loop / cost backstop).
    let maxIterations: Int

    init(maxIterations: Int = 6) {
        self.maxIterations = max(1, maxIterations)
    }

    /// Run the loop. `history` is the conversation so far (the user's prompt is the
    /// last message). Throws only if the PROVIDER throws — every tool failure is an
    /// `isError` tool_result fed back to the model, not a thrown error.
    func run(
        systemPrompt: String,
        history: [ToolTurnMessage],
        registry: AIToolRegistry,
        provider: any ToolUseSending,
        maxTokens: Int
    ) async throws -> AgenticResult {
        var messages = history
        var usedTools = false
        let tools = registry.definitions()

        for iteration in 0..<maxIterations {
            // Bug #323: a Stop (or a session transition) cancels the streaming task
            // that awaits this loop. Observe it at the top of every round so a
            // runaway tool loop aborts PROMPTLY instead of grinding to the iteration
            // cap with the chat's `isLoading` stuck true. CancellationError unwinds
            // to `runSend`'s `catch is CancellationError` (a user Stop is not an
            // error), which keeps any partial reply.
            try Task.checkCancellation()
            let request = AIToolRequest(
                systemPrompt: systemPrompt, messages: messages, tools: tools, maxTokens: maxTokens)
            let turn = try await provider.sendToolRequest(request)

            switch turn {
            case .text(let text):
                return AgenticResult(finalText: text, usedTools: usedTools)

            case .toolUse(let blocks):
                usedTools = true
                // Re-append the assistant turn LOSSLESSLY (the API requires exactly
                // these blocks on the re-sent turn).
                messages.append(ToolTurnMessage(role: .assistant, content: blocks))
                // Run every requested tool; collect the results as a single
                // tool_result-leading user turn (provider history invariant).
                var resultBlocks: [ToolContentBlock] = []
                for call in turn.toolCalls {
                    // Bug #323 (Gate-4 Medium): also observe cancellation BETWEEN
                    // in-round tool calls, so a Stop during a multi-tool round aborts
                    // promptly instead of running the rest of the round. (A single
                    // long-running tool that ignores cancellation internally still
                    // can't be interrupted mid-call — the in-app tools are local +
                    // fast; deeper per-tool cancellation would require making
                    // `AITool.run` cancellation-aware, tracked as a follow-up.)
                    try Task.checkCancellation()
                    let result = await registry.run(call)
                    resultBlocks.append(.toolResult(result))
                }
                Self.log.info(
                    "agentic iteration \(iteration + 1, privacy: .public): ran \(resultBlocks.count, privacy: .public) tool(s)")
                messages.append(ToolTurnMessage(role: .user, content: resultBlocks))
            }
        }

        // Cap reached while the model still wanted tools — return its last words if
        // any, else a graceful message. Never loop unbounded.
        Self.log.warning("agentic loop hit the \(self.maxIterations, privacy: .public)-iteration cap")
        let lastText = Self.lastAssistantText(in: messages)
        return AgenticResult(
            finalText: lastText ?? "I wasn't able to finish answering within the tool-call limit.",
            usedTools: usedTools)
    }

    /// The most recent non-empty assistant text in the history (for the cap path).
    private static func lastAssistantText(in messages: [ToolTurnMessage]) -> String? {
        for message in messages.reversed() where message.role == .assistant {
            let text = message.content.compactMap {
                if case .text(let t) = $0 { return t } else { return nil }
            }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return nil
    }
}
