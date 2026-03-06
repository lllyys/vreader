// Purpose: Regression tests for URL prefix consistency after EPUBParser.open().
// Verifies the critical invariant: resourceBaseURL().path must have
// extractedRootURL().path as a prefix — this is what WKWebView checks
// when deciding whether to allow loading a resource.
//
// Bug context: WKWebView blocked EPUB content because extractedRootURL()
// returned /private/var/mobile/... while resourceBaseURL() returned
// /var/mobile/... due to .standardizedFileURL resolving symlinks inconsistently.
//
// @coordinates-with: EPUBParser.swift, EPUBParserProtocol.swift, ZIPReaderTests.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Multi-file ZIP Builder

/// Builds a minimal valid ZIP archive with multiple stored (uncompressed) entries.
/// Reuses the little-endian Data helpers from ZIPReaderTests pattern.
private struct ZIPBuilder {
    struct Entry {
        let path: String
        let content: Data
    }

    /// Creates a ZIP file on disk containing all given entries.
    static func createZIP(entries: [Entry]) throws -> URL {
        var archive = Data()
        var localHeaderOffsets: [Int] = []

        // Write Local File Header + data for each entry
        for entry in entries {
            let nameData = Data(entry.path.utf8)
            localHeaderOffsets.append(archive.count)
            archive.append(buildLocalFileHeader(nameData: nameData, content: entry.content))
            archive.append(nameData)
            archive.append(entry.content)
        }

        // Write Central Directory
        let cdOffset = archive.count
        for (i, entry) in entries.enumerated() {
            let nameData = Data(entry.path.utf8)
            archive.append(buildCentralDirectoryEntry(
                nameData: nameData,
                content: entry.content,
                localHeaderOffset: UInt32(localHeaderOffsets[i])
            ))
            archive.append(nameData)
        }
        let cdSize = archive.count - cdOffset

        // Write End of Central Directory
        archive.append(buildEOCD(
            entryCount: UInt16(entries.count),
            cdSize: UInt32(cdSize),
            cdOffset: UInt32(cdOffset)
        ))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub-test-\(UUID().uuidString).epub")
        try archive.write(to: url)
        return url
    }

    private static func buildLocalFileHeader(nameData: Data, content: Data) -> Data {
        var h = Data()
        h.appendUInt32LE(0x04034b50)
        h.appendUInt16LE(20)
        h.appendUInt16LE(0)
        h.appendUInt16LE(0)  // stored
        h.appendUInt16LE(0)
        h.appendUInt16LE(0)
        h.appendUInt32LE(0)  // crc32 (ignored)
        h.appendUInt32LE(UInt32(content.count))
        h.appendUInt32LE(UInt32(content.count))
        h.appendUInt16LE(UInt16(nameData.count))
        h.appendUInt16LE(0)
        return h
    }

    private static func buildCentralDirectoryEntry(
        nameData: Data,
        content: Data,
        localHeaderOffset: UInt32
    ) -> Data {
        var e = Data()
        e.appendUInt32LE(0x02014b50)
        e.appendUInt16LE(20)
        e.appendUInt16LE(20)
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)  // stored
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt32LE(0)  // crc32
        e.appendUInt32LE(UInt32(content.count))
        e.appendUInt32LE(UInt32(content.count))
        e.appendUInt16LE(UInt16(nameData.count))
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt32LE(0)
        e.appendUInt32LE(localHeaderOffset)
        return e
    }

    private static func buildEOCD(entryCount: UInt16, cdSize: UInt32, cdOffset: UInt32) -> Data {
        var e = Data()
        e.appendUInt32LE(0x06054b50)
        e.appendUInt16LE(0)
        e.appendUInt16LE(0)
        e.appendUInt16LE(entryCount)
        e.appendUInt16LE(entryCount)
        e.appendUInt32LE(cdSize)
        e.appendUInt32LE(cdOffset)
        e.appendUInt16LE(0)
        return e
    }
}

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

// MARK: - EPUB Template Builders

/// Builds minimal valid EPUB XML files.
private enum EPUBTemplate {

