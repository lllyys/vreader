// Purpose: The Chat scope menu — the popover that opens upward from the context
// bar's scope chip (Feature #86 WI-3, design #1455). Four rows (Section / Chapter
// / Book so far / Whole book), each with a radio check, a one-line descriptor, a
// token estimate, and — for Whole book — an "On-demand" tag. The footer is
// spoiler-aware: Whole book warns it can reference pages ahead.
//
// @coordinates-with: ChatContextBar.swift, ChatContextScope.swift,
//   ChatContextScope+Menu.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/chat-context-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// The Chat context-scope selection menu (popover).
struct ChatScopeMenu: View {
    let selected: ChatContextScope
    let theme: ReaderThemeV2
    /// Picked a scope row.
    let onSelect: (ChatContextScope) -> Void

    static func rowIdentifier(_ scope: ChatContextScope) -> String {
        "chatScopeRow.\(scope.rawValue)"
    }

    /// All four scopes. WI-5 added the on-demand Whole-book row now that its
    /// retrieval + armed/reading/ready states exist (it was filtered out in WI-3
    /// to avoid offering whole-book before retrieval was built).
    static let menuScopes: [ChatContextScope] = ChatContextScope.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color(theme.ruleColor))
            VStack(spacing: 0) {
                // WI-3 ships the three synchronous scopes only. The on-demand
                // Whole-book row lands in WI-5 together with its retrieval +
                // armed/reading/ready states — so the menu never offers whole-book
                // (with its spoiler-aware copy) while requests would silently use a
                // narrower slice (Gate-4 High).
                ForEach(Self.menuScopes, id: \.self) { scope in
                    row(scope)
                }
            }
            .padding(.vertical, 4)
            Divider().overlay(Color(theme.ruleColor))
            footer
        }
        .frame(width: 286)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(theme.paperColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(theme.ruleColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.18), radius: 18, y: 8)
        .accessibilityIdentifier("chatScopeMenu")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Chat context")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(theme.inkColor))
            Text("How much of the book the assistant reads")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(theme.subColor))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func row(_ scope: ChatContextScope) -> some View {
        let isSelected = scope == selected
        Button { onSelect(scope) } label: {
            HStack(alignment: .top, spacing: 10) {
                radio(isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(scope.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(theme.inkColor))
                        if scope.isOnDemand {
                            Text("ON-DEMAND")
                                .font(.system(size: 9.5, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(Color(theme.accentColor))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(onDemandTagFill)))
                        }
                    }
                    Text(scope.menuDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(theme.subColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text(scope.tokenEstimate)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(theme.subColor))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color(selectedRowFill) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.rowIdentifier(scope))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func radio(_ isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color(theme.accentColor) : .clear)
                .overlay(
                    Circle().stroke(
                        isSelected ? .clear : Color(theme.ruleColor), lineWidth: 1.5
                    )
                )
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 18, height: 18)
        .padding(.top, 1)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color(theme.subColor))
            Text(ChatContextScope.menuFooter(forSelected: selected))
                .font(.system(size: 11.5))
                .foregroundStyle(Color(theme.subColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var selectedRowFill: UIColor {
        theme.isDark
            ? UIColor(red: 214/255, green: 136/255, blue: 90/255, alpha: 0.12)
            : UIColor(red: 140/255, green: 47/255, blue: 47/255, alpha: 0.05)
    }

    private var onDemandTagFill: UIColor {
        theme.isDark
            ? UIColor(red: 214/255, green: 136/255, blue: 90/255, alpha: 0.16)
            : UIColor(red: 140/255, green: 47/255, blue: 47/255, alpha: 0.08)
    }
}
#endif
