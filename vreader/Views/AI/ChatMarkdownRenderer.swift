// Purpose: Bug #335 — render an AI chat message's raw LLM string as a formatted
// `AttributedString` so markdown markup (`**bold**`, `*em*`, `` `code` ``,
// `[text](url)`, `-` lists) renders as formatting instead of literal characters.
//
// Why this exists: SwiftUI's `Text(_:)` parses markdown ONLY for string literals
// / `LocalizedStringKey`. `ChatMessage.content` is a `String` variable, so
// `Text(message.content)` rendered the markup verbatim (the bug: `**笔记：**`,
// `**[copyright]**` shown literally).
//
// Key decisions:
// - **`.inlineOnlyPreservingWhitespace`**: parses inline emphasis/code/links AND
//   keeps newlines + runs of whitespace, so `-` list items and blank-line
//   paragraphs keep their line structure (the design clamps the bubble to 3
//   lines, so structure must survive). Full block grammar (`<ul>`, headings)
//   isn't laid out by a single `Text`, but the literal-markup bug — the actual
//   complaint — is fixed, and line structure is preserved.
// - **`.returnPartiallyParsedIfPossible`**: a half-open `**` from mid-stream
//   coalesced deltas (#323) degrades gracefully instead of throwing.
// - Pure + `nonisolated static` so it unit-tests without a render pass and can be
//   called from the `@MainActor` row body.
//
// @coordinates-with: AIChatMessageRow.swift, ChatMessage.swift

import Foundation

enum ChatMarkdownRenderer {

    /// Converts a raw chat-message string into a formatted `AttributedString`.
    /// Inline markdown (bold/italic/code/links) renders as formatting; newlines
    /// and whitespace are preserved. Falls back to plain text if parsing fails.
    nonisolated static func attributedString(from raw: String) -> AttributedString {
        guard !raw.isEmpty else { return AttributedString("") }
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: raw, options: options) {
            return parsed
        }
        return AttributedString(raw)
    }
}
