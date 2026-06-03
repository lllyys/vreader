// Purpose: ViewModel for multi-turn AI chat conversations.
// Manages conversation history, context window, and book context injection.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Sliding window: only last N messages sent as context to the AI.
// - Full message history preserved in `messages` for display.
// - Book context text injected via bookContext property (set by reader container).
// - When bookContext is set, it is prepended as "[Book Context]" in the contextText.
// - bookFingerprint is set on the AIRequest for cache key differentiation.
// - Empty/whitespace messages are silently ignored.
// - On error: user message preserved, errorMessage set, conversation continues.
// - Context text for AIRequest is built by serializing book context + conversation history.
//
// @coordinates-with: ChatMessage.swift, AIService.swift, AIChatView.swift

import Foundation

/// ViewModel for multi-turn AI chat conversations.
@Observable
@MainActor
final class AIChatViewModel {

    // MARK: - Published State

    /// Full conversation history (for display).
    private(set) var messages: [ChatMessage] = []

    /// Whether a request is currently in flight.
    private(set) var isLoading: Bool = false

    /// Error message from the last failed request, nil if no error.
    var errorMessage: String?

    /// Feature #78 (Ask-AI on selection): a one-shot pre-fill for the chat
    /// INPUT field. When a user taps "Ask AI" on a text selection, the reader
    /// host seeds this with the selected text; `AIChatView` consumes it into its
    /// input (NOT auto-sent — the user edits/frames the question), then clears
    /// it. Nil when there is nothing pending. Set only via `seedInput(_:)`.
    private(set) var seededInput: String?

    /// Seeds the chat input with `text` (one-shot; consumed + cleared by the
    /// view). Whitespace-only / empty text is ignored (no seed).
    func seedInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        seededInput = text
    }

    /// Clears any pending seed without applying it (the view calls this once it
    /// has decided whether to consume the seed — see `AIChatView`).
    func clearSeed() {
        seededInput = nil
    }

    // MARK: - Configuration

    /// Book fingerprint for book-context mode. Nil = general chat.
    let bookFingerprint: DocumentFingerprint?

    /// Maximum number of messages to include in the AI context window.
    let contextWindowSize: Int

    /// Current book content text for context injection.
    /// Set by the reader container with the visible section/chapter/page text.
    /// When non-nil and non-empty, prepended as "[Book Context]" in the AI request.
    var bookContext: String?

    /// Feature #86 WI-3: the breadth of book text the Chat tab reads. Drives the
    /// context-bar scope chip. Changing it (via `setScope`) re-assembles
    /// `bookContext` through `onScopeChanged` (the coordinator's single funnel).
    /// Default `.chapter` matches the shipped WI-1 behavior.
    private(set) var scope: ChatContextScope = .chapter

    /// Set by the reader coordinator: invoked after a scope change so the
    /// coordinator re-computes `bookContext` for the new scope.
    var onScopeChanged: (() -> Void)?

    /// Selects a new Chat context scope and re-assembles the book context.
    /// A no-op when the scope is unchanged (avoids a redundant re-assembly).
    func setScope(_ newScope: ChatContextScope) {
        guard newScope != scope else { return }
        scope = newScope
        onScopeChanged?()
    }

    // MARK: - Dependencies

    private let aiService: AIService

    // MARK: - Init

    /// Creates a new chat view model.
    ///
    /// - Parameters:
    ///   - aiService: The AI service for sending requests.
    ///   - bookFingerprint: If non-nil, book context is included in requests.
    ///   - contextWindowSize: Max messages in the sliding context window (default 10).
    init(
        aiService: AIService,
        bookFingerprint: DocumentFingerprint? = nil,
        contextWindowSize: Int = 10
    ) {
        self.aiService = aiService
        self.bookFingerprint = bookFingerprint
        self.contextWindowSize = contextWindowSize
    }

    // MARK: - Actions

    /// Sends a user message and streams the AI response incrementally.
    /// Empty or whitespace-only messages are silently ignored.
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Clear previous error
        errorMessage = nil

        // Add user message to history
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        isLoading = true
        defer { isLoading = false }

        // Build context from conversation history (sliding window)
        let contextText = buildContextText()

        let request = AIRequest(
            actionType: .questionAnswer,
            bookFingerprint: bookFingerprint,
            locator: nil,
            contextText: contextText,
            userPrompt: trimmed,
            targetLanguage: nil,
            promptVersion: "v1"
        )

        do {
            // Create an empty assistant message for incremental streaming
            let assistantMessage = ChatMessage(role: .assistant, content: "")
            messages.append(assistantMessage)
            let assistantIndex = messages.count - 1

            let stream = try await aiService.streamRequest(request)
            for try await chunk in stream {
                messages[assistantIndex].content += chunk.text
            }

            // If streaming produced no content, remove the empty message
            if messages[assistantIndex].content.isEmpty {
                messages.remove(at: assistantIndex)
            }
        } catch let aiError as AIError {
            // Remove empty assistant message if it was added
            if let last = messages.last, last.role == .assistant && last.content.isEmpty {
                messages.removeLast()
            }
            errorMessage = aiError.localizedDescription
        } catch {
            // Remove empty assistant message if it was added
            if let last = messages.last, last.role == .assistant && last.content.isEmpty {
                messages.removeLast()
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Clears the entire conversation history and resets state.
    func clearHistory() {
        messages = []
        isLoading = false
        errorMessage = nil
    }

    // MARK: - Private

    /// Builds a serialized context string from the recent conversation history.
    /// Uses the sliding window to limit context size.
    /// When `bookContext` is set, prepends it as a "[Book Context]" section.
    private func buildContextText() -> String {
        var parts: [String] = []

        // Prepend book context if available
        if let ctx = bookContext, !ctx.isEmpty {
            parts.append("[Book Context]\n\(ctx)")
        }

        let windowMessages = recentMessages()
        if !windowMessages.isEmpty {
            let historyText = windowMessages.map { msg in
                let roleLabel: String
                switch msg.role {
                case .user: roleLabel = "User"
                case .assistant: roleLabel = "Assistant"
                case .system: roleLabel = "System"
                }
                return "\(roleLabel): \(msg.content)"
            }.joined(separator: "\n")
            parts.append(historyText)
        }

        return parts.joined(separator: "\n\n")
    }

    /// Returns the most recent messages within the context window size.
    private func recentMessages() -> [ChatMessage] {
        if messages.count <= contextWindowSize {
            return messages
        }
        return Array(messages.suffix(contextWindowSize))
    }
}
