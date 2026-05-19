// Purpose: Feature #56 WI-2.5 — tests for the four concrete
// `ChapterTextProviding` adapters (EPUB / TXT / MD / PDF). Each adapter is
// exercised against an in-memory fixture book: `translationUnits()` returns
// units in reading order, `sourceText(for:)` returns the unit's plain text,
// an out-of-book unit throws, a zero-unit book returns `[]`, and `unit(after:)`
// returns the next unit / `nil` at the last unit.
//
// `unit(containing:)` boundary contract (plan Decision 2.6) is covered per
// adapter: a mid-book locator maps to the right unit; a locator that predates
// the book's first unit (empty book, negative offset, unknown EPUB href)
// returns `nil`; a position past the last unit clamps to the last unit. UTF-16
// slicing is checked with a CJK fixture so `NSString` math matches the
// `charOffsetUTF16` semantics.
//
// EPUB units = spine documents (not TOC entries) — a multi-spine fixture proves
// the unit is the spine doc.
//
// @coordinates-with: ChapterTextProviding.swift, EPUBChapterTextProvider.swift,
//   TXTChapterTextProvider.swift, MDChapterTextProvider.swift,
//   PDFChapterTextProvider.swift

import Testing
import Foundation
import PDFKit
@testable import vreader

@Suite("ChapterTextProvider")
struct ChapterTextProviderTests {

    // MARK: - Fixtures

