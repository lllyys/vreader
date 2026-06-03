// Purpose: The Chat sources menu — the popover that opens upward from the context
// bar's sources chip (Feature #86 WI-4, design #1455). Three toggle rows over the
// reader's own annotations (Notes / Highlights / Bookmarks), each with a per-book
// count. When all three are off, none of the reader's marks leave the device.
//
// @coordinates-with: ChatContextBar.swift, ChatSourceSelection.swift,
//   ChatAnnotationCache.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/chat-context-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// The Chat annotation-sources toggle menu (popover).
struct ChatSourcesMenu: View {
    let selection: ChatSourceSelection
    /// Per-book counts (notes / highlights / bookmarks).
    let counts: (notes: Int, highlights: Int, bookmarks: Int)
    let theme: ReaderThemeV2
    /// Toggled a kind — returns the new selection.
    let onToggle: (ChatSourceSelection) -> Void

    private enum Kind { case notes, highlights, bookmarks }

    static func rowIdentifier(_ kind: String) -> String { "chatSourcesRow.\(kind)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color(theme.ruleColor))
            VStack(spacing: 0) {
                row(.notes, label: "Notes", icon: "note.text", count: counts.notes, isOn: selection.notes)
                row(.highlights, label: "Highlights", icon: "highlighter", count: counts.highlights, isOn: selection.highlights)
                row(.bookmarks, label: "Bookmarks", icon: "bookmark", count: counts.bookmarks, isOn: selection.bookmarks)
            }
            .padding(.vertical, 4)
            Divider().overlay(Color(theme.ruleColor))
            footer
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(theme.paperColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(theme.ruleColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.18), radius: 18, y: 8)
        .accessibilityIdentifier("chatSourcesMenu")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Your annotations")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Color(theme.inkColor))
            Text("Add what you’ve marked to the context")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(theme.subColor))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    @ViewBuilder
    private func row(_ kind: Kind, label: String, icon: String, count: Int, isOn: Bool) -> some View {
        Button { onToggle(toggled(kind)) } label: {
            HStack(spacing: 11) {
                iconTile(icon, on: isOn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(theme.inkColor))
                    Text("\(count) in this book")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(theme.subColor))
                }
                Spacer(minLength: 8)
                switchView(isOn)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(Self.rowIdentifier(label.lowercased()))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    @ViewBuilder
    private func iconTile(_ icon: String, on: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(Color(on ? ChatContextBar.accentGreen : theme.subColor))
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(tileFill(on: on))))
    }

    @ViewBuilder
    private func switchView(_ on: Bool) -> some View {
        Capsule()
            .fill(Color(on ? ChatContextBar.accentGreen : (theme.isDark ? .init(white: 1, alpha: 0.12) : .init(white: 0, alpha: 0.12))))
            .frame(width: 38, height: 22)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 18, height: 18).padding(2)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color(theme.subColor))
            Text("Included alongside the book text so answers can cite what you marked.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(theme.subColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func toggled(_ kind: Kind) -> ChatSourceSelection {
        var s = selection
        switch kind {
        case .notes:      s.notes.toggle()
        case .highlights: s.highlights.toggle()
        case .bookmarks:  s.bookmarks.toggle()
        }
        return s
    }

    private func tileFill(on: Bool) -> UIColor {
        if on { return ChatContextBar.accentGreen.withAlphaComponent(theme.isDark ? 0.25 : 0.12) }
        return theme.isDark ? .init(white: 1, alpha: 0.05) : .init(white: 0, alpha: 0.04)
    }
}
#endif
