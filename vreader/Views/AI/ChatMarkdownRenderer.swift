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
//   keeps newlines + runs of whitespace, so paragraph structure survives (the
//   design clamps the bubble to 3 lines). It does NOT lay out block lists, so
//   unordered-list markers (`- ` / `* ` / `+ `) are pre-normalised to a `• `
//   bullet (Gate-4 Medium) — they then read as bullets instead of literal
//   hyphens within the single `Text`.
// - **`.returnPartiallyParsedIfPossible`**: a half-open `**` from mid-stream
//   coalesced deltas (#323) degrades gracefully instead of throwing.
// - **Link safety (Gate-4 Medium / security)**: markdown `[text](url)` from
//   attacker-influenced LLM output could embed arbitrary URL schemes
//   (`tel:`, custom app/deep-link schemes, `javascript:`). After parsing, every
//   link whose scheme is NOT in a small safe allowlist (`http`/`https`/`mailto`)
//   is stripped — the text stays, the live link does not — closing the
//   phishing / deep-link surface in this selectable surface.
// - Pure + `nonisolated static` so it unit-tests without a render pass and can be
//   called from the `@MainActor` row body. (Gate-4 Low — the per-render reparse
//   is accepted: #323 coalesces streaming to ~one flush per 96 chars and chat /
//   summary messages are short, so the O(n) reparse is not a hot path.)
//
// @coordinates-with: AIChatMessageRow.swift, AISummaryCard+Bilingual.swift,
//   ChatMessage.swift

import Foundation

enum ChatMarkdownRenderer {

    /// URL schemes a rendered chat/summary link may keep. Everything else is
    /// stripped to its plain text.
    private static let safeLinkSchemes: Set<String> = ["http", "https", "mailto"]

    /// Converts a raw chat-message string into a formatted `AttributedString`.
    /// Inline markdown (bold/italic/code/safe links) renders as formatting;
    /// unordered-list markers become bullets; newlines/whitespace are preserved.
    /// Falls back to plain text if parsing fails.
    nonisolated static func attributedString(from raw: String) -> AttributedString {
        guard !raw.isEmpty else { return AttributedString("") }
        let normalised = normaliseListMarkers(raw)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var parsed = try? AttributedString(markdown: normalised, options: options) else {
            return AttributedString(normalised)
        }
        stripUnsafeLinks(&parsed)
        return parsed
    }

    /// Replaces a leading unordered-list marker (`-`, `*`, or `+` followed by a
    /// space) on each line with a `• ` bullet, preserving any indentation. Inline
    /// parsing doesn't lay out lists, so without this the markers render as
    /// literal hyphens (Gate-4 Medium).
    private nonisolated static func normaliseListMarkers(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let s = String(line)
            guard let range = s.range(of: #"^(\s*)[-*+]\s+"#, options: .regularExpression) else {
                return s
            }
            let indent = s[s.startIndex..<range.lowerBound] + s[range].prefix { $0 == " " || $0 == "\t" }
            return "\(indent)• \(s[range.upperBound...])"
        }.joined(separator: "\n")
    }

    /// Removes the `.link` attribute from any run whose URL scheme is not in
    /// `safeLinkSchemes`, leaving the visible text intact (Gate-4 Medium / sec).
    private nonisolated static func stripUnsafeLinks(_ string: inout AttributedString) {
        for run in string.runs where run.link != nil {
            let scheme = run.link?.scheme?.lowercased()
            if scheme == nil || !safeLinkSchemes.contains(scheme!) {
                string[run.range].link = nil
            }
        }
    }
}
