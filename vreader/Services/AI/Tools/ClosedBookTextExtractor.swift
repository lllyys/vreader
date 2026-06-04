// Purpose: Feature #91 WI-8b — extract a CLOSED book's full plain text from its
// on-device file, dispatching per format. This is the file-I/O half of the
// get_book_content production path (the BookContentProvider adapter): EPUB via the
// EPUBParser spine, TXT/MD via encoding-detected decode (matching the search/TTS
// path), PDF via PDFKit. A `Sendable` value type with no stored state — safe to
// call off the main actor.
//
// The supported set mirrors GetBookContentGate.supportedFormats; an unsupported
// format (native azw3) throws rather than returning empty — the WI-6c gate already
// rejects it before extractText is reached, so this throw is a defence-in-depth.
//
// @coordinates-with: BookContentProviderAdapter.swift (consumer), EPUBParser.swift
//   + EPUBTextExtractor.stripHTML, TXTService (encoding detect), BookFormat.swift,
//   LibraryBookItem.resolvedFileURL (the same sandbox-path convention),
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Foundation
import PDFKit

struct ClosedBookTextExtractor: Sendable {

    /// Extract a book's full plain text from its on-device file URL. Throws for an
    /// unreadable file or an unsupported format.
    func extract(url: URL, format: String) async throws -> String {
        switch format.lowercased() {
        case "epub": return try await Self.extractEPUB(url: url)
        case "txt", "md": return try Self.extractPlainText(url: url)
        case "pdf": return try Self.extractPDF(url: url)
        default:
            throw AIError.providerError("Text extraction is not supported for \(format) books.")
        }
    }

    // MARK: - Per-format

    static func extractEPUB(url: URL) async throws -> String {
        let parser = EPUBParser()
        let metadata = try await parser.open(url: url)
        var parts: [String] = []
        for item in metadata.spineItems {
            // Skip an inaccessible spine item — partial text beats none.
            guard let xhtml = try? await parser.contentForSpineItem(href: item.href) else { continue }
            let plain = EPUBTextExtractor.stripHTML(xhtml)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty { parts.append(plain) }
        }
        await parser.close()
        return parts.joined(separator: "\n\n")
    }

    /// TXT/MD — decode through the SAME canonical decoder the reader + search use
    /// (`TXTService.decodeForDisplayAndSearch`: UTF-16 BOM, NSString heuristics,
    /// GBK/Big5/Shift_JIS/EUC-KR, …) so a closed-book read decodes exactly what the
    /// reader opens (Gate-4 Medium — a partial copy mis-decoded non-UTF-8 books).
    /// UTF-8 is the last-resort fallback if the canonical decoder returns nil.
    static func extractPlainText(url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if let (decoded, _) = TXTService.decodeForDisplayAndSearch(data) {
            return decoded
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func extractPDF(url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw AIError.providerError("Couldn't open the PDF file.")
        }
        var pages: [String] = []
        for index in 0..<doc.pageCount {
            if let page = doc.page(at: index), let text = page.string {
                pages.append(text)
            }
        }
        return pages.joined(separator: "\n\n")
    }
}
