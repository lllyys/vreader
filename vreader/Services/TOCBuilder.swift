// Purpose: Format-specific TOC construction helpers.
// Builds flat TOCEntry lists from format-specific sources.
//
// Key decisions:
// - EPUB: builds from EPUBSpineItem titles (skips untitled items).
// - PDF: placeholder for outline tree traversal (not yet wired).
// - TXT/MD: always empty (no inherent TOC structure).
//
// @coordinates-with: TOCProvider.swift, EPUBTypes.swift, LocatorFactory.swift

import Foundation

/// Namespace for format-specific TOC construction.
enum TOCBuilder {

    // MARK: - EPUB

    /// Builds TOC entries from EPUB spine items.
    /// Spine items without titles are excluded.
    static func fromSpineItems(
        _ items: [EPUBSpineItem],
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        items.enumerated().compactMap { index, item in
            guard let rawTitle = item.title,
                  !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            let locator = LocatorFactory.epub(
                fingerprint: fingerprint,
                href: item.href,
                progression: 0.0
            )

            guard let locator else { return nil }

            return TOCEntry(
                title: title,
                level: 0,
                locator: locator,
                sequenceIndex: index
            )
        }
    }

    // MARK: - PDF

    /// Builds TOC entries from PDF outline entries.
    /// Each entry provides a title, nesting level, and page index.
    static func fromPDFOutline(
        entries: [(title: String, level: Int, page: Int)],
        fingerprint: DocumentFingerprint
    ) -> [TOCEntry] {
        entries.enumerated().compactMap { index, entry in
            let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return nil }

            let locator = LocatorFactory.pdf(
                fingerprint: fingerprint,
                page: entry.page
            )

            guard let locator else { return nil }

            return TOCEntry(
                title: trimmedTitle,
                level: entry.level,
                locator: locator,
                sequenceIndex: index
            )
        }
    }

    // MARK: - TXT

    /// TXT files have no inherent table of contents.
    static func forTXT() -> [TOCEntry] {
        []
    }

    // MARK: - MD

    /// MD heading extraction is deferred to a future version.
    static func forMD() -> [TOCEntry] {
        []
    }
}
