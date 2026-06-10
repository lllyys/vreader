// Purpose: Feature #97 — the `list_library` agentic tool: enumerate the user's
// library (titles / authors / format) so the AI chat can answer "what books are
// in my library?" — a LIST query with no search phrase, which `search_other_books`
// (requires a query) and `get_book_content` (a named book) can't serve.
//
// Contract (read-only, never throws — AITool):
// - List the library via the shared `LibrarySearchBackend.libraryBooks()` (same
//   seam `search_other_books` uses — no new dependency).
// - Dedupe by `fingerprintKey`; optionally exclude the open book.
// - Sort with TOTAL, deterministic tie-breakers (the source is unsorted).
// - Cap the list (never dump a 500-title library into the prompt) and ANNOUNCE the
//   partial count (rule 49 — no silent caps). Byte-clamp the payload.
// - A library-list failure → an `isError` result (recoverable DATA, never throws).
//
// Format/title hardening (Gate-2 audit): the displayed FORMAT is derived from the
// CANONICAL fingerprint (Bug #246 class — `item.format` is a stale-prone parallel
// column); a legacy `restore_<sha256>` placeholder title (bug #247, now rare since
// restore passes a `titleOverride`) renders "(pending restore)" so the model never
// surfaces an internal id.
//
// @coordinates-with: LibraryBookSearchGate.swift (the backend seam),
//   ToolResultText.swift (one-line + byte-clamp), AITool.swift (DTOs),
//   AgenticToolRegistryBuilder.swift (registration),
//   dev-docs/plans/20260610-feature-97-list-library-tool.md

import Foundation
import OSLog

/// `list_library` — enumerate the user's library books (titles/authors/format).
struct ListLibraryTool: AITool {

    static let toolName = "list_library"
    private static let log = Logger(subsystem: "com.vreader.app", category: "ListLibraryTool")
    /// A legacy restore-temp placeholder title: `restore_<sha256>` (64 hex). Bug
    /// #247 now passes a real `titleOverride`, so this is defensive cleanup of old
    /// rows — anchored + 64-hex so an ordinary title starting with "restore" is
    /// untouched.
    private static let restorePlaceholder = try! NSRegularExpression(
        pattern: "^restore_[0-9a-fA-F]{64}$")

    private let backend: any LibrarySearchBackend
    /// The open book's fingerprint key (excluded when `include_current_book=false`).
    private let currentBookFingerprintKey: String?
    private let maxBooks: Int          // hard cap — never dump the whole shelf
    private let maxContentBytes: Int

