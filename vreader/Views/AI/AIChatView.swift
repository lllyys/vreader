// Purpose: Chat interface view for multi-turn AI conversations.
// Displays message bubbles, text input, and loading/error states.
//
// Re-skinned for feature #65 visual-identity v2 (WI-2): the message
// list renders the design's two `ChatBubble` forms via `AIChatMessageRow`
// (accent user bubble + sparkle-avatar serif assistant row), and the
// input bar is the design's rounded pill field with a circular send
// button. The empty-state, error banner, auto-scroll, the bug-#94
// keyboard handling, and the `clearHistory` toolbar button are
// preserved unchanged.
//
// Key decisions:
// - ScrollView + ForEach for message list with auto-scroll to bottom.
// - Text input at bottom with send button.
// - Clear button in toolbar.
// - Loading indicator during requests.
// - Error banner dismissible by tapping or sending next message.
// - User messages right-aligned, assistant messages left-aligned.
// - `theme` is additive with a `.paper` default so the call site stays
//   non-breaking; `AIReaderPanel` passes the real theme it holds.
//
// @coordinates-with: AIChatViewModel.swift, ChatMessage.swift,
//   AIChatMessageRow.swift, AIReaderPanel.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// Multi-turn AI chat interface.
struct AIChatView: View {

    @Bindable var viewModel: AIChatViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    /// Visual-identity-v2 theme tokens (feature #65 WI-2). Defaults to
    /// `.paper` so existing callers / previews that omit it keep working.
    var theme: ReaderThemeV2 = .paper

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
                        AIChatMessageRow(message: message, theme: theme)
                            .id(message.id)
                    }

                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking\u{2026}")
                                .font(.caption)
                                // Bug #310 (Codex Gate-4 Low): same cream-sheet
                                // dark-mode trap as the empty state — route the
                                // loading caption through the designed sub token.
                                .foregroundStyle(Color(Self.secondaryContentColor(for: theme)))
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
                .foregroundStyle(Color(Self.secondaryContentColor(for: theme)))
                .accessibilityHidden(true)

            if viewModel.bookFingerprint != nil {
                Text("Ask questions about this book")
                    .font(.headline)
                    .foregroundStyle(Color(Self.secondaryContentColor(for: theme)))
            } else {
                Text("Start a conversation")
                    .font(.headline)
                    .foregroundStyle(Color(Self.secondaryContentColor(for: theme)))
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

    /// The design's rounded pill input field with a circular send
    /// button — `vreader-panels.jsx` `ChatView`'s input row. The
    /// previous plain `TextField` + `arrow.up.circle.fill` button is
    /// replaced; the multiline (`axis: .vertical`, `lineLimit(1...5)`)
    /// behaviour and the bug-#94 focus / submit wiring are preserved.
    @ViewBuilder
    private var inputBar: some View {
        Color(theme.ruleColor).frame(height: 0.5)

        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                // Bug #310: themed placeholder. SwiftUI ignores `.foregroundStyle`
                // on a `TextField`'s own placeholder (it stays the system
                // appearance-aware colour — ~1.07:1, near-invisible over the cream
                // sheet in Dark Mode), so overlay a `Text` in the designed `sub`
                // token. Identical font + the shared padding below keep it aligned
                // with the entered text.
                if inputText.isEmpty {
                    Text(inputPlaceholder)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(Self.secondaryContentColor(for: theme)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField("", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(theme.inkColor))
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendCurrentMessage()
                    }
                    .accessibilityIdentifier("chatInputField")
                    // Bug #310 (Codex Gate-4 Medium): the empty prompt `""`
                    // would leave VoiceOver an unlabeled field (the overlay
                    // placeholder is accessibilityHidden), so carry the label
                    // explicitly.
                    .accessibilityLabel(inputPlaceholder)
            }
            .padding(.leading, 14)
            .padding(.vertical, 6)

            Button {
                sendCurrentMessage()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(Color(sendButtonFillColor))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityIdentifier("chatSendButton")
            .accessibilityLabel("Send message")
        }
        .padding(6)
        .background(
            Capsule().fill(Color(pillFillColor))
        )
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - Private

    /// The input placeholder mirrors the empty state's book/no-book
    /// split: the reader AI-sheet chat (`bookFingerprint != nil`) uses
    /// the design's book-specific copy; the Library general-chat sheet
    /// (`bookFingerprint == nil`) keeps the neutral pre-v2 wording so
    /// the WI-2 re-skin does not regress that reused surface.
    private var inputPlaceholder: String {
        viewModel.bookFingerprint != nil
            ? "Ask about this book\u{2026}"
            : "Type a message\u{2026}"
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isLoading
    }

    /// Bug #310: the empty-state (icon + headline) and the input placeholder
    /// must read the designed cream-aware `sub` token — NOT the system
    /// appearance-aware `.secondary`, which resolves to ~1.07:1 (near-white)
    /// over the cream AI sheet (`#fcf8f0`) in Dark Mode. Same restore-to-
    /// designed-token fix as the sibling `AIReaderPanelHeader` subtitle
    /// (#285 / #297 / #300 class). `static` so a contrast test can pin it
    /// without rendering the view.
    static func secondaryContentColor(for theme: ReaderThemeV2) -> UIColor {
        theme.subColor
    }

    /// The pill's neutral wash — design `ChatView` input container.
    private var pillFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.04)
    }

    /// The send button's fill — accent when a message can be sent,
    /// a neutral wash otherwise (design `ChatView`'s `draft.trim()`
    /// conditional).
    private var sendButtonFillColor: UIColor {
        guard canSend else {
            return theme.isDark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.10)
        }
        return theme.accentColor
    }

    private func sendCurrentMessage() {
        let text = inputText
        inputText = ""
        Task {
            await viewModel.sendMessage(text)
        }
    }
}
#endif