    static func containerXML(opfPath: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.utf8)
    }

    /// Builds a minimal OPF with one or more spine items.
    /// `hrefs` are relative to the OPF directory.
    static func contentOPF(title: String = "Test Book", hrefs: [String]) -> Data {
        var manifestItems = ""
        var spineItems = ""
        for (i, href) in hrefs.enumerated() {
            let id = "item\(i)"
            manifestItems += """
                <item id="\(id)" href="\(href)" media-type="application/xhtml+xml"/>\n
            """
            spineItems += "    <itemref idref=\"\(id)\"/>\n"
        }
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(title)</dc:title>
          </metadata>
          <manifest>
            \(manifestItems)
          </manifest>
          <spine>
            \(spineItems)
          </spine>
        </package>
        """.utf8)
    }

    static func minimalXHTML(title: String = "Chapter") -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>\(title)</title></head>
          <body><p>Content of \(title)</p></body>
        </html>
        """.utf8)
    }
}

// MARK: - URL Prefix Consistency Tests

@Suite("EPUBParser - URL Prefix Consistency")
struct EPUBParserURLPrefixTests {

    // MARK: - OPF at root level

    @Test("resourceBaseURL has extractedRootURL as prefix when OPF is at root")
    func rootLevelOPFPrefixConsistency() async throws {
        // OPF at root: container.xml points to "content.opf"
        let epubURL = try ZIPBuilder.createZIP(entries: [
            .init(path: "META-INF/container.xml",
                  content: EPUBTemplate.containerXML(opfPath: "content.opf")),
            .init(path: "content.opf",
                  content: EPUBTemplate.contentOPF(hrefs: ["chapter.xhtml"])),
            .init(path: "chapter.xhtml",
                  content: EPUBTemplate.minimalXHTML(title: "Chapter 1")),
        ])
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let parser = EPUBParser()
        let metadata = try await parser.open(url: epubURL)
        defer { Task { await parser.close() } }

        let rootURL = try await parser.extractedRootURL()
        let baseURL = try await parser.resourceBaseURL()

        // Critical invariant: WKWebView requires this
        #expect(
            baseURL.path.hasPrefix(rootURL.path),
            "resourceBaseURL \(baseURL.path) must have extractedRootURL \(rootURL.path) as prefix"
        )

