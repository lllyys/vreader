// Purpose: Feature #91 WI-6b — the `search_other_books` agentic tool: full-text
// search the user's WHOLE LIBRARY (excluding the open book, which
// search_current_book covers) across books that are SAFELY searchable from their
// persisted index. The persistent-index risk is isolated in the pure
// `LibraryBookSearchGate`; this file is orchestration + formatting only.
//
// Contract (read-only, never throws — AITool):
// - List the library, drop the open book, gate each remaining book.
// - For each searchable book (up to a cap): restore TXT/MD offsets if needed,
//   FTS-search it, collect the top snippets.
// - Report EXCLUDED books by count (not-indexed / needs-reindex / stale) so the
//   model knows coverage is partial and never receives a mis-resolved result.
// - NO on-demand (re)indexing (expensive). A per-book search failure is skipped,
//   not fatal. Missing query / a library-list failure → an isError result.
//
// @coordinates-with: LibraryBookSearchGate.swift (the gate + backend seam),
//   ToolResultText.swift (one-line + byte-clamp), AITool.swift (DTOs),
//   AIToolRegistry.swift (dispatch),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6b)

import Foundation
import OSLog

/// `search_other_books` — full-text search the rest of the library's
/// safely-indexed books and return matching snippets grouped by book.
struct SearchOtherBooksTool: AITool {

    static let toolName = "search_other_books"
    private static let log = Logger(subsystem: "com.vreader.app", category: "SearchOtherBooksTool")

    private let backend: any LibrarySearchBackend
    /// The currently-open book's fingerprint key, excluded from the search
    /// (search_current_book owns it). nil when no book is open.
    private let currentBookFingerprintKey: String?
    private let maxBooks: Int          // cap on books actually searched
    private let perBookResults: Int    // cap on snippets per book
    private let maxContentBytes: Int

