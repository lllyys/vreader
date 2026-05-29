// Purpose: Builds table of contents entries for a given book format.
// Extracted from ReaderContainerView to reduce file size (pure refactor).
// Static methods - no instance state.
//
// @coordinates-with ReaderContainerView.swift, TOCBuilder.swift, EPUBParser.swift,
//   TXTService.swift (TXT TOC derives from the reader's chapter index — bug #286)

import Foundation
import PDFKit
import os

/// Builds TOC entries for each supported book format.
/// All methods are static and run asynchronously.
enum ReaderTOCFactory {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "vreader",
        category: "TOC"
    )

    /// Builds table of contents entries for the given book format.
    static func buildTOC(
        format: String,
        fileURL: URL,
        fingerprint: DocumentFingerprint
    ) async -> [TOCEntry] {
        switch format {
        case "epub":
            let parser = EPUBParser()
            do {
                let metadata = try await parser.open(url: fileURL)
                await parser.close()
                return TOCBuilder.fromSpineItems(metadata.spineItems, fingerprint: fingerprint)
            } catch {
                await parser.close()
                return []
            }

        case "pdf":
            return await Task.detached {
                extractPDFOutline(from: fileURL, fingerprint: fingerprint)
            }.value

        case "txt":
            // Bug #286 / GH #30: derive TOC entries from the reader's full-text
            // chapter index — a single source of truth. `buildTXTTOCEntries`
            // decodes via `decodeForDisplayAndSearch` (the reader's decoder) and
            // runs `buildChapterIndexFromFullText` (the reader's chapter pass), so
            // every TOC entry offset lands exactly on a reader chapter start.
            // Pre-fix this path decoded via raw `String(data:encoding:)` with a
            // UTF-8-only fallback and a SECOND `detectBestRule` over the TOC's own
            // decoded string, so on non-UTF-8 files the offsets diverged from the
            // reader's chapters and TOC taps navigated to the wrong chapter.
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return [] }
            return TXTService.buildTXTTOCEntries(data: data, fingerprint: fingerprint)

        case "md":
            do {
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                return TOCBuilder.forMD(text: text, fingerprint: fingerprint)
            } catch {
                return []
            }

        default:
            return []
        }
    }

    /// Extracts outline entries from a PDF document.
    /// Nonisolated so it can run off-main-actor in Task.detached.
    nonisolated private static func extractPDFOutline(
        from url: URL,
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        guard let document = PDFDocument(url: url),
              let outline = document.outlineRoot else { return [] }
        var entries: [(title: String, level: Int, page: Int)] = []
        walkOutline(outline, document: document, level: 0, into: &entries)
        return TOCBuilder.fromPDFOutline(entries: entries, fingerprint: fingerprint)
    }

    nonisolated private static func walkOutline(
        _ node: PDFOutline,
        document: PDFDocument,
        level: Int,
        into entries: inout [(title: String, level: Int, page: Int)]
    ) {
        for i in 0..<node.numberOfChildren {
            guard let child = node.child(at: i) else { continue }
            if let label = child.label,
               let dest = child.destination,
               let page = dest.page {
                let pageIndex = document.index(for: page)
                entries.append((title: label, level: level, page: pageIndex))
            }
            walkOutline(child, document: document, level: level + 1, into: &entries)
        }
    }
}
