// Purpose: Feature #42 Phase 2 WI-2b — the deterministic EPUB-assembly core.
// Given decoded MOBI parts (WI-2a's `MobiPart`s), lay out the EPUB's file
// entries: a stable path for each part, a generated content.opf (manifest +
// markup-ordered spine), an EPUB3 nav document, META-INF/container.xml, and the
// mimetype. Pure + deterministic (no clock, no RNG — the package identifier is
// the SHA-256 of the part bytes) → 100% CI-testable.
//
// WI-2c zips these `EPUBFile` entries into a `.epub` on disk (honoring the
// stored-mimetype flag); WI-3 verifies href fidelity against a real Kindle book;
// WI-4 wires the whole pipeline into BookImporter.
//
// @coordinates-with: MobiDocument.swift, Libmobi.swift,
//   vreader/Services/Libmobi/BUILD-RECIPE.md

import Foundation
import CryptoKit

/// One file destined for the EPUB OCF container.
struct EPUBFile: Equatable {
    /// Path relative to the EPUB root (e.g. `OEBPS/text/part0001.xhtml`).
    let path: String
    let data: Data
    /// EPUB OCF requires the `mimetype` entry be STORED (uncompressed) and
    /// first in the zip. WI-2c honors this flag when packaging.
    let isStored: Bool
}

/// Errors from EPUB assembly.
enum MobiEPUBError: Error, Equatable {
    /// No markup parts → there is nothing to put in the spine or the TOC nav,
    /// and an empty `<ol>` is invalid EPUB3. Mirrors the decode layer's
    /// `MobiDecodeError.noMarkup`; in the real pipeline `decodeParts` already
    /// rejects this, so reaching the assembler with zero markup is a bug.
    case noMarkup
}

enum MobiEPUBAssembler {

    /// Lay out decoded MOBI `parts` into ordered EPUB file entries. Markup parts
    /// become the reading order (spine), in decode order; flow (CSS/SVG) and
    /// resources (images/fonts) go in the manifest only. Filenames are
    /// deterministic and stable so the OPF hrefs and the on-disk paths always
    /// agree.
    ///
    /// The returned array is ordered `[mimetype, container.xml, content.opf,
    /// nav, …parts]` — WI-2c writes them in this order so `mimetype` lands
    /// first.
    ///
    /// - Throws: `MobiEPUBError.noMarkup` if there are no markup parts — an
    ///   empty spine + empty TOC `<ol>` is invalid EPUB3, so reject rather than
    ///   emit a malformed package (Codex Gate-4).
    static func assemble(parts: [MobiPart], title: String) throws -> [EPUBFile] {
        let markup = parts.filter { $0.section == .markup }
        let flow = parts.filter { $0.section == .flow }
        let resources = parts.filter { $0.section == .resource }
        guard !markup.isEmpty else { throw MobiEPUBError.noMarkup }

        // Stable, content-addressed identifier — same MOBI → same EPUB id.
        let identifier = "urn:uuid:" + packageUUID(for: parts)

        // 1. Assign each part a stable path + manifest id, partitioned by section.
        var manifest: [ManifestEntry] = []
        var spineIDs: [String] = []
        var files: [EPUBFile] = []

        for (i, part) in markup.enumerated() {
            let id = "html\(pad(i))"
            let href = "text/part\(pad(i)).xhtml"
            manifest.append(ManifestEntry(id: id, href: href, mediaType: "application/xhtml+xml"))
            spineIDs.append(id)
            files.append(EPUBFile(path: "OEBPS/\(href)", data: part.data, isStored: false))
        }
        for (i, part) in flow.enumerated() {
            let ext = part.fileExtension.isEmpty ? "css" : part.fileExtension
            let id = "flow\(pad(i))"
            let href = "styles/flow\(pad(i)).\(ext)"
            manifest.append(ManifestEntry(id: id, href: href, mediaType: mediaType(forExtension: ext)))
            files.append(EPUBFile(path: "OEBPS/\(href)", data: part.data, isStored: false))
        }
        for (i, part) in resources.enumerated() {
            let ext = part.fileExtension.isEmpty ? "bin" : part.fileExtension
            let id = "res\(pad(i))"
            let href = "resources/res\(pad(i)).\(ext)"
            manifest.append(ManifestEntry(id: id, href: href, mediaType: mediaType(forExtension: ext)))
            files.append(EPUBFile(path: "OEBPS/\(href)", data: part.data, isStored: false))
        }

        // 2. Generated documents.
        let navEntry = ManifestEntry(id: "nav", href: "nav.xhtml",
                                     mediaType: "application/xhtml+xml", properties: "nav")
        let opf = contentOPF(identifier: identifier, title: title,
                             manifest: manifest + [navEntry], spineIDs: spineIDs)
        let nav = navDocument(title: title, markupHrefs: markup.indices.map { "text/part\(pad($0)).xhtml" })

        // 3. Assemble in container order (mimetype FIRST + stored).
        var result: [EPUBFile] = [
            EPUBFile(path: "mimetype", data: Data("application/epub+zip".utf8), isStored: true),
            EPUBFile(path: "META-INF/container.xml", data: Data(containerXML.utf8), isStored: false),
            EPUBFile(path: "OEBPS/content.opf", data: Data(opf.utf8), isStored: false),
            EPUBFile(path: "OEBPS/nav.xhtml", data: Data(nav.utf8), isStored: false),
        ]
        result.append(contentsOf: files)
        return result
    }

