// Purpose: Tests for WI-2 — EPUBMetadataExtractor cover image extraction.
// Verifies extractMetadata returns real OPF metadata and extractCoverImage
// returns UIImage for valid covers, nil for edge cases.
//
// @coordinates-with: MetadataExtractor.swift, EPUBParser.swift, CustomCoverStore.swift

import Testing
import UIKit
@testable import vreader

@Suite("EPUBMetadataExtractor — Cover Extraction")
struct EPUBMetadataExtractorTests {

    // MARK: - Helpers

    /// Creates a minimal valid EPUB (ZIP) with the given OPF content and optional cover image.
    /// Layout: META-INF/container.xml + OEBPS/content.opf + optional OEBPS/<coverPath>.
    private static func createMinimalEPUB(
        opfXML: String,
        coverPath: String? = nil,
        coverData: Data? = nil,
        containerXML: String? = nil
    ) throws -> URL {
        let container = containerXML ?? """
        <?xml version="1.0" encoding="UTF-8"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """

        var entries: [(path: String, data: Data)] = [
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opfXML.utf8)),
        ]

        // Add a minimal chapter so spine validation passes
        let chapterHTML = Data("""
        <html><body><p>Hello</p></body></html>
        """.utf8)
        entries.append(("OEBPS/chapter1.xhtml", chapterHTML))

        if let coverPath = coverPath, let coverData = coverData {
            entries.append(("OEBPS/\(coverPath)", coverData))
        }

        return try buildZIP(entries: entries)
    }

    /// Builds a ZIP file from a list of (path, data) entries (stored/uncompressed).
    private static func buildZIP(entries: [(path: String, data: Data)]) throws -> URL {
        var archive = Data()
        var centralDirectory = Data()
        var cdEntryCount: UInt16 = 0

        for (path, content) in entries {
            let nameData = Data(path.utf8)
            let localHeaderOffset = UInt32(archive.count)

            // Local File Header
            archive.appendUInt32LE(0x04034b50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0) // stored
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(0) // crc32 (ignored)
            archive.appendUInt32LE(UInt32(content.count))
            archive.appendUInt32LE(UInt32(content.count))
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.appendUInt16LE(0)
            archive.append(nameData)
            archive.append(content)

            // Central Directory Entry
            centralDirectory.appendUInt32LE(0x02014b50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0) // stored
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(UInt32(content.count))
            centralDirectory.appendUInt32LE(UInt32(content.count))
            centralDirectory.appendUInt16LE(UInt16(nameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(localHeaderOffset)
            centralDirectory.append(nameData)

            cdEntryCount += 1
        }

        let cdOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        let cdSize = UInt32(centralDirectory.count)

        // EOCD
        archive.appendUInt32LE(0x06054b50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(cdEntryCount)
        archive.appendUInt16LE(cdEntryCount)
        archive.appendUInt32LE(cdSize)
        archive.appendUInt32LE(cdOffset)
        archive.appendUInt16LE(0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-epub-\(UUID().uuidString).epub")
        try archive.write(to: url)
        return url
    }

    /// Creates a minimal valid JPEG image data (smallest valid JPEG).
    private static func makeTestJPEGData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 2, height: 2), format: format
        )
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.jpegData(compressionQuality: 0.5)!
    }

    /// Creates a minimal valid PNG image data.
    private static func makeTestPNGData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 2, height: 2), format: format
        )
        let image = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.pngData()!
    }

    // MARK: - extractMetadata Tests

    @Test("extractMetadata — reads title and author from OPF")
    func extractMetadata_readsOPF() async throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Real EPUB Title</dc:title>
            <dc:creator>Jane Author</dc:creator>
          </metadata>
          <manifest>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        let epubURL = try Self.createMinimalEPUB(opfXML: opf)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let metadata = try await extractor.extractMetadata(from: epubURL)
        #expect(metadata.title == "Real EPUB Title")
        #expect(metadata.author == "Jane Author")
    }

    @Test("extractMetadata — falls back to filename on parse error")
    func extractMetadata_fallbackOnError() async throws {
        // Create a file that's not a valid ZIP
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bad EPUB.epub")
        try Data("not a zip".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = EPUBMetadataExtractor()
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "Bad EPUB")
        #expect(metadata.author == nil)
    }

    // MARK: - extractCoverImage Tests

    @Test("extractCoverImage — valid EPUB with JPEG cover returns UIImage")
    func extractCoverImage_jpegCover() async throws {
        let jpegData = Self.makeTestJPEGData()
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Cover Test</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="Images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        let epubURL = try Self.createMinimalEPUB(
            opfXML: opf,
            coverPath: "Images/cover.jpg",
            coverData: jpegData
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image != nil, "Should return a UIImage for valid JPEG cover")
    }

    @Test("extractCoverImage — valid EPUB with PNG cover returns UIImage")
    func extractCoverImage_pngCover() async throws {
        let pngData = Self.makeTestPNGData()
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>PNG Cover Test</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        let epubURL = try Self.createMinimalEPUB(
            opfXML: opf,
            coverPath: "cover.png",
            coverData: pngData
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image != nil, "Should return a UIImage for valid PNG cover")
    }

    @Test("extractCoverImage — EPUB2 meta cover extracts correctly")
    func extractCoverImage_epub2() async throws {
        let jpegData = Self.makeTestJPEGData()
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>EPUB2 Cover</dc:title>
            <meta name="cover" content="cover-img"/>
          </metadata>
          <manifest>
            <item id="cover-img" href="images/cover.jpg" media-type="image/jpeg"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        let epubURL = try Self.createMinimalEPUB(
            opfXML: opf,
            coverPath: "images/cover.jpg",
            coverData: jpegData
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image != nil, "Should extract cover from EPUB2 meta+manifest")
    }

    @Test("extractCoverImage — EPUB without cover returns nil")
    func extractCoverImage_noCover() async throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>No Cover</dc:title>
          </metadata>
          <manifest>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        let epubURL = try Self.createMinimalEPUB(opfXML: opf)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image == nil, "Should return nil when no cover metadata exists")
    }

    @Test("extractCoverImage — corrupt image data returns nil")
    func extractCoverImage_corruptData() async throws {
        let corruptData = Data([0xFF, 0xD8, 0x00, 0x01, 0x02, 0x03]) // broken JPEG
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Corrupt Cover</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        let epubURL = try Self.createMinimalEPUB(
            opfXML: opf,
            coverPath: "cover.jpg",
            coverData: corruptData
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image == nil, "Should return nil for corrupt image data")
    }

    @Test("extractCoverImage — SVG cover returns nil (UIImage cannot decode SVG)")
    func extractCoverImage_svgCover() async throws {
        let svgData = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <rect fill="red" width="100" height="100"/>
        </svg>
        """.utf8)
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>SVG Cover</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="cover.svg" media-type="image/svg+xml" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        let epubURL = try Self.createMinimalEPUB(
            opfXML: opf,
            coverPath: "cover.svg",
            coverData: svgData
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image == nil, "Should return nil for SVG cover (UIImage cannot decode)")
    }

    @Test("extractCoverImage — non-EPUB file returns nil")
    func extractCoverImage_nonEPUBFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).txt")
        try Data("plain text".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: url)
        #expect(image == nil, "Should return nil for non-EPUB file")
    }

    @Test("extractCoverImage — cover href in OPF but entry missing from ZIP returns nil")
    func extractCoverImage_missingEntry() async throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Missing Entry</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="Images/missing.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        // Create EPUB without the cover image file
        let epubURL = try Self.createMinimalEPUB(opfXML: opf)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image == nil, "Should return nil when cover entry is missing from ZIP")
    }

    @Test("extractCoverImage — percent-encoded cover path resolves correctly")
    func extractCoverImage_percentEncoded() async throws {
        let jpegData = Self.makeTestJPEGData()
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Encoded Cover</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="Images/cover%20image.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        // The actual file path in the ZIP uses the decoded name
        let epubURL = try Self.createMinimalEPUB(
            opfXML: opf,
            coverPath: "Images/cover image.jpg",
            coverData: jpegData
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image != nil, "Should decode percent-encoded path and find cover")
    }

    @Test("extractCoverImage — cover with ../ relative path resolves correctly")
    func extractCoverImage_relativeParentPath() async throws {
        let jpegData = Self.makeTestJPEGData()
        // OPF is at OEBPS/content.opf, cover href is ../cover.jpg
        // Resolved archive path: cover.jpg (at root)
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Relative Path Cover</dc:title>
          </metadata>
          <manifest>
            <item id="cover" href="../cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        // The cover file is at root level, not inside OEBPS
        var entries: [(path: String, data: Data)] = [
            ("META-INF/container.xml", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/chapter1.xhtml", Data("<html><body><p>Hello</p></body></html>".utf8)),
            ("cover.jpg", jpegData),
        ]

        let epubURL = try Self.buildZIP(entries: entries)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image != nil, "Should resolve ../ path relative to OPF directory")
    }

    // MARK: - Bug #122 — redundant-prefix cover href

    @Test("extractCoverImage — bug #122: redundant-prefix href falls back to basename")
    func extractCoverImage_redundantPrefixHref() async throws {
        // Reproduce the "道诡异仙" EPUB shape: OPF lives at OEBPS/content.opf
        // and declares <item href="OEBPS/cover.jpg" id="cover"/>. Spec join
        // → "OEBPS/OEBPS/cover.jpg" which doesn't exist in the archive. The
        // real cover sits at OEBPS/Images/cover.jpg with the same basename.
        // Without the bug-#122 fallback chain, extractCoverImage returns nil.
        let jpegData = Self.makeTestJPEGData()
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Redundant Prefix EPUB</dc:title>
            <meta name="cover" content="cover-id"/>
          </metadata>
          <manifest>
            <item id="cover-id" href="OEBPS/cover.jpg" media-type="image/jpeg"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """

        // Place the actual cover at OEBPS/Images/cover.jpg (createMinimalEPUB
        // prepends OEBPS/ to coverPath).
        let epubURL = try Self.createMinimalEPUB(
            opfXML: opf,
            coverPath: "Images/cover.jpg",
            coverData: jpegData
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let extractor = EPUBMetadataExtractor()
        let image = await extractor.extractCoverImage(from: epubURL)
        #expect(image != nil, "Bug #122: basename fallback should locate OEBPS/Images/cover.jpg")
    }

    // MARK: - Protocol Default

    @Test("MetadataExtractor default extractCoverImage returns nil")
    func protocolDefault_returnsNil() async {
        let extractor = TXTMetadataExtractor()
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let image = await extractor.extractCoverImage(from: url)
        #expect(image == nil, "Default protocol implementation should return nil")
    }
}

// MARK: - Test Helpers

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }
    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
