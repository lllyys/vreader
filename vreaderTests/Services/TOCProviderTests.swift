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

    @Test("MD TOC returns empty in V1")
    func mdTOCEmpty() {
        let entries = TOCBuilder.forMD()
        #expect(entries.isEmpty)
    }
}
