// Purpose: Feature #91 WI-6c — the `get_book_content` agentic tool: fetch the text
// of a library book by title so the AI chat can read on-demand across the library.
// The locality + format risk is isolated in the pure `GetBookContentGate`; this
// file is orchestration + capping only.
//
// Contract (read-only, never throws — AITool):
// - Resolve the book by title; a no-match → an isError "not found" result.
// - Gate on locality + format: a remote-only book → "not downloaded"; a native
//   AZW3/MOBI → "unsupported format" — explicit isError results the model routes
//   around (never a throw, never a silent empty read).
// - Extract the text; a read failure → an isError result. Cap the returned text
//   to `max_chars` (optional, ceiling-bounded) and a hard UTF-8 byte budget.
//
// The model identifies the book by TITLE (what it sees from search_other_books /
// the user) — not the internal fingerprint key.
//
// @coordinates-with: GetBookContentGate.swift (the gate + provider seam),
//   ToolResultText.swift (byte-clamp), AITool.swift (DTOs),
//   AIToolRegistry.swift (dispatch),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6c)

import Foundation
import OSLog

/// `get_book_content` — fetch a library book's text by title (local, supported
/// formats only).
struct GetBookContentTool: AITool {

    static let toolName = "get_book_content"
    private static let log = Logger(subsystem: "com.vreader.app", category: "GetBookContentTool")

    private let provider: any BookContentProvider
    private let maxChars: Int          // hard ceiling on returned characters
    private let maxContentBytes: Int   // hard UTF-8 byte budget

    init(
        provider: any BookContentProvider,
        maxChars: Int = 8_000,
        maxContentBytes: Int = 16_000
    ) {
        self.provider = provider
        self.maxChars = max(1, maxChars)
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: """
                Fetch the text of one of the user's books by its title, so you can \
                read or quote its content. Only books stored on this device in a \
                supported format (EPUB, TXT, Markdown, PDF) can be read. Use the \
                exact title as it appears in the library or in a search result.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("The title of the book to fetch."),
                    ]),
                    "start_char": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Optional 0-based character offset to start from (to read a later section). Defaults to 0."),
                    ]),
                    "max_chars": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Optional cap on how many characters of text to return from start_char."),
                    ]),
                ]),
                "required": .array([.string("title")]),
            ]))
    }

    func run(_ input: JSONValue) async -> ToolResult {
        guard let title = input["title"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return errorResult("Missing required 'title' — name the book to fetch.")
        }
        let displayTitle = ToolResultText.oneLine(title, maxChars: 120)

        let info: BookContentInfo
        switch await provider.findBook(title: title) {
        case .notFound:
            return errorResult("No book titled \"\(displayTitle)\" is in the library.")
        case .ambiguous(let candidates):
            // Two+ books share the title — don't silently pick one (Gate-4 High).
            // Surface them (with author) so the model can disambiguate with the user.
            let list = candidates.prefix(5).map { candidate -> String in
                let t = ToolResultText.oneLine(candidate.title, maxChars: 80)
                return candidate.author.map { "\(t) by \(ToolResultText.oneLine($0, maxChars: 60))" } ?? t
            }.joined(separator: "; ")
            return errorResult(
                "Several books match \"\(displayTitle)\": \(list). Ask the user which one, or give a more specific title.")
        case .found(let resolved):
            info = resolved
        }

        // `format` is DERIVED from the fingerprint key (canonical, drift-proof). A
        // nil here means a malformed key — shouldn't happen for a real library row.
        guard let format = info.format else {
            return errorResult(
                "\"\(ToolResultText.oneLine(info.title, maxChars: 120))\" has unreadable metadata.")
        }

        switch GetBookContentGate.evaluate(isReadable: info.isReadable, format: format) {
        case .notLocal:
            return errorResult(
                "\"\(ToolResultText.oneLine(info.title, maxChars: 120))\" isn't downloaded to this device yet — its text can't be read until it's downloaded.")
        case .unsupportedFormat:
            return errorResult(
                "\"\(ToolResultText.oneLine(info.title, maxChars: 120))\" is a \(format.uppercased()) book; its text can't be extracted here (only EPUB, TXT, Markdown, and PDF are supported).")
        case .extractable:
            break
        }

        let text: String
        do {
            text = try await provider.extractText(fingerprintKey: info.fingerprintKey)
        } catch {
            Self.log.error(
                "get_book_content: extract failed: \(String(describing: error), privacy: .public)")
            return errorResult(
                "Couldn't read the text of \"\(ToolResultText.oneLine(info.title, maxChars: 120))\".")
        }

        let total = text.count
        if total == 0 {
            return ToolResult(
                toolUseID: "",
                content: ToolResultText.clamp(
                    "\"\(ToolResultText.oneLine(info.title, maxChars: 120))\" has no extractable text.",
                    toBytes: maxContentBytes),
                isError: false)
        }
        // Range: an optional 0-based start offset (to read later sections) — past
        // the end is an explicit out-of-range error result, not an empty read.
        let start = max(0, input["start_char"]?.intValue ?? 0)
        if start >= total {
            return errorResult(
                "\"\(ToolResultText.oneLine(info.title, maxChars: 120))\" has \(total) characters; start_char \(start) is past the end.")
        }
        // Cap: the smaller of the model's request and the hard ceiling, then a
        // hard UTF-8 byte budget on top (so a CJK book can't blow the budget).
        let requested = input["max_chars"]?.intValue
        let charBudget = min(maxChars, max(1, requested ?? maxChars))
        return ToolResult(
            toolUseID: "",
            content: formatContent(
                title: info.title, text: text, start: start, charBudget: charBudget, total: total),
            isError: false)
    }

    /// An `isError` result whose content is byte-clamped like the success path.
    private func errorResult(_ message: String) -> ToolResult {
        ToolResult(
            toolUseID: "", content: ToolResultText.clamp(message, toBytes: maxContentBytes), isError: true)
    }

    // MARK: - Formatting

    private func formatContent(
        title: String, text: String, start: Int, charBudget: Int, total: Int
    ) -> String {
        let window = String(text.dropFirst(start).prefix(charBudget))
        // Gate-4 r3 Medium: the header's reported END must reflect what is ACTUALLY
        // returned after the UTF-8 byte clamp — otherwise a CJK body clamped shorter
        // than `window` would advertise a too-large END and the model, paging with
        // start_char=END, would skip the clamped-off text. So clamp the SLICE first
        // (reserving the header's bytes + 1 for a possible "…"), THEN derive END.
        func header(end: Int) -> String {
            "Content of \"\(ToolResultText.oneLine(title, maxChars: 120))\" (characters \(start)–\(end) of \(total)):\n"
        }
        let headerBytes = header(end: start + window.count).utf8.count
        let sliceBudget = max(0, maxContentBytes - headerBytes - "…".utf8.count)
        let slice = ToolResultText.truncateToBytes(window, sliceBudget)
        let end = start + slice.count               // characters actually included
        let more = end < total                      // …text remains after this window
        // The recomputed header is ≤ the reserved header bytes (end ≤ window end),
        // so header + slice (+ "…") stays within maxContentBytes.
        return header(end: end) + slice + (more ? "…" : "")
    }
}
