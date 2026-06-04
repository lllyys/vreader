// Purpose: Feature #91 WI-6c — the locality + format SAFETY GATE for
// get_book_content, plus the provider seam the tool depends on. A closed book's
// text can be extracted ONLY when the file is on-device (BookFileState.local) AND
// the format has a closed-book text path. This is the Gate-2-flagged coverage
// risk: native AZW3/MOBI has NO closed-book text extractor, and a remote-only /
// failed row has no local file — both must yield an explicit error result the
// model can route around, never a throw and never a silent empty read.
//
// Supported closed-book formats: EPUB, TXT, Markdown, PDF. NOT azw3 (the canonical
// Kindle format, which subsumes azw/mobi/prc) — feature #42 converts NEW Kindle
// imports to EPUB by default, so only legacy-native `.azw3` rows hit this.
//
// The gate is a PURE function of (isReadable, format) → exhaustively testable.
// Title resolution is AMBIGUITY-AWARE (Gate-4 High): the model only ever sees
// titles, and two books can share one, so the provider returns notFound / found /
// ambiguous rather than silently picking one. The canonical format is DERIVED from
// the fingerprint key (Gate-4 High), so it is structurally immune to the stale
// `book.format` column drift (the Bug #246 class — the WI-6b lesson) — a caller
// cannot supply a drifted format.
//
// @coordinates-with: GetBookContentTool.swift (consumer), BookFileState.swift
//   (.local locality), BookFormat.swift / DocumentFingerprint.swift (the canonical
//   format), PersistenceActor / EPUBTextExtractor (the WI-8 adapter),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6c)

import Foundation

/// Whether a resolved book's text can be extracted, or why not.
enum BookContentEligibility: Sendable, Equatable {
    case extractable
    /// The file is not on-device (BookFileState != .local) — remote-only,
    /// downloading, failed, or missing.
    case notLocal
    /// No closed-book text path for this format (native azw3/mobi/prc).
    case unsupportedFormat
}

/// A resolved book. `format` is DERIVED from `fingerprintKey` — a caller cannot
/// supply a drifted `book.format` (Gate-4 High; the Bug #246 class). `format` is
/// nil only when the fingerprint key is malformed (should never happen for a real
/// library row).
struct BookContentInfo: Sendable, Equatable {
    let fingerprintKey: String
    let title: String
    let isReadable: Bool   // BookFileState == .local

    init(fingerprintKey: String, title: String, isReadable: Bool) {
        self.fingerprintKey = fingerprintKey
        self.title = title
        self.isReadable = isReadable
    }

    /// Canonical format (rawValue), parsed from the fingerprint key — never the
    /// stale `book.format` column.
    var format: String? { DocumentFingerprint(canonicalKey: fingerprintKey)?.format.rawValue }
}

/// One candidate when a title matches more than one book — enough metadata
/// (author) for the model to disambiguate with the user.
struct BookContentMatch: Sendable, Equatable {
    let title: String
    let author: String?
}

/// The outcome of resolving a model-supplied title.
enum BookTitleResolution: Sendable, Equatable {
    case notFound
    case found(BookContentInfo)
    /// More than one library book matches the title.
    case ambiguous([BookContentMatch])
}

/// The book-content backend get_book_content depends on: resolve a book by title
/// (ambiguity-aware) and extract its closed-book text. The production adapter
/// (WI-8) wraps `PersistenceActor` (title lookup + locality) + the per-format text
/// extractors via the closed-book reopen path; tests use a stub.
protocol BookContentProvider: Sendable {
    func findBook(title: String) async -> BookTitleResolution
    /// Extract the book's text from its on-device file. Throws on a read failure
    /// (the tool turns that into an `isError` result).
    func extractText(fingerprintKey: String) async throws -> String
}

/// The pure locality + format safety gate (the WI-6c risk core).
enum GetBookContentGate {

    /// Formats with a closed-book text path. azw3 (native Kindle) is excluded.
    static let supportedFormats: Set<String> = ["epub", "txt", "md", "pdf"]

    static func isSupportedFormat(_ format: String) -> Bool {
        supportedFormats.contains(format)
    }

    /// Decide whether a resolved book's text is extractable. Locality is checked
    /// FIRST: a remote azw3 reports `notLocal` (you can't read the file at all)
    /// rather than `unsupportedFormat`.
    static func evaluate(isReadable: Bool, format: String) -> BookContentEligibility {
        guard isReadable else { return .notLocal }
        guard isSupportedFormat(format) else { return .unsupportedFormat }
        return .extractable
    }
}
