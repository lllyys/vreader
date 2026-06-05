// Purpose: Feature #88 WI-5 — the Conversations bottom sheet, the switcher behind
// the Chat-tab session bar's title pill. A "Conversations" header + Close button,
// a dashed New-conversation row, then the saved sessions (or the first-chat empty
// state). Each row swipes to Rename (inline, accent-bordered field) / Delete (red).
// Tapping a row switches to it; tapping New / a row dismisses the sheet.
//
// Loads the list via `viewModel.loadSessionSummaries()` in `.task` (and re-loads
// after rename / delete). The row pieces live in `ConversationsSheetRows.swift` to
// keep this file under the ~300-line guide. Theming mirrors ChatSessionBar.
//
// @coordinates-with: AIChatView.swift, AIChatViewModel.swift,
//   AIChatViewModel+Sessions.swift, AIChatViewModel+SessionTransitions.swift,
//   ConversationsSheetRows.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/session-switcher-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// The nested "Conversations" switcher sheet (Feature #88 WI-5).
struct ConversationsSheet: View {
    let viewModel: AIChatViewModel
    let theme: ReaderThemeV2
    /// Called to dismiss the sheet (tapping Close, New, or a row).
    let onDismiss: () -> Void

    @State private var summaries: [ChatSessionSummary] = []
    /// The session currently being renamed in place (nil ⇒ no row in edit mode).
    @State private var renamingId: UUID?
    @State private var renameDraft: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            newConversationRow
            if summaries.isEmpty {
                ConversationsEmptyState(theme: theme)
            } else {
                sessionList
            }
        }
        .background(Color(theme.backgroundColor).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("conversationsSheet")
        .task { await reload() }
        .onChange(of: viewModel.activeSessionId) { _, _ in
            // Keep the list live when the active session changes underneath an open
            // sheet — e.g. the first turn of a new conversation settles + creates its
            // row, or a switch/delete-fallback lands (Gate-4 WI-5 Medium).
            Task { await reload() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Conversations")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(Color(theme.inkColor))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(theme.subColor))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(iconButtonFill)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("conversationsCloseButton")
            .accessibilityLabel("Close conversations")
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(height: 0.5)
        }
    }

    // MARK: - New conversation row (dashed)

    @ViewBuilder
    private var newConversationRow: some View {
        Button {
            Task { await viewModel.newConversation() }
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: [Color(theme.accentColor), Color(theme.accentColor).opacity(0.67)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    )
                Text("New conversation")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        Color(theme.ruleColorForDashedBorder),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .accessibilityIdentifier("conversationsNewRow")
        .accessibilityLabel("New conversation")
    }

    // MARK: - Session list

    @ViewBuilder
    private var sessionList: some View {
        List {
            ForEach(summaries) { summary in
                rowContent(for: summary)
                    .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteSession(summary.id)
                                await reload()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("conversationDelete-\(summary.id.uuidString)")

                        Button {
                            beginRename(summary)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.gray)
                        .accessibilityIdentifier("conversationRename-\(summary.id.uuidString)")
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private func rowContent(for summary: ChatSessionSummary) -> some View {
        if renamingId == summary.id {
            RenameRow(
                theme: theme,
                draft: $renameDraft,
                isFocused: $renameFieldFocused,
                onDone: { commitRename(for: summary.id) }
            )
        } else {
            SessionRow(
                summary: summary,
                isActive: summary.id == viewModel.activeSessionId,
                theme: theme
            )
            .contentShape(Rectangle())   // the WHOLE row is tappable, not just opaque bits
            .onTapGesture {
                // Tapping the ALREADY-active row must NOT re-switch — switchToSession
                // cancels the in-flight stream + snaps to the settled snapshot
                // (Gate-4 WI-5 Medium). Just close the sheet for the active row.
                if summary.id != viewModel.activeSessionId {
                    Task { await viewModel.switchToSession(summary.id) }
                }
                onDismiss()
            }
        }
    }

    // MARK: - Actions

    private func beginRename(_ summary: ChatSessionSummary) {
        renameDraft = summary.title
        renamingId = summary.id
        renameFieldFocused = true
    }

    private func commitRename(for id: UUID) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingId = nil
        renameFieldFocused = false
        guard !trimmed.isEmpty else { return }
        Task {
            await viewModel.renameSession(id: id, to: trimmed)
            await reload()
        }
    }

    private func reload() async {
        summaries = await viewModel.loadSessionSummaries()
    }

    private var iconButtonFill: UIColor {
        theme.isDark
            ? UIColor(white: 1, alpha: 0.07)
            : UIColor(white: 0, alpha: 0.05)
    }
}

private extension ReaderThemeV2 {
    /// The dashed New-conversation border tint (design: white@16% dark / black@16%
    /// light — slightly stronger than `ruleColor` so the dash reads).
    var ruleColorForDashedBorder: UIColor {
        isDark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor(white: 0, alpha: 0.16)
    }
}
#endif
