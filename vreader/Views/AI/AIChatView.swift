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
    // Internal (not private) so the composer extracted into AIChatView+Composer.swift
    // can read them (Feature #86 WI-4: keep AIChatView.swift under the size guide).
    @State var inputText: String = ""
    @FocusState var isInputFocused: Bool

    /// Visual-identity-v2 theme tokens (feature #65 WI-2). Defaults to
    /// `.paper` so existing callers / previews that omit it keep working.
    var theme: ReaderThemeV2 = .paper

    /// Feature #86 WI-3/4: which context-bar menu is presented (or none).
    @State private var openMenu: ContextMenuKind?
    private enum ContextMenuKind { case scope, sources }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                messageList

                if let error = viewModel.errorMessage {
                    errorBanner(message: error)
                }

                // Feature #86 WI-3/4/5b: the docked context bar above the composer.
                // For the on-demand Whole-book scope, the bar morphs into the
                // retrieval cluster (Armed/Reading/Ready); otherwise the normal
                // scope + sources chips.
                if viewModel.scope == .wholeBook, let retrieval = viewModel.wholeBookRetrieval {
                    ChatRetrievalCluster(
                        phase: retrieval.phase,
                        theme: theme,
                        progressFraction: retrieval.progressFraction,
                        unitProgressLabel: retrieval.unitProgressLabel,
                        onScopeTap: { toggleMenu(.scope) },
                        onCancel: { retrieval.cancel() }
                    )
                } else {
                    ChatContextBar(
                        scope: viewModel.scope,
                        theme: theme,
                        isScopeMenuOpen: openMenu == .scope,
                        onScopeTap: { toggleMenu(.scope) },
                        sourcesCount: viewModel.sources.activeCount,
                        isSourcesMenuOpen: openMenu == .sources,
                        onSourcesTap: { toggleMenu(.sources) }
                    )
                }

                inputBar
            }

            // Feature #86 WI-3/4: the scope / sources menus float above the
            // composer (scope at leading, sources at trailing) with a shared
            // tap-scrim that dismisses whichever is open.
            if openMenu != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { openMenu = nil }
            }
            if openMenu == .scope {
                ChatScopeMenu(
                    selected: viewModel.scope,
                    theme: theme,
                    onSelect: { scope in
                        viewModel.setScope(scope)
                        openMenu = nil
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.bottom, 80)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if openMenu == .sources {
                ChatSourcesMenu(
                    selection: viewModel.sources,
                    counts: viewModel.sourceCounts,
                    theme: theme,
                    onToggle: { viewModel.setSources($0) }   // stays open for multi-toggle
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
                .padding(.bottom, 80)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: openMenu)
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
        // Feature #78: consume a pending Ask-AI seed BOTH on initial mount (the
        // seed is set before this view exists, and the Chat tab is only selected
        // on the panel's onAppear) AND on later changes — an .onChange-only
        // consumer would miss the first seed and open Chat with an empty input.
        .onAppear { applySeedIfPossible() }
        .task(id: viewModel.seededInput) { applySeedIfPossible() }
    }

    /// Feature #78: the pure decision for consuming a pending Ask-AI seed —
    /// extracted so it's testable without rendering the view (Gate-4 Medium).
    /// `.apply` when there's a seed and the input is empty; `.dropAndClear` when
    /// a seed arrives over an active draft (never clobber the draft); `.none`
    /// when there's nothing pending. Both non-`.none` cases clear the VM seed so
    /// a pending seed can't linger and inject after the user clears the draft.
    enum SeedDecision: Equatable { case apply(String); case dropAndClear; case none }

    static func seedDecision(seededInput: String?, currentInput: String) -> SeedDecision {
        guard let seed = seededInput else { return .none }
        return currentInput.isEmpty ? .apply(seed) : .dropAndClear
    }

    /// Feature #86 WI-3/4: toggle a context-bar menu (tapping the open one closes it,
    /// tapping the other switches to it).
    private func toggleMenu(_ kind: ContextMenuKind) {
        openMenu = (openMenu == kind) ? nil : kind
    }

    /// One-shot consumption of `viewModel.seededInput` (applies the pure
    /// `seedDecision` to the view's `@State`).
    private func applySeedIfPossible() {
        switch Self.seedDecision(seededInput: viewModel.seededInput, currentInput: inputText) {
        case .apply(let seed):
            inputText = seed
            isInputFocused = true
            viewModel.clearSeed()
        case .dropAndClear:
            viewModel.clearSeed()
        case .none:
            break
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

}
#endif
