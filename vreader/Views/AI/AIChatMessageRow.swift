// Purpose: Feature #65 WI-2 — the re-skinned AI chat message row.
// Replaces the pre-v2 private `ChatBubbleView`
// (`Color.blue.opacity(0.15)` / `Color.secondary.opacity(0.1)`
// bubbles) with the design's two `ChatBubble` forms: an accent-filled
// user bubble with an asymmetric corner, and a sparkle-avatar + serif
// assistant/system row.
//
// Mirrors `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`
// — the `ChatBubble` component (the `role === 'user'` accent bubble
// branch and the sparkle-avatar non-user branch).
//
// Role routing is exposed through the pure static `form(for:)` mapper
// + the `BubbleForm` enum (the `AISummaryTabView.section(for:)` /
// `SearchView.contentState` precedent) so a re-skin regression that
// forks or drops a role can be pinned without a SwiftUI render pass.
//
// @coordinates-with: AIChatView.swift, ChatMessage.swift,
//   ReaderThemeV2.swift, ReaderTypography.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// A single re-skinned chat message row — design `vreader-panels.jsx`
/// `ChatBubble`. A `.user` message renders the accent bubble form; an
/// `.assistant` / `.system` message renders the sparkle-avatar row form.
struct AIChatMessageRow: View {

    /// The chat message to render (its `role` selects the form).
    let message: ChatMessage

    /// Visual-identity-v2 theme tokens for the bubble surface + ink.
    let theme: ReaderThemeV2

    // MARK: - Bubble form

    /// The two distinct visual forms the design's `ChatBubble` draws.
    /// The design has exactly two branches — `role === 'user'` and
    /// everything-else — so `.assistant` and `.system` share `.assistantRow`.
    enum BubbleForm: Equatable {
        /// Accent-filled bubble, right-aligned, asymmetric top-right corner.
        case userBubble
        /// Sparkle avatar + serif body row, left-aligned.
        case assistantRow
    }

    /// Pure mapping from a message role to its bubble form. Exposed
    /// `static` so the re-skin regression guard pins the role split
    /// without a render pass (the `AISummaryTabView.section(for:)`
    /// precedent).
    static func form(for role: ChatRole) -> BubbleForm {
        switch role {
        case .user:               return .userBubble
        // The design's non-user `ChatBubble` branch — `system` is the
        // book-context-injection role and shares the assistant row.
        case .assistant, .system: return .assistantRow
        }
    }

    var body: some View {
        switch Self.form(for: message.role) {
        case .userBubble:    userBubble
        case .assistantRow:  assistantRow
        }
    }

    // MARK: - Forms

    /// The accent user bubble — design `ChatBubble` `role === 'user'`.
    /// Right-aligned, accent fill, white sans body, an asymmetric
    /// top-right corner (`borderTopRightRadius: 6` against the 18pt
    /// other corners).
    @ViewBuilder
    private var userBubble: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 48)
            Text(message.content)
                .font(.system(size: 14))
                .lineSpacing(2)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    UserBubbleShape()
                        .fill(Color(theme.accentColor))
                )
        }
        .padding(.horizontal, 18)
        .accessibilityIdentifier("chatBubble-\(message.role.rawValue)")
    }

    /// The sparkle-avatar assistant/system row — design `ChatBubble`
    /// non-user branch. A 24pt accent-gradient sparkle avatar followed
    /// by a serif body, left-aligned.
    @ViewBuilder
    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 8) {
            sparkleAvatar
            VStack(alignment: .leading, spacing: 0) {
                // Bug #335: render the LLM's markdown as formatting. `content` is
                // a `String` variable, so `Text(_:)`'s literal-only markdown
                // parsing left `**bold**` / `-` lists showing verbatim — the pure
                // `ChatMarkdownRenderer` turns it into a formatted AttributedString.
                Text(ChatMarkdownRenderer.attributedString(from: message.content))
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14.5)))
                    .lineSpacing(4)
                    .foregroundStyle(Color(theme.inkColor))
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Feature #86 WI-6: the "Drew on" provenance row under the reply.
                if !message.citations.isEmpty {
                    ChatCitationRow(citations: message.citations, theme: theme)
                        .padding(.bottom, 4)
                }
            }
            Spacer(minLength: 32)
        }
        .padding(.horizontal, 18)
        .accessibilityIdentifier("chatBubble-\(message.role.rawValue)")
    }

    /// The 24pt accent-gradient circle with a white sparkle — design
    /// `ChatBubble`'s assistant avatar.
    private var sparkleAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(theme.accentColor),
                        Color(theme.accentColor).opacity(0.67),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .padding(.top, 2)
            .accessibilityHidden(true)
    }
}

// MARK: - User bubble shape

/// The user bubble's asymmetric rounded rectangle — design `ChatBubble`
/// `borderRadius: 18, borderTopRightRadius: 6`. SwiftUI exposes no
/// per-corner radius on `RoundedRectangle`, so the path is built
/// explicitly: 18pt on three corners, 6pt on the top-right.
private struct UserBubbleShape: Shape {
    private let largeRadius: CGFloat = 18
    private let smallRadius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = largeRadius
        let tr = smallRadius
        // Clamp radii so a very short bubble (empty content) can't
        // produce an inverted arc.
        let maxR = min(rect.width, rect.height) / 2
        let big = min(r, maxR)
        let small = min(tr, maxR)

        // Start after the top-left corner, walk clockwise.
        path.move(to: CGPoint(x: rect.minX + big, y: rect.minY))
        // Top edge → top-right (small radius).
        path.addLine(to: CGPoint(x: rect.maxX - small, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - small, y: rect.minY + small),
            radius: small, startAngle: .degrees(-90), endAngle: .degrees(0),
            clockwise: false
        )
        // Right edge → bottom-right (large radius).
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - big))
        path.addArc(
            center: CGPoint(x: rect.maxX - big, y: rect.maxY - big),
            radius: big, startAngle: .degrees(0), endAngle: .degrees(90),
            clockwise: false
        )
        // Bottom edge → bottom-left (large radius).
        path.addLine(to: CGPoint(x: rect.minX + big, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + big, y: rect.maxY - big),
            radius: big, startAngle: .degrees(90), endAngle: .degrees(180),
            clockwise: false
        )
        // Left edge → top-left (large radius).
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + big))
        path.addArc(
            center: CGPoint(x: rect.minX + big, y: rect.minY + big),
            radius: big, startAngle: .degrees(180), endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
#endif
