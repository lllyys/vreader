// Purpose: Tests for TOCEntry and TOCProviding — structure, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("TOCEntry")
struct TOCEntryTests {

    @Test("TOCEntry initializes with correct values")
    func initCorrectValues() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 1000,
            format: .epub
        )
        let locator = LocatorFactory.epub(
            fingerprint: fp,
            href: "ch1.xhtml",
            progression: 0.0
        )!

        let entry = TOCEntry(title: "Chapter 1", level: 0, locator: locator)

        #expect(entry.title == "Chapter 1")
        #expect(entry.level == 0)
        #expect(entry.locator.href == "ch1.xhtml")
    }

    @Test("negative level is clamped to zero")
    func negativeLevelClamped() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 1000,
            format: .epub
        )
        let locator = LocatorFactory.epub(
            fingerprint: fp,
            href: "ch1.xhtml",
            progression: 0.0
        )!

        let entry = TOCEntry(title: "Test", level: -5, locator: locator)

        #expect(entry.level == 0)
    }

    @Test("TOCEntry is Equatable")
    func equatable() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 1000,
            format: .epub
        )
        let locator = LocatorFactory.epub(
            fingerprint: fp,
            href: "ch1.xhtml",
            progression: 0.0
        )!

        let a = TOCEntry(title: "Chapter 1", level: 0, locator: locator)
        let b = TOCEntry(title: "Chapter 1", level: 0, locator: locator)

        #expect(a == b)
    }

    @Test("TOCEntry id is stable across instances")
    func stableId() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 1000,
            format: .epub
        )
        let locator = LocatorFactory.epub(
            fingerprint: fp,
            href: "ch1.xhtml",
            progression: 0.0
        )!

        let a = TOCEntry(title: "Chapter 1", level: 0, locator: locator)
        let b = TOCEntry(title: "Chapter 1", level: 0, locator: locator)

        #expect(a.id == b.id)
    }

    @Test("EPUB TOC from spine items with titles")
    func epubTOCFromSpine() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 1000,
            format: .epub
        )
        let spineItems = [
            EPUBSpineItem(id: "1", href: "ch1.xhtml", title: "Chapter 1", index: 0),
            EPUBSpineItem(id: "2", href: "ch2.xhtml", title: nil, index: 1),
            EPUBSpineItem(id: "3", href: "ch3.xhtml", title: "Chapter 3", index: 2),
        ]

        let entries = TOCBuilder.fromSpineItems(spineItems, fingerprint: fp)

        // Only items with titles should be included
        #expect(entries.count == 2)
        #expect(entries[0].title == "Chapter 1")
        #expect(entries[1].title == "Chapter 3")
    }

    // MARK: - Bug #321 — un-nav'd spine items must not pollute the Contents list

    @Test("EPUBMetadata.withResolvedTitles nils un-nav'd items so the TOC reflects the nav doc only")
    func withResolvedTitles_dropsSectionNPlaceholders_whenNavDocExists() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 1000,
            format: .epub
        )
        // M=4 spine items, each with the synthetic "Section N" placeholder EPUBParser
        // assigns at OPF-parse time (navTitles empty there).
        let placeholderSpine = (1...4).map {
            EPUBSpineItem(id: "s\($0)", href: "ch\($0).xhtml", title: "Section \($0)", index: $0 - 1)
        }
        let metadata = EPUBMetadata(
            title: "The Half Second", author: nil, language: nil,
            readingDirection: .ltr, layout: .reflowable,
            spineItems: placeholderSpine, coverImageHref: nil
        )
        // N=2 nav-doc entries (ch1, ch3). ch2 + ch4 are un-nav'd spine items.
        let navTitles = ["ch1.xhtml": "Prologue", "ch3.xhtml": "Chapter Two"]

        let resolved = metadata.withResolvedTitles(navTitles)
        // Un-nav'd items are nil-titled (NOT left as "Section 2"/"Section 4").
        #expect(resolved.spineItems.map(\.title) == ["Prologue", nil, "Chapter Two", nil])

        // End-to-end: the Contents list has exactly the N nav entries — no
        // "Section N" pollution interleaved with the real chapters.
        let entries = TOCBuilder.fromSpineItems(resolved.spineItems, fingerprint: fp)
        #expect(entries.count == 2)
        #expect(entries.map(\.title) == ["Prologue", "Chapter Two"])
    }

    @Test("PDF TOC from outline entries")
    func pdfTOCFromOutline() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 2000,
            format: .pdf
        )
        let outlineEntries: [(title: String, level: Int, page: Int)] = [
            (title: "Chapter 1", level: 0, page: 0),
            (title: "Section 1.1", level: 1, page: 3),
            (title: "", level: 0, page: 5),
            (title: "Chapter 2", level: 0, page: 10),
        ]

        let entries = TOCBuilder.fromPDFOutline(entries: outlineEntries, fingerprint: fp)

        #expect(entries.count == 3)
        #expect(entries[0].title == "Chapter 1")
        #expect(entries[0].level == 0)
        #expect(entries[1].title == "Section 1.1")
        #expect(entries[1].level == 1)
        #expect(entries[2].title == "Chapter 2")
    }

    @Test("PDF TOC skips entries with empty titles")
    func pdfTOCSkipsEmptyTitles() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 2000,
            format: .pdf
        )
        let entries = TOCBuilder.fromPDFOutline(
            entries: [(title: "", level: 0, page: 0)],
            fingerprint: fp
        )
        #expect(entries.isEmpty)
    }

    @Test("EPUB TOC skips whitespace-only titles")
    func epubTOCSkipsWhitespaceOnlyTitles() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 1000,
            format: .epub
        )
        let spineItems = [
            EPUBSpineItem(id: "1", href: "ch1.xhtml", title: "  ", index: 0),
            EPUBSpineItem(id: "2", href: "ch2.xhtml", title: " Chapter 2 ", index: 1),
        ]

        let entries = TOCBuilder.fromSpineItems(spineItems, fingerprint: fp)

        #expect(entries.count == 1)
        #expect(entries[0].title == "Chapter 2")
    }

    @Test("TXT TOC returns empty")
    func txtTOCEmpty() {
        let entries = TOCBuilder.forTXT()
        #expect(entries.isEmpty)
    }

    @Test("MD TOC returns empty for text without headings")
    func mdTOCEmptyWithoutHeadings() {
        let fp = DocumentFingerprint(
            contentSHA256: "toc_test_sha256_0000000000000000000000000000000000000000000000000",
            fileByteCount: 1000,
            format: .md
        )
        let entries = TOCBuilder.forMD(text: "No headings here.", fingerprint: fp)
        #expect(entries.isEmpty)
    }
}