    init(
        backend: any LibrarySearchBackend,
        currentBookFingerprintKey: String?,
        maxBooks: Int = 100,
        maxContentBytes: Int = 8_000
    ) {
        self.backend = backend
        self.currentBookFingerprintKey = currentBookFingerprintKey
        self.maxBooks = max(1, maxBooks)
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: """
                List the books in the user's library (their bookshelf) — titles, \
                authors, and format. Use this for "what books do I have?" / "what's \
                in my library?" questions that have no search term. To search WITHIN \
                books use search_other_books; to read a specific book use \
                get_book_content.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "include_current_book": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to include the book currently open (default true)."),
                    ]),
                    "sort_by": .object([
                        "type": .string("string"),
                        "enum": .array([.string("title"), .string("author"), .string("recent")]),
                        "description": .string(
                            "Order: title (A–Z), author (A–Z), or recent (most recently read first). Default recent."),
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Max books to list (clamped to 1…100). Omit to list as many as fit."),
                    ]),
                ]),
            ]))
    }

    func run(_ input: JSONValue) async -> ToolResult {
        let includeCurrent = input["include_current_book"]?.boolValue ?? true
        let sortBy = SortBy(rawValue: input["sort_by"]?.stringValue ?? "") ?? .recent
        // Clamp a requested limit to 1…maxBooks — a non-positive limit must NOT
        // empty a non-empty library (Gate-2 Medium).
        let cap = min(max(1, input["limit"]?.intValue ?? maxBooks), maxBooks)

        let books: [LibraryBookItem]
        do {
            books = try await backend.libraryBooks()
        } catch {
            Self.log.error(
                "list_library: library list failed: \(String(describing: error), privacy: .public)")
            return ToolResult(
                toolUseID: "",
                content: ToolResultText.clamp("Couldn't list the library.", toBytes: maxContentBytes),
                isError: true)
        }

        // Dedupe by fingerprintKey (keep first), then optionally drop the open book.
        var seen = Set<String>()
        var deduped: [LibraryBookItem] = []
        for book in books where seen.insert(book.fingerprintKey).inserted {
            deduped.append(book)
        }
        let filtered = includeCurrent
            ? deduped
            : deduped.filter { $0.fingerprintKey != currentBookFingerprintKey }

        guard !filtered.isEmpty else {
            // Gate-4 Medium: distinguish a truly-empty library from one whose only
            // book is the open one (excluded) — the latter is NOT "no books".
            let message = deduped.isEmpty
                ? "The library has no books."
                : "No other books in the library (only the currently-open book)."
            return ToolResult(toolUseID: "", content: message, isError: false)
        }

        let sorted = sortBooks(filtered, by: sortBy)
        let shown = Array(sorted.prefix(cap))

        var lines: [String] = []
        lines.append(shown.count < sorted.count
            ? "Showing \(shown.count) of \(sorted.count) books in the library:"
            : "\(sorted.count) book\(sorted.count == 1 ? "" : "s") in the library:")
        for book in shown {
            lines.append("• " + line(for: book))
        }
        return ToolResult(
            toolUseID: "",
            content: ToolResultText.clamp(lines.joined(separator: "\n"), toBytes: maxContentBytes),
            isError: false)
    }

    // MARK: - Sort

    private enum SortBy: String {
        case title, author, recent
    }

    private func sortBooks(_ books: [LibraryBookItem], by sortBy: SortBy) -> [LibraryBookItem] {
        switch sortBy {
        case .title:
            return books.sorted { a, b in
                if a.title.localizedCaseInsensitiveCompare(b.title) != .orderedSame {
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
                return a.fingerprintKey < b.fingerprintKey
            }
        case .author:
            // nil author sorts last.
            let sentinel = "\u{10FFFF}"
            return books.sorted { a, b in
                let aa = a.author ?? sentinel, bb = b.author ?? sentinel
                if aa.localizedCaseInsensitiveCompare(bb) != .orderedSame {
                    return aa.localizedCaseInsensitiveCompare(bb) == .orderedAscending
                }
                if a.title.localizedCaseInsensitiveCompare(b.title) != .orderedSame {
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
                return a.fingerprintKey < b.fingerprintKey
            }
        case .recent:
            return books.sorted { a, b in
                let al = a.lastReadAt ?? .distantPast, bl = b.lastReadAt ?? .distantPast
                if al != bl { return al > bl }            // most recent first
                if a.addedAt != b.addedAt { return a.addedAt > b.addedAt }
                if a.title.localizedCaseInsensitiveCompare(b.title) != .orderedSame {
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
                return a.fingerprintKey < b.fingerprintKey
            }
        }
    }

    // MARK: - Formatting

    private func line(for book: LibraryBookItem) -> String {
        let title = ToolResultText.oneLine(displayTitle(book), maxChars: 120)
        var text = title
        if let author = book.author, !author.isEmpty {
            text += " — \(ToolResultText.oneLine(author, maxChars: 80))"
        }
        text += " · \(canonicalFormat(book).uppercased())"
        // Gate-4 Medium: guard against non-finite (`+.infinity` would TRAP in
        // `Int(_:)`, violating the never-crash AITool contract) and clamp a drifted
        // `> 1` fraction so it never renders "134%".
        if let progress = book.progressFraction, progress.isFinite, progress > 0 {
            let clamped = min(progress, 1)
            text += " · \(Int((clamped * 100).rounded()))%"
        }
        return text
    }

    /// A legacy `restore_<sha256>` placeholder renders friendly; an empty title is
    /// labeled; everything else passes through.
    private func displayTitle(_ book: LibraryBookItem) -> String {
        let title = book.title
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        if Self.restorePlaceholder.firstMatch(in: title, range: range) != nil {
            return "(pending restore)"
        }
        return title.isEmpty ? "(untitled)" : title
    }

    /// The CANONICAL format from the fingerprint key (Bug #246 class — never trust
    /// the stale-prone `item.format` column); fall back to `item.format` only when
    /// the key is malformed.
    private func canonicalFormat(_ book: LibraryBookItem) -> String {
        DocumentFingerprint(canonicalKey: book.fingerprintKey)?.format.rawValue ?? book.format
    }
}