    // MARK: - Generated XML

    private static let containerXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private static func contentOPF(identifier: String, title: String,
                                   manifest: [ManifestEntry], spineIDs: [String]) -> String {
        let items = manifest.map { entry -> String in
            let props = entry.properties.map { " properties=\"\($0)\"" } ?? ""
            return "    <item id=\"\(entry.id)\" href=\"\(entry.href)\" media-type=\"\(entry.mediaType)\"\(props)/>"
        }.joined(separator: "\n")
        let itemrefs = spineIDs.map { "    <itemref idref=\"\($0)\"/>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">\(xmlEscape(identifier))</dc:identifier>
            <dc:title>\(xmlEscape(title))</dc:title>
            <dc:language>und</dc:language>
          </metadata>
          <manifest>
        \(items)
          </manifest>
          <spine>
        \(itemrefs)
          </spine>
        </package>
        """
    }

    private static func navDocument(title: String, markupHrefs: [String]) -> String {
        let items = markupHrefs.enumerated().map { i, href in
            "        <li><a href=\"\(href)\">\(xmlEscape(title)) — \(i + 1)</a></li>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <head><title>\(xmlEscape(title))</title></head>
          <body>
            <nav epub:type="toc" id="toc">
              <ol>
        \(items)
              </ol>
            </nav>
          </body>
        </html>
        """
    }

    // MARK: - Helpers

    private struct ManifestEntry {
        let id: String
        let href: String
        let mediaType: String
        var properties: String? = nil
    }

    /// 4-digit zero-padded index for stable, sortable filenames.
    private static func pad(_ i: Int) -> String { String(format: "%04d", i) }

    /// Deterministic identifier: SHA-256 over each part's bytes (order-sensitive),
    /// formatted UUID-like. No clock / RNG, so the same MOBI always yields the
    /// same EPUB identity.
    private static func packageUUID(for parts: [MobiPart]) -> String {
        var hasher = SHA256()
        for part in parts {
            // Domain-separate each field so two part lists with identical bytes
            // but different section / uid / extension cannot collide on one id
            // (Codex Gate-4 High). The length-prefixed header + delimiter make
            // the boundary between fields and payload unambiguous.
            let header = "\(part.section)|\(part.uid)|\(part.fileExtension)|\(part.data.count)\n"
            hasher.update(data: Data(header.utf8))
            hasher.update(data: part.data)
        }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        // Shape the first 32 hex chars as 8-4-4-4-12.
        let h = Array(hex.prefix(32))
        func seg(_ a: Int, _ b: Int) -> String { String(h[a..<b]) }
        return "\(seg(0, 8))-\(seg(8, 12))-\(seg(12, 16))-\(seg(16, 20))-\(seg(20, 32))"
    }

    private static func mediaType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "xhtml": return "application/xhtml+xml"
        case "css":           return "text/css"
        case "svg":           return "image/svg+xml"
        case "jpg", "jpeg":   return "image/jpeg"
        case "png":           return "image/png"
        case "gif":           return "image/gif"
        case "bmp":           return "image/bmp"
        case "otf":           return "font/otf"
        case "ttf":           return "font/ttf"
        case "mp3":           return "audio/mpeg"
        case "mpg", "mpeg":   return "video/mpeg"
        case "pdf":           return "application/pdf"
        default:              return "application/octet-stream"
        }
    }

    /// Minimal XML text/attribute escaper (local to keep the feature self-
    /// contained). Order matters: `&` first.
    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