        // Also verify spine item content URL has the prefix
        let firstHref = metadata.spineItems[0].href
        let contentURL = baseURL.appendingPathComponent(firstHref)
        #expect(
            contentURL.path.hasPrefix(rootURL.path),
            "content URL \(contentURL.path) must have extractedRootURL \(rootURL.path) as prefix"
        )
    }

    // MARK: - OPF in subdirectory (typical EPUB layout)

    @Test("resourceBaseURL has extractedRootURL as prefix when OPF is in OEBPS/")
    func subdirectoryOPFPrefixConsistency() async throws {
        // Typical layout: OEBPS/content.opf
        let epubURL = try ZIPBuilder.createZIP(entries: [
            .init(path: "META-INF/container.xml",
                  content: EPUBTemplate.containerXML(opfPath: "OEBPS/content.opf")),
            .init(path: "OEBPS/content.opf",
                  content: EPUBTemplate.contentOPF(hrefs: ["chapter1.xhtml", "chapter2.xhtml"])),
            .init(path: "OEBPS/chapter1.xhtml",
                  content: EPUBTemplate.minimalXHTML(title: "Chapter 1")),
            .init(path: "OEBPS/chapter2.xhtml",
                  content: EPUBTemplate.minimalXHTML(title: "Chapter 2")),
        ])
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let parser = EPUBParser()
        let metadata = try await parser.open(url: epubURL)
        defer { Task { await parser.close() } }

        let rootURL = try await parser.extractedRootURL()
        let baseURL = try await parser.resourceBaseURL()

        #expect(
            baseURL.path.hasPrefix(rootURL.path),
            "resourceBaseURL \(baseURL.path) must have extractedRootURL \(rootURL.path) as prefix"
        )

        // Verify all spine items produce valid prefixed content URLs
        for item in metadata.spineItems {
            let contentURL = baseURL.appendingPathComponent(item.href)
            #expect(
                contentURL.path.hasPrefix(rootURL.path),
                "content URL for \(item.href) (\(contentURL.path)) must have extractedRootURL \(rootURL.path) as prefix"
            )
        }
    }

    // MARK: - Deeply nested OPF

    @Test("resourceBaseURL has extractedRootURL as prefix with deeply nested OPF")
    func deeplyNestedOPFPrefixConsistency() async throws {
        let epubURL = try ZIPBuilder.createZIP(entries: [
            .init(path: "META-INF/container.xml",
                  content: EPUBTemplate.containerXML(opfPath: "a/b/c/content.opf")),
            .init(path: "a/b/c/content.opf",
                  content: EPUBTemplate.contentOPF(hrefs: ["ch.xhtml"])),
            .init(path: "a/b/c/ch.xhtml",
                  content: EPUBTemplate.minimalXHTML()),
        ])
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let parser = EPUBParser()
        _ = try await parser.open(url: epubURL)
        defer { Task { await parser.close() } }

        let rootURL = try await parser.extractedRootURL()
        let baseURL = try await parser.resourceBaseURL()

        #expect(
            baseURL.path.hasPrefix(rootURL.path),
            "resourceBaseURL \(baseURL.path) must have extractedRootURL \(rootURL.path) as prefix"
        )

        // baseURL should be the OPF directory: extractedRoot/a/b/c/
        #expect(baseURL.path.contains("/a/b/c"))
    }

    // MARK: - Consistent URL scheme (no /private/var vs /var mismatch)

    @Test("extractedRootURL and resourceBaseURL share same URL scheme and prefix")
    func noPrivateVarMismatch() async throws {
        let epubURL = try ZIPBuilder.createZIP(entries: [
            .init(path: "META-INF/container.xml",
                  content: EPUBTemplate.containerXML(opfPath: "OEBPS/content.opf")),
            .init(path: "OEBPS/content.opf",
                  content: EPUBTemplate.contentOPF(hrefs: ["ch.xhtml"])),
            .init(path: "OEBPS/ch.xhtml",
                  content: EPUBTemplate.minimalXHTML()),
        ])
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let parser = EPUBParser()
        _ = try await parser.open(url: epubURL)
        defer { Task { await parser.close() } }

        let rootURL = try await parser.extractedRootURL()
        let baseURL = try await parser.resourceBaseURL()

        // Both paths must start with the same directory component —
        // if one resolves /private/var and the other /var, this fails.
        let rootComponents = rootURL.pathComponents
        let baseComponents = baseURL.pathComponents

        // The first N components of baseURL must match rootURL exactly
        for i in 0..<rootComponents.count {
            #expect(
                baseComponents[i] == rootComponents[i],
                "Path component mismatch at index \(i): '\(baseComponents[i])' vs '\(rootComponents[i])'"
            )
        }
    }

    // MARK: - Content retrieval uses consistent paths

    @Test("contentForSpineItem resolves within extractedRootURL")
    func contentRetrievalUsesConsistentPaths() async throws {
        let epubURL = try ZIPBuilder.createZIP(entries: [
            .init(path: "META-INF/container.xml",
                  content: EPUBTemplate.containerXML(opfPath: "OEBPS/content.opf")),
            .init(path: "OEBPS/content.opf",
                  content: EPUBTemplate.contentOPF(hrefs: ["ch.xhtml"])),
            .init(path: "OEBPS/ch.xhtml",
                  content: EPUBTemplate.minimalXHTML(title: "Test Chapter")),
        ])
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let parser = EPUBParser()
        let metadata = try await parser.open(url: epubURL)
        defer { Task { await parser.close() } }

        // contentForSpineItem should succeed — it would fail if
        // internal path resolution had /private/var vs /var mismatch
        let content = try await parser.contentForSpineItem(href: metadata.spineItems[0].href)
        #expect(content.contains("Test Chapter"))
    }

    // MARK: - Cleanup

    @Test("close removes extracted directory")
    func closeRemovesExtractedDir() async throws {
        let epubURL = try ZIPBuilder.createZIP(entries: [
            .init(path: "META-INF/container.xml",
                  content: EPUBTemplate.containerXML(opfPath: "content.opf")),
            .init(path: "content.opf",
                  content: EPUBTemplate.contentOPF(hrefs: ["ch.xhtml"])),
            .init(path: "ch.xhtml",
                  content: EPUBTemplate.minimalXHTML()),
        ])
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let parser = EPUBParser()
        _ = try await parser.open(url: epubURL)

        let rootURL = try await parser.extractedRootURL()
        #expect(FileManager.default.fileExists(atPath: rootURL.path))

        await parser.close()

        #expect(!FileManager.default.fileExists(atPath: rootURL.path))
    }
}
