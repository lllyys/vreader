// Purpose: Feature #91 WI-6a — the first agentic tool executor. A thin, read-only
// wrapper over `SearchProviding.search` scoped to the book the user is currently
// reading (its fingerprint is already indexed in the live SearchService), so the
// model can full-text search the open book mid-conversation. `run` NEVER throws —
// a missing query or a search failure is an `isError` ToolResult the loop routes
// around (the AITool contract).
//
// Key decisions:
// - Always page 0, pageSize = maxResults: the model asks one focused question; it
//   doesn't paginate. The cap bounds both the search work and the tool_result size.
// - FTS5 `<b>…</b>` highlight markers are stripped (same as the search UI's
//   HighlightedSnippet) so the model sees clean prose, and the snippet is
//   whitespace-collapsed to one line.
// - The content is byte-clamped (UTF-8) so a pathological snippet set can't blow
//   the tool_result past a sane budget.
//
// @coordinates-with: AITool.swift (DTOs + protocol), AIToolRegistry.swift (dispatch),
//   SearchService.swift (SearchProviding), HighlightedSnippet.swift (marker strip),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6a)

import Foundation
import OSLog

/// `search_current_book` — full-text search the open book and return matching
/// snippets with their source context.
struct SearchCurrentBookTool: AITool {

    static let toolName = "search_current_book"
    private static let log = Logger(subsystem: "com.vreader.app", category: "SearchCurrentBookTool")

    private let search: any SearchProviding
    private let bookFingerprint: DocumentFingerprint
    private let maxResults: Int
    private let maxContentBytes: Int

    init(
        search: any SearchProviding,
        bookFingerprint: DocumentFingerprint,
        maxResults: Int = 8,
        maxContentBytes: Int = 6_000
    ) {
        self.search = search
        self.bookFingerprint = bookFingerprint
        self.maxResults = max(1, maxResults)
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: """
                Full-text search the book the user is currently reading. Returns the \
                matching snippets with their location (chapter / page / section) so \
                you can quote or cite where something appears. Use this to find a \
                passage, character, term, or quote inside the current book.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Words or a short phrase to find in the current book."),
                    ]),
                ]),
                "required": .array([.string("query")]),
            ]))
    }

    func run(_ input: JSONValue) async -> ToolResult {
        guard let query = input["query"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return errorResult(
                "Missing required 'query' — provide a non-empty string of words to search for.")
        }
        // The query is echoed back in the header / error text, so bound it to one
        // short line first — an oversized model-supplied query can't blow the
        // tool_result budget (every return path is clamped below).
        let displayQuery = ToolResultText.oneLine(query, maxChars: 120)
        do {
            let page = try await search.search(
                query: query, bookFingerprint: bookFingerprint, page: 0, pageSize: maxResults)
            return ToolResult(
                toolUseID: "",
                content: Self.format(
                    displayQuery: displayQuery, page: page,
                    maxResults: maxResults, maxBytes: maxContentBytes),
                isError: false)
        } catch {
            Self.log.error(
                "search_current_book failed: \(String(describing: error), privacy: .public)")
            return errorResult("Search failed for \"\(displayQuery)\". The book may not be indexed yet.")
        }
    }

    /// An `isError` result whose content is byte-clamped like the success path.
    private func errorResult(_ message: String) -> ToolResult {
        ToolResult(
            toolUseID: "", content: ToolResultText.clamp(message, toBytes: maxContentBytes), isError: true)
    }

    // MARK: - Formatting

    /// Render a result page as plain text for the model: a count header + one line
    /// per result `N. snippet — source`, byte-clamped on EVERY branch.
    static func format(displayQuery: String, page: SearchResultPage, maxResults: Int, maxBytes: Int) -> String {
        let shown = Array(page.results.prefix(maxResults))
        guard !shown.isEmpty else {
            return ToolResultText.clamp(
                "No matches for \"\(displayQuery)\" in the current book.", toBytes: maxBytes)
        }
        let count = page.totalEstimate ?? shown.count
        let countLabel = "\(count)\(page.hasMore ? "+" : "")"
        var lines = ["Found \(countLabel) match(es) for \"\(displayQuery)\" in the current book:"]
        for (i, result) in shown.enumerated() {
            // Both snippet AND sourceContext are book-controlled text — normalize
            // BOTH to one line, and put the source at line-end (em-dash separator,
            // no closing bracket a chapter title could spoof) so the one-line-per-
            // result contract holds regardless of book metadata.
            let snippet = ToolResultText.oneLine(result.snippet, maxChars: 400)
            let source = ToolResultText.oneLine(result.sourceContext, maxChars: 80)
            lines.append("\(i + 1). \(snippet) — \(source)")
        }
        return ToolResultText.clamp(lines.joined(separator: "\n"), toBytes: maxBytes)
    }
}
