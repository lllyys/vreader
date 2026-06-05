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
                    // Feature #86 WI-5b (Gate-4): the field itself is non-editable
                    // while the whole book is being read — not just the send button.
                    .disabled(viewModel.isComposerDisabled)
                    .onChange(of: viewModel.isComposerDisabled) { _, disabled in
                        if disabled { isInputFocused = false }
                    }
                    .accessibilityIdentifier("chatInputField")
                    // Bug #310: the empty prompt `""` would leave VoiceOver an
                    // unlabeled field (the overlay placeholder is hidden), so
                    // carry the label explicitly.
                    .accessibilityLabel(inputPlaceholder)
            }
            .padding(.leading, 14)
            .padding(.vertical, 6)

            let sendState = composerSendState
            Button {
                switch sendState {
                case .stop: viewModel.cancelStreaming()
                case .send: sendCurrentMessage()
                case .disabled: break
                }
            } label: {
                sendDisc(for: sendState)
            }
            .buttonStyle(.plain)
            .disabled(sendState == .disabled)
            .accessibilityIdentifier("chatSendButton")
            .accessibilityLabel(sendState == .stop ? "Stop" : "Send")
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
        // Feature #86 WI-5b: while the whole book is being read, the composer is
        // disabled and the placeholder says so.
        if viewModel.isComposerDisabled { return "Reading\u{2026} ask once the book is ready" }
        return viewModel.bookFingerprint != nil
            ? "Ask about this book\u{2026}"
            : "Type a message\u{2026}"
    }

    /// Feature #87 WI-1: the send disc's resolved state (disabled / send / stop).
    /// A request in flight morphs the disc into the Stop control.
    var composerSendState: ComposerSendState {
        ComposerSendState.resolve(
            isLoading: viewModel.isLoading,
            hasInput: !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isComposerDisabled: viewModel.isComposerDisabled)
    }

    /// Feature #87 WI-1: the 32px send disc rendered for `state`. Three looks per
    /// the design (`stop-control-87.md`): disabled (neutral disc, muted arrow);
    /// send (accent disc, white `arrow.up`); stop (accent disc, white
    /// `square.fill` + a sweeping ring overlay).
    @ViewBuilder
    func sendDisc(for state: ComposerSendState) -> some View {
        ZStack {
            Circle().fill(Color(sendDiscFillColor(for: state)))
            switch state {
            case .stop:
                Image(systemName: "square.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                // The sweeping ring overlay signals an in-flight request.
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(0.7)
            case .send:
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            case .disabled:
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(Self.secondaryContentColor(for: theme)))
            }
        }
        .frame(width: 32, height: 32)
    }

    /// The send disc's fill for a given state — accent for `.send`/`.stop`, a
    /// neutral wash for `.disabled`.
    func sendDiscFillColor(for state: ComposerSendState) -> UIColor {
        switch state {
        case .disabled:
            return theme.isDark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.10)
        case .send, .stop:
            return theme.accentColor
        }
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

    func sendCurrentMessage() {
        let text = inputText
        inputText = ""
        Task { await viewModel.sendMessage(text) }
    }
}
#endif