    init(
        backend: any LibrarySearchBackend,
        currentBookFingerprintKey: String?,
        maxBooks: Int = 10,
        perBookResults: Int = 3,
        maxContentBytes: Int = 8_000
    ) {
        self.backend = backend
        self.currentBookFingerprintKey = currentBookFingerprintKey
        self.maxBooks = max(1, maxBooks)
        self.perBookResults = max(1, perBookResults)
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: """
                Full-text search the user's OTHER books (the whole library except \
                the one currently open). Returns matching snippets grouped by book \
                title, so you can find where something appears across the library. \
                Only books that have been indexed are searched; un-indexed books \
                are reported as a count.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Words or a short phrase to find across the other books."),
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
        let displayQuery = ToolResultText.oneLine(query, maxChars: 120)

        let books: [LibraryBookItem]
        do {
            books = try await backend.libraryBooks()
        } catch {
            Self.log.error(
                "search_other_books: library list failed: \(String(describing: error), privacy: .public)")
            return errorResult("Couldn't list the library to search.")
        }

        // Drop the open book; gate each remaining book on its persisted index.
        let others = books.filter { $0.fingerprintKey != currentBookFingerprintKey }
        var excludedCount = 0
        var eligible: [(book: LibraryBookItem, fingerprint: DocumentFingerprint, restore: [Int: Int]?)] = []
        for book in others {
            guard let fingerprint = DocumentFingerprint(canonicalKey: book.fingerprintKey) else {
                excludedCount += 1   // malformed key — treat as not searchable
                continue
            }
            let state = await backend.indexState(fingerprintKey: book.fingerprintKey)
            // Gate-4 High: gate on the CANONICAL format parsed from the
            // fingerprint key, NOT `book.format` (a stale-prone parallel column —
            // the Bug #246 class). A drifted row must not be mis-gated (a real
            // TXT/MD included without offset restore → dropped results, or a real
            // EPUB/PDF wrongly excluded as staleOffsets).
            switch LibraryBookSearchGate.evaluate(format: fingerprint.format.rawValue, state: state) {
            case .searchable(let restore):
                eligible.append((book, fingerprint, restore))
            case .excluded:
                excludedCount += 1
            }
        }

        // Search up to maxBooks eligible books (report the rest as capped).
        let toSearch = eligible.prefix(maxBooks)
        let cappedOut = eligible.count - toSearch.count
        var hitsByBook: [(title: String, snippets: [String])] = []
        var searchFailures = 0
        for entry in toSearch {
            if let offsets = entry.restore {
                await backend.restoreSegmentOffsets(fingerprint: entry.fingerprint, offsets: offsets)
            }
            do {
                let page = try await backend.search(
                    query: query, fingerprint: entry.fingerprint, limit: perBookResults)
                let snippets = page.results.prefix(perBookResults).map {
                    ToolResultText.oneLine($0.snippet, maxChars: 300)
                }
                if !snippets.isEmpty {
                    hitsByBook.append((entry.book.title, Array(snippets)))
                }
            } catch {
                Self.log.error(
                    "search_other_books: per-book search failed: \(String(describing: error), privacy: .public)")
                searchFailures += 1   // one book failing must not fail the whole tool…
                continue              // …but it must NOT be counted as searched (Gate-4 r2 Medium)
            }
        }

        return ToolResult(
            toolUseID: "",
            content: format(
                displayQuery: displayQuery, hitsByBook: hitsByBook,
                attemptedCount: toSearch.count, failedCount: searchFailures,
                excludedCount: excludedCount, cappedOut: cappedOut),
            isError: false)
    }

    /// An `isError` result whose content is byte-clamped like the success path.
    private func errorResult(_ message: String) -> ToolResult {
        ToolResult(
            toolUseID: "", content: ToolResultText.clamp(message, toBytes: maxContentBytes), isError: true)
    }

    // MARK: - Formatting

    private func format(
        displayQuery: String, hitsByBook: [(title: String, snippets: [String])],
        attemptedCount: Int, failedCount: Int, excludedCount: Int, cappedOut: Int
    ) -> String {
        // Coverage footer FIRST — it's the partial-coverage signal the model needs,
        // so it must NEVER be the part that truncation drops (Gate-4 r3 Medium: it
        // was appended last and byte-clamped away when the hit set was large).
        var coverage: [String] = []
        if excludedCount > 0 {
            // Gate-4 Low: excludedCount spans not-indexed, needs-reindex,
            // stale-offsets, AND malformed fingerprint keys — keep the label
            // accurate rather than understating it as "not indexed" only.
            coverage.append(
                "\(excludedCount) book(s) not searched (not indexed, need re-indexing, or unreadable metadata)")
        }
        if failedCount > 0 {
            coverage.append("\(failedCount) book(s) failed to search")
        }
        if cappedOut > 0 {
            coverage.append("\(cappedOut) more indexed book(s) not searched (result cap)")
        }
        let footer = coverage.isEmpty ? "" : "(" + coverage.joined(separator: "; ") + ".)"

        // A book whose search THREW was attempted but NOT completed — don't let it
        // inflate the "searched N books" coverage claim (Gate-4 r2 Medium).
        let completedCount = attemptedCount - failedCount
        var lines: [String] = []
        if hitsByBook.isEmpty {
            if completedCount > 0 {
                lines.append(
                    "No matches for \"\(displayQuery)\" in \(completedCount) other indexed book(s).")
            } else if failedCount > 0 {
                lines.append(
                    "Couldn't search \(failedCount) indexed book(s) — the search failed.")
            } else {
                lines.append(
                    "No other indexed books to search for \"\(displayQuery)\".")
            }
        } else {
            let total = hitsByBook.reduce(0) { $0 + $1.snippets.count }
            lines.append(
                "Found \(total) match(es) for \"\(displayQuery)\" across \(hitsByBook.count) other book(s):")
            for (book, snippets) in hitsByBook {
                lines.append("• \(ToolResultText.oneLine(book, maxChars: 80)):")
                for (i, snippet) in snippets.enumerated() {
                    lines.append("    \(i + 1). \(snippet)")
                }
            }
        }
        let body = lines.joined(separator: "\n")

        // Reserve the footer's bytes so it always survives: clamp only the BODY to
        // the remaining budget, then append the (unclamped) footer.
        guard !footer.isEmpty else { return ToolResultText.clamp(body, toBytes: maxContentBytes) }
        let bodyBudget = max(0, maxContentBytes - (footer.utf8.count + 1))  // +1 for the "\n"
        return ToolResultText.clamp(body, toBytes: bodyBudget) + "\n" + footer
    }
}
