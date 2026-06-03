// Purpose: The AI Chat composer (input pill + send button) + its styling
// helpers, extracted from AIChatView.swift to keep that file under the ~300-line
// guide as the context bar / scope / sources / retrieval surfaces accrete
// (Feature #86 WI-4). Behaviour is unchanged — the design pill input row, the
// bug-#94 focus/submit wiring, and the bug-#310 themed placeholder all move
// verbatim.
//
// @coordinates-with: AIChatView.swift, AIChatViewModel.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

extension AIChatView {

    // MARK: - Input Bar

    /// The design's rounded pill input field with a circular send button —
    /// `vreader-panels.jsx` `ChatView`'s input row. Multiline (`axis: .vertical`,
    /// `lineLimit(1...5)`) with the bug-#94 focus/submit wiring.
    @ViewBuilder
    var inputBar: some View {
        // Feature #86 WI-3: the cluster's single top rule lives on the docked
        // ChatContextBar above this composer (design #1455), so the composer
        // draws no rule of its own.
        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                // Bug #310: themed placeholder. SwiftUI ignores `.foregroundStyle`
                // on a `TextField`'s own placeholder (it stays the system
                // appearance-aware colour — ~1.07:1, near-invisible over the cream
                // sheet in Dark Mode), so overlay a `Text` in the designed `sub`
                // token. Identical font + the shared padding keep it aligned.
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
                    .onSubmit { sendCurrentMessage() }
                    .accessibilityIdentifier("chatInputField")
                    // Bug #310: the empty prompt `""` would leave VoiceOver an
                    // unlabeled field (the overlay placeholder is hidden), so
                    // carry the label explicitly.
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
                    .background(Circle().fill(Color(sendButtonFillColor)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityIdentifier("chatSendButton")
            .accessibilityLabel("Send message")
        }
        .padding(6)
        .background(Capsule().fill(Color(pillFillColor)))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - Composer helpers

    /// The input placeholder mirrors the empty state's book/no-book split: the
    /// reader AI-sheet chat (`bookFingerprint != nil`) uses the design's
    /// book-specific copy; the Library general-chat sheet keeps the neutral
    /// pre-v2 wording so the WI-2 re-skin doesn't regress that reused surface.
    var inputPlaceholder: String {
        viewModel.bookFingerprint != nil
            ? "Ask about this book\u{2026}"
            : "Type a message\u{2026}"
    }

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isLoading
    }

    /// Bug #310: the empty-state + the placeholder must read the designed
    /// cream-aware `sub` token — NOT the system appearance-aware `.secondary`,
    /// which resolves to ~1.07:1 over the cream AI sheet in Dark Mode. `static`
    /// so a contrast test can pin it without rendering the view.
    static func secondaryContentColor(for theme: ReaderThemeV2) -> UIColor {
        theme.subColor
    }

    /// The pill's neutral wash — design `ChatView` input container.
    var pillFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.04)
    }

    /// The send button's fill — accent when sendable, a neutral wash otherwise.
    var sendButtonFillColor: UIColor {
        guard canSend else {
            return theme.isDark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.10)
        }
        return theme.accentColor
    }

    func sendCurrentMessage() {
        let text = inputText
        inputText = ""
        Task { await viewModel.sendMessage(text) }
    }
}
#endif
