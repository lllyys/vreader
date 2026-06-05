// Purpose: Feature #88 WI-4 — the slim Chat-tab SESSION BAR docked at the top of
// the Chat tab (book chat only), above the message list. Left = a tappable pill
// (chat-bubble glyph + active conversation title + chevron) that opens the
// Conversations switcher (WI-5); right = a "New" pill that starts a fresh thread.
//
// From the `SessionBar` artboard: a 0.5pt bottom rule, a serif semibold title
// pill (truncates tail-first under width pressure — the "New" pill holds a higher
// layout priority so it never gets pushed off), an accent-green compose plus.
// Mirrors ChatContextBar's theming idiom (Color(theme.ruleColor) etc.).
//
// @coordinates-with: AIChatView.swift, AIChatViewModel.swift, ReaderThemeV2.swift,
//   ChatContextBar.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/session-switcher-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// The Chat-tab session bar: a left title pill (tap → Conversations) + a right
/// "New" compose pill (Feature #88 WI-4).
struct ChatSessionBar: View {
    /// The active conversation's display title.
    let title: String
    /// Whether the Conversations switcher is currently open (drives the title
    /// pill's wash + chevron rotation).
    let isOpen: Bool
    let theme: ReaderThemeV2
    /// Tapped the title pill (opens the Conversations switcher — WI-5).
    let onTitleTap: () -> Void
    /// Tapped "New" (starts a fresh conversation).
    let onNew: () -> Void

    static let titleIdentifier = "chatSessionBarTitle"
    static let newIdentifier = "chatSessionBarNew"

    /// The accent "on" green — matches `ChatContextBar.accentGreen` (design `#3a6a5a`).
    static let accentGreen = UIColor(red: 0x3a / 255, green: 0x6a / 255, blue: 0x5a / 255, alpha: 1)

    var body: some View {
        HStack(spacing: 0) {
            titlePill
            Spacer(minLength: 8)
            newButton
                .layoutPriority(1)   // New stays full-size; a long title truncates instead
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(height: 0.5)
        }
        .accessibilityIdentifier("chatSessionBar")
    }

    // MARK: - Left: title pill

    @ViewBuilder
    private var titlePill: some View {
        Button(action: onTitleTap) {
            HStack(spacing: 7) {
                glyphCircle
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(theme.inkColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(theme.subColor))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isOpen)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(titlePillFill)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.titleIdentifier)
        .accessibilityLabel("Conversation: \(title)")
    }

    /// The 22×22 subtly-filled circle holding the chat-bubble glyph.
    @ViewBuilder
    private var glyphCircle: some View {
        Image(systemName: "bubble.left")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color(theme.subColor))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color(glyphCircleFill))
            )
    }

    /// Transparent at rest; a subtle wash while the switcher is open.
    private var titlePillFill: UIColor {
        guard isOpen else { return .clear }
        return theme.isDark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(white: 0, alpha: 0.05)
    }

    private var glyphCircleFill: UIColor {
        theme.isDark
            ? UIColor(white: 1, alpha: 0.07)
            : UIColor(white: 0, alpha: 0.05)
    }

    // MARK: - Right: New pill

    @ViewBuilder
    private var newButton: some View {
        Button(action: onNew) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(Self.accentGreen))
                Text("New")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.clear))
            .overlay(
                Capsule().stroke(Color(theme.ruleColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.newIdentifier)
        .accessibilityLabel("New conversation")
    }
}
#endif