    private static func fingerprint(_ format: BookFormat) -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 1024,
            format: format
        )
    }

    // MARK: - EPUB adapter

    /// An EPUB whose spine has three documents; one logical TOC chapter spans
    /// two of them — the translation unit must still be the spine document.
    private func makeEPUBAdapter() async -> (EPUBChapterTextProvider, MockEPUBParser) {
        let parser = MockEPUBParser()
        let spine = [
            EPUBSpineItem(id: "s1", href: "OEBPS/ch1.xhtml", title: "Chapter One", index: 0),
            EPUBSpineItem(id: "s2", href: "OEBPS/ch2a.xhtml", title: "Chapter Two", index: 1),
            EPUBSpineItem(id: "s3", href: "OEBPS/ch2b.xhtml", title: nil, index: 2),
        ]
        await parser.setMetadata(EPUBMetadata(
            title: "Fixture", author: nil, language: "en",
            readingDirection: .ltr, layout: .reflowable, spineItems: spine
        ))
        await parser.setSpineContent([
            "OEBPS/ch1.xhtml": "<html><body><p>First spine text.</p></body></html>",
            "OEBPS/ch2a.xhtml": "<html><body><p>Second <b>bold</b> spine.</p></body></html>",
            "OEBPS/ch2b.xhtml": "<html><body><p>Third spine continues.</p></body></html>",
        ])
        // The adapter calls `contentForSpineItem`, which the mock guards on
        // `_isOpen` — open it so spine-text reads succeed.
        _ = try? await parser.open(url: URL(fileURLWithPath: "/tmp/fixture.epub"))
        let adapter = EPUBChapterTextProvider(parser: parser, spineItems: spine)
        return (adapter, parser)
    }

    @Test func epubTranslationUnitsAreSpineDocumentsInOrder() async throws {
        let (adapter, _) = await makeEPUBAdapter()
        let units = try await adapter.translationUnits()
        #expect(units == [
            TranslationUnitID(kind: .epubHref, value: "OEBPS/ch1.xhtml"),
            TranslationUnitID(kind: .epubHref, value: "OEBPS/ch2a.xhtml"),
            TranslationUnitID(kind: .epubHref, value: "OEBPS/ch2b.xhtml"),
        ])
    }

    @Test func epubSourceTextIsHTMLStripped() async throws {
        let (adapter, _) = await makeEPUBAdapter()
        let text = try await adapter.sourceText(
            for: TranslationUnitID(kind: .epubHref, value: "OEBPS/ch2a.xhtml")
        )
        #expect(text == "Second bold spine.")
    }

    @Test func epubSourceTextForUnknownUnitThrows() async throws {
        let (adapter, _) = await makeEPUBAdapter()
        let bogus = TranslationUnitID(kind: .epubHref, value: "OEBPS/nope.xhtml")
        await #expect(throws: ChapterTextProviderError.unknownUnit(bogus)) {
            _ = try await adapter.sourceText(for: bogus)
        }
    }

    @Test func epubUnitContainingResolvesByHref() async throws {
        let (adapter, _) = await makeEPUBAdapter()
        let fp = Self.fingerprint(.epub)
        let locator = Locator(
            bookFingerprint: fp, href: "OEBPS/ch2a.xhtml", progression: 0.5,
            totalProgression: 0.5, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let unit = await adapter.unit(containing: locator)
        #expect(unit == TranslationUnitID(kind: .epubHref, value: "OEBPS/ch2a.xhtml"))
    }

    @Test func epubUnitContainingReturnsNilForUnknownHref() async throws {
        let (adapter, _) = await makeEPUBAdapter()
        let fp = Self.fingerprint(.epub)
        let locator = Locator(
            bookFingerprint: fp, href: "OEBPS/missing.xhtml", progression: 0,
            totalProgression: 0, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let unit = await adapter.unit(containing: locator)
        #expect(unit == nil)
    }

    @Test func epubUnitAfterReturnsNextThenNil() async throws {
        let (adapter, _) = await makeEPUBAdapter()
        let next = await adapter.unit(
            after: TranslationUnitID(kind: .epubHref, value: "OEBPS/ch1.xhtml")
        )
        #expect(next == TranslationUnitID(kind: .epubHref, value: "OEBPS/ch2a.xhtml"))
        let atEnd = await adapter.unit(
            after: TranslationUnitID(kind: .epubHref, value: "OEBPS/ch2b.xhtml")
        )
        #expect(atEnd == nil)
    }

    @Test func epubEmptySpineReturnsNoUnits() async throws {
        let parser = MockEPUBParser()
        await parser.setMetadata(EPUBMetadata(
            title: "Empty", author: nil, language: "en",
            readingDirection: .ltr, layout: .reflowable, spineItems: []
        ))
        let adapter = EPUBChapterTextProvider(parser: parser, spineItems: [])
        let units = try await adapter.translationUnits()
        #expect(units.isEmpty)
        let fp = Self.fingerprint(.epub)
        let locator = Locator(
            bookFingerprint: fp, href: "OEBPS/ch1.xhtml", progression: 0,
            totalProgression: 0, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator) == nil)
    }

    // MARK: - TXT adapter

    /// Three chapters with populated UTF-16 offsets, derived from a real
    /// full-text decode so the offsets match exactly what the loader produces.
    private func makeTXTAdapter() -> TXTChapterTextProvider {
        let full = "Chapter 1\nAlpha body text.\n"   // 0..<27
            + "Chapter 2\nBeta body text.\n"          // 27..<53
            + "Chapter 3\nGamma body text."           // 53..<79
        var chapters = [
            TXTChapter(index: 0, title: "Chapter 1", startByte: 0, endByte: 27),
            TXTChapter(index: 1, title: "Chapter 2", startByte: 27, endByte: 53),
            TXTChapter(index: 2, title: "Chapter 3", startByte: 53, endByte: 79),
        ]
        // Populate UTF-16 offsets exactly as TXTOffsetTranslator does, by
        // slicing the full text on the byte boundaries (ASCII => byte == utf16).
        TXTOffsetTranslator.populateUTF16Offsets(chapters: &chapters) { ch in
            let ns = full as NSString
            return ns.substring(with: NSRange(
                location: Int(ch.startByte),
                length: Int(ch.endByte - ch.startByte)
            ))
        }
        return TXTChapterTextProvider(fingerprint: Self.fingerprint(.txt),
                                      fullText: full, chapters: chapters)
    }

    @Test func txtTranslationUnitsAreChapterIndices() async throws {
        let adapter = makeTXTAdapter()
        let units = try await adapter.translationUnits()
        #expect(units == [
            TranslationUnitID(kind: .txtChapterIndex, value: "0"),
            TranslationUnitID(kind: .txtChapterIndex, value: "1"),
            TranslationUnitID(kind: .txtChapterIndex, value: "2"),
        ])
    }

    @Test func txtSourceTextSlicesByUTF16Bounds() async throws {
        let adapter = makeTXTAdapter()
        let text = try await adapter.sourceText(
            for: TranslationUnitID(kind: .txtChapterIndex, value: "1")
        )
        #expect(text == "Chapter 2\nBeta body text.\n")
    }

    @Test func txtSourceTextForUnknownUnitThrows() async throws {
        let adapter = makeTXTAdapter()
        let bogus = TranslationUnitID(kind: .txtChapterIndex, value: "99")
        await #expect(throws: ChapterTextProviderError.unknownUnit(bogus)) {
            _ = try await adapter.sourceText(for: bogus)
        }
    }

    @Test func txtUnitContainingMapsCharOffsetToChapter() async throws {
        let adapter = makeTXTAdapter()
        let fp = Self.fingerprint(.txt)
        // Offset 40 lands inside chapter 2 (27..<53).
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 40, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let unit = await adapter.unit(containing: locator)
        #expect(unit == TranslationUnitID(kind: .txtChapterIndex, value: "1"))
    }

    @Test func txtUnitContainingClampsPastEndToLastUnit() async throws {
        let adapter = makeTXTAdapter()
        let fp = Self.fingerprint(.txt)
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 100_000, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let unit = await adapter.unit(containing: locator)
        #expect(unit == TranslationUnitID(kind: .txtChapterIndex, value: "2"))
    }

    @Test func txtUnitContainingReturnsNilForNegativeOffset() async throws {
        let adapter = makeTXTAdapter()
        let fp = Self.fingerprint(.txt)
        // A negative offset predates the book's first unit -> nil (not unit 0).
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: -5, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator) == nil)
    }

    @Test func txtUnitContainingNilOffsetResolvesToFirstUnit() async throws {
        let adapter = makeTXTAdapter()
        let fp = Self.fingerprint(.txt)
        // No offset at all (e.g. start of book) -> unit 0.
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator)
            == TranslationUnitID(kind: .txtChapterIndex, value: "0"))
    }

    @Test func txtSourceTextSlicesCJKByUTF16Bounds() async throws {
        // A CJK chapter: each Han character is 1 UTF-16 unit but >1 byte.
        // Proves `sourceText` slices on UTF-16 offsets, not bytes.
        let full = "第一章\n春眠不觉晓。\n" + "第二章\n处处闻啼鸟。"
        var chapters = [
            TXTChapter(index: 0, title: "第一章", startByte: 0,
                       endByte: Int64(("第一章\n春眠不觉晓。\n" as NSString).length)),
            TXTChapter(index: 1, title: "第二章", startByte: 0, endByte: 0),
        ]
        // Populate UTF-16 offsets by slicing the full text on UTF-16 boundaries.
        let ch0Len = ("第一章\n春眠不觉晓。\n" as NSString).length
        chapters[0] = TXTChapter(index: 0, title: "第一章", startByte: 0, endByte: 1,
                                 globalStartUTF16: 0, textLengthUTF16: ch0Len)
        chapters[1] = TXTChapter(
            index: 1, title: "第二章", startByte: 1, endByte: 2,
            globalStartUTF16: ch0Len,
            textLengthUTF16: (full as NSString).length - ch0Len
        )
        let adapter = TXTChapterTextProvider(
            fingerprint: Self.fingerprint(.txt), fullText: full, chapters: chapters
        )
        let chapter1 = try await adapter.sourceText(
            for: TranslationUnitID(kind: .txtChapterIndex, value: "1")
        )
        #expect(chapter1 == "第二章\n处处闻啼鸟。")
    }

    @Test func txtUnitAfterReturnsNextThenNil() async throws {
        let adapter = makeTXTAdapter()
        let next = await adapter.unit(
            after: TranslationUnitID(kind: .txtChapterIndex, value: "0")
        )
        #expect(next == TranslationUnitID(kind: .txtChapterIndex, value: "1"))
        let atEnd = await adapter.unit(
            after: TranslationUnitID(kind: .txtChapterIndex, value: "2")
        )
        #expect(atEnd == nil)
    }

    @Test func txtEmptyBookReturnsNoUnits() async throws {
        let adapter = TXTChapterTextProvider(
            fingerprint: Self.fingerprint(.txt), fullText: "", chapters: []
        )
        #expect(try await adapter.translationUnits().isEmpty)
        let fp = Self.fingerprint(.txt)
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 0, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator) == nil)
    }

    // MARK: - MD adapter

    /// A Markdown render with three heading-bounded chapters plus a short
    /// pre-heading preamble that forms unit 0.
    private func makeMDAdapter() -> MDChapterTextProvider {
        // renderedText: heading text is plain in the rendered output.
        let rendered = "Preamble line.\n"            // 0..<15  -> chapter 0
            + "Intro\nIntro body paragraph.\n"        // 15..<43 -> chapter 1
            + "Methods\nMethods body text.\n"         // 43..<70 -> chapter 2
            + "Results\nResults discussion."          // 70..<97 -> chapter 3
        let headings = [
            MDHeading(level: 1, text: "Intro", charOffsetUTF16: 15),
            MDHeading(level: 1, text: "Methods", charOffsetUTF16: 43),
            MDHeading(level: 1, text: "Results", charOffsetUTF16: 70),
        ]
        return MDChapterTextProvider(fingerprint: Self.fingerprint(.md),
                                     renderedText: rendered, headings: headings)
    }

    @Test func mdTranslationUnitsIncludePreambleThenHeadings() async throws {
        let adapter = makeMDAdapter()
        let units = try await adapter.translationUnits()
        #expect(units == [
            TranslationUnitID(kind: .mdChapterIndex, value: "0"),
            TranslationUnitID(kind: .mdChapterIndex, value: "1"),
            TranslationUnitID(kind: .mdChapterIndex, value: "2"),
            TranslationUnitID(kind: .mdChapterIndex, value: "3"),
        ])
    }

    @Test func mdSourceTextSlicesByHeadingBounds() async throws {
        let adapter = makeMDAdapter()
        let chapter2 = try await adapter.sourceText(
            for: TranslationUnitID(kind: .mdChapterIndex, value: "2")
        )
        #expect(chapter2 == "Methods\nMethods body text.\n")
        let preamble = try await adapter.sourceText(
            for: TranslationUnitID(kind: .mdChapterIndex, value: "0")
        )
        #expect(preamble == "Preamble line.\n")
    }

    @Test func mdSourceTextForUnknownUnitThrows() async throws {
        let adapter = makeMDAdapter()
        let bogus = TranslationUnitID(kind: .mdChapterIndex, value: "9")
        await #expect(throws: ChapterTextProviderError.unknownUnit(bogus)) {
            _ = try await adapter.sourceText(for: bogus)
        }
    }

    @Test func mdUnitContainingMapsCharOffsetToChapter() async throws {
        let adapter = makeMDAdapter()
        let fp = Self.fingerprint(.md)
        // Offset 50 lands inside chapter 2 (43..<70).
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 50, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let unit = await adapter.unit(containing: locator)
        #expect(unit == TranslationUnitID(kind: .mdChapterIndex, value: "2"))
    }

    @Test func mdUnitContainingReturnsNilForNegativeOffset() async throws {
        let adapter = makeMDAdapter()
        let fp = Self.fingerprint(.md)
        // A negative offset predates the book's first unit -> nil (not unit 0).
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: -1, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator) == nil)
    }

    @Test func mdUnitContainingClampsPastEndToLastUnit() async throws {
        let adapter = makeMDAdapter()
        let fp = Self.fingerprint(.md)
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 100_000, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator)
            == TranslationUnitID(kind: .mdChapterIndex, value: "3"))
    }

    @Test func mdUnitAfterReturnsNextThenNil() async throws {
        let adapter = makeMDAdapter()
        let next = await adapter.unit(
            after: TranslationUnitID(kind: .mdChapterIndex, value: "1")
        )
        #expect(next == TranslationUnitID(kind: .mdChapterIndex, value: "2"))
        let atEnd = await adapter.unit(
            after: TranslationUnitID(kind: .mdChapterIndex, value: "3")
        )
        #expect(atEnd == nil)
    }

    @Test func mdHeadingAtOffsetZeroHasNoPreambleUnit() async throws {
        // When the document begins with a heading, there is no preamble
        // chapter — unit 0 is the first heading's chapter.
        let rendered = "Title\nFirst body.\nSecond\nSecond body."
        let headings = [
            MDHeading(level: 1, text: "Title", charOffsetUTF16: 0),
            MDHeading(level: 1, text: "Second", charOffsetUTF16: 18),
        ]
        let adapter = MDChapterTextProvider(
            fingerprint: Self.fingerprint(.md), renderedText: rendered, headings: headings
        )
        let units = try await adapter.translationUnits()
        #expect(units == [
            TranslationUnitID(kind: .mdChapterIndex, value: "0"),
            TranslationUnitID(kind: .mdChapterIndex, value: "1"),
        ])
        let first = try await adapter.sourceText(
            for: TranslationUnitID(kind: .mdChapterIndex, value: "0")
        )
        #expect(first == "Title\nFirst body.\n")
    }

    @Test func mdNoHeadingsTreatsWholeDocumentAsOneUnit() async throws {
        let adapter = MDChapterTextProvider(
            fingerprint: Self.fingerprint(.md),
            renderedText: "Just one block of prose, no headings at all.",
            headings: []
        )
        let units = try await adapter.translationUnits()
        #expect(units == [TranslationUnitID(kind: .mdChapterIndex, value: "0")])
        let text = try await adapter.sourceText(for: units[0])
        #expect(text == "Just one block of prose, no headings at all.")
    }

    @Test func mdEmptyDocumentReturnsNoUnits() async throws {
        let adapter = MDChapterTextProvider(
            fingerprint: Self.fingerprint(.md), renderedText: "", headings: []
        )
        #expect(try await adapter.translationUnits().isEmpty)
        let fp = Self.fingerprint(.md)
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: 0, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator) == nil)
    }

    // MARK: - PDF adapter

    /// Writes a 5-page PDF with one identifiable line of text per page.
    private func makePDFFixture() throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctp-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { ctx in
            for page in 1...5 {
                ctx.beginPage()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24)
                ]
                "Page \(page) content line".draw(at: CGPoint(x: 72, y: 72), withAttributes: attrs)
            }
        }
        return url
    }

    @Test func pdfTranslationUnitsArePageRanges() async throws {
        let url = try makePDFFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        // Default: one page per unit.
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: url
        )
        let units = try await adapter.translationUnits()
        #expect(units == [
            TranslationUnitID(kind: .pdfPageRange, value: "0-0"),
            TranslationUnitID(kind: .pdfPageRange, value: "1-1"),
            TranslationUnitID(kind: .pdfPageRange, value: "2-2"),
            TranslationUnitID(kind: .pdfPageRange, value: "3-3"),
            TranslationUnitID(kind: .pdfPageRange, value: "4-4"),
        ])
    }

    @Test func pdfTranslationUnitsGroupPagesWhenConfigured() async throws {
        let url = try makePDFFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: url, pagesPerUnit: 2
        )
        let units = try await adapter.translationUnits()
        // 5 pages, 2 per unit => ranges 0-1, 2-3, 4-4.
        #expect(units == [
            TranslationUnitID(kind: .pdfPageRange, value: "0-1"),
            TranslationUnitID(kind: .pdfPageRange, value: "2-3"),
            TranslationUnitID(kind: .pdfPageRange, value: "4-4"),
        ])
    }

    @Test func pdfSourceTextConcatenatesPagesInRange() async throws {
        let url = try makePDFFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: url, pagesPerUnit: 2
        )
        let text = try await adapter.sourceText(
            for: TranslationUnitID(kind: .pdfPageRange, value: "0-1")
        )
        #expect(text.contains("Page 1 content line"))
        #expect(text.contains("Page 2 content line"))
        #expect(!text.contains("Page 3 content line"))
    }

    @Test func pdfSourceTextForUnknownUnitThrows() async throws {
        let url = try makePDFFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: url
        )
        let bogus = TranslationUnitID(kind: .pdfPageRange, value: "50-60")
        await #expect(throws: ChapterTextProviderError.unknownUnit(bogus)) {
            _ = try await adapter.sourceText(for: bogus)
        }
    }

    @Test func pdfUnitContainingMapsPageToRange() async throws {
        let url = try makePDFFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: url, pagesPerUnit: 2
        )
        let fp = Self.fingerprint(.pdf)
        // Page 3 is in range 2-3.
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: 3,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        let unit = await adapter.unit(containing: locator)
        #expect(unit == TranslationUnitID(kind: .pdfPageRange, value: "2-3"))
    }

    @Test func pdfUnitContainingClampsPastEndToLastUnit() async throws {
        let url = try makePDFFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: url, pagesPerUnit: 2
        )
        let fp = Self.fingerprint(.pdf)
        // Page 999 is past the last unit (4-4) -> clamps to the last unit.
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: 999,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator)
            == TranslationUnitID(kind: .pdfPageRange, value: "4-4"))
    }

    @Test func pdfUnitContainingReturnsNilForNegativePage() async throws {
        let url = try makePDFFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: url
        )
        let fp = Self.fingerprint(.pdf)
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: -1,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator) == nil)
    }

    @Test func pdfSourceTextForMalformedRangeStringThrows() async throws {
        let url = try makePDFFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: url
        )
        // An inverted ("5-2") and a non-numeric ("a-b") page-range value are
        // both rejected — they decode to no valid range, so the unit is
        // unknown.
        let inverted = TranslationUnitID(kind: .pdfPageRange, value: "5-2")
        await #expect(throws: ChapterTextProviderError.unknownUnit(inverted)) {
            _ = try await adapter.sourceText(for: inverted)
        }
        let nonNumeric = TranslationUnitID(kind: .pdfPageRange, value: "a-b")
        await #expect(throws: ChapterTextProviderError.unknownUnit(nonNumeric)) {
            _ = try await adapter.sourceText(for: nonNumeric)
        }
    }

    @Test func pdfUnitAfterReturnsNextThenNil() async throws {
        let url = try makePDFFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: url, pagesPerUnit: 2
        )
        let next = await adapter.unit(
            after: TranslationUnitID(kind: .pdfPageRange, value: "0-1")
        )
        #expect(next == TranslationUnitID(kind: .pdfPageRange, value: "2-3"))
        let atEnd = await adapter.unit(
            after: TranslationUnitID(kind: .pdfPageRange, value: "4-4")
        )
        #expect(atEnd == nil)
    }

    @Test func pdfMissingFileReturnsNoUnits() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctp-missing-\(UUID().uuidString).pdf")
        let adapter = PDFChapterTextProvider(
            fingerprint: Self.fingerprint(.pdf), fileURL: missing
        )
        #expect(try await adapter.translationUnits().isEmpty)
        let fp = Self.fingerprint(.pdf)
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: 0,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(await adapter.unit(containing: locator) == nil)
    }
}
