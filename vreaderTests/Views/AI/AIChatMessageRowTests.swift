// Purpose: Feature #65 WI-2 — composition + role-discrimination tests
// for the re-skinned chat message row (`AIChatMessageRow`). The v2
// re-skin replaces the private `ChatBubbleView` (`Color.blue.opacity`
// /`Color.secondary.opacity` bubbles) with the design's two forms:
// an accent user bubble with an asymmetric corner, and a sparkle-
// avatar + serif assistant/system row.
//
// `AIChatMessageRow` is a pure presentational view. Its honest
// unit-testable surface is two layers (the `AISummaryTabView` /
// `SearchView.contentState` precedent):
//
//  1. Role routing — `AIChatMessageRow.form(for:)` is a pure static
//     mapper from a `ChatRole` to the `BubbleForm` it renders. These
//     tests pin that `.user` selects the accent bubble form and that
//     `.assistant` / `.system` both select the sparkle-avatar row form
//     — the design's two-branch split. The compile-time guard against
//     a new unmapped `ChatRole` is the exhaustive `switch` in
//     `form(for:)` itself; these tests pin the split for the three
//     current roles.
//
//  2. Composition — SwiftUI is forced to materialise `body` for
//     representative message inputs (empty, long, CJK, RTL) across every
//     `ReaderThemeV2` case and both forms, so a re-skin regression that
//     traps under a particular theme/role/input is caught without a
//     render pass.
//
// @coordinates-with: AIChatMessageRow.swift, ChatMessage.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("AI Chat message row re-skin — feature #65 WI-2")
@MainActor
struct AIChatMessageRowTests {

    // MARK: - Fixtures

    /// Representative message-content inputs the row must lay out:
    /// an empty string (an assistant message is appended empty before
    /// the first stream chunk arrives — `AIChatViewModel.sendMessage`),
    /// a long multi-sentence string, CJK text (no inter-word spaces —
    /// exercises the wrapping path of both forms), and an RTL Arabic
    /// string (bidi text through the accent bubble + serif row).
    private static let contentInputs: [String] = [
        "",
        String(repeating: "Drawing on the book's context, here is a "
            + "focused answer to your question. ", count: 20),
        "根据这本书的语境，这是对你问题的一个有针对性的回答。",
        "ما رأيك في هذا المقطع؟ هذا نص عربي يُكتب من اليمين إلى اليسار.",
    ]

    private static func message(_ role: ChatRole, _ content: String = "x") -> ChatMessage {
        ChatMessage(role: role, content: content)
    }

    // MARK: - Role → form routing

    @Test("A `.user` message selects the accent user-bubble form")
    func userMessageSelectsUserBubbleForm() {
        // The design's `ChatBubble` renders `role === 'user'` as an
        // accent-filled bubble with an asymmetric corner. Pin that the
        // role mapper routes `.user` to `.userBubble`.
        #expect(AIChatMessageRow.form(for: .user) == .userBubble)
    }

    @Test("An `.assistant` message selects the sparkle-avatar row form")
    func assistantMessageSelectsAssistantRowForm() {
        // The design renders a non-user message as a sparkle avatar +
        // serif body row. Pin `.assistant` → `.assistantRow`.
        #expect(AIChatMessageRow.form(for: .assistant) == .assistantRow)
    }

    @Test("A `.system` message selects the sparkle-avatar row form")
    func systemMessageSelectsAssistantRowForm() {
        // `system` (book-context injection role) shares the design's
        // non-user branch — it must NOT render as a user bubble.
        #expect(AIChatMessageRow.form(for: .system) == .assistantRow)
    }

    @Test("`.assistant` and `.system` resolve to the same (non-user) form")
    func assistantAndSystemShareTheNonUserForm() {
        // The design has exactly two `ChatBubble` branches: `user` and
        // everything-else. Pin that the two non-user roles collapse to
        // one form so a re-skin can't accidentally fork them.
        #expect(AIChatMessageRow.form(for: .assistant)
            == AIChatMessageRow.form(for: .system))
    }

    @Test("Only `.user` selects the user-bubble form — the role split is exact")
    func onlyUserRoleSelectsUserBubble() {
        // Pins the role split for the three current `ChatRole`s: exactly
        // one (`.user`) maps to `.userBubble`, the other two to
        // `.assistantRow`. The compile-time guard for a *new* role is
        // the exhaustive `switch` in `form(for:)`; `allRoles` here is
        // hand-maintained and must be extended alongside any new case.
        let allRoles: [ChatRole] = [.user, .assistant, .system]
        let userBubbleRoles = allRoles.filter {
            AIChatMessageRow.form(for: $0) == .userBubble
        }
        #expect(userBubbleRoles == [.user])
        let assistantRowRoles = allRoles.filter {
            AIChatMessageRow.form(for: $0) == .assistantRow
        }
        #expect(Set(assistantRowRoles) == Set([.assistant, .system]))
    }

    // MARK: - Composition across themes (layout-trap regression guard)

    @Test(
        "The row body builds for every role + input across every theme",
        arguments: ReaderThemeV2.allCases
    )
    func rowBodyBuildsForEveryThemeRoleAndInput(_ theme: ReaderThemeV2) {
        // A re-skin regression that traps the row under a specific
        // theme/role/input (a token that traps, a layout that crashes
        // on empty content, a CJK wrapping fault) surfaces here. All
        // five themes × three roles × four content inputs must
        // materialise `body` without trapping.
        for role in [ChatRole.user, .assistant, .system] {
            for content in Self.contentInputs {
                let row = AIChatMessageRow(
                    message: Self.message(role, content),
                    theme: theme
                )
                _ = row.body
            }
        }
    }

    @Test("The user-bubble form builds for an empty content string")
    func userBubbleBuildsForEmptyContent() {
        // Defensive: a user message is never appended empty by the VM,
        // but the bubble must still compose around an empty string
        // rather than trap.
        let row = AIChatMessageRow(
            message: Self.message(.user, ""),
            theme: .paper
        )
        #expect(AIChatMessageRow.form(for: row.message.role) == .userBubble)
        _ = row.body
    }

    @Test("The assistant-row form builds for an empty content string")
    func assistantRowBuildsForEmptyContent() {
        // `AIChatViewModel.sendMessage` appends an empty `.assistant`
        // message and streams chunks into it — the row is rendered with
        // "" before the first chunk lands. The sparkle avatar + serif
        // body must compose around an empty string.
        let row = AIChatMessageRow(
            message: Self.message(.assistant, ""),
            theme: .dark
        )
        #expect(AIChatMessageRow.form(for: row.message.role) == .assistantRow)
        _ = row.body
    }

    @Test("The user-bubble form builds for a long multi-sentence message")
    func userBubbleBuildsForLongContent() {
        let long = String(
            repeating: "What do you make of this passage and its irony? ",
            count: 30
        )
        let row = AIChatMessageRow(
            message: Self.message(.user, long),
            theme: .sepia
        )
        _ = row.body
    }

    @Test("The assistant-row form builds for CJK content")
    func assistantRowBuildsForCJKContent() {
        // CJK has no inter-word spaces; the serif assistant body's
        // wrapping must not trap. Pin composition under an OLED theme.
        let row = AIChatMessageRow(
            message: Self.message(.assistant, "这一行是小说的主题陈述，带着刻意的反讽。"),
            theme: .oled
        )
        _ = row.body
    }

    @Test("The user-bubble form builds for CJK content")
    func userBubbleBuildsForCJKContent() {
        let row = AIChatMessageRow(
            message: Self.message(.user, "你对这段话怎么看？"),
            theme: .photo
        )
        _ = row.body
    }
}
