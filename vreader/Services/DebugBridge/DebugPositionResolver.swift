// Purpose: Pure value-type parser that turns the `?position=<value>` URL
// parameter from `vreader-debug://open` into a typed `DebugPosition` per
// book format. Native-mode-only — unified-renderer mode is rejected at the
// call site (RealDebugBridgeContext.open).
//
// DEBUG-only. No OS dependencies, no actor isolation; safe to call from
// any context.
//
// @coordinates-with: DebugCommand.swift (URL grammar),
//   RealDebugBridgeContext.swift (consumer),
//   dev-docs/plans/20260503-feature-48-debugbridge-probe-completion.md (#49 WI-7)

#if DEBUG

import Foundation

/// Typed position payload after parsing the per-format `position` string.
/// The bridge converts this to a `Locator` (`locator(bookFingerprint:)`) and
/// drives the active reader via the production `.readerNavigateToLocator`
/// path (Bug #257) — no parallel seek implementation.
enum DebugPosition: Equatable, Sendable {
    /// TXT / MD: 0-based UTF-16 character offset within the document.
    case charOffsetUTF16(Int)
    /// EPUB: opaque CFI string (validated only for non-emptiness here;
    /// real CFI parsing happens inside the EPUB bridge).
    case epubCFI(String)
    /// AZW3: opaque CFI-like string handed to Foliate-js.
    case foliateCFI(String)
    /// PDF: 1-based page number.
    case pdfPage(Int)

    /// Bug #257: convert this typed position into a `Locator` so the bridge
    /// can drive the reader through the same `.readerNavigateToLocator`
    /// notification that TOC / search / restore use — there is no separate
    /// DEBUG-only seek path. Returns nil only when `Locator.validated`
    /// rejects the fields (e.g. a negative offset that slipped past the
    /// resolver's own guards), so callers fail loudly rather than navigating
    /// to a malformed locator.
    ///
    /// Per-format mapping:
    /// - `.charOffsetUTF16(n)` → `Locator.charOffsetUTF16 = n` (TXT / MD).
    /// - `.pdfPage(n)` → `Locator.page = n - 1` (the URL value is 1-based;
    ///   `Locator.page` is the 0-based PDFKit page index the PDF reader's
    ///   navigate handler feeds straight into `pageDidChange`).
    /// - `.epubCFI(s)` / `.foliateCFI(s)` → `Locator.cfi = s`.
    func locator(bookFingerprint: DocumentFingerprint) -> Locator? {
        switch self {
        case .charOffsetUTF16(let offset):
            return Locator.validated(
                bookFingerprint: bookFingerprint,
                charOffsetUTF16: offset
            )
        case .pdfPage(let page):
            // URL value is 1-based; Locator.page is the 0-based PDFKit index.
            return Locator.validated(
                bookFingerprint: bookFingerprint,
                page: max(0, page - 1)
            )
        case .epubCFI(let cfi), .foliateCFI(let cfi):
            return Locator.validated(
                bookFingerprint: bookFingerprint,
                cfi: cfi
            )
        }
    }
}

/// Errors thrown by `DebugPositionResolver.resolve(_:format:)`.
enum DebugPositionResolverError: Error, Equatable {
    /// Format string didn't match any supported `BookFormat` raw value.
    case unknownFormat(String)
    /// Position string didn't match the format's expected shape.
    case invalidPositionForFormat(format: String, position: String, reason: String)
    /// Format is recognized but `position` not yet supported (e.g., MD same
    /// as TXT — handled by mapping).
    case formatUnsupported(format: String)
}

/// Pure parser. Stateless; tests construct it directly.
enum DebugPositionResolver {

    /// Resolve a `position` string against a book format.
    /// - Parameters:
    ///   - position: Raw URL-decoded string from the `?position=` param.
    ///   - format: BookFormat raw value ("txt", "md", "epub", "azw3", "pdf").
    /// - Returns: Typed `DebugPosition`.
    /// - Throws: `DebugPositionResolverError` on shape mismatch.
    static func resolve(_ position: String, format: String) throws -> DebugPosition {
        guard let bookFormat = BookFormat(rawValue: format.lowercased()) else {
            throw DebugPositionResolverError.unknownFormat(format)
        }
        switch bookFormat {
        case .txt, .md:
            // Both formats use UTF-16 character offsets. Accept positive
            // integers (and zero) only — negative offsets are invalid.
            guard let offset = Int(position), offset >= 0 else {
                throw DebugPositionResolverError.invalidPositionForFormat(
                    format: format,
                    position: position,
                    reason: "Expected non-negative UTF-16 character offset (e.g. \"42\")."
                )
            }
            return .charOffsetUTF16(offset)
        case .epub:
            // EPUB CFI strings start with "epubcfi(" or are the simpler
            // "href#fragment" form. We don't validate the full CFI grammar
            // here — the EPUB bridge does that — just reject empty input.
            guard !position.isEmpty else {
                throw DebugPositionResolverError.invalidPositionForFormat(
                    format: format,
                    position: position,
                    reason: "EPUB position must not be empty."
                )
            }
            return .epubCFI(position)
        case .azw3:
            // AZW3 → Foliate-js CFI. Same shape rejection as EPUB.
            guard !position.isEmpty else {
                throw DebugPositionResolverError.invalidPositionForFormat(
                    format: format,
                    position: position,
                    reason: "AZW3 position must not be empty."
                )
            }
            return .foliateCFI(position)
        case .pdf:
            // PDF page numbers are 1-based.
            guard let page = Int(position), page >= 1 else {
                throw DebugPositionResolverError.invalidPositionForFormat(
                    format: format,
                    position: position,
                    reason: "Expected 1-based page number (e.g. \"3\")."
                )
            }
            return .pdfPage(page)
        }
    }
}

#endif
