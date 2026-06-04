// Purpose: Feature #91 — shared text helpers for the agentic tool executors'
// `ToolResult.content`. Both search_current_book (WI-6a) and search_other_books
// (WI-6b) normalize book-controlled text (snippets, chapter titles) to one
// bounded line and byte-clamp the whole result so a pathological book can't blow
// the tool_result budget. Extracted from WI-6a so the two tools share one copy.
//
// @coordinates-with: SearchCurrentBookTool.swift, SearchOtherBooksTool.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6a/6b)

import Foundation

enum ToolResultText {

    /// Strip FTS5 `<b>…</b>` highlight markers, collapse all whitespace/newlines
    /// to single spaces, and cap the character length — so any book-controlled
    /// text (snippet or chapter title) renders as one bounded line.
    static func oneLine(_ text: String, maxChars: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard collapsed.count > maxChars else { return collapsed }
        return String(collapsed.prefix(maxChars)) + "…"
    }

    /// Truncate to a UTF-8 byte budget on a Character boundary, appending a marker
    /// when truncated (so the model knows the result was cut).
    static func clamp(_ string: String, toBytes maxBytes: Int) -> String {
        guard string.utf8.count > maxBytes else { return string }
        let suffix = "\n…(truncated)"
        let budget = max(0, maxBytes - suffix.utf8.count)
        var out = ""
        var used = 0
        for ch in string {
            let n = String(ch).utf8.count
            if used + n > budget { break }
            out.append(ch)
            used += n
        }
        return out + suffix
    }
}
