// Purpose: Chat interface view for multi-turn AI conversations.
// Displays message bubbles, text input, and loading/error states.
//
// Key decisions:
// - ScrollView + ForEach for message list with auto-scroll to bottom.
// - Text input at bottom with send button.
// - Clear button in toolbar.
// - Loading indicator during requests.
// - Error banner dismissible by tapping or sending next message.
// - User messages right-aligned, assistant messages left-aligned.
//
// @coordinates-with: AIChatViewModel.swift, ChatMessage.swift, AIReaderPanel.swift

#if canImport(UIKit)
import SwiftUI

/// Multi-turn AI chat interface.
struct AIChatView: View {

    @Bindable var viewModel: AIChatViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messageList

            if let error = viewModel.errorMessage {
                errorBanner(message: error)
            }

            inputBar
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.clearHistory()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.messages.isEmpty)
                .accessibilityIdentifier("chatClearButton")
                .accessibilityLabel("Clear chat history")
            }
            // Bug #94: keyboard-toolbar Done button as secondary dismissal —
            // covers the case where the message list is short or empty and
            // .scrollDismissesKeyboard has no scrollable surface to drag.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
                .accessibilityIdentifier("chatKeyboardDoneButton")
            }
        }
    }

    // MARK: - Message List

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty {
                        emptyStateView
                    }

                    ForEach(viewModel.messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }

                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking\u{2026}")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("loading-indicator")
                        .accessibilityIdentifier("chatLoadingIndicator")
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: viewModel.messages.count) {
                if let lastMessage = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) {
                if viewModel.isLoading {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("loading-indicator", anchor: .bottom)
                    }
                }
            }
            // Bug #94: scroll-to-dismiss + interactive drag matches the
            // standard iOS chat-app keyboard dismissal pattern. Without this
            // the keyboard stays up unless the user closes the whole AI sheet.
            .scrollDismissesKeyboard(.interactively)
        }
        // Bug #94: tap-outside-input dismissal. `contentShape(Rectangle())`
        // makes the empty space hit-testable; `onTapGesture` only fires for
        // quick taps, so long-press text selection inside message bubbles
        // still works (selection's long-press fires first). Empty-list
        // taps also fall through here.
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = false
        }
        .accessibilityIdentifier("chatMessageList")
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 60)

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if viewModel.bookFingerprint != nil {
                Text("Ask questions about this book")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Start a conversation")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("chatEmptyState")
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .accessibilityIdentifier("chatErrorBanner")
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        Divider()

        HStack(spacing: 8) {
            TextField("Type a message\u{2026}", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit {
                    sendCurrentMessage()
                }
                .accessibilityIdentifier("chatInputField")

            Button {
                sendCurrentMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        canSend ? .blue : .gray.opacity(0.5)
                    )
            }
            .disabled(!canSend)
            .accessibilityIdentifier("chatSendButton")
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Private

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isLoading
    }

    private func sendCurrentMessage() {
        let text = inputText
        inputText = ""
        Task {
            await viewModel.sendMessage(text)
        }
    }
}

// MARK: - Chat Bubble View

/// Individual chat message bubble.
private struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .assistant || message.role == .system {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal)
        .accessibilityIdentifier("chatBubble-\(message.role.rawValue)")
    }

    private var bubbleBackground: some ShapeStyle {
        if message.role == .user {
            return Color.blue.opacity(0.15)
        } else {
            return Color.secondary.opacity(0.1)
        }
    }
}
#endif
