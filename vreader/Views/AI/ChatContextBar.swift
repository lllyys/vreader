// Purpose: The persistent ~40px context bar docked directly above the Chat
// composer (Feature #86 WI-3, design #1455). WI-3 renders the left **scope chip**
// (tap → ChatScopeMenu); WI-4 adds the right **sources chip**. The bar shares the
// composer's top rule and never scrolls away — scope is a thread-wide property,
// not a one-shot like the Summarize chips.
//
// The scope chip is a quiet outline pill: a Sparkle accent glyph, the muted
// "Context" label, the bold current-scope name, and a chevron. It tints to a
// faint accent wash only while its menu is open (accent discipline — the bar is
// permanently docked, so it can't shout).
//
// @coordinates-with: ChatScopeMenu.swift, AIChatView.swift, ChatContextScope.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/chat-context-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// The Chat context bar (WI-3: scope chip only).
struct ChatContextBar: View {
    let scope: ChatContextScope
    let theme: ReaderThemeV2
    /// Whether the scope menu is currently open (drives the chip's accent wash).
    let isScopeMenuOpen: Bool
    /// Tapped the scope chip.
    let onScopeTap: () -> Void

    static let scopeChipIdentifier = "chatContextScopeChip"

    var body: some View {
        HStack(spacing: 0) {
            scopeChip
            Spacer(minLength: 0)
            // WI-4: sources chip docks here.
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(height: 0.5)
        }
        .accessibilityIdentifier("chatContextBar")
    }

    @ViewBuilder
    private var scopeChip: some View {
        Button(action: onScopeTap) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(theme.accentColor))
                Text("Context")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(theme.subColor))
                Text(scope.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                Image(systemName: isScopeMenuOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(theme.subColor))
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, 11)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color(chipFill))
            )
            .overlay(
                Capsule().stroke(
                    Color(isScopeMenuOpen ? theme.accentColor : theme.ruleColor),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.scopeChipIdentifier)
        .accessibilityLabel("Chat context scope: \(scope.displayName)")
    }

    /// Transparent at rest; a faint accent wash while the menu is open.
    private var chipFill: UIColor {
        guard isScopeMenuOpen else { return .clear }
        return theme.isDark
            ? UIColor(red: 214/255, green: 136/255, blue: 90/255, alpha: 0.14)
            : UIColor(red: 140/255, green: 47/255, blue: 47/255, alpha: 0.07)
    }
}
#endif
