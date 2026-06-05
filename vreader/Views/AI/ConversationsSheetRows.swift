// Purpose: Feature #88 WI-5 — the row + empty-state pieces of the Conversations
// sheet, split out of `ConversationsSheet.swift` to keep both files under the
// ~300-line guide. `SessionRow` renders one conversation (active-tinted with an
// "Active" pill, chat-bubble glyph, 2-line snippet, "{n} messages · {when}"
// footer); `ConversationsEmptyState` is the first-chat empty state; `RenameRow`
// is the in-place accent-bordered rename field; `relativeSessionTime` is the
// compact "Now / 2h ago / Yesterday / Apr 18" formatter.
//
// Theming mirrors ChatSessionBar / ChatContextBar (Color(theme.inkColor) etc.).
//
// @coordinates-with: ConversationsSheet.swift, ChatSessionRecord.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/session-switcher-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// One conversation row in the Conversations sheet (#88 WI-5 — `SessionRow`).
struct SessionRow: View {
    let summary: ChatSessionSummary
    let isActive: Bool
    let theme: ReaderThemeV2

    /// The accent "on" green — matches `ChatSessionBar.accentGreen` (design `#3a6a5a`).
    static let accentGreen = UIColor(red: 0x3a / 255, green: 0x6a / 255, blue: 0x5a / 255, alpha: 1)

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            glyphCircle
            VStack(alignment: .leading, spacing: 2) {
                titleRow
                Text(summary.snippet)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(theme.subColor))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .lineSpacing(1)
                footer
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(rowBackground))
        )
        .contentShape(Rectangle())
        .accessibilityIdentifier("conversationRow-\(summary.id.uuidString)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isActive ? "\(summary.title), active conversation" : summary.title)
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 7) {
            Text(summary.title)
                .font(.system(size: 14.5, weight: .semibold, design: .serif))
                .foregroundStyle(Color(isActive ? theme.accentColor : theme.inkColor))
                .lineLimit(1)
                .truncationMode(.tail)
            if isActive {
                Text("Active")
                    .font(.system(size: 9.5, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(Self.accentGreen)))
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        Text("\(summary.messageCount) \(summary.messageCount == 1 ? "message" : "messages") · \(relativeSessionTime(summary.updatedAt))")
            .font(.system(size: 11))
            .foregroundStyle(Color(theme.subColor))
            .padding(.top, 2)
    }

    /// The 30×30 circle: filled accent if active, else a subtle fill.
    @ViewBuilder
    private var glyphCircle: some View {
        Image(systemName: "bubble.left")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color(isActive ? .white : theme.subColor))
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color(isActive ? theme.accentColor : subtleFill))
            )
    }

    /// Accent-tinted background for the active row; transparent otherwise.
    private var rowBackground: UIColor {
        guard isActive else { return .clear }
        return theme.isDark
            ? UIColor(red: 214/255, green: 136/255, blue: 90/255, alpha: 0.12)
            : UIColor(red: 140/255, green: 47/255, blue: 47/255, alpha: 0.06)
    }

    private var subtleFill: UIColor {
        theme.isDark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(white: 0, alpha: 0.05)
    }
}

/// The first-chat empty state for the Conversations sheet (#88 WI-5 —
/// `EmptyConversations`).
struct ConversationsEmptyState: View {
    let theme: ReaderThemeV2

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Image(systemName: "bubble.left")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(glyphFill))
                )
                .padding(.bottom, 14)
            Text("No past conversations")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(Color(theme.inkColor))
            Text("This is your first chat about this book. Start a new conversation any time and it'll be saved here.")
                .font(.system(size: 13))
                .foregroundStyle(Color(theme.subColor))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 5)
                .padding(.horizontal, 40)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("conversationsEmptyState")
    }

    private var glyphFill: UIColor {
        theme.isDark
            ? UIColor(white: 1, alpha: 0.05)
            : UIColor(white: 0, alpha: 0.04)
    }
}

/// The in-place rename field for a session row (#88 WI-5 — `RenameRow`): an
/// accent-bordered `TextField` pre-filled with the title + a "Done" button.
struct RenameRow: View {
    let theme: ReaderThemeV2
    @Binding var draft: String
    @FocusState.Binding var isFocused: Bool
    let onDone: () -> Void

    static let accentGreen = SessionRow.accentGreen

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "bubble.left")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(theme.accentColor))
                )
            TextField("", text: $draft)
                .font(.system(size: 14.5, weight: .semibold, design: .serif))
                .foregroundStyle(Color(theme.inkColor))
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(onDone)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(fieldFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(theme.accentColor), lineWidth: 1.5)
                )
                .accessibilityIdentifier("conversationRenameField")
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color(theme.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("conversationRenameDone")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(rowBackground))
        )
    }

    private var fieldFill: UIColor {
        theme.isDark ? UIColor(red: 0x2b/255, green: 0x29/255, blue: 0x26/255, alpha: 1)
                     : .white
    }

    private var rowBackground: UIColor {
        theme.isDark
            ? UIColor(red: 214/255, green: 136/255, blue: 90/255, alpha: 0.12)
            : UIColor(red: 140/255, green: 47/255, blue: 47/255, alpha: 0.06)
    }
}

/// Compact relative time for a session footer ("Now / 5m ago / 2h ago /
/// Yesterday / Apr 18 / Apr 18, 2023"). Idiomatic + locale-aware.
func relativeSessionTime(_ date: Date, now: Date = Date()) -> String {
    let seconds = now.timeIntervalSince(date)
    if seconds < 60 { return "Now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
    if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }

    let calendar = Calendar.current
    if calendar.isDateInYesterday(date) { return "Yesterday" }

    let formatter = DateFormatter()
    if calendar.isDate(date, equalTo: now, toGranularity: .year) {
        formatter.dateFormat = "MMM d"
    } else {
        formatter.dateFormat = "MMM d, yyyy"
    }
    return formatter.string(from: date)
}
#endif
