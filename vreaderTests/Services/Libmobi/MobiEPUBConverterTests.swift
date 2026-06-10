// Feature #42 Phase 2 WI-2c: the end-to-end MOBI→EPUB converter. CI-safe cases
// package synthetic assembled files into an OCF zip and assert the archive shape
// (mimetype first + exact, container/opf present, round-trippable). One real-AZW3
// case runs the FULL decode→assemble→package pipeline against an actual Kindle
// book, skipped when test-books/ is absent (CI) — the rendered-in-Readium proof
// is WI-5's device verification.

import Testing
import Foundation
@testable import vreader

@Suite("MOBI→EPUB converter (Feature #42 Phase 2 WI-2c)")
struct MobiEPUBConverterTests {

    private func part(_ s: MobiPart.Section, _ uid: Int, _ ext: String, _ body: String) -> MobiPart {
        MobiPart(section: s, uid: uid, fileExtension: ext, data: Data(body.utf8))
    }

    private var sampleFiles: [EPUBFile] {
        get throws {
            try MobiEPUBAssembler.assemble(parts: [
                part(.markup, 0, "html", "<html><body><p>Ch1</p></body></html>"),
                part(.markup, 1, "html", "<html><body><p>Ch2</p></body></html>"),
                part(.flow, 0, "css", "p{}"),
                part(.resource, 0, "jpg", "img-bytes"),
            ], title: "T")
        }
    }

    // MARK: CI-safe packaging (synthetic, no libmobi)

    @Test("packaged epub is a valid zip with mimetype FIRST and exact content")
    func packageMimetypeFirst() throws {
        let epub = try MobiEPUBConverter.package(files: try sampleFiles)
        let names = try ZIPWriter.listEntryNames(in: epub)
        #expect(names.first == "mimetype", "OCF requires the mimetype entry first")
        let mimetype = try ZIPWriter.extractEntry(named: "mimetype", from: epub)
        #expect(String(decoding: mimetype, as: UTF8.self) == "application/epub+zip")
    }

    @Test("packaged epub contains container.xml + content.opf + part files")
    func packageContainsStructure() throws {
        let epub = try MobiEPUBConverter.package(files: try sampleFiles)
        let names = Set(try ZIPWriter.listEntryNames(in: epub))
        #expect(names.contains("META-INF/container.xml"))
        #expect(names.contains("OEBPS/content.opf"))
        #expect(names.contains("OEBPS/nav.xhtml"))
        #expect(names.contains("OEBPS/text/part0000.xhtml"))
        #expect(names.contains("OEBPS/resources/res0000.jpg"))
    }

    @Test("content.opf round-trips through the archive byte-identically")
    func opfRoundTrips() throws {
        let files = try sampleFiles
        let original = try #require(files.first { $0.path == "OEBPS/content.opf" }).data
        let epub = try MobiEPUBConverter.package(files: files)
        let extracted = try ZIPWriter.extractEntry(named: "OEBPS/content.opf", from: epub)
        #expect(extracted == original)
    }

    /// Independent of ZIPWriter's own read helpers: parse the RAW first local
    /// file header and assert the EPUB-critical OCF invariant — `mimetype` is
    /// the first entry AND is Stored (compression method 0). If ZIPWriter ever
    /// starts deflating, this fails before a non-compliant EPUB can ship
    /// (Codex Gate-4 Medium — enforces the storage contract package() relies on).
    @Test("the first archive entry is mimetype, written Stored (method 0)")
    func mimetypeRawHeaderIsStored() throws {
        let bytes = [UInt8](try MobiEPUBConverter.package(files: try sampleFiles))
        try #require(bytes.count > 30)
        // Local file header signature 0x04034b50 (little-endian) at offset 0.
        #expect(le32(bytes, 0) == 0x0403_4b50)
        // Compression method (offset 8, u16 LE) must be 0 = Stored.
        #expect(le16(bytes, 8) == 0, "mimetype must be Stored, not deflated, for OCF")
        // Filename (length at offset 26, bytes at offset 30) must be "mimetype".
        let nameLen = Int(le16(bytes, 26))
        try #require(bytes.count >= 30 + nameLen)
        #expect(String(decoding: bytes[30..<(30 + nameLen)], as: UTF8.self) == "mimetype")
    }

    // MARK: WI-4a — self-describing EPUB round-trips through EPUBMetadataExtractor

    @Test("packaged EPUB is self-describing — title + author recover via EPUBMetadataExtractor")
    func selfDescribingMetadataRecovers() async throws {
        let parts = [
            part(.markup, 0, "html", "<html><body><p>hi</p></body></html>"),
            part(.resource, 0, "jpg", "pretend-jpeg"),
        ]
        let files = try MobiEPUBAssembler.assemble(parts: parts, title: "My Title", author: "Jane Doe")
        let epub = try MobiEPUBConverter.package(files: files)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wi4a-\(UUID().uuidString).epub")
        try epub.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let meta = try await EPUBMetadataExtractor().extractMetadata(from: tmp)
        #expect(meta.title == "My Title")
        #expect(meta.author == "Jane Doe")
    }

    @Test("converter version is a positive constant")
    func converterVersion() {
        #expect(MobiEPUBConverter.version == 2)  // bump on any output-byte change
    }

    private func le16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }
    private func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }

    // MARK: Real-book end-to-end (SKIPPED in CI)

    @Test("a real AZW3 converts to a structurally-valid epub",
          .enabled(if: MobiDocumentTests.realAzw3Path != nil))
    func realAzw3ConvertsToEPUB() throws {
        let path = try #require(MobiDocumentTests.realAzw3Path)
        let epub = try MobiEPUBConverter.convert(mobiPath: path)

        let names = try ZIPWriter.listEntryNames(in: epub)
        #expect(names.first == "mimetype")
        #expect(names.contains("OEBPS/content.opf"))
        #expect(names.contains { $0.hasPrefix("OEBPS/text/part") }, "must carry markup")

        // The OPF must declare a non-empty spine, and a markup part must be XHTML.
        let opf = String(decoding: try ZIPWriter.extractEntry(named: "OEBPS/content.opf", from: epub),
                         as: UTF8.self)
        #expect(opf.contains("<itemref"))
        let firstPart = try #require(names.first { $0.hasPrefix("OEBPS/text/part") })
        let markup = String(decoding: try ZIPWriter.extractEntry(named: firstPart, from: epub),
                            as: UTF8.self).lowercased()
        #expect(markup.contains("<html") || markup.contains("<body") || markup.contains("<p"))
    }
}
