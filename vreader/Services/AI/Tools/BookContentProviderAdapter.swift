// Purpose: Feature #91 WI-8b — the production BookContentProvider the
// get_book_content tool (WI-6c) depends on. Resolves a model-supplied TITLE to a
// library book via `LibraryPersisting.fetchAllLibraryBooks()` (ambiguity-aware:
// notFound / found / ambiguous-with-author), and extracts a resolved book's text
// off-actor via `ClosedBookTextExtractor`. The locality + format SAFETY decisions
// stay in the pure `GetBookContentGate` (the tool calls it on this adapter's
// `BookContentInfo`); this adapter is pure resolution + extraction glue.
//
// `BookContentInfo.format` is DERIVED from the fingerprint key (the WI-6c
// drift-proof contract), so this adapter only supplies fingerprintKey/title/
// isReadable — never a stale `book.format` column.
//
// @coordinates-with: GetBookContentGate.swift (BookContentProvider seam),
//   GetBookContentTool.swift (consumer), ClosedBookTextExtractor.swift,
//   LibraryPersisting.swift (fetchAllLibraryBooks), DocumentFingerprint.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Foundation

struct BookContentProviderAdapter: BookContentProvider {

    private let library: any LibraryPersisting
    private let extractor: ClosedBookTextExtractor

    init(library: any LibraryPersisting, extractor: ClosedBookTextExtractor = ClosedBookTextExtractor()) {
        self.library = library
        self.extractor = extractor
    }

    /// Resolve a book by case-insensitive exact title. 0 matches → notFound; 1 →
    /// found; 2+ → ambiguous (with author so the model can disambiguate).
    func findBook(title: String) async -> BookTitleResolution {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return .notFound }

        let books = (try? await library.fetchAllLibraryBooks()) ?? []
        let matches = books.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == query
        }
        switch matches.count {
        case 0:
            return .notFound
        case 1:
            let book = matches[0]
            return .found(BookContentInfo(
                fingerprintKey: book.fingerprintKey,
                title: book.title,
                isReadable: book.isReadable))   // BookFileState == .local
        default:
            return .ambiguous(matches.map { BookContentMatch(title: $0.title, author: $0.author) })
        }
    }

    /// Extract the book's text from its on-device file. The format is the CANONICAL
    /// format parsed from the fingerprint key (never a stale column); a malformed
    /// key throws (the tool turns that into an isError result).
    func extractText(fingerprintKey: String) async throws -> String {
        guard let fingerprint = DocumentFingerprint(canonicalKey: fingerprintKey) else {
            throw AIError.providerError("Unreadable book metadata.")
        }
        let format = fingerprint.format.rawValue
        // resolveExisting tries the format's candidate extensions (.txt/.text,
        // .md/.markdown) so a restore/lazy-download book materialized under its
        // ORIGINAL extension is still found (Gate-4 r2 Medium).
        let url = ImportedBookFileURL.resolveExisting(fingerprintKey: fingerprintKey, format: format)
        return try await extractor.extract(url: url, format: format)
    }
}
